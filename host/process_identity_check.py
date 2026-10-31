"""Join browser-reported roles to a same-session guest procfs snapshot."""
from pathlib import Path
import argparse,json,re

def parse_snapshot(text):
    text=re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]','',text)
    records={};current=None
    for line in text.splitlines():
        marker=re.fullmatch(r'PROC_IDENTITY_PID=(\d+)',line.strip())
        if marker:
            current=int(marker[1]);records[current]={};continue
        field=re.fullmatch(r'(Name|Pid|PPid|Threads|State):\s*(.*)',line)
        if current is not None and field:
            value=field[2]
            records[current][field[1]]=int(value) if field[1] in ('Pid','PPid','Threads') else value
    return records

def assess(browser,snapshot):
    if browser.get('ok') is not True:return {'ok':False,'error':'Browser role evidence unavailable'}
    browsers=[p for p in browser.get('browser_pids',[]) if snapshot.get(p,{}).get('Pid')==p]
    renderers=[]
    rejected=[]
    for pid in list(browser.get('browser_pids',[]))+list(browser.get('renderer_pids',[])):
        item=snapshot.get(pid,{})
        if item and (str(item.get('State','')).startswith(('Z','X')) or item.get('Threads',0)<1):
            rejected.append({'pid':pid,'reason':'dead/zombie or zero threads','state':item.get('State'),'threads':item.get('Threads')})
    for pid in browser.get('renderer_pids',[]):
        item=snapshot.get(pid,{})
        if item.get('Pid')!=pid or item.get('Threads',0)<1:continue
        if str(item.get('State','')).startswith(('Z','X')):continue
        chain=[];parent=pid
        while parent in snapshot and parent not in chain and len(chain)<32:
            chain.append(parent);parent=snapshot[parent].get('PPid')
        if any(p in browsers for p in chain[1:]):renderers.append({'pid':pid,'ancestry':chain,'procfs':item})
    return {'ok':bool(browsers and renderers) and not rejected,'browser_matches':browsers,'renderer_matches':renderers,'rejected':rejected,
            'note':'Role is from Chromium; PID, threads and parent chain are independently read from guest procfs. Z/X or zero-thread targets are rejected before injection.'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('session');args=ap.parse_args();p=Path(args.session)
    try:
        browser=json.loads((p/'browser-processes.json').read_text(encoding='utf-8-sig'))
        result=assess(browser,parse_snapshot((p/'console.log').read_text(encoding='utf-8',errors='replace')))
    except (OSError,ValueError,TypeError) as exc:
        result={'ok':False,'error':'Process identity evidence unavailable: '+str(exc)}
    if p.is_dir():(p/'process-identity.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result));return 0 if result['ok'] else 1
if __name__=='__main__':raise SystemExit(main())
