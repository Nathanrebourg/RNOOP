#!/usr/bin/env python3
"""Offline NROOP research: historical evidence, real-engine sensitivity and civil-day attribution.
No physiological equation is implemented in Python. Default app scores and source files are never written.
"""
from __future__ import annotations
import argparse
import bisect
import copy
import hashlib
import html
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from nroop_lab import finite

VERSION='nroop-research-v1'
STREAMS=('hr','rr','gravity','events','band')

def digest(data): return hashlib.sha256(data).hexdigest()
def checksum(s): return isinstance(s,str) and len(s)==64 and all(c in '0123456789abcdef' for c in s)
def load(path):
    p=Path(path)
    if p.stat().st_size>512*1024**2: raise ValueError('Input exceeds 512 MiB.')
    return json.loads(p.read_text(encoding='utf-8'))
def save_new(path,value):
    # Exclusive creation prevents accidental replacement of a recording, report or backup.
    with Path(path).open('x',encoding='utf-8') as f: json.dump(value,f,allow_nan=False,indent=2,sort_keys=True)
def recipe(r):
    result={}
    for key,default in [('useV2',True),('deepWindow',False)]:
        value=r.get(key)
        if value is not None and type(value) is not bool:raise ValueError('Recipe options must be boolean or null.')
        result[key]=default if value is None else value
    if r.get('rrIdentity') is not None:
        if r['rrIdentity']!='store-key-v1':raise ValueError('Unknown R-R identity contract.')
        result['rrIdentity']=r['rrIdentity']
    return result
def check_report(p):
    if p.get('schema')!=1 or p.get('model')!='nroop-lab-v1' or p.get('origin') not in {'recorded','synthetic'} or p.get('research',{}).get('version')!=VERSION:
        raise ValueError('Need a versioned research replay report.')
    if not checksum(p.get('inputSHA256')) or not checksum(p.get('ownerHash')) or type(p.get('dayStart')) is not int:
        raise ValueError('Missing report identity/provenance.')

def attach_history(recording,reports):
    r=copy.deepcopy(recording)
    if r.get('origin') not in {'recorded','synthetic'} or not isinstance(r.get('owner'),str):raise ValueError('Missing recording provenance.')
    owner=digest(r['owner'].encode());by_day={};seen=set()
    for n in r.get('history',[]):
        if n['dayStart'] in by_day:raise ValueError('Duplicate history date.')
        by_day[n['dayStart']]=n
    for p in reports:
        check_report(p);day=p['dayStart'];research=p['research']
        if p['ownerHash']!=owner or p['origin']!=r['origin'] or day>=r['dayStart'] or day not in by_day or day in seen or research.get('recipe')!=recipe(r):
            raise ValueError('Historical report must match one distinct prior owner/date/origin/recipe.')
        seen.add(day);n=by_day[day];obs=research['observation'];q=research['quality']
        if any(obs.get(k)!=n.get(k) for k in ['hrv','rhr']):
            raise ValueError('Historical computed values differ from replay; quality cannot be transferred.')
        if any(not finite(q.get(k)) or not 0<=q[k]<=1 for k in ['hrv','rhr']):raise ValueError('Invalid historical quality.')
        if 'evidence' in n:raise ValueError('Existing historical evidence must not be silently replaced.')
        n['evidence']={'version':VERSION,'origin':p['origin'],'ownerHash':owner,'inputSHA256':p['inputSHA256'],
            'dayStart':day,**research['recipe'],'hrv':obs.get('hrv'),'rhr':obs.get('rhr'),'hrvQuality':q['hrv'],'rhrQuality':q['rhr']}
    return r

