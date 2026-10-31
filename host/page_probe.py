"""Read actual DOM results through an explicitly configured local CDP endpoint.

No page mutation and no click simulation: real input remains the harness's job.
Uses only the Python standard library; unavailable evidence never means PASS.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
import socket
import struct
import time
import urllib.parse
import uuid
from pathlib import Path


class WebSocket:
    def __init__(self, endpoint: str, path: str, timeout: float):
        u = urllib.parse.urlsplit(endpoint)
        if u.scheme != 'http' or u.hostname not in ('127.0.0.1', 'localhost', '::1'):
            raise ValueError('CDP endpoint must be local http://localhost:port')
        self.conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.conn.putrequest('GET', path)
        for k, v in {'Upgrade': 'websocket', 'Connection': 'Upgrade',
                     'Sec-WebSocket-Key': key, 'Sec-WebSocket-Version': '13'}.items():
            self.conn.putheader(k, v)
        self.conn.endheaders()
        # Parse through a private file: HTTPResponse's file may have buffered
        # the first frame, so keep using the same stream after the upgrade.
        self.stream = self.conn.sock.makefile('rb')
        status = self.stream.readline().decode('ascii')
        headers = {}
        while True:
            line = self.stream.readline()
            if line in (b'\r\n', b'\n', b''):
                break
            k, v = line.decode('ascii').split(':', 1)
            headers[k.lower()] = v.strip()
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        if ' 101 ' not in status or headers.get('sec-websocket-accept') != accept:
            self.close()
            raise RuntimeError('CDP WebSocket upgrade rejected')

    def close(self):
        if getattr(self, 'stream', None):
            self.stream.close()
        self.conn.close()

    def send(self, payload: bytes, opcode=1):
        mask = os.urandom(4)
        n = len(payload)
        header = bytes([0x80 | opcode])
        header += bytes([0x80 | n]) if n < 126 else (bytes([0xFE]) + struct.pack('!H', n) if n < 65536 else bytes([0xFF]) + struct.pack('!Q', n))
        self.conn.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def read(self, n):
        out = b''
        while len(out) < n:
            chunk = self.stream.read(n - len(out))
            if not chunk:
                raise EOFError('CDP disconnected')
            out += chunk
        return out

    def receive(self):
        chunks = []
        total = 0
        while True:
            a, b = self.read(2)
            opcode = a & 15
            n = b & 127
            if n == 126:
                n = struct.unpack('!H', self.read(2))[0]
            elif n == 127:
                n = struct.unpack('!Q', self.read(8))[0]
            total += n
            if total > 8 * 1024 * 1024:
                raise ValueError('oversize CDP message')
            mask = self.read(4) if b & 128 else None
            data = self.read(n)
            if mask:
                data = bytes(v ^ mask[i % 4] for i, v in enumerate(data))
            if opcode == 8:
                raise EOFError('CDP closed')
            if opcode == 9:
                self.send(data, 10)
                continue
            if opcode == 10:
                continue
            if opcode not in (0, 1):
                raise ValueError('unexpected CDP frame')
            chunks.append(data)
            if a & 128:
                return json.loads(b''.join(chunks))


EXPRESSION = r'''(() => {
 const rows = {}; for (const prefix of ['T','C']) for (let i=1;i<=6;i++) {
   const e=document.getElementById('s-'+prefix+i);
   rows[prefix+i]={pass:!!e && e.classList.contains('st-pass'), text:e ? e.textContent : null};
 }
 const v=document.getElementById('verdict');
 const nav=performance.getEntriesByType('navigation')[0];
 return {url:location.href, title:document.title, h1:document.querySelector('h1') ? document.querySelector('h1').textContent : null, ready_state:document.readyState,
   time_origin:performance.timeOrigin, body_text:document.body ? document.body.innerText : '',
   page_load_end_ms: nav ? performance.timeOrigin + nav.loadEventEnd : null,
   dom_content_loaded_ms: nav ? performance.timeOrigin + nav.domContentLoadedEventEnd : null,
   keyboard_value:document.getElementById('kb') ? document.getElementById('kb').value : null,
   keyboard_echo:document.getElementById('kb-echo') ? document.getElementById('kb-echo').textContent : null,
   rows, verdict_pass:!!v && v.classList.contains('v-pass')};
})()'''


def assess(value, target_id, expected_url, mode, expected_text=None, expected_body_sha256=None):
    if not isinstance(value, dict):
        return {'ok': False, 'error': 'DOM response missing'}
    body = value.pop('body_text', '')
    value['body_sha256'] = hashlib.sha256(body.encode()).hexdigest()
    value['body_length'] = len(body)
    origin = value.get('time_origin')
    value['navigation_id'] = f'{target_id}:{origin}' if isinstance(origin, (int, float)) and origin > 0 else None
    value['target_id'] = target_id
    value['expected_url'] = expected_url
    value['mode'] = mode
    value['expected_body_sha256'] = expected_body_sha256
    base_ok = (value.get('url') == expected_url and value.get('ready_state') == 'complete'
               and bool(body.strip()) and bool(value['navigation_id']))
    if expected_body_sha256:
        base_ok = base_ok and value['body_sha256'] == expected_body_sha256
    # Page contract: the static index has no T/C/verdict nodes; interaction only
    # owns T1-T6 and layout only C1-C6.  Missing/not-applicable is never false.
    basename = expected_url.rsplit('/', 1)[-1]
    kind = {'index.html': 'static_index', 'interaction.html': 'interaction',
            'layout.html': 'layout'}.get(basename)
    value['page_kind'] = kind
    raw_rows = value.get('rows') or {}
    if kind == 'static_index':
        value['rows'] = {f'{p}{i}': 'not_applicable' for p in ('T', 'C') for i in range(1, 7)}
        value['verdict'] = 'not_applicable'
        value['ok'] = base_ok and bool((value.get('h1') or '').strip()) and bool((value.get('title') or '').strip())
    elif kind in ('interaction', 'layout'):
        prefix = 'T' if kind == 'interaction' else 'C'
        other = 'C' if prefix == 'T' else 'T'
        value['rows'] = {f'{prefix}{i}': raw_rows.get(f'{prefix}{i}', {'pass': False, 'text': None})
                         for i in range(1, 7)}
        value['rows'].update({f'{other}{i}': 'not_applicable' for i in range(1, 7)})
        value['verdict'] = 'not_applicable' if mode == 'page' else bool(value.get('verdict_pass'))
        if mode == 'page':
            value['ok'] = base_ok and all(value['rows'][f'{prefix}{i}'].get('pass') is True
                                          for i in range(1, 7))
        elif mode in ('js', 'css'):
            value['ok'] = base_ok and value.get('verdict_pass') is True and all(
                value['rows'][f'{prefix}{i}'].get('pass') is True for i in range(1, 7))
        else:
            value['ok'] = base_ok
    else:
        # Unknown document: page mode must not pass just because the URL matched.
        value['rows'] = {f'{p}{i}': 'not_applicable' for p in ('T', 'C') for i in range(1, 7)}
        value['verdict'] = 'not_applicable'
        value['ok'] = False
        value['error'] = 'unknown page contract for expected URL'
    if mode in ('js', 'css'):
        prefix = 'T' if mode == 'js' else 'C'
        value['ok'] = value['ok'] and value.get('verdict_pass') is True and all(
            raw_rows.get(f'{prefix}{i}', {}).get('pass') is True for i in range(1, 7))
    if mode == 'input':
        value['expected_text'] = expected_text
        value['ok'] = value['ok'] and bool(expected_text) and value.get('keyboard_value') == expected_text and expected_text in (value.get('keyboard_echo') or '')
    return value


def probe(endpoint, expected_url, mode, timeout=10, expected_text=None, expected_body_sha256=None):
    u = urllib.parse.urlsplit(endpoint)
    if u.scheme != 'http' or u.hostname not in ('127.0.0.1', 'localhost', '::1'):
        raise ValueError('CDP endpoint must be local http://localhost:port')
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=timeout)
    try:
        conn.request('GET', '/json/list', headers={'Connection': 'close'})
        response = conn.getresponse()
        if response.status != 200:
            raise RuntimeError('CDP target list unavailable')
        targets = json.loads(response.read(1024 * 1024))
    except Exception as exc:
        raise RuntimeError('CDP target-list transport: ' + str(exc)) from exc
    finally:
        conn.close()
    matches = [t for t in targets if t.get('type') == 'page' and t.get('url') == expected_url]
    if len(matches) != 1:
        raise RuntimeError('expected exactly one matching page target')
    target = matches[0]
    wsurl = urllib.parse.urlsplit(target['webSocketDebuggerUrl'])
    ws = WebSocket(endpoint, wsurl.path + ('?' + wsurl.query if wsurl.query else ''), timeout)
    try:
        ws.send(json.dumps({'id': 1, 'method': 'Runtime.evaluate', 'params': {
            'expression': EXPRESSION, 'returnByValue': True}}).encode())
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = ws.receive()
            if message.get('id') == 1:
                if 'error' in message or message.get('result', {}).get('exceptionDetails'):
                    raise RuntimeError('DOM evaluation failed')
                return assess(message.get('result', {}).get('result', {}).get('value'), target['id'], expected_url, mode, expected_text, expected_body_sha256)
        raise TimeoutError('CDP result timeout')
    except Exception as exc:
        raise RuntimeError('CDP DOM transport: ' + str(exc)) from exc
    finally:
        ws.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--endpoint', required=True)
    ap.add_argument('--expected-url', required=True)
    ap.add_argument('--mode', choices=['page', 'js', 'css', 'input'], default='page')
    ap.add_argument('--out', required=True)
    ap.add_argument('--expected-text')
    ap.add_argument('--expected-body-sha256')
    args = ap.parse_args()
    try:
        result = probe(args.endpoint, args.expected_url, args.mode, expected_text=args.expected_text,
                       expected_body_sha256=args.expected_body_sha256)
    except Exception as exc:
        result = {'ok': False, 'error': str(exc)}
    result['probe_id'] = str(uuid.uuid4())
    result['observed_at_unix'] = time.time()
    Path(args.out).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get('ok') is True else 1


if __name__ == '__main__':
    raise SystemExit(main())
