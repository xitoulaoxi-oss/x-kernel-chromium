"""Compare browser, page, and flattened-target CDP routes in a live session."""
from pathlib import Path
import argparse,importlib.util,json,http.client,time,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('probe',ROOT/'host/page_probe.py')
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',required=True);args=ap.parse_args()
    run=Path(args.run);endpoint=(run/'cdp-endpoint.txt').read_text().strip();u=urllib.parse.urlsplit(endpoint)
    rows=[]
    def get(path):
        c=http.client.HTTPConnection(u.hostname,u.port,timeout=5)
        try:c.request('GET',path,headers={'Connection':'close'});return json.loads(c.getresponse().read())
        finally:c.close()
    def call(ws,ident,method,params=None,session=None):
        message={'id':ident,'method':method,'params':params or {}}
        if session:message['sessionId']=session
        start=time.monotonic();ws.send(json.dumps(message).encode())
        try:
            while True:
                reply=ws.receive()
                if reply.get("method"): rows.append({"event":reply})
                if reply.get('id')==ident:
                    rows.append({'method':method,'session':session,'reply':reply,'seconds':time.monotonic()-start});return reply
        except Exception as exc:rows.append({'method':method,'session':session,'error':str(exc)});return None
    try:
        version=get('/json/version');targets=get('/json/list')
        target=next(t for t in targets if t.get('type')=='page')
        rows.append({'target':{k:target.get(k) for k in ('id','url','title')}})
        ws=probe.WebSocket(endpoint,urllib.parse.urlsplit(version['webSocketDebuggerUrl']).path,4)
        try:
            call(ws,1,'Browser.getVersion')
            call(ws,2,'Target.getTargets')
            attached=call(ws,3,'Target.attachToTarget',{'targetId':target['id'],'flatten':True})
            session=attached.get('result',{}).get('sessionId') if attached else None
            if session:call(ws,4,'Runtime.evaluate',{'expression':'1+1','returnByValue':True},session)
        finally:ws.close()
        ws=probe.WebSocket(endpoint,urllib.parse.urlsplit(target['webSocketDebuggerUrl']).path,4)
        try:call(ws,5,'Runtime.evaluate',{'expression':'1+1','returnByValue':True})
        finally:ws.close()
    except Exception as exc:rows.append({'error':str(exc)})
    (run/('cdp-routes-'+str(time.time_ns())+'.json')).write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(rows,ensure_ascii=True))
if __name__=='__main__':main()
