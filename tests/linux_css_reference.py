"""Run an isolated Linux Chrome reference; never score it as an AArch64 QEMU run."""
from pathlib import Path
import argparse,base64,json,os,platform,subprocess,sys,time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from css_layout_probe import capture,page_socket,rpc

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--chrome',required=True);ap.add_argument('--out',required=True)
    ap.add_argument('--width',type=int,required=True);ap.add_argument('--height',type=int,required=True)
    ap.add_argument('--fontconfig',required=True);args=ap.parse_args()
    if platform.system()!='Linux':raise RuntimeError('Linux reference requires a Linux runtime')
    root=Path(__file__).resolve().parents[1];out=Path(args.out).resolve();out.mkdir(exist_ok=False)
    page=root/'pages/layout.html';url=page.as_uri();log=(out/'chrome.log').open('wb')
    cmd=[str(Path(args.chrome).resolve()),'--headless=new','--no-sandbox','--no-first-run','--disable-background-networking',
         '--disable-sync','--disable-component-update','--disable-dev-shm-usage','--remote-debugging-port=0',
         '--user-data-dir='+str(out/'profile'),url]
    env=dict(os.environ,FONTCONFIG_FILE=str(Path(args.fontconfig).resolve()))
    (out/'invocation.json').write_text(json.dumps({'argv':cmd,'fontconfig':env['FONTCONFIG_FILE'],'platform':platform.platform(),
        'architecture':platform.machine(),'scope':'Diagnostic Linux CSS reference only'},indent=2),encoding='utf-8')
    proc=subprocess.Popen(cmd,stdout=log,stderr=log,env=env);result={'ok':False};endpoint=None;ws=None
    try:
        marker=out/'profile/DevToolsActivePort';deadline=time.monotonic()+30
        while not marker.exists() and time.monotonic()<deadline:
            if proc.poll() is not None:raise RuntimeError('Chrome exited before debugger became ready')
            time.sleep(.2)
        endpoint='http://127.0.0.1:'+marker.read_text().splitlines()[0]
        ws=page_socket(endpoint,url)
        # Overrides are session-scoped; retain this attachment until capture.
        rpc(ws,'Emulation.setDeviceMetricsOverride',{'width':args.width,'height':args.height,'deviceScaleFactor':1,'mobile':False})
        rpc(ws,'Page.reload',{'ignoreCache':True},call_id=2)
        time.sleep(2)
        result=capture(endpoint,url,page)
        result['requested_viewport']={'width':args.width,'height':args.height,'dpr':1}
        result['viewport_matches_requested']=result.get('viewport')==result['requested_viewport']
        result['ok']=result['ok'] and result['viewport_matches_requested']
        result['reference_scope']='Linux x86_64 headless; same browser version and extracted guest fonts; not an official-platform result.'
        shot=rpc(ws,'Page.captureScreenshot',{'format':'png'},call_id=3)
        (out/'linux-layout.png').write_bytes(base64.b64decode(shot['data']))
    except Exception as exc:result={'ok':False,'error':str(exc)}
    finally:
        if ws:ws.close()
        if endpoint:
            try:
                ws=page_socket(endpoint,url)
                try:rpc(ws,'Browser.close')
                finally:ws.close()
            except Exception:pass
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()
    (out/'css-layout.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=True));return 0 if result.get('ok') else 1
if __name__=='__main__':raise SystemExit(main())
