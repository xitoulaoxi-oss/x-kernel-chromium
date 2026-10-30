#!/usr/bin/env python3
"""Ring layout/decoder tests for trace-followup/02 (no QEMU)."""
import importlib.util, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ring', ROOT / 'host/ring_decode.py')
ring = importlib.util.module_from_spec(spec); spec.loader.exec_module(ring)


def build(entries_by_cpu=None, schema=2, total=None, cpus=4, esize=40, epc=1024,
          checksum=None, bad_header=False):
    buf = bytearray(ring.TOTAL_LEN)
    buf[0:8] = b'XKRING02' if not bad_header else b'BADMAGIC'
    struct.pack_into('<IIIIII', buf, 8, schema, 128,
                     total if total is not None else ring.TOTAL_LEN,
                     cpus, esize, epc)
    struct.pack_into('<QQIIQ', buf, 32, 12345, 1000000, 0, 0, 0)
    checksum = ring.fnv1a64(bytes(buf[:128])) if checksum is None else checksum
    struct.pack_into('<Q', buf, 56, checksum)
    entries_by_cpu = entries_by_cpu or {}
    for cpu in range(ring.CPU_COUNT):
        items = entries_by_cpu.get(cpu, [])
        seq = max((e[0] for e in items), default=0) + (1 if items else 0)
        head = seq % ring.ENTRIES_PER_CPU
        struct.pack_into('<QQII', buf, 128 + cpu * 64, seq, max(0, seq - ring.ENTRIES_PER_CPU), head, 0)
        for seqno, ticks, kind, flags, ecpu in items:
            slot = seqno % ring.ENTRIES_PER_CPU
            o = ring.ENTRIES_OFF + (cpu * ring.ENTRIES_PER_CPU + slot) * ring.ENTRY_SIZE
            struct.pack_into('<QQQQHHI', buf, o, seqno, ticks, seqno * 10, seqno * 11, kind, ecpu, flags)
    return bytes(buf)


def main():
    failures = []
    def check(name, cond, detail=''):
        print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f' {detail}'))
        if not cond: failures.append(name)

    d = ring.decode(build())
    check('empty ring ok', d['ok'], d)
    check('header sizes', d['header']['entry_size'] == 40 and d['header']['total_len'] == 164224, d['header'])

    valid = build({0: [(0, 100, 1, 1, 0), (1, 200, 2, 1, 0)], 1: [(0, 101, 1, 1, 1)]})
    d = ring.decode(valid)
    check('valid entries ok', d['ok'] and len(d['cpus'][0]['entries']) == 2 and len(d['cpus'][1]['entries']) == 1, d)

    half = build({0: [(5, 100, 1, 0, 0)]})
    d = ring.decode(half)
    check('half-written entry rejected', d['ok'] and d['cpus'][0]['uncommitted_or_stale'] == 1 and d['cpus'][0]['entries'] == [], d)

    wrapped = build({0: [(1300, 999, 3, 1, 0)]})
    d = ring.decode(wrapped)
    check('wrapped retained range', d['ok'] and d['cpus'][0]['retained_seq'] == [278, 1300], d['cpus'][0])

    dup = bytearray(build({0: [(7, 1, 1, 1, 0)]}))
    src = ring.ENTRIES_OFF + 7 * ring.ENTRY_SIZE
    dst = ring.ENTRIES_OFF + 8 * ring.ENTRY_SIZE
    dup[dst:dst + ring.ENTRY_SIZE] = dup[src:src + ring.ENTRY_SIZE]
    d = ring.decode(bytes(dup))
    check('duplicate seq rejected', not d['ok'] and d['cpus'][0]['duplicate_seq'] == 1, d)

    d = ring.decode(build(schema=3))
    check('wrong schema rejected', not d['ok'], d['header'])
    d = ring.decode(build(total=ring.TOTAL_LEN - 8))
    check('wrong total rejected', not d['ok'], d['header'])
    d = ring.decode(build(cpus=2))
    check('wrong cpu count rejected', not d['ok'], d['header'])
    d = ring.decode(build(checksum=0))
    check('wrong checksum rejected', not d['ok'], d['header'])
    d = ring.decode(build(bad_header=True))
    check('wrong magic rejected', not d['ok'], d['header'])
    d = ring.decode(valid[:100])
    check('short buffer rejected', not d['ok'], d)

    print('RING-LAYOUT-TESTS-PASS' if not failures else f'{len(failures)} FAILURES')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
