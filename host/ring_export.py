#!/usr/bin/env python3
"""Export the static XK_TRACE_RING from guest physical memory over QMP.

Address chain:
  symbol virtual address (nm) - kimage_voffset (boot console) = guest physical.
No old PC mapping and no 0x70000000 channel-test address are reused.
"""
from __future__ import annotations
import argparse, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from host.qmp_memory_export import Qmp  # noqa: E402
from host.ring_decode import parse_header, decode, ENTRY_SIZE, ENTRIES_OFF, COMMITTED, TOTAL_LEN  # noqa: E402
import struct


def read_phys(q: Qmp, addr: int, length: int) -> bytes:
    out = bytearray()
    step = 4096
    while len(out) < length:
        n = min(step, length - len(out))
        text = q.hmp(f'xp /{n}bx {hex(addr + len(out))}')
        chunk = bytearray()
        for m in re.finditer(r'0x([0-9a-fA-F]{2})', text or ''):
            chunk.append(int(m.group(1), 16))
        if len(chunk) != n:
            raise RuntimeError(f'xp chunk at {hex(addr + len(out))}: got {len(chunk)} of {n}')
        out.extend(chunk)
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True)
    ap.add_argument('--symbol', required=True, help='virtual address from nm, e.g. 0xffff80000092dd80')
    ap.add_argument('--out', required=True)
    ap.add_argument('--raw', required=True)
    ap.add_argument('--full', action='store_true')
    ap.add_argument('--quit', action='store_true')
    args = ap.parse_args()
    s = pathlib.Path(args.session)
    console = (s / 'console.log').read_text(encoding='utf-8', errors='replace')
    m = re.search(r'kimage_voffset=(0x[0-9a-fA-F]+)', console)
    if not m:
        raise SystemExit('kimage_voffset not found in console.log')
    voffset = int(m.group(1), 16)
    base = 0xffff800000000000 - voffset
    symbol = int(args.symbol, 0)
    phys = base + (symbol - 0xffff800000000000)
    cmd = (s / 'qemu-cmd.txt').read_text(encoding='utf-8', errors='replace')
    qm = re.search(r'-qmp\s+tcp:127\.0\.0\.1:(\d+)', cmd)
    port = int(qm.group(1))
    q = Qmp(port)
    try:
        head = read_phys(q, phys, 4096)
        header = parse_header(head, require_full=False)
        first = None
        if header['ok'] and not args.full:
            o = ENTRIES_OFF
            seq, ticks, a0, a1, kind, cpu, flags = struct.unpack_from('<QQQQHHI', head, o)
            first = {'seq': seq, 'ticks': ticks, 'arg0': a0, 'arg1': a1, 'kind': kind,
                     'cpu': cpu, 'flags': flags, 'committed': bool(flags & COMMITTED)}
        # Freeze, read the frozen image, then resume.  A full ring is read only
        # while stopped so entries cannot change under the exporter.
        q.cmd({'execute': 'stop'})
        frozen = read_phys(q, phys, 4096)
        full_ring = None
        if args.full:
            full_ring = read_phys(q, phys, TOTAL_LEN)
        q.cmd({'execute': 'cont'})
        result_ring = None
        if args.full:
            decoded = decode(full_ring)
            kinds = {}
            chain = []
            for cpu in decoded.get('cpus', []):
                for e in cpu['entries']:
                    kinds[str(e['kind'])] = kinds.get(str(e['kind']), 0) + 1
                chain.append({'cpu': cpu['cpu'], 'seq': cpu['seq'],
                              'entries': cpu['entries'][:24]})
            result_ring = {'ok': decoded.get('ok'), 'counts_by_kind': kinds,
                           'per_cpu': chain, 'total_entries': sum(kinds.values())}
        result = {
            'schema': 'xk-ring-export/1',
            'session': str(s), 'qmp_port': port,
            'kimage_voffset': hex(voffset), 'symbol_vaddr': hex(symbol),
            'phys_base': hex(base), 'symbol_phys': hex(phys),
            'address_chain': 'symbol_vaddr - kimage_voffset (boot console)',
            'header': header,
            'self_test_entry': first,
            'ring': result_ring,
            'normal_equals_stopped': head == frozen,
            'ok': False,
            'limits': ['header + one self-test entry only', 'QMP local debug channel'],
        }
        base_ok = bool(header.get('ok') and head == frozen)
        if args.full and result_ring:
            base_ok = (base_ok and result_ring.get('ok')
                       and result_ring['counts_by_kind'].get('2', 0) > 0
                       and result_ring['counts_by_kind'].get('4', 0) > 0
                       and result_ring['counts_by_kind'].get('6', 0) > 0)
            result['limits'] = ['full frozen image; no live concurrent decode', 'QMP local debug channel']
        else:
            base_ok = bool(base_ok and first and first['kind'] == 1 and first['committed'])
        result['ok'] = base_ok
        pathlib.Path(args.raw).write_bytes(full_ring if args.full else head)
        pathlib.Path(args.out).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(result, indent=2))
    finally:
        if args.quit:
            try:
                q.cmd({'execute': 'quit'})
            except Exception:
                pass
        q.close()
    return 0 if json.loads(pathlib.Path(args.out).read_text())['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
