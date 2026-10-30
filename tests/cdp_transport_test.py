"""Exercise the real CDP HTTP/WebSocket transport against a local fake browser."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

spec=importlib.util.spec_from_file_location('page_probe',Path(__file__).resolve().parents[1]/'host/page_probe.py')
page_probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(page_probe)


class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        if self.path=='/json/list':
            body=json.dumps([{'id':'page-a','type':'page','url':'file:///index.html',
                              'webSocketDebuggerUrl':'ws://127.0.0.1:9222/devtools/page/page-a'}]).encode()
            self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            return
        if self.path!='/devtools/page/page-a':self.send_error(404);return
        accept=base64.b64encode(hashlib.sha1((self.headers['Sec-WebSocket-Key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        self.send_response(101);self.send_header('Upgrade','websocket');self.send_header('Connection','Upgrade');self.send_header('Sec-WebSocket-Accept',accept);self.end_headers()
        a,b=self.rfile.read(2);n=b&127
        if n==126:n=struct.unpack('!H',self.rfile.read(2))[0]
        elif n==127:n=struct.unpack('!Q',self.rfile.read(8))[0]
        mask=self.rfile.read(4)
        payload=self.rfile.read(n)
        call=json.loads(bytes(v^mask[i%4] for i,v in enumerate(payload)))
        if call.get('method')!='Runtime.evaluate':return
        value={'url':'file:///index.html','title':'test','ready_state':'complete',
               'time_origin':123.45,'body_text':'actual DOM fixture', 'verdict_pass':True,
               'rows':{f'{p}{i}':{'pass':True,'text':'passed'} for p in ('T','C') for i in range(1,7)}}
        result=json.dumps({'id':call['id'],'result':{'result':{'value':value}}}).encode()
        frame=b'\x81'+(bytes([len(result)]) if len(result)<126 else b'\x7e'+struct.pack('!H',len(result)))+result
        self.wfile.write(frame);self.wfile.flush()


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.endpoint=f'http://127.0.0.1:{self.server.server_port}'
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join(timeout=2)
    def test_http_and_websocket_semantic_roundtrip(self):
        result=page_probe.probe(self.endpoint,'file:///index.html','js')
        self.assertTrue(result['ok']);self.assertEqual(result['navigation_id'],'page-a:123.45')
        self.assertNotIn('body_text',result)
    def test_wrong_target_url_is_rejected(self):
        with self.assertRaises(RuntimeError):page_probe.probe(self.endpoint,'file:///wrong.html','page')


if __name__=='__main__':unittest.main(verbosity=2)
