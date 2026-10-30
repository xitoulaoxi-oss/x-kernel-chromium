"""Read CSS geometry without modifying the official page; compare equal viewports."""
from pathlib import Path
import argparse,hashlib,http.client,json,math,re,time,urllib.parse
from page_probe import WebSocket

EXPRESSION=r'''(() => {
  const box=e=>{const r=e.getBoundingClientRect();return {x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height}};
  const children=id=>Array.from(document.getElementById(id).children).map(box);
  const style=(id,key)=>getComputedStyle(document.getElementById(id))[key];
  return {url:location.href,ready_state:document.readyState,user_agent:navigator.userAgent,
    viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},
    time_origin:performance.timeOrigin,body_text:document.body.innerText,
    checks:Object.fromEntries(Array.from({length:6},(_,i)=>{const id='C'+(i+1);return [id,document.getElementById('s-'+id).classList.contains('st-pass')]})),
    verdict:document.getElementById('verdict').classList.contains('v-pass'),
    boxes:{flex:children('c1'),grid:children('c2'),border_box:[box(document.getElementById('c3-box'))]},
    styles:{radius:style('c4-rounded','borderTopLeftRadius'),border:style('c4-rounded','borderTopWidth'),
      odd:getComputedStyle(document.getElementById('c5').tBodies[0].rows[0]).backgroundColor,
      even:getComputedStyle(document.getElementById('c5').tBodies[0].rows[1]).backgroundColor,
      center:style('c6-center','textAlign'),justify:style('c6-justify','textAlign')}
  };
})()'''

def page_socket(endpoint,url):
    u=urllib.parse.urlsplit(endpoint)
    if u.scheme!='http' or u.hostname not in ('127.0.0.1','localhost','::1'):raise ValueError('Endpoint must be local')
    conn=http.client.HTTPConnection(u.hostname,u.port or 80,timeout=10)
    try:
        conn.request('GET','/json/list',headers={'Connection':'close'})
        response=conn.getresponse()
        if response.status!=200:raise RuntimeError('Target list unavailable')
        matches=[p for p in json.loads(response.read()) if p.get('type')=='page' and p.get('url')==url]
    finally:conn.close()
    if len(matches)!=1:raise RuntimeError('Expected exactly one CSS page')
    return WebSocket(endpoint,urllib.parse.urlsplit(matches[0]['webSocketDebuggerUrl']).path,10)

def rpc(ws,method,params=None,call_id=1):
    ws.send(json.dumps({'id':call_id,'method':method,'params':params or {}}).encode())
    while True:
        reply=ws.receive()
        if reply.get('id')==call_id:
            if 'error' in reply:raise RuntimeError(str(reply['error']))
            return reply.get('result',{})

def capture(endpoint,url,page_file):
    ws=page_socket(endpoint,url)
    try:
        result=rpc(ws,'Runtime.evaluate',{'expression':EXPRESSION,'returnByValue':True})
        if result.get('exceptionDetails'):raise RuntimeError('CSS DOM evaluation failed')
        value=result['result']['value']
        version_info=rpc(ws,'Browser.getVersion',call_id=2)
    finally:ws.close()
    body=value.pop('body_text')
    value['body_sha256']=hashlib.sha256(body.encode()).hexdigest()
    value['html_sha256']=hashlib.sha256(Path(page_file).read_bytes()).hexdigest()
    value['browser_product']=version_info.get('product')
    version=re.search(r'(?:HeadlessChrome|Chrome)/([0-9.]+)',value.get('browser_product',''))
    value['browser_version']=version[1] if version else None
    value['ok']=(value['url']==url and value['ready_state']=='complete' and value['verdict'] is True
                 and set(value['checks'])=={f'C{i}' for i in range(1,7)} and all(value['checks'].values()))
    value['observed_at_unix']=time.time()
    return value

def compare(reference,guest,tolerance=1.0):
    reasons=[];deltas=[]
    if reference.get('ok') is not True or guest.get('ok') is not True:reasons.append('one CSS probe did not pass')
    for key in ('html_sha256','browser_version','viewport','styles'):
        if not reference.get(key) or reference.get(key)!=guest.get(key):reasons.append(f'{key} differs or is absent')
    for name,expected_count in (('flex',3),('grid',4),('border_box',1)):
        a=reference.get('boxes',{}).get(name,[]);b=guest.get('boxes',{}).get(name,[])
        if len(a)!=expected_count or len(b)!=expected_count:
            reasons.append(f'{name} geometry is incomplete');continue
        for i,(x,y) in enumerate(zip(a,b)):
            for key in ('x','y','width','height'):
                av=x.get(key);bv=y.get(key)
                if not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in (av,bv)):
                    reasons.append(f'{name}[{i}].{key} is not finite');continue
                delta=abs(av-bv);deltas.append({'box':name,'index':i,'field':key,'absolute_px':delta})
                if delta>tolerance:reasons.append(f'{name}[{i}].{key} differs by {delta}px')
    return {'ok':not reasons,'reasons':reasons,'tolerance_px':tolerance,'deltas':deltas,
            'scope':'Same-version Linux x86_64 headless CSS reference against x-kernel AArch64 X11; not official-platform or pixel-equivalence certification.'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--endpoint',required=True);ap.add_argument('--expected-url',required=True)
    ap.add_argument('--page-file',required=True);ap.add_argument('--out',required=True);args=ap.parse_args()
    try:result=capture(args.endpoint,args.expected_url,args.page_file)
    except Exception as exc:result={'ok':False,'error':str(exc)}
    Path(args.out).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=True));return 0 if result.get('ok') else 1
if __name__=='__main__':raise SystemExit(main())
