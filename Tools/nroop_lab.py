#!/usr/bin/env python3
"""Local NROOP lab: read-only WHOOP 5 backup conversion, synthetic example and held-out report evaluation.
The Swift replay executable performs all physiological calculations. This module never reimplements them.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import html
import json
import math
import shutil
import sqlite3
import statistics
import tempfile
import zipfile
from contextlib import contextmanager
from datetime import date, datetime, timezone
from pathlib import Path

NATURAL = 'Did you wake naturally without an alarm or obligation?'
RESTED = 'Did you wake feeling rested?'
DISRUPTED = 'Was your sleep disrupted by an external event?'
RANGES = {'recovery': (0, 100), 'hrmax': (30, 250), 'sleep_need': (3, 12)}
UNITS = {'recovery': 'points/100', 'hrmax': 'bpm', 'sleep_need': 'hours'}

def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)

@contextmanager
def database(path):
    path = Path(path)
    with tempfile.TemporaryDirectory(prefix='nroop-lab-') as temp:
        if path.suffix.lower() in {'.noopbak', '.zip'}:
            with zipfile.ZipFile(path) as z:
                matches = [x for x in z.infolist() if x.filename == 'noop-backup.sqlite']
                if len(matches) != 1 or matches[0].file_size > 2 * 1024**3:
                    raise ValueError('Backup needs one noop-backup.sqlite entry, at most 2 GiB.')
                local = Path(temp) / 'snapshot.sqlite'
                with z.open(matches[0]) as src, local.open('wb') as dst:
                    shutil.copyfileobj(src, dst)
        else:
            local = path.resolve()
            wal = Path(str(local) + '-wal')
            if wal.exists() and wal.stat().st_size:
                raise ValueError('Use a checkpointed backup, not a live database with pending WAL data.')
        conn = sqlite3.connect(local.as_uri() + '?mode=ro&immutable=1', uri=True)
        conn.row_factory = sqlite3.Row
        try:
            conn.execute('PRAGMA query_only=ON')
            conn.execute('PRAGMA trusted_schema=OFF')
            yield conn
        finally:
            conn.close()

def convert(path, *, owner, day, offset, age, case_id, manual=None, deep=False, v2=True, computed_id=None):
    if not owner or not case_id or not finite(age) or not 0 <= age <= 120 or abs(offset) > 50400:
        raise ValueError('Explicit owner, case ID, age and valid fixed UTC offset are required.')
    d = date.fromisoformat(day)
    start = int(datetime(d.year,d.month,d.day,tzinfo=timezone.utc).timestamp()) - offset
    if not 946684800 <= start <= 4102444800: raise ValueError('Unsupported day.')
    warnings = []
    with database(path) as c:
        tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {'hrSample','gravitySample'}.issubset(tables): raise ValueError('Missing raw HR/gravity tables.')
        def columns(table): return {r[1] for r in c.execute(f'PRAGMA table_info("{table}")')}
        def read(table, fields, owner_id, lo, hi, cap):
            if table not in tables: return []
            rows = c.execute(f'SELECT {fields} FROM "{table}" WHERE deviceId=? AND ts>=? AND ts<? ORDER BY ts LIMIT ?',
                             (owner_id,lo,hi,cap)).fetchall()
            if len(rows) >= cap: raise ValueError(f'{table} reached read cap; no clipped recording produced.')
            result = [dict(r) for r in rows]
            for row in result:
                if type(row['ts']) is not int: raise ValueError(f'{table}: invalid timestamp.')
                if table == 'hrSample' and (type(row['bpm']) is not int or not 0 <= row['bpm'] <= 300):
                    raise ValueError('Corrupt BPM domain; recording rejected without clipping.')
                if table == 'gravitySample' and any(not finite(row[a]) or abs(row[a]) > 1_000_000 for a in ['x','y','z']):
                    raise ValueError('Corrupt gravity domain; recording rejected without clipping.')
            return result
        lo = start - 108000; end = start + 86400
        hr = read('hrSample','ts,bpm',owner,lo,end,300000)
        gravity = read('gravitySample','ts,x,y,z',owner,lo,end,300000)
        if not hr: raise ValueError('No heart rate for this owner/day window.')
        rr = []
        if 'rrInterval' in tables and {'srcChannel','tsSuspect','ord','seq'}.issubset(columns('rrInterval')):
            # Same strict WHOOP 5 single-transport policy as WhoopStore.Reads. Never convert legacy units.
            channel = c.execute('''SELECT MIN(srcChannel) FROM rrInterval WHERE deviceId=? AND ts>=? AND ts<?
                AND srcChannel IN (5,7) AND (tsSuspect IS NULL OR tsSuspect<>1)''',(owner,lo,end)).fetchone()[0]
            if channel is not None:
                rr = [dict(r) for r in c.execute('''SELECT ts,rrMs,srcChannel,ord,seq FROM rrInterval
                    WHERE deviceId=? AND ts>=? AND ts<? AND srcChannel=? AND (tsSuspect IS NULL OR tsSuspect<>1)
                    ORDER BY ts,ord,rrMs,seq LIMIT 600000''',(owner,lo,end,channel))]
                if len(rr) >= 600000: raise ValueError('R-R read reached cap.')
                if any(type(r['rrMs']) is not int or not 0 <= r['rrMs'] <= 65535 for r in rr):
                    raise ValueError('Corrupt R-R domain; recording rejected without clipping.')
            else: warnings.append('No labelled WHOOP 5 R-R transport; legacy R-R withheld.')
        else: warnings.append('R-R provenance schema unavailable; R-R withheld.')
        events = read('event','ts,kind',owner,lo,end,50000)
        band = read('sleepStateSample','ts,state',owner,lo,end,300000)
        history = []
        if 'dailyMetric' in tables:
            cols = columns('dailyMetric')
            fields = ['day','totalSleepMin','avgHrv','restingHr','respRateBpm']
            select = ','.join(f'"{f}"' if f in cols else f'NULL AS "{f}"' for f in fields)
            first = date.fromordinal(d.toordinal()-30).isoformat()
            rows = c.execute(f'SELECT {select} FROM dailyMetric WHERE deviceId=? AND day>=? AND day<? ORDER BY day',
                             (computed_id or owner+'-noop',first,day)).fetchall()
            answers = {}
            if 'journal' in tables:
                for a in c.execute('SELECT day,question,answeredYes FROM journal WHERE deviceId=? AND day>=? AND day<?',
                                   ('noop-journal',first,day)):
                    if a['answeredYes'] not in (0,1): continue
                    key=(a['day'],a['question']); value=bool(a['answeredYes'])
                    if key in answers and answers[key] != value: answers[key]=None
                    else: answers.setdefault(key,value)
            seen=set()
            for row in rows:
                if row['day'] in seen: raise ValueError('Duplicate computed history day.')
                seen.add(row['day'])
                prior=date.fromisoformat(row['day'])
                n={'dayStart':int(datetime(prior.year,prior.month,prior.day,tzinfo=timezone.utc).timestamp())-offset,'source':'computed'}
                for key,col in [('hrv','avgHrv'),('rhr','restingHr'),('resp','respRateBpm')]:
                    if row[col] is not None: n[key]=row[col]
                if row['totalSleepMin'] is not None: n['hours']=row['totalSleepMin']/60
                for key,q in [('naturalWake',NATURAL),('rested',RESTED),('disrupted',DISRUPTED)]:
                    value=answers.get((row['day'],q))
                    if value is not None: n[key]=value
                history.append(n)
        streams=[]
        for back in range(1,8):
            prior=start-back*86400
            h=read('hrSample','ts,bpm',owner,prior,prior+86400,100000)
            g=read('gravitySample','ts,x,y,z',owner,prior,prior+86400,100000)
            if h or g: streams.append({'owner':owner,'dayStart':prior,'hr':h,'gravity':g})
    result={'rrIdentity':'store-key-v1','schema':1,'origin':'recorded','caseID':case_id,'owner':owner,'dayStart':start,'now':end,
            'offset':offset,'age':age,'useV2':v2,'deepWindow':deep,'hr':hr,'gravity':gravity,'rr':rr,
            'events':events,'band':band,'history':history,'historyStreams':streams,'warnings':warnings}
    if manual is not None: result['manualHRmax']=manual
    # Reject nonfinite SQLite values before emitting invalid or misleading JSON.
    json.dumps(result,allow_nan=False)
    return result

def read_references(path):
    result={}
    with Path(path).open(encoding='utf-8-sig',newline='') as f:
        for row in csv.DictReader(f):
            key=(row.get('caseID',''),row.get('metric',''))
            source=row.get('source','')
            if not key[0] or key[1] not in RANGES or source not in {'whoop','diary','measured'}:
                raise ValueError('Reference needs caseID, known metric and independent source (whoop/diary/measured).')
            if key in result: raise ValueError('Duplicate reference case/metric.')
            value=float(row['value']);lo,hi=RANGES[key[1]]
            if not finite(value) or not lo<=value<=hi: raise ValueError('Invalid reference value.')
            independent=row.get('independent','').lower()
            split=row.get('split','')
            if independent not in {'true','false'} or split not in {'training','holdout'}:
                raise ValueError('Explicit independent=true/false and split=training/holdout are required.')
            result[key]={'value':value,'source':source,'independent':independent=='true','split':split}
    return result

def evaluate(reports,references):
    seen=set();case_ids=set();hashes=set();samples={};cases=[];unavailable=0;synthetic=0;training=0
    for r in reports:
        if r.get('schema')!=1 or r.get('model')!='nroop-lab-v1' or r.get('origin') not in {'synthetic','recorded'}:
            raise ValueError('Unknown replay schema/model/origin.')
        case=r.get('caseID');owner=r.get('ownerHash');day=r.get('dayStart');digest=r.get('inputSHA256','')
        if not case or not owner or type(day) is not int or len(digest)!=64 or any(x not in '0123456789abcdef' for x in digest):
            raise ValueError('Missing case identity or input checksum.')
        if (owner,day) in seen or case in case_ids or digest in hashes: raise ValueError('Duplicate case, recording or owner/day.')
        seen.add((owner,day));case_ids.add(case);hashes.add(digest)
        cases.append({'caseID':case,'origin':r['origin'],'dayStart':day,'metrics':r.get('metrics',{}),'inputSHA256':digest})
        if r['origin']=='synthetic': synthetic+=1
        for metric,value in r.get('metrics',{}).items():
            if metric not in RANGES or not isinstance(value,dict): raise ValueError('Unknown metric.')
            if value.get('unit') != UNITS[metric]: raise ValueError('Unsupported or mixed metric units.')
            lo,hi=RANGES[metric]
            for v in [value.get('original'),value.get('candidate')]:
                if v is not None and (not finite(v) or not lo<=v<=hi): raise ValueError('Nonfinite/out-of-range score.')
            ref=references.get((case,metric))
            if ref is None: continue
            if ref.get('source') not in {'whoop','diary','measured'} or not finite(ref.get('value')):
                raise ValueError('Invalid independent reference.')
            if r['origin']!='recorded' or ref.get('independent') is not True: continue
            if ref.get('split')!='holdout': training+=1;continue
            if value.get('original') is None or value.get('candidate') is None: unavailable+=1;continue
            a=value['original']-ref['value'];b=value['candidate']-ref['value']
            samples.setdefault(metric,[]).append((a,b))
    metrics={}
    for name,errors in samples.items():
        metrics[name]={'n':len(errors),'original_mae':statistics.mean(abs(a) for a,b in errors),
                       'candidate_mae':statistics.mean(abs(b) for a,b in errors),
                       'original_bias':statistics.mean(a for a,b in errors),'candidate_bias':statistics.mean(b for a,b in errors)}
    return {'model':'nroop-lab-v1','interpretation':'External-reference agreement only; not clinical validation.',
            'metrics':metrics,'cases':cases,'unavailable':unavailable,'synthetic_excluded':synthetic,'training_excluded':training}

def render_html(summary):
    rows=''.join('<tr><td>'+html.escape(name+' ('+UNITS[name]+')')+'</td>'+''.join('<td>'+html.escape(str(stats[k]))+'</td>'
                 for k in ['n','original_mae','candidate_mae','original_bias','candidate_bias'])+'</tr>'
                 for name,stats in summary['metrics'].items())
    cases=''.join('<tr><td>'+html.escape(str(c['caseID']))+'</td><td>'+html.escape(c['origin'])+'</td></tr>' for c in summary['cases'])
    details=''.join('<tr><td>'+html.escape(str(c['caseID']))+'</td><td>'+html.escape(c['origin'])+'</td><td>'+html.escape(name+' ('+UNITS[name]+')')+
        '</td><td>'+html.escape(str(v.get('original','nil')))+'</td><td>'+html.escape(str(v.get('candidate','nil')))+
        '</td><td>'+html.escape(str(v.get('status','unknown')))+'</td></tr>'
        for c in summary['cases'] for name,v in c['metrics'].items())
    return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>NROOP local algorithm evaluation</title><style>body{font:16px system-ui;max-width:1000px;margin:40px auto;padding:20px;background:#101719;color:#e6f1ee}table{width:100%;border-collapse:collapse;margin:24px 0}td,th{padding:12px;text-align:left;border-bottom:1px solid #3b4b48}p{line-height:1.6;color:#b9ceca}</style>
<h1>NROOP local algorithm evaluation</h1><p>'''+html.escape(summary['interpretation'])+''' Only recorded cases with an explicitly independent held-out reference contribute to the same matched comparison.</p>
<table><tr><th>Metric</th><th>Matched n</th><th>Original MAE</th><th>Candidate MAE</th><th>Original bias</th><th>Candidate bias</th></tr>'''+rows+'''</table><p>'''+html.escape(f"Synthetic excluded: {summary['synthetic_excluded']}; training references excluded: {summary['training_excluded']}; unavailable comparisons: {summary['unavailable']}.")+''' An empty table means no eligible comparison, not zero error. References such as WHOOP scores are comparators, not ground truth.</p><table><tr><th>Case</th><th>Origin</th></tr>'''+cases+'</table><h2>Descriptive case results</h2><p>Synthetic results are visible here for inspection and never contribute to recorded-reference agreement.</p><table><tr><th>Case</th><th>Origin</th><th>Metric</th><th>Original</th><th>Candidate</th><th>Status</th></tr>'+details+'</table></html>'

def example():
    day=1728000000;owner='synthetic-example'
    hr=[{'ts':day+i,'bpm':60 if i<21600 else 70} for i in range(36000)]
    gravity=[{'ts':day+i,'x':0 if i<21600 else (0.5 if i%2==0 else 0),'y':0,'z':1} for i in range(36000)]
    rr=[{'ts':day+i,'rrMs':980 if i%2==0 else 1020,'srcChannel':5,'seq':0} for i in range(21600)]
    history=[{'dayStart':day-back*86400,'source':'computed','hours':9 if back<=7 else 6.5,'hrv':60,'rhr':55,'resp':14,
              'naturalWake':back<=7,'rested':back<=7,'disrupted':False} for back in range(1,31)]
    streams=[{'owner':owner,'dayStart':day-back*86400,'hr':[{'ts':day-back*86400+i,'bpm':200} for i in range(120)],
              'gravity':[{'ts':day-back*86400+i,'x':0.5 if i%2==0 else 0,'y':0,'z':1} for i in range(120)]} for back in range(1,4)]
    return {'rrIdentity':'store-key-v1','schema':1,'origin':'synthetic','caseID':'example-synthetic','owner':owner,'dayStart':day,'now':day+36000,
            'offset':0,'age':30,'hr':hr,'gravity':gravity,'rr':rr,'events':[],'band':[],'history':history,'historyStreams':streams}

def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('inspect');p.add_argument('backup',type=Path)
    p=sub.add_parser('capture');p.add_argument('backup',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--owner',required=True);p.add_argument('--day',required=True);p.add_argument('--offset',required=True,type=int)
    p.add_argument('--age',required=True,type=float);p.add_argument('--case-id',required=True);p.add_argument('--manual-hrmax',type=float)
    p.add_argument('--computed-id');p.add_argument('--deep-window',action='store_true');p.add_argument('--v1',action='store_true')
    p=sub.add_parser('example');p.add_argument('output',type=Path)
    p=sub.add_parser('evaluate');p.add_argument('reports',type=Path,nargs='+');p.add_argument('--references',type=Path)
    p.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        if args.command=='inspect':
            with database(args.backup) as c:
                tables={r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if 'hrSample' not in tables: raise ValueError('Missing raw HR table.')
                owners=[dict(r) for r in c.execute('SELECT deviceId AS owner,COUNT(*) AS rows,MIN(ts) AS firstTs,MAX(ts) AS lastTs FROM hrSample GROUP BY deviceId LIMIT 1000')]
                namespaces=[r[0] for r in c.execute('SELECT DISTINCT deviceId FROM dailyMetric LIMIT 1000')] if 'dailyMetric' in tables else []
                print(json.dumps({'rawOwners':owners,'dailyNamespaces':namespaces},indent=2))
        elif args.command=='capture':
            if args.backup.resolve()==args.output.resolve(): raise ValueError('Output must not overwrite source backup.')
            result=convert(args.backup,owner=args.owner,day=args.day,offset=args.offset,age=args.age,case_id=args.case_id,
                           manual=args.manual_hrmax,deep=args.deep_window,v2=not args.v1,computed_id=args.computed_id)
            args.output.write_text(json.dumps(result,allow_nan=False,separators=(',',':')),encoding='utf-8')
        elif args.command=='example':args.output.write_text(json.dumps(example(),allow_nan=False,separators=(',',':')),encoding='utf-8')
        else:
            refs=read_references(args.references) if args.references else {}
            result=evaluate([json.loads(p.read_text(encoding='utf-8')) for p in args.reports],refs)
            args.output.mkdir(parents=True,exist_ok=True)
            (args.output/'evaluation.json').write_text(json.dumps(result,allow_nan=False,indent=2),encoding='utf-8')
            (args.output/'evaluation.html').write_text(render_html(result),encoding='utf-8')
        print('Completed locally; no data uploaded and no source score modified.')
    except (OSError,ValueError,KeyError,sqlite3.Error,zipfile.BadZipFile) as e:parser.exit(2,f'Error: {e}\n')

if __name__=='__main__':main()
