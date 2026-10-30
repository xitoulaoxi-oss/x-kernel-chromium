"""Control CDP message delivery through QEMU without involving Chromium.

Fixture responses are transport evidence only, never browser acceptance.
"""
from pathlib import Path
import argparse,importlib.util,json,subprocess,threading,time
from http.server import ThreadingHTTPServer

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('transport_fixture',ROOT/'tests/cdp_transport_test.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)


def run_case(out,hold):
    out.mkdir(parents=True,exist_ok=False)
    events=[]
    class Handler(fixture.Handler):
        protocol_version='HTTP/1.1'
        def do_GET(self):
            events.append({'path':self.path,'event':'start','at':time.time()})
            super().do_GET()
            events.append({'path':self.path,'event':'reply_sent','at':time.time()})
            if self.path.startswith('/devtools/') and hold:time.sleep(15)
            self.close_connection=True
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    direct={}
    try:
        direct=fixture.page_probe.probe(f'http://127.0.0.1:{server.server_port}','file:///index.html','js',timeout=3)
        command=f"printf '#!/bin/sh\\nexec nc -w 20 10.0.2.2 {server.server_port}\\n' > /tmp/xk-cdp-forward.sh; echo MOCK_BACKEND_READY"
        args=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'host/xkwin.ps1'),
              '-EnableGuestCdp','-Kernel','artifacts/kernel-procfs.bin',
              '-Disk',r'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
              '-Command',command,'-PageProbeMode','js','-ExpectedPageUrl','file:///index.html',
              '-CommandTimeoutSec','30','-AfterScriptWait','0','-OutDir',str(out)]
        with (out/'driver.log').open('wb') as log:
            result=subprocess.run(args,cwd=ROOT,stdout=log,stderr=log,timeout=90)
        summary={'fixture':True,'hold_after_reply_s':15 if hold else 0,
                 'direct_host_ok':direct.get('ok'),'qemu_exit':result.returncode,'events':events}
    finally:
        server.shutdown();server.server_close();thread.join(timeout=2)
    (out/'diagnostic.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps(summary))
    return summary


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',required=True);args=ap.parse_args()
    out=Path(args.out);out.mkdir(parents=True,exist_ok=False)
    results=[run_case(out/'close_after_reply',False),run_case(out/'hold_after_reply',True)]
    (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')

if __name__=='__main__':main()
