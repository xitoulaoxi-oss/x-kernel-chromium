#!/usr/bin/env python3
"""Host-only export of a small guest physical record over QMP.

Never uses the guest shell.  Reads the record before and after QMP `stop`,
validates magic/schema/length/nonce/checksum, and writes an export contract.
"""
from __future__ import annotations
import argparse, json, pathlib, re, socket, struct, time

MAGIC = b'XKTRC001'
SCHEMA = 1
LENGTH = 128


def fnv1a64(data: bytes) -> int:
    h = 0xcbf29ce484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001b3) & 0xffffffffffffffff
    return h


class Qmp:
    def __init__(self, port: int):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=10)
        self.file = self.sock.makefile('rwb')
        self._read()  # greeting
        self.cmd({'execute': 'qmp_capabilities'})

    def _read(self):
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError('QMP connection closed')
            doc = json.loads(line)
            if 'event' in doc:
                continue
            return doc

    def cmd(self, obj):
        self.file.write((json.dumps(obj) + '\n').encode())
        self.file.flush()
        doc = self._read()
        if 'error' in doc:
            raise RuntimeError(doc['error'])
        return doc.get('return')

    def hmp(self, command: str):
        return self.cmd({'execute': 'human-monitor-command', 'arguments': {'command-line': command}})

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


def parse_xp(text: str) -> bytes:
    out = bytearray()
    for m in re.finditer(r'0x([0-9a-fA-F]{2})', text or ''):
        out.append(int(m.group(1), 16))
    return bytes(out)


def verify(data: bytes, meta: dict) -> dict:
    problems = []
    if len(data) != meta['length']:
        problems.append(f'length {len(data)} != {meta["length"]}')
    if data[:8] != MAGIC:
        problems.append(f'magic {data[:8]!r} != {MAGIC!r}')
    schema, length, nonce, checksum = struct.unpack_from('<IIQQ', data, 8)
    if schema != meta['schema']:
        problems.append(f'schema {schema} != {meta["schema"]}')
    if length != meta['length']:
        problems.append(f'field length {length} != {meta["length"]}')
    if nonce != meta['nonce']:
        problems.append(f'nonce {nonce} != {meta["nonce"]}')
    zeroed = bytearray(data)
    struct.pack_into('<Q', zeroed, 24, 0)
    want = fnv1a64(bytes(zeroed))
    if checksum != want or f'{checksum:016x}' != meta['checksum_fnv1a64']:
        problems.append(f'checksum {checksum:016x} != {want:016x}')
    return {'ok': not problems, 'problems': problems, 'bytes': len(data),
            'schema': schema, 'nonce': nonce, 'checksum': f'{checksum:016x}'}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True, help='xkwin output directory')
    ap.add_argument('--record', required=True, help='expected record file')
    ap.add_argument('--meta', required=True)
    ap.add_argument('--addr', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--quit', action='store_true')
    args = ap.parse_args()
    session = pathlib.Path(args.session)
    cmd_text = (session / 'qemu-cmd.txt').read_text(encoding='utf-8', errors='replace')
    m = re.search(r'-qmp\s+tcp:127\.0\.0\.1:(\d+)', cmd_text)
    if not m:
        raise SystemExit('QMP port not found in qemu-cmd.txt')
    port = int(m.group(1))
    meta = json.loads(pathlib.Path(args.meta).read_text(encoding='utf-8'))
    addr = int(args.addr, 0)
    q = Qmp(port)
    result = {'schema': 'xk-memory-export/1', 'qmp_port': port, 'address': hex(addr),
              'record_file': args.record, 'method': 'QMP human-monitor-command xp'}
    try:
        normal = parse_xp(q.hmp(f'xp /{meta["length"]}bx {hex(addr)}'))
        result['normal'] = {'read': verify(normal, meta), 'hex_head': normal[:16].hex()}
        q.cmd({'execute': 'stop'})
        time.sleep(0.5)
        result['stopped_status'] = q.cmd({'execute': 'query-status'})
        stopped = parse_xp(q.hmp(f'xp /{meta["length"]}bx {hex(addr)}'))
        result['stopped'] = {'read': verify(stopped, meta), 'hex_head': stopped[:16].hex()}
        result['normal_equals_stopped'] = normal == stopped
        q.cmd({'execute': 'cont'})
        result['ok'] = (result['normal']['read']['ok'] and result['stopped']['read']['ok']
                        and result['normal_equals_stopped'])
    finally:
        if args.quit:
            try:
                q.cmd({'execute': 'quit'})
            except Exception:
                pass
        q.close()
    pathlib.Path(args.out).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    raise SystemExit(main())
