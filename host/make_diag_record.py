#!/usr/bin/env python3
"""Build the iteration/02 host-readable diagnostic record.

Layout (little-endian, 128 bytes):
  0  magic 'XKTRC001' (8)
  8  schema u32 = 1
 12  length u32 = 128
 16  nonce u64 (random per record)
 24  checksum u64 (FNV-1a over the record with this field zero)
 32  payload 96 bytes
"""
import argparse, json, pathlib, secrets, struct

MAGIC = b'XKTRC001'
SCHEMA = 1
LENGTH = 128


def fnv1a64(data: bytes) -> int:
    h = 0xcbf29ce484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001b3) & 0xffffffffffffffff
    return h


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--meta', required=True)
    ap.add_argument('--nonce', type=int, default=0)
    args = ap.parse_args()
    nonce = args.nonce or secrets.randbits(64)
    payload = bytes((i * 37 + 11) & 0xff for i in range(LENGTH - 32))
    buf = bytearray(LENGTH)
    buf[0:8] = MAGIC
    struct.pack_into('<I', buf, 8, SCHEMA)
    struct.pack_into('<I', buf, 12, LENGTH)
    struct.pack_into('<Q', buf, 16, nonce)
    struct.pack_into('<Q', buf, 24, 0)
    buf[32:] = payload
    checksum = fnv1a64(bytes(buf))
    struct.pack_into('<Q', buf, 24, checksum)
    p = pathlib.Path(args.out)
    p.write_bytes(bytes(buf))
    meta = {'file': str(p), 'bytes': len(buf), 'magic': MAGIC.decode(), 'schema': SCHEMA,
            'length': LENGTH, 'nonce': nonce, 'checksum_fnv1a64': f'{checksum:016x}'}
    pathlib.Path(args.meta).write_text(json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
