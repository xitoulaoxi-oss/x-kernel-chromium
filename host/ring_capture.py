#!/usr/bin/env python3
"""Fail-safe frozen capture of XK_TRACE_RING for a real stall.

Differences from qmp_memory_export.py:
  * stopping is explicit; the VM is left stopped unless --resume is given;
  * header length/schema are checked before any full-ring read or unpack;
  * every chunk checks its actual length, the dump hash is saved, and the
    1 MiB cap is enforced before reading;
  * failures still write a structured report with the bytes obtained.
"""
from __future__ import annotations
import argparse, hashlib, json, pathlib, re, socket, struct, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from host.qmp_memory_export import Qmp  # noqa: E402
from host.ring_decode import parse_header, decode, TOTAL_LEN  # noqa: E402

MAX_BYTES = 1 << 20
CHUNK = 4096


def read_chunk(q: Qmp, addr: int, n: int) -> bytes:
    text = q.hmp(f'xp /{n}bx {hex(addr)}')
    out = bytearray()
    for m in re.finditer(r'0x([0-9a-fA-F]{2})', text or ''):
        out.append(int(m.group(1), 16))
    if len(out) != n:
        raise RuntimeError(f'short chunk at {hex(addr)}: {len(out)} of {n}')
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True)
    ap.add_argument('--symbol', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--raw', required=True)
    ap.add_argument('--resume', action='store_true', help='explicitly resume after the dump')
    ap.add_argument('--quit', action='store_true', help='quit only together with --resume')
    args = ap.parse_args()
    s = pathlib.Path(args.session)
    result = {'schema': 'xk-ring-capture/1', 'session': str(s), 'stage': 'init',
              'timeline': [], 'resumed': False, 'error': None, 'ok': False}
    partial = bytearray()
    q = None
    try:
        console = (s / 'console.log').read_text(encoding='utf-8', errors='replace')
        m = re.search(r'kimage_voffset=(0x[0-9a-fA-F]+)', console)
        if not m:
            raise RuntimeError('kimage_voffset not found')
        voffset = int(m.group(1), 16)
        base = 0xffff800000000000 - voffset
        symbol = int(args.symbol, 0)
        phys = base + (symbol - 0xffff800000000000)
        result.update({'kimage_voffset': hex(voffset), 'phys_base': hex(base),
                       'symbol_vaddr': hex(symbol), 'symbol_phys': hex(phys)})
        cmd = (s / 'qemu-cmd.txt').read_text(encoding='utf-8', errors='replace')
        port = int(re.search(r'-qmp\s+tcp:127\.0\.0\.1:(\d+)', cmd).group(1))
        q = Qmp(port)
        result['timeline'].append({'event': 'connect', 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
        before = q.cmd({'execute': 'query-status'})
        result['status_before'] = before
        if before.get('status') == 'paused':
            result['already_paused'] = True
        else:
            result['stage'] = 'stop'
            q.cmd({'execute': 'stop'})
            result['timeline'].append({'event': 'stop-sent', 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
            deadline = time.time() + 10
            last = None
            while time.time() < deadline:
                last = q.cmd({'execute': 'query-status'})
                if last.get('status') == 'paused':
                    break
                time.sleep(0.1)
            result['status_stopped'] = last
            if not last or last.get('status') != 'paused':
                raise RuntimeError('VM did not reach paused state')
            result['timeline'].append({'event': 'paused', 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
        # Header gate before any full read.
        result['stage'] = 'header'
        head = read_chunk(q, phys, 128)
        partial.extend(head)
        header = parse_header(head, require_full=False)
        result['header'] = header
        if not header['ok']:
            raise RuntimeError('header rejected: ' + '; '.join(header['problems']))
        if header['total_len'] > MAX_BYTES:
            raise RuntimeError(f"total_len {header['total_len']} over cap {MAX_BYTES}")
        if header['total_len'] != TOTAL_LEN:
            raise RuntimeError(f"unexpected object length {header['total_len']}")
        # Full frozen read in bounded chunks.
        result['stage'] = 'full-read'
        raw = bytearray(head)
        while len(raw) < header['total_len']:
            n = min(CHUNK, header['total_len'] - len(raw))
            raw.extend(read_chunk(q, phys + len(raw), n))
        result['bytes_read'] = len(raw)
        result['dump_sha256'] = hashlib.sha256(bytes(raw)).hexdigest()
        pathlib.Path(args.raw).write_bytes(bytes(raw))
        result['stage'] = 'decode'
        decoded = decode(bytes(raw))
        kinds = {}
        per_cpu = []
        for cpu in decoded['cpus']:
            for e in cpu['entries']:
                kinds[str(e['kind'])] = kinds.get(str(e['kind']), 0) + 1
            per_cpu.append({'cpu': cpu['cpu'], 'seq': cpu['seq'], 'dropped': cpu['dropped'],
                            'retained_seq': cpu['retained_seq'], 'entries': len(cpu['entries']),
                            'half_written': cpu['uncommitted_or_stale']})
        result.update({'ring_ok': decoded['ok'], 'counts_by_kind': kinds,
                       'per_cpu': per_cpu, 'total_entries': sum(kinds.values())})
        result['ok'] = bool(decoded['ok'] and result['bytes_read'] == header['total_len'])
        result['stage'] = 'complete'
    except Exception as exc:  # noqa: BLE001 - report every failure stage
        result['error'] = str(exc)
        result['partial_bytes'] = len(partial)
        result['partial_sha256'] = hashlib.sha256(bytes(partial)).hexdigest()
        if partial:
            pathlib.Path(args.raw).write_bytes(bytes(partial))
    finally:
        if q is not None:
            if args.resume and not result.get('already_paused'):
                try:
                    q.cmd({'execute': 'cont'})
                    result['resumed'] = True
                    result['timeline'].append({'event': 'cont', 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
                except Exception as exc:  # noqa: BLE001
                    result.setdefault('resume_error', str(exc))
            if args.quit and result['resumed']:
                try:
                    q.cmd({'execute': 'quit'})
                except Exception:
                    pass
            q.close()
    pathlib.Path(args.out).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
