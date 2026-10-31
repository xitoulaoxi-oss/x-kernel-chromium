#!/usr/bin/env python3
"""Ring layout/decoder tests for stall-resolution/01 (no QEMU)."""
import importlib.util, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ring', ROOT / 'host/ring_decode.py')
ring = importlib.util.module_from_spec(spec); spec.loader.exec_module(ring)

N = ring.ENTRIES_PER_CPU


def build(entries_by_cpu=None, seq_by_cpu=None, schema=2, total=None, cpus=4, esize=40, epc=N,
          checksum=None, bad_header=False, tps=1000000, domain=0):
    buf = bytearray(ring.TOTAL_LEN)
    buf[0:8] = b'XKRING02' if not bad_header else b'BADMAGIC'
    struct.pack_into('<IIIIII', buf, 8, schema, 128,
                     total if total is not None else ring.TOTAL_LEN, cpus, esize, epc)
    struct.pack_into('<QQIIQ', buf, 32, 12345, tps, domain, 0, 0)
    checksum = ring.fnv1a64(bytes(buf[:128])) if checksum is None else checksum
    struct.pack_into('<Q', buf, 56, checksum)
    entries_by_cpu = entries_by_cpu or {}
    seq_by_cpu = seq_by_cpu or {}
    for cpu in range(ring.CPU_COUNT):
        items = entries_by_cpu.get(cpu, [])
        seq = seq_by_cpu.get(cpu, max((e[0] for e in items), default=-1) + 1)
        head = seq % N
        struct.pack_into('<QQII', buf, 128 + cpu * 64, seq, max(0, seq - N), head, 0)
        for seqno, ticks, kind, flags, ecpu in items:
            slot = seqno % N
            o = ring.ENTRIES_OFF + (cpu * N + slot) * 40
            struct.pack_into('<QQQQHHI', buf, o, seqno, ticks, seqno * 10, seqno * 11, kind, ecpu, flags)
    return bytes(buf)


def linear(count, start=0):
    return [(start + i, 100 + i, 2, 1, 0) for i in range(count)]


def main():
    failures = []
    def check(name, cond, detail=''):
        print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f' {detail}'))
        if not cond: failures.append(name)

    d = ring.decode(build())
    check('empty ring ok', d['ok'] and d['cpus'][0]['counts']['unused'] == N, d)

    for count, label in ((N - 1, 'N-1'), (N, 'N'), (N + 1, 'N+1')):
        # Build a full linear history, then retain only slots that survived wrap.
        items = linear(count)
        if count > N:
            # Slots from seq count-N .. count-1 survive; earlier ones are overwritten.
            keep = [e for e in items if e[0] >= count - N]
            d = ring.decode(build({0: keep}, seq_by_cpu={0: count}))
            expect = N
        else:
            d = ring.decode(build({0: items}, seq_by_cpu={0: count}))
            expect = count
        check(f'{label} capacity valid={expect}', d['ok'] and d['cpus'][0]['counts']['valid'] == expect,
              d.get('cpus', [{}])[0].get('counts'))

    d = ring.decode(build({0: [(0, 1, 2, 1, 0)]}, seq_by_cpu={0: N}))
    check('seq0 is valid when metadata seq=N', d['ok'] and d['cpus'][0]['counts']['valid'] == 1,
          d['cpus'][0])

    d = ring.decode(build({0: [(9000, 1, 2, 1, 0)]}, seq_by_cpu={0: 1}))
    check('future seq is corrupt, not ok', not d['ok'] and d['cpus'][0]['counts']['corrupt'] == 1,
          d['cpus'][0])

    half = build({0: [(5, 100, 2, 0, 0)]})
    d = ring.decode(half)
    check('half-written entry counted, not decoded', d['ok'] and d['cpus'][0]['counts']['half_written'] == 1
          and d['cpus'][0]['entries'] == [], d['cpus'][0])

    d = ring.decode(build({0: [(7, 1, 2, 1, 1)]}))
    check('wrong CPU is corrupt', not d['ok'] and d['cpus'][0]['counts']['corrupt'] == 1, d['cpus'][0])

    d = ring.decode(build({0: [(0, 1, 99, 1, 0)]}))
    check('unknown kind is corrupt', not d['ok'] and d['cpus'][0]['counts']['unknown_kind'] == 1, d['cpus'][0])

    # Duplicate committed seq in two slots.
    buf = bytearray(build({0: [(7, 1, 2, 1, 0)]}))
    src = ring.ENTRIES_OFF + 7 * 40
    dst = ring.ENTRIES_OFF + 8 * 40
    buf[dst:dst + 40] = buf[src:src + 40]
    d = ring.decode(bytes(buf))
    check('duplicate seq rejected', not d['ok'] and d['cpus'][0]['duplicate_seq'] == 1, d['cpus'][0])

    d = ring.decode(build({0: [(400, 1, 2, 1, 0)]}, seq_by_cpu={0: 1500}))
    check('old wrapped entry is stale, not fatal', d['ok'] and d['cpus'][0]['counts']['stale'] == 1, d['cpus'][0])

    d = ring.decode(build(schema=3))
    check('wrong schema rejected', not d['ok'], d['header'])
    d = ring.decode(build(total=ring.TOTAL_LEN - 8))
    check('wrong total rejected', not d['ok'], d['header'])
    d = ring.decode(build(cpus=2))
    check('wrong cpu count rejected', not d['ok'], d['header'])
    d = ring.decode(build(tps=0))
    check('zero ticks_per_sec rejected', not d['ok'], d['header'])
    d = ring.decode(build(domain=1))
    check('wrong clock domain rejected', not d['ok'], d['header'])
    d = ring.decode(build(checksum=0))
    check('wrong checksum rejected', not d['ok'], d['header'])
    d = ring.decode(build(bad_header=True))
    check('wrong magic rejected', not d['ok'], d['header'])
    d = ring.decode(build({0: [(0, 1, 2, 1, 0)]})[:100])
    check('short buffer rejected', not d['ok'], d)

    print('RING-LAYOUT-TESTS-PASS' if not failures else f'{len(failures)} FAILURES')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
