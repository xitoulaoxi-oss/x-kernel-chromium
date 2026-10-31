"""Acceptance regressions: no QEMU or original-tree mutation required."""
import copy
import importlib.util
import json
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'host/acceptance'
spec = importlib.util.spec_from_file_location('probe', ROOT/'host/page_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        temp_root = ROOT / 'experiments/REVIEW-FIX/test-tmp'
        temp_root.mkdir(parents=True, exist_ok=True)
        if not temp_root.resolve().is_relative_to(ROOT.resolve()):
            raise RuntimeError('fixture directory escaped the workspace')
        self.temp = tempfile.TemporaryDirectory(dir=temp_root)
        self.dir = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def run_tool(self, name, *args):
        return subprocess.run([sys.executable, str(PLAN/name), *map(str,args)],
                              capture_output=True, text=True, encoding='utf-8',
                              env=dict(os.environ, PYTHONIOENCODING='utf-8'))

    def put(self, path, doc):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(doc), encoding='utf-8')

    def stability(self):
        rows = [dict(round=i+1, planned_s=60+i*120, sent_s=60+i*120,
                     drift_s=0, completed_s=63+i*120, colors=835, ok=True,
                     semantic_ok=True, before_navigation_id=f't:{i}', navigation_id=f't:{i+1}')
                for i in range(10)]
        self.put(self.dir/'load-schedule.json', dict(count=10, interval_s=120, start_s=60,total_s=1800.5,rows=rows))
        self.put(self.dir/'zz-final.stats.json', dict(colors=835,blank=False))
        (self.dir/'console.log').write_text('\n'.join(f'HB t={i*60} chrome=11 mem_mb=700' for i in range(1,31)))
        return rows

    def invoke_stability(self):
        result = self.run_tool('summarize_stability.py', self.dir)
        doc=json.loads((self.dir/'stability-load.json').read_text())
        return result,doc

    def test_complete_30min_navigation_evidence_passes(self):
        self.stability(); r,d=self.invoke_stability()
        self.assertEqual(r.returncode,0,r.stderr); self.assertEqual(d['verdict'],'PASS')

    def test_29_minutes_fails(self):
        self.stability(); p=self.dir/'load-schedule.json'; d=json.loads(p.read_text());d['total_s']=1740;self.put(p,d)
        r,d=self.invoke_stability();self.assertNotEqual(r.returncode,0);self.assertEqual(d['verdict'],'FAIL')

    def test_old_frame_fails_even_if_colorful(self):
        self.stability();p=self.dir/'load-schedule.json';d=json.loads(p.read_text())
        for row in d['rows']:row['navigation_id']=row['before_navigation_id']
        self.put(p,d);r,d=self.invoke_stability();self.assertNotEqual(r.returncode,0)

    def test_color_only_legacy_evidence_fails(self):
        self.stability();p=self.dir/'load-schedule.json';d=json.loads(p.read_text())
        for row in d['rows']:row.pop('navigation_id');row.pop('semantic_ok')
        self.put(p,d);self.assertNotEqual(self.invoke_stability()[0].returncode,0)

    def test_duplicate_heartbeats_fail(self):
        self.stability();(self.dir/'console.log').write_text(('HB t=60 chrome=11 mem_mb=700\n')*30)
        self.assertNotEqual(self.invoke_stability()[0].returncode,0)

    def test_browser_disappeared_midrun_fails(self):
        self.stability();p=self.dir/'console.log';p.write_text(p.read_text().replace('t=600 chrome=11','t=600 chrome=0'))
        self.assertNotEqual(self.invoke_stability()[0].returncode,0)

    def test_missing_crash_marker_but_harness_error_fails(self):
        self.stability();(self.dir/'harness-error.txt').write_text('console timeout')
        self.assertNotEqual(self.invoke_stability()[0].returncode,0)

    def test_shortened_expectation_cannot_pass(self):
        self.stability();r=self.run_tool('summarize_stability.py',self.dir,'--expect-minutes','29')
        self.assertNotEqual(r.returncode,0)

    def cold_runs(self):
        paths=[]
        for i in range(20):
            p=self.dir/f'C{i+1:02}';paths.append(p)
            self.put(p/'startup-ready.json',dict(ready=True,attempts=[dict(attempt=1)],actions=[]))
            self.put(p/'zz-final.stats.json',dict(colors=835,blank=False))
            (p/'console.log').write_text('WM_NAME(UTF8_STRING) = "初赛指定测试页 · x-kernel + Chromium - Chromium"',encoding='utf-8')
        return paths

    def test_20_first_attempts_pass(self):
        paths=self.cold_runs();r=self.run_tool('summarize_coldstart.py',*paths,'--g1')
        self.assertEqual(r.returncode,0,r.stderr)

    def test_restart_is_not_first_attempt_success(self):
        paths=self.cold_runs();self.put(paths[7]/'startup-ready.json',dict(ready=True,attempts=[dict(attempt=2)],actions=[dict(action='restart')]))
        r=self.run_tool('summarize_coldstart.py',*paths,'--g1');self.assertNotEqual(r.returncode,0)

    def test_repeated_directory_cannot_make_20(self):
        paths=self.cold_runs();r=self.run_tool('summarize_coldstart.py',*([paths[0]]*20),'--g1')
        self.assertNotEqual(r.returncode,0)

    def test_only_19_runs_fail(self):
        paths=self.cold_runs();r=self.run_tool('summarize_coldstart.py',*paths[:19],'--g1')
        self.assertNotEqual(r.returncode,0)

    def page_value(self, page="interaction.html"):
        return dict(url='file:///'+page,ready_state='complete',time_origin=100,
                    body_text='six real results',verdict_pass=True,
                    rows={f'{p}{i}':dict(pass_=True, **{'pass':True}) for p in ('T','C') for i in range(1,7)})

    def test_real_js_and_css_rows_pass(self):
        for mode in ('js','css'):
            page = 'interaction.html' if mode == 'js' else 'layout.html'
            self.assertTrue(probe.assess(self.page_value(page),'target','file:///'+page,mode)['ok'])

    def test_js_not_run_fails(self):
        v=self.page_value();v['verdict_pass']=False
        self.assertFalse(probe.assess(v,'target','file:///interaction.html','js')['ok'])

    def test_one_css_failure_fails(self):
        v=self.page_value('layout.html');v['rows']['C4']['pass']=False
        self.assertFalse(probe.assess(v,'target','file:///layout.html','css')['ok'])

    def test_wrong_url_fails(self):
        self.assertFalse(probe.assess(self.page_value(),'target','file:///other.html','page')['ok'])

    def test_keyboard_requires_value_and_echo(self):
        v=self.page_value();v['keyboard_value']='hello x-kernel';v['keyboard_echo']='echo: hello x-kernel'
        self.assertTrue(probe.assess(v,'target','file:///interaction.html','input','hello x-kernel')['ok'])

    def test_stale_echo_without_typed_value_fails(self):
        v=self.page_value();v['keyboard_value']='';v['keyboard_echo']='echo: hello x-kernel'
        self.assertFalse(probe.assess(v,'target','file:///interaction.html','input','hello x-kernel')['ok'])

    @unittest.skipUnless(os.name=='nt','Windows harness guard')
    def test_diagnostic_policy_cannot_modify_original_disk(self):
        r=subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'host/xkwin.ps1'),
                          '-EnableGuestCdp','-Writable'],capture_output=True,text=True,errors='replace')
        self.assertNotEqual(r.returncode,0)
        self.assertIn('requires a QEMU snapshot',r.stdout+r.stderr)

    def test_probe_transport_failure_has_nonzero_and_evidence(self):
        path=self.dir/'probe.json'
        r=subprocess.run([sys.executable,str(ROOT/'host/page_probe.py'),'--endpoint','https://example.invalid',
                          '--expected-url','file:///test.html','--out',str(path)],capture_output=True)
        self.assertNotEqual(r.returncode,0);self.assertFalse(json.loads(path.read_text())['ok'])

    def test_incomplete_rehearsals_fail(self):
        paths=[]
        for i in range(3):
            p=self.dir/f'scene{i+1}';paths.append(p)
            self.put(p/'scene.json',dict(scene=i+1,functional_rc=0,stability_verdict='PASS',stability_rc=None))
            self.put(p/'functional/run/functional.json',dict(passed=3,total=3))
        r=self.run_tool('summarize_scenes.py',*paths)
        self.assertNotEqual(r.returncode,0)

    def frame_socket(self, incoming):
        ws=probe.WebSocket.__new__(probe.WebSocket)
        ws.stream=io.BytesIO(incoming)
        ws.conn=mock.Mock()
        return ws

    def test_websocket_fragmentation_and_ping(self):
        ws=self.frame_socket(b'\x01\x05{"id"\x89\x01x\x80\x03:1}')
        self.assertEqual(ws.receive(),{'id':1})
        self.assertTrue(ws.conn.sock.sendall.called)

    def test_websocket_masks_client_frames(self):
        ws=self.frame_socket(b'')
        with mock.patch.object(probe.os,'urandom',return_value=b'abcd'):
            ws.send(b'hello')
        raw=ws.conn.sock.sendall.call_args.args[0]
        self.assertEqual(raw[:2],b'\x81\x85')
        self.assertEqual(bytes(v ^ raw[2+i%4] for i,v in enumerate(raw[6:])),b'hello')

    def test_websocket_disconnect_is_failure(self):
        ws=self.frame_socket(b'\x81\x10short')
        with self.assertRaises(EOFError):ws.receive()

    def test_websocket_upgrade_validates_accept(self):
        connection=mock.Mock()
        connection.sock.makefile.return_value=io.BytesIO(b'HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Accept: wrong\r\n\r\n')
        with mock.patch.object(probe.http.client,'HTTPConnection',return_value=connection):
            with self.assertRaises(RuntimeError):probe.WebSocket('http://127.0.0.1:9222','/devtools/page/a',1)
        connection.close.assert_called_once()


if __name__=='__main__':
    unittest.main(verbosity=2)
