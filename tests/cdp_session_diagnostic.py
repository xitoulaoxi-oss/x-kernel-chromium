"""Inspect session lifetime and browser versus renderer protocol dispatch."""
from pathlib import Path
import argparse,importlib.util,json,http.client,time,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('probe',ROOT/'host/page_probe.py')
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',required=True);args=ap.parse_args()
    run=Path(args.run);endpoint=(run/'cdp-endpoint.txt').read_text().strip();u=urllib.parse.urlsplit(endpoint)
    records=[];counter=0
    def get(path):
        c=http.client.HTTPConnection(u.hostname,u.port,timeout=5)
        try:c.request('GET',path,headers={'Connection':'close'});return json.loads(c.getresponse().read())
        finally:c.close()
    ws=None
    try:
        version=get('/json/version');target=next(t for t in get('/json/list') if t.get('type')=='page')
        records.append({'target':{k:target.get(k) for k in ('id','url','title')}})
        ws=probe.WebSocket(endpoint,urllib.parse.urlsplit(version['webSocketDebuggerUrl']).path,3)
        def call(method,params=None,session=None):
            nonlocal counter
            counter+=1;message={'id':counter,'method':method,'params':params or {}}
            if session:message['sessionId']=session
            ws.send(json.dumps(message).encode())
            try:
                while True:
                    response=ws.receive()
                    if response.get('method'):records.append({'event':response})
                    if response.get('id')==counter:
                        records.append({'request':message,'reply':response});return response
            except Exception as exc:records.append({'request':message,'error':str(exc)});return None
        call('Browser.getVersion')
        call('SystemInfo.getProcessInfo')
        attached=call('Target.attachToTarget',{'targetId':target['id'],'flatten':False})
        sid=attached.get('result',{}).get('sessionId') if attached else None
        if sid:
            call('Target.sendMessageToTarget',{'sessionId':sid,'message':json.dumps({'id':101,'method':'Runtime.evaluate','params':{'expression':'1+1','returnByValue':True}})})
            call('Target.getTargetInfo',{'targetId':target['id']})
            call('Target.detachFromTarget',{'sessionId':sid})
        call('Target.setAutoAttach',{'autoAttach':True,'waitForDebuggerOnStart':False,'flatten':True})
        # Querying the target also gives queued attach events a chance to arrive.
        call('Target.getTargets')
        sessions=[r['event']['params']['sessionId'] for r in records
                  if r.get('event',{}).get('method')=='Target.attachedToTarget'
                  and r['event']['params']['targetInfo']['targetId']==target['id']]
        if sessions:call('Runtime.evaluate',{'expression':'1+1','returnByValue':True},sessions[-1])
        attached=call('Target.attachToBrowserTarget')
        browser_sid=attached.get('result',{}).get('sessionId') if attached else None
        if browser_sid:call('Browser.getVersion',session=browser_sid)
        call('Browser.getVersion')
    except Exception as exc:records.append({'error':str(exc)})
    finally:
        if ws:ws.close()
    path=run/('cdp-sessions-'+str(time.time_ns())+'.json')
    path.write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(records,ensure_ascii=True))
if __name__=='__main__':main()