def perturbations(recording):
    variants={}
    for name in ['identity','reversed','duplicated','dropout-300s','shift-1s','hr-plus-3']:
        r=copy.deepcopy(recording)
        # Derived cases are never eligible as recorded independent accuracy observations.
        r['origin']='synthetic';r['caseID']=str(r.get('caseID',''))[:150]+'-stress-'+name
        for n in r.get('history',[]):
            if n.get('evidence'):n['evidence']['origin']='synthetic'
        if name=='reversed':
            for s in STREAMS:r[s]=list(reversed(r.get(s,[])))
        elif name=='duplicated':
            for s in STREAMS:r[s]=r.get(s,[])*2
        elif name=='dropout-300s':
            start=min((x['ts'] for x in r.get('hr',[]) if x['ts']>=r['dayStart']),default=r['dayStart'])
            for s in STREAMS:r[s]=[x for x in r.get(s,[]) if not start<=x['ts']<start+300]
        elif name=='shift-1s':
            for s in STREAMS:
                r[s]=[{**x,'ts':x['ts']+1} for x in r.get(s,[]) if x['ts']+1<=r['now']]
        elif name=='hr-plus-3':
            r['hr']=[{**x,'bpm':x['bpm']+3 if x['bpm']>0 else x['bpm']} for x in r.get('hr',[])]
        variants[name]=r
    return variants

def metrics_of(report):
    m=dict(report.get('metrics',{}))
    b=report.get('research',{}).get('baselineComparison')
    if b is not None:m['baseline_recovery']=b
    return m

def compare_reports(base,other):
    a=metrics_of(base);b=metrics_of(other);out={}
    for key in sorted(set(a)|set(b)):
        left=a.get(key,{});right=b.get(key,{})
        if left.get('unit')!=right.get('unit'):raise ValueError('Metric unit mismatch.')
        row={'unit':left.get('unit')}
        for side in ['original','candidate']:
            x=left.get(side);y=right.get(side)
            if any(v is not None and not finite(v) for v in [x,y]):raise ValueError('Nonfinite comparison.')
            row[side+'Delta']=y-x if x is not None and y is not None else None
            row[side+'Availability']='matched' if x is not None and y is not None else 'lost' if x is not None else 'gained' if y is not None else 'missing-both'
        for side in ['original','candidate']:
            x=base.get('research',{}).get('bands',{}).get(key,{}).get(side)
            y=other.get('research',{}).get('bands',{}).get(key,{}).get(side)
            row[side+'BandChange']={'from':x,'to':y,'changed':x!=y} if x is not None and y is not None else None
        row['originalStatus']=left.get('status');row['variantStatus']=right.get('status');out[key]=row
    return out

def page(title,body):
    return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>'+html.escape(title)+'</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:20px;background:#101719;color:#e6f1ee}p{line-height:1.6}table{border-collapse:collapse;width:100%;margin:24px 0}td,th{padding:10px;text-align:left;border-bottom:1px solid #3b4b48}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style><h1>'+html.escape(title)+'</h1>'+body+'</html>'
def render_explanation(report):
    check_report(report)
    x=report['research'].get('explanation')
    if x is None:return page('NROOP recovery explanation','<p>No replay recovery explanation: essential current data are missing.</p>')
    rows=''.join('<tr>'+''.join('<td>'+html.escape(str(t.get(k)))+'</td>' for k in ['name','z','normalizedWeight','contributionZ'])+'</tr>' for t in x.get('terms',[]))
    return page('NROOP recovery explanation','<p>Case: '+html.escape(str(report.get('caseID')))+'. Scope: five-driver recovery with strictly prior computed baselines. This explains the local replay, not the app final score or physiological causes.</p><p>Score: '+html.escape(str(x.get('score','unavailable')))+'. Status: '+html.escape(x.get('status','unknown'))+'</p><table><tr><th>Term</th><th>z</th><th>Normalized weight</th><th>Contribution in z</th></tr>'+rows+'</table><p>Contributions add in composite z space, not nonlinear score points. Missing terms: '+html.escape(', '.join(x.get('missing',[])))+'</p><h2>Personal references</h2><pre>'+html.escape(json.dumps(x.get('baselines',{}),indent=2,allow_nan=False))+'</pre>')

