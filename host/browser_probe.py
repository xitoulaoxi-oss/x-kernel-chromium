"""Read browser-owned process roles; CPU numbers are not performance evidence."""
from pathlib import Path
import argparse,json,http.client,time,urllib.parse
from page_probe import WebSocket

def assess_processes(processes):
    if not isinstance(processes,list):raise ValueError('Process list missing')
    ids=[]
    for entry in processes:
        pid=entry.get('id')
        if not isinstance(pid,int) or isinstance(pid,bool) or pid<=0:raise ValueError('Invalid process ID')
        if pid in ids:raise ValueError('Duplicate process ID')
        if not isinstance(entry.get('type'),str):raise ValueError('Missing process role')
        ids.append(pid)
    browsers=[p['id'] for p in processes if p['type']=='browser']
    renderers=[p['id'] for p in processes if p['type']=='renderer']
    return {'ok':bool(browsers and renderers),'browser_pids':browsers,
            'renderer_pids':renderers,'processes':processes,
            'role_source':'Chromium SystemInfo.getProcessInfo',
            'cpu_time_note':'Raw API values only; guest CPU accounting is not validated.'}

def probe(endpoint):
    u=urllib.parse.urlsplit(endpoint)
    if u.scheme!='http' or u.hostname not in ('127.0.0.1','localhost','::1'):raise ValueError('Endpoint must be local')
    conn=http.client.HTTPConnection(u.hostname,u.port or 80,timeout=5)
    try:
        conn.request('GET','/json/version',headers={'Connection':'close'})
        response=conn.getresponse()
        if response.status!=200:raise RuntimeError('Browser endpoint unavailable')
        version=json.loads(response.read())
    finally:conn.close()
    ws=WebSocket(endpoint,urllib.parse.urlsplit(version['webSocketDebuggerUrl']).path,5)
    try:
        ws.send(json.dumps({'id':1,'method':'SystemInfo.getProcessInfo'}).encode())
        while True:
            reply=ws.receive()
            if reply.get('id')==1:
                if 'error' in reply:raise RuntimeError(str(reply['error']))
                result=assess_processes(reply.get('result',{}).get('processInfo'))
                result['browser_product']=version.get('Browser');return result
    finally:ws.close()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--endpoint',required=True);ap.add_argument('--out',required=True);args=ap.parse_args()
    try:result=probe(args.endpoint)
    except Exception as exc:result={'ok':False,'error':str(exc)}
    result['observed_at_unix']=time.time()
    Path(args.out).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=True));return 0 if result.get('ok') else 1
if __name__=='__main__':raise SystemExit(main())
