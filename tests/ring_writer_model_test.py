#!/usr/bin/env python3
"""Model the trace_ring writer's reuse/commit order against the decoder."""
import importlib.util, pathlib, struct

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ring', ROOT / 'host/ring_decode.py')
ring = importlib.util.module_from_spec(spec); spec.loader.exec_module(ring)
spec2 = importlib.util.spec_from_file_location('t', ROOT / 'tests/ring_layout_test.py')
t = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(t)

failures = []
def check(name, cond, detail=''):
    print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f' {detail}'))
    if not cond: failures.append(name)

N = ring.ENTRIES_PER_CPU
buf = bytearray(t.build({0: [(0, 111, 2, 1, 0)]}, seq_by_cpu={0: N}))
slot0 = ring.ENTRIES_OFF
meta = 128

def decode_counts():
    d = ring.decode(bytes(buf))
    return d, d['cpus'][0]['counts']

# Phase 1: writer clears commit for reuse of seq N in slot 0.
struct.pack_into('<I', buf, slot0 + 36, 0)
d, c = decode_counts()
check('reuse with commit cleared is half-written', c['half_written'] == 1 and c['valid'] == 0, c)

# Phase 2: write new seq/payload for seq N, still no commit.
struct.pack_into('<QQQQHHI', buf, slot0, N, 999, N, N + 1, 2, 0, 0)
d, c = decode_counts()
check('payload before commit is half-written', c['half_written'] == 1 and c['valid'] == 0, c)

# Phase 3: writer publishes reservation seq=N+1, commit still 0.
struct.pack_into('<Q', buf, meta, N + 1)
d, c = decode_counts()
check('reservation before commit is half-written, not future', c['half_written'] == 1 and c['corrupt'] == 0, c)

# Phase 4: commit last; the new record becomes valid.
struct.pack_into('<I', buf, slot0 + 36, 1)
d, c = decode_counts()
check('commit last publishes exactly one valid record', d['ok'] and c['valid'] == 1 and c['half_written'] == 0, c)

# Phase 5: without clearing the old commit, a reader would accept a mixed
# payload; assert the decoder sees the *new* seq only after commit in the fixed
# protocol, and that a stale future seq is corrupt.
buf2 = bytearray(t.build({0: [(9000, 1, 2, 1, 0)]}, seq_by_cpu={0: 1}))
d2 = ring.decode(bytes(buf2)); c2 = d2['cpus'][0]['counts']
check('future seq is not accepted', not d2['ok'] and c2['corrupt'] == 1, c2)

print('WRITER-MODEL-TESTS-PASS' if not failures else f'{len(failures)} FAILURES')
raise SystemExit(1 if failures else 0)