def run_sensitivity(recording_path,replay,output,timeout=60):
    p=Path(recording_path).resolve();binary=Path(replay).resolve();out=Path(output).resolve()
    if out.exists():raise ValueError('Sensitivity output must be a new directory.')
    if not binary.is_file():raise ValueError('Replay executable missing.')
    raw=p.read_bytes()
    if len(raw)>512*1024**2:raise ValueError('Recording exceeds 512 MiB.')
    recording=json.loads(raw);out.mkdir(parents=True)
    def run(src,dst):
        try:result=subprocess.run([str(binary),str(src),str(dst)],capture_output=True,text=True,timeout=timeout)
        except (subprocess.TimeoutExpired,OSError) as e:raise ValueError('Replay failed or timed out; no valid sensitivity result.') from e
        if result.returncode!=0:raise ValueError('Replay rejected a case: '+result.stderr[:1000])
        r=load(dst);check_report(r);return r
    base=run(p,out/'baseline-report.json')
    summary={'version':VERSION,'kind':'sensitivity-not-accuracy','sourceSHA256':digest(raw),'executableSHA256':digest(binary.read_bytes()),
        'interpretation':'Input perturbation response, not accuracy. Deltas only on matched available values; missing is not zero. Ordering and duplicate rows can expose timestamp or cleaner sensitivity; no physiological improvement is implied.', 'variants':{}}
    for name,r in perturbations(recording).items():
        src=out/(name+'.json');dst=out/(name+'-report.json');save_new(src,r)
        try:
            report=run(src,dst)
            summary['variants'][name]={'status':'complete','inputSHA256':report['inputSHA256'],'comparison':compare_reports(base,report)}
        except ValueError as error:
            # Never clip sensor values to manufacture a valid stress case. Preserve other audit results.
            summary['variants'][name]={'status':'rejected','inputSHA256':digest(src.read_bytes()),'comparison':{},'error':str(error)}
    summary['rejectedVariants']=sum(v['status']=='rejected' for v in summary['variants'].values())
    save_new(out/'sensitivity.json',summary)
    def band_text(value): return 'unavailable' if value is None else value['from']+' → '+value['to']
    rows=''.join('<tr><td>'+html.escape(name)+'</td><td>'+html.escape(metric)+'</td><td>'+html.escape(str(v['originalDelta']))+'</td><td>'+html.escape(str(v['candidateDelta']))+'</td><td>'+html.escape(v['candidateAvailability'])+'</td><td>'+html.escape(band_text(v['originalBandChange']))+'</td><td>'+html.escape(band_text(v['candidateBandChange']))+'</td></tr>' for name,x in summary['variants'].items() for metric,v in x['comparison'].items())
    failures=''.join('<p>Variant '+html.escape(name)+' rejected: '+html.escape(v['error'])+'</p>' for name,v in summary['variants'].items() if v['status']=='rejected')
    (out/'sensitivity.html').write_text(page('NROOP input sensitivity',failures+'<p>'+html.escape(summary['interpretation'])+'</p><table><tr><th>Variant</th><th>Metric</th><th>Original delta</th><th>Candidate delta</th><th>Candidate availability</th><th>Original band</th><th>Candidate band</th></tr>'+rows+'</table>'),encoding='utf-8')
    (out/'recovery-explanation.html').write_text(render_explanation(base),encoding='utf-8')
    if p.read_bytes()!=raw:raise ValueError('Source changed during replay; result invalid.')
    return summary

def civil_fragments(start,end,itinerary):
    if type(start) is not int or type(end) is not int or not 946684800<=start<end<=4102444800 or end-start>4*86400:
        raise ValueError('Civil audit needs a bounded UTC window of at most four days.')
    if not 1<=len(itinerary)<=32:raise ValueError('Declare one zone or at most 32 contiguous itinerary intervals.')
    intervals=[];cursor=start
    for row in itinerary:
        if type(row.get('start')) is not int or type(row.get('end')) is not int or row['start']!=cursor or not cursor<row['end']<=end:
            raise ValueError('Itinerary must exactly cover the window without gaps or overlaps, in UTC order.')
        try:z=ZoneInfo(row['zone'])
        except (KeyError,ValueError,ZoneInfoNotFoundError) as e:raise ValueError('Unknown explicit IANA zone.') from e
        intervals.append((cursor,row['end'],row['zone'],z));cursor=row['end']
    if cursor!=end:raise ValueError('Itinerary must cover the full UTC window.')
    fragments=[]
    # Each UTC second is visited once. This also handles midnight transitions and skipped civil dates.
    for lo,hi,name,z in intervals:
        for ts in range(lo,hi):
            date=datetime.fromtimestamp(ts,z).date().isoformat()
            if fragments and fragments[-1]['zone']==name and fragments[-1]['date']==date and fragments[-1]['end']==ts:
                fragments[-1]['end']=ts+1;fragments[-1]['seconds']+=1
            else:fragments.append({'start':ts,'end':ts+1,'zone':name,'date':date,'seconds':1})
    return fragments

