#!/usr/bin/env python3
"""Fail-safe frozen capture of XK_TRACE_RING (stall-resolution/04).

Invariants:
  * every successfully read chunk is retained in the partial evidence;
  * the raw file and the report are written BEFORE any explicit resume;
  * no automatic resume/quit; an already-paused VM stays paused;
  * header/schema/length are validated before a full read or unpack;
  * total read is capped at 1 MiB.
"""
from __future__ import annotations
import argparse, hashlib, json, pathlib, re, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from host.qmp_memory_export import Qmp  # noqa: E402
from host.ring_decode import parse_header, decode, TOTAL_LEN  # noqa: E402

MAX_BYTES = 1 << 20
CHUNK = 4096


def read_exact(q: Qmp, addr: int, n: int) -> bytes:
    text = q.hmp(f'xp /{n}bx {hex(addr)}')
    out = bytearray()
    for m in re.finditer(r'0x([0-9a-fA-F]{2})', text or ''):
        out.append(int(m.group(1), 16))
    if len(out) != n:
        raise RuntimeError(f'short chunk at {hex(addr)}: {len(out)} of {n}')
    return bytes(out)


def utc() -> str:
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True)
    ap.add_argument('--symbol', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--raw', required=True)
    ap.add_argument('--resume', action='store_true')
    ap.add_argument('--quit', action='store_true')
    ap.add_argument('--fault-after-chunks', type=int, default=0,
                    help='test-only: raise after N full chunks have been read')
    ap.add_argument('--phys-base', default='', help='fallback base when console lacks kimage_voffset')
    args = ap.parse_args()
    s = pathlib.Path(args.session)
    report = {
        'schema': 'xk-ring-capture/2', 'session': str(s), 'stage': 'init',
        'timeline': [], 'resumed': False, 'error': None, 'ok': False,
        'partial_blocks': [], 'report_before_resume': None,
    }
    partial = bytearray()
    q = None

    def persist():
        # Raw first, then the report.  A raw write failure is reported but does
        # not prevent the structured report from being written.
        try:
            pathlib.Path(args.raw).write_bytes(bytes(partial))
            report['raw_written'] = True
        except Exception as exc:  # noqa: BLE001
            report['raw_written'] = False
            report['raw_write_error'] = str(exc)
        report['partial_bytes'] = len(partial)
        report['partial_sha256'] = hashlib.sha256(bytes(partial)).hexdigest()
        report['report_before_resume'] = True
        pathlib.Path(args.out).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    try:
        console = (s / 'console.log').read_text(encoding='utf-8', errors='replace')
        m = re.search(r'kimage_voffset=(0x[0-9a-fA-F]+)', console)
        if m:
            voffset = int(m.group(1), 16)
            base = 0xffff800000000000 - voffset
            chain = 'symbol_vaddr - kimage_voffset from boot console'
        elif args.phys_base:
            base = int(args.phys_base, 0)
            voffset = 0xffff800000000000 - base
            chain = 'explicit --phys-base fallback (console omitted kimage_voffset)'
        else:
            raise RuntimeError('kimage_voffset not found and no --phys-base supplied')
        symbol = int(args.symbol, 0)
        phys = base + (symbol - 0xffff800000000000)
        report.update({'kimage_voffset': hex(voffset) if voffset else None, 'phys_base': hex(base),
                       'address_chain': chain, 'symbol_vaddr': hex(symbol), 'symbol_phys': hex(phys)})
        cmd = (s / 'qemu-cmd.txt').read_text(encoding='utf-8', errors='replace')
        port = int(re.search(r'-qmp\s+tcp:127\.0\.0\.1:(\d+)', cmd).group(1))
        q = Qmp(port)
        report['timeline'].append({'event': 'connect', 'utc': utc()})
        before = q.cmd({'execute': 'query-status'})
        report['status_before'] = before
        if before.get('status') == 'paused':
            report['already_paused'] = True
        else:
            report['stage'] = 'stop'
            q.cmd({'execute': 'stop'})
            report['timeline'].append({'event': 'stop-sent', 'utc': utc()})
            deadline = time.time() + 10
            last = None
            while time.time() < deadline:
                last = q.cmd({'execute': 'query-status'})
                if last.get('status') == 'paused':
                    break
                time.sleep(0.1)
            report['status_stopped'] = last
            if not last or last.get('status') != 'paused':
                raise RuntimeError('VM did not reach paused state')
            report['timeline'].append({'event': 'paused', 'utc': utc()})

        report['stage'] = 'header'
        head = read_exact(q, phys, 128)
        partial.extend(head)
        report['partial_blocks'].append({'address': hex(phys), 'bytes': len(head), 'kind': 'header'})
        header = parse_header(head, require_full=False)
        report['header'] = header
        if not header['ok']:
            raise RuntimeError('header rejected: ' + '; '.join(header['problems']))
        if header['total_len'] > MAX_BYTES:
            raise RuntimeError(f"total_len {header['total_len']} over cap {MAX_BYTES}")
        if header['total_len'] != TOTAL_LEN:
            raise RuntimeError(f'unexpected object length {header["total_len"]}')

        report['stage'] = 'full-read'
        chunks = 0
        while len(partial) < header['total_len']:
            n = min(CHUNK, header['total_len'] - len(partial))
            addr = phys + len(partial)
            block = read_exact(q, addr, n)
            partial.extend(block)
            chunks += 1
            report['partial_blocks'].append({'address': hex(addr), 'bytes': len(block), 'kind': 'data'})
            if args.fault_after_chunks and chunks >= args.fault_after_chunks:
                raise RuntimeError(f'injected transport failure after {chunks} data chunks')
        report['bytes_read'] = len(partial)
        report['stage'] = 'decode'
        decoded = decode(bytes(partial))
        counts = {}
        per_cpu = []
        for cpu in decoded['cpus']:
            for e in cpu['entries']:
                counts[str(e['kind'])] = counts.get(str(e['kind']), 0) + 1
            per_cpu.append({'cpu': cpu['cpu'], 'seq': cpu['seq'], 'dropped': cpu['dropped'],
                            'retained_seq': cpu['retained_seq'], 'entries': len(cpu['entries']),
                            'half_written': cpu['counts']['half_written'],
                            'stale': cpu['counts']['stale'], 'corrupt': cpu['counts']['corrupt']})
        report.update({'ring_ok': decoded['ok'], 'severe': decoded['severe'],
                       'counts_by_kind': counts, 'per_cpu': per_cpu,
                       'total_entries': sum(counts.values())})
        report['ok'] = bool(decoded['ok'] and report['bytes_read'] == header['total_len'])
        report['stage'] = 'complete'
    except Exception as exc:  # noqa: BLE001
        report['error'] = str(exc)
        if report['stage'] == 'init':
            report['stage'] = 'setup'
    finally:
        persist()
        # Explicit resume only after the report/raw are on disk.
        if q is not None and args.resume and not report.get('already_paused'):
            try:
                q.cmd({'execute': 'cont'})
                report['resumed'] = True
                report['timeline'].append({'event': 'cont', 'utc': utc()})
            except Exception as exc:  # noqa: BLE001
                report['resume_error'] = str(exc)
        # Re-write the final report with the resume outcome; this is not the
        # original evidence write and is clearly marked.
        pathlib.Path(args.out).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        if q is not None:
            if args.quit and report['resumed']:
                try:
                    q.cmd({'execute': 'quit'})
                except Exception:
                    pass
            q.close()
    print(json.dumps(report, indent=2))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
