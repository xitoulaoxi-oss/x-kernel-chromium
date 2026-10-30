"""A real, isolated host Chrome control for guest CDP transport diagnosis."""
from pathlib import Path
import argparse,importlib.util,json,subprocess,time,http.client,urllib.parse

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('probe',ROOT/'host/page_probe.py')
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',required=True);args=ap.parse_args()
    out=Path(args.out);out.mkdir(parents=True,exist_ok=False)
    chrome=Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe')
    url=(ROOT/'pages/index.html').as_uri();result={};browser_ws=None
    log=(out/'chrome.log').open('wb')
    proc=subprocess.Popen([str(chrome),'--headless=new','--disable-gpu','--no-first-run',
        '--disable-background-networking','--disable-sync','--disable-component-update',
        '--remote-debugging-port=0','--user-data-dir='+str(out/'profile'),url],stdout=log,stderr=log)
    try:
        marker=out/'profile/DevToolsActivePort';deadline=time.monotonic()+20
        while not marker.exists() and time.monotonic()<deadline:time.sleep(.2)
        port,path=marker.read_text().splitlines()[:2];endpoint='http://127.0.0.1:'+port
        result['endpoint']=endpoint;result['url']=url
        browser_ws=probe.WebSocket(endpoint,path,5)
        browser_ws.send(json.dumps({'id':1,'method':'Browser.getVersion'}).encode())
        result['browser_reply']=browser_ws.receive()
        result['page']=probe.probe(endpoint,url,'page',timeout=5)
    except Exception as exc:result['error']=str(exc)
    finally:
        if browser_ws:
            try:browser_ws.send(json.dumps({'id':99,'method':'Browser.close'}).encode())
            except Exception:pass
            browser_ws.close()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()
    (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=True));return 0 if result.get('page',{}).get('ok') else 1

if __name__=='__main__':raise SystemExit(main())