def calendar_ledger(recording,itinerary,report=None):
    r=recording;start=r['dayStart']-108000;end=r['now'];fragments=civil_fragments(start,end,itinerary)
    for f in fragments:f['observedHRSeconds']=0
    starts=[f['start'] for f in fragments];values={};boundary=0
    for h in r.get('hr',[]):
        ts=h['ts'];bpm=h['bpm']
        if type(ts) is not int or type(bpm) is not int or not start<=ts<=end or not 0<=bpm<=300:raise ValueError('Invalid/out-of-window HR sample.')
        if ts==end:boundary+=1;continue
        if bpm>0:values.setdefault(ts,set()).add(bpm)
    conflict=0
    for ts,v in values.items():
        if len(v)!=1:conflict+=1;continue
        fragments[bisect.bisect_right(starts,ts)-1]['observedHRSeconds']+=1
    sessions=[]
    if report is not None:
        check_report(report)
        if report['ownerHash']!=digest(r['owner'].encode()) or report['dayStart']!=r['dayStart']:raise ValueError('Calendar report owner/day mismatch.')
        for s in report['research'].get('sessions',[]):
            a=s['start'];b=s['end']
            if type(a) is not int or type(b) is not int or not start<=a<b<=end:raise ValueError('Session outside audited UTC window.')
            f=fragments[bisect.bisect_right(starts,b-1)-1]
            sessions.append({'start':a,'end':b,'seconds':b-a,'wakeDate':f['date'],'wakeZone':f['zone']})
    return {'version':VERSION,'kind':'civil-attribution-only','start':start,'end':end,'elapsedSeconds':end-start,
        'interpretation':'Explicit zone history only. Each absolute second belongs to one fragment; repeated civil dates remain separate fragments. Wake date uses end-1. Physiological replay remains fixed-offset and stored days are not changed.',
        'fragments':fragments,'sessions':sessions,'conflictingHRSeconds':conflict,'endBoundaryRows':boundary}

def main():
    p=argparse.ArgumentParser(description=__doc__);subs=p.add_subparsers(dest='command',required=True)
    a=subs.add_parser('attach-history');a.add_argument('recording',type=Path);a.add_argument('reports',type=Path,nargs='+');a.add_argument('--output',type=Path,required=True)
    a=subs.add_parser('sensitivity');a.add_argument('recording',type=Path);a.add_argument('--replay',type=Path,required=True);a.add_argument('--output',type=Path,required=True)
    a=subs.add_parser('calendar');a.add_argument('recording',type=Path);z=a.add_mutually_exclusive_group(required=True);z.add_argument('--zone');z.add_argument('--itinerary',type=Path);a.add_argument('--report',type=Path);a.add_argument('--output',type=Path,required=True)
    a=subs.add_parser('explain');a.add_argument('report',type=Path);a.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    try:
        if args.command=='sensitivity':run_sensitivity(args.recording,args.replay,args.output)
        elif args.command=='attach-history':save_new(args.output,attach_history(load(args.recording),[load(f) for f in args.reports]))
        elif args.command=='calendar':
            r=load(args.recording);itinerary=load(args.itinerary) if args.itinerary else [{'start':r['dayStart']-108000,'end':r['now'],'zone':args.zone}]
            report=load(args.report) if args.report else None
            if report is not None and report.get('inputSHA256')!=digest(args.recording.read_bytes()):raise ValueError('Calendar report checksum does not match this recording.')
            result=calendar_ledger(r,itinerary,report);result['inputSHA256']=digest(args.recording.read_bytes());save_new(args.output,result)
        else:
            text=render_explanation(load(args.report))
            with args.output.open('x',encoding='utf-8') as f:f.write(text)
        print('Completed locally. No source recording, stored baseline or app score modified.')
    except (OSError,ValueError,KeyError,TypeError) as e:p.exit(2,'Error: '+str(e)+'\n')

if __name__=='__main__':main()
