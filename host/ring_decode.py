#!/usr/bin/env python3
"""Decode the trace-followup/02 fixed-capacity per-CPU event ring.

Layout (little-endian):
  header 128 B, per-CPU metadata 64 B, entries 40 B.
  4 CPUs x 1024 entries x 40 B = 163840 B; total = 128 + 256 + 163840 = 164224 B.

Header:
  0  magic 'XKRING02' (8)
  8  schema u32 = 2
 12  header_len u32 = 128
 16  total_len u32 = 164224
 20  cpu_count u32 = 4
 24  entry_size u32 = 40
 28  entries_per_cpu u32 = 1024
 32  boot_nonce u64
 40  ticks_per_sec u64
 48  clock_domain u32 (0 = arch timer counter)
 52  flags u32
 56  header_checksum u64 (FNV-1a over the 128-byte header with this field zero)
 64  reserved

Per-CPU metadata (64 B, at 128 + cpu*64):
  0  seq u64        total records ever written on this CPU
  8  dropped u64    records overwritten because the ring wrapped
 16  head u32       next slot index (seq % entries_per_cpu)
 20  flags u32
 24  reserved

Entry (40 B, at entries_off + cpu*entries_per_cpu*40 + slot*40):
  0  seq u64        per-CPU sequence
  8  ticks u64      arch timer counter at write
 16  arg0 u64
 24  arg1 u64
 32  kind u16
 34  cpu u16
 36  flags u32      bit0 COMMITTED, bit1 HALF_WRITE marker (0 while writing)
"""
from __future__ import annotations
import argparse, json, pathlib, struct

MAGIC = b'XKRING02'
SCHEMA = 2
HEADER_LEN = 128
META_LEN = 64
ENTRY_SIZE = 40
CPU_COUNT = 4
ENTRIES_PER_CPU = 1024
ENTRIES_OFF = HEADER_LEN + META_LEN * CPU_COUNT
TOTAL_LEN = ENTRIES_OFF + ENTRY_SIZE * ENTRIES_PER_CPU * CPU_COUNT
COMMITTED = 1


def fnv1a64(data: bytes) -> int:
    h = 0xcbf29ce484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001b3) & 0xffffffffffffffff
    return h


def parse_header(data: bytes, require_full: bool = True) -> dict:
    if len(data) < HEADER_LEN:
        raise ValueError(f'short header: {len(data)}')
    magic = data[:8]
    schema, hlen, total, cpus, esize, epc = struct.unpack_from('<IIIIII', data, 8)
    nonce, tps, domain, flags, checksum = struct.unpack_from('<QQIIQ', data, 32)
    zeroed = bytearray(data[:HEADER_LEN])
    struct.pack_into('<Q', zeroed, 56, 0)
    want = fnv1a64(bytes(zeroed))
    problems = []
    if magic != MAGIC: problems.append(f'magic {magic!r}')
    if schema != SCHEMA: problems.append(f'schema {schema}')
    if hlen != HEADER_LEN: problems.append(f'header_len {hlen}')
    if total != TOTAL_LEN: problems.append(f'total_len {total}')
    if cpus != CPU_COUNT: problems.append(f'cpu_count {cpus}')
    if esize != ENTRY_SIZE: problems.append(f'entry_size {esize}')
    if epc != ENTRIES_PER_CPU: problems.append(f'entries_per_cpu {epc}')
    if checksum != want: problems.append(f'header_checksum {checksum:016x} != {want:016x}')
    if require_full and len(data) < TOTAL_LEN: problems.append(f'buffer {len(data)} < {TOTAL_LEN}')
    return {
        'ok': not problems, 'problems': problems,
        'magic': magic.decode('latin1'), 'schema': schema, 'header_len': hlen,
        'total_len': total, 'cpu_count': cpus, 'entry_size': esize,
        'entries_per_cpu': epc, 'boot_nonce': nonce, 'ticks_per_sec': tps,
        'clock_domain': domain, 'flags': flags,
    }


def decode(data: bytes) -> dict:
    try:
        header = parse_header(data)
    except ValueError as exc:
        return {'ok': False, 'error': str(exc)}
    cpus = []
    if header['ok']:
        for cpu in range(CPU_COUNT):
            mo = HEADER_LEN + cpu * META_LEN
            seq, dropped, head, mflags = struct.unpack_from('<QQII', data, mo)
            entries = []
            bad = 0
            for slot in range(ENTRIES_PER_CPU):
                o = ENTRIES_OFF + (cpu * ENTRIES_PER_CPU + slot) * ENTRY_SIZE
                eseq, ticks, a0, a1, kind, ecpu, eflags = struct.unpack_from('<QQQQHHI', data, o)
                if eflags & COMMITTED == 0:
                    # An all-zero slot is unused, not a half write.  Only a slot
                    # with some non-zero content and no commit is suspicious.
                    if eseq or ticks or a0 or a1 or kind or ecpu:
                        bad += 1
                    continue
                # A committed slot must belong to the current retained window and
                # carry this CPU's id; otherwise it is stale or corrupt.
                if eseq + ENTRIES_PER_CPU <= seq or ecpu != cpu:
                    bad += 1
                    continue
                entries.append({'seq': eseq, 'ticks': ticks, 'arg0': a0, 'arg1': a1,
                                'kind': kind, 'cpu': ecpu, 'flags': eflags})
            entries.sort(key=lambda e: e['seq'])
            duplicate_seq = sum(1 for a, b in zip(entries, entries[1:]) if a['seq'] == b['seq'])
            retained_lo = max(0, seq - ENTRIES_PER_CPU + 1) if seq else None
            cpus.append({
                'cpu': cpu, 'seq': seq, 'dropped': dropped, 'head': head,
                'entries': entries, 'uncommitted_or_stale': bad,
                'duplicate_seq': duplicate_seq,
                'retained_seq': [retained_lo, seq - 1] if seq else [],
            })
    ok = bool(header['ok']) and all(c['duplicate_seq'] == 0 for c in cpus)
    return {'ok': ok, 'header': header, 'cpus': cpus}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('file', nargs='?')
    ap.add_argument('--out')
    args = ap.parse_args()
    if not args.file:
        ap.error('file required')
    data = pathlib.Path(args.file).read_bytes()
    out = decode(data)
    text = json.dumps(out, indent=2)
    if args.out:
        pathlib.Path(args.out).write_text(text + '\n', encoding='utf-8')
    print(text)
    return 0 if out.get('ok') else 1


if __name__ == '__main__':
    raise SystemExit(main())
