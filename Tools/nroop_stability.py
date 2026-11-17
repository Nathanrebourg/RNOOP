#!/usr/bin/env python3
"""Read-only progressive synchronization simulation using the actual Swift replay executable."""
from __future__ import annotations
import argparse,copy,json,subprocess
from pathlib import Path
from nroop_research import STREAMS,check_report,compare_reports,digest,load,page,save_new
import html

VERSION='nroop-sync-audit-v1'
def captured_span(recording):
    allowed=recording['dayStart']-108000;now=recording['now']
    timestamps=[row['ts'] for stream in STREAMS for row in recording.get(stream,[])]
    if any(type(ts) is not int or not allowed<=ts<=now for ts in timestamps):raise ValueError('Captured timestamp outside replay window.')
    return (min(timestamps),max(timestamps)+1) if timestamps else (recording['dayStart'],now)

def progressive_input(recording,fraction,direction):
    if type(fraction) not in (int,float) or not 0<fraction<=1 or direction not in {'oldest-first','newest-first'}:
        raise ValueError('Declare a fraction in (0,1] and oldest/newest-first direction.')
    r=copy.deepcopy(recording);start,end=captured_span(r)
    if type(start) is not int or type(end) is not int or not 0<end-start<=194401:raise ValueError('Invalid replay UTC window.')
    span=int((end-start)*fraction)
    for stream in STREAMS:
        rows=r.get(stream,[])
        if fraction<1:
            r[stream]=[x for x in rows if (start<=x['ts']<start+span if direction=='oldest-first' else end-span<=x['ts']<=end)]
    r['origin']='synthetic';r['caseID']=str(r.get('caseID',''))[:130]+f'-sync-{direction}-{int(fraction*100)}'
    for night in r.get('history',[]):
        if night.get('evidence'):night['evidence']['origin']='synthetic'
    return r

def sync_audit(recording_path,replay,output,timeout=60):
    p=Path(recording_path).resolve();binary=Path(replay).resolve();out=Path(output).resolve()
    if out.exists():raise ValueError('Choose a new synchronization output directory.')
    if not binary.is_file():raise ValueError('Actual replay executable missing.')
    raw=p.read_bytes()
    if len(raw)>512*1024**2:raise ValueError('Recording exceeds512MiB.')
    r=json.loads(raw);out.mkdir(parents=True)
    # Snapshot the input: a concurrent writer cannot change the baseline being replayed.
    reference=out/'reference-input.json';reference.write_bytes(raw)
    def run(src,dst):
        try:result=subprocess.run([str(binary),str(src),str(dst)],capture_output=True,text=True,timeout=timeout)
        except (OSError,subprocess.TimeoutExpired) as error:raise ValueError('Replay unavailable or timed out.') from error
        if result.returncode:raise ValueError('Replay rejected input: '+result.stderr[:1000])
        report=load(dst);check_report(report);return report
    base=run(reference,out/'reference-report.json');steps=[]
    for direction in ['oldest-first','newest-first']:
        for fraction in [.25,.5,.75,1.0]:
            variant=progressive_input(r,fraction,direction);name=f'{direction}-{int(fraction*100)}'
            src=out/(name+'.json');save_new(src,variant)
            step={'direction':direction,'fraction':fraction,'state':'provisional' if fraction<1 else 'available-input-reference',
                'strapCollectionComplete':None,'rows':{s:len(variant.get(s,[])) for s in STREAMS}}
            try:
                report=run(src,out/(name+'-report.json'))
                step.update(status='complete',comparison=compare_reports(base,report),quality=report['research']['quality'],inputSHA256=report['inputSHA256'])
            except ValueError as error:step.update(status='rejected',comparison={},error=str(error))
            steps.append(step)
    summary={'version':VERSION,'kind':'simulated-arrival-not-accuracy','sourceSHA256':digest(raw),'executableSHA256':digest(binary.read_bytes()),
        'capturedStart':captured_span(r)[0],'capturedEndExclusive':captured_span(r)[1],
        'interpretation':'Fixed now and historical baselines. Percentages describe the first-to-last captured timestamp span (or declared day if empty), not actual packet arrival or completed strap collection. Partial results are provisional;100% is only the available-input reference.', 'steps':steps}
    save_new(out/'synchronization.json',summary)
    rows=''.join('<tr><td>'+html.escape(s['direction'])+'</td><td>'+str(int(s['fraction']*100))+'%</td><td>'+html.escape(s['state'])+'</td><td>'+html.escape(name)+'</td><td>'+html.escape(str(v['originalDelta']))+'</td><td>'+html.escape(str(v['candidateDelta']))+'</td><td>'+html.escape(v['candidateAvailability'])+'</td></tr>' for s in steps for name,v in s['comparison'].items())
    errors=''.join('<p>'+html.escape(s['direction']+': '+s.get('error',''))+'</p>' for s in steps if s['status']=='rejected')
    (out/'synchronization.html').write_text(page('NROOP progressive synchronization', '<p>'+html.escape(summary['interpretation'])+'</p>'+errors+'<table><tr><th>Simulated order</th><th>Span</th><th>State</th><th>Metric</th><th>Original delta</th><th>Candidate delta</th><th>Availability</th></tr>'+rows+'</table>'),encoding='utf-8')
    if p.read_bytes()!=raw:raise ValueError('Source changed during audit; use the isolated snapshot and rerun.')
    return summary

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('recording',type=Path);p.add_argument('--replay',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    try:sync_audit(a.recording,a.replay,a.output);print('Completed locally; provisional simulations do not certify final strap collection.')
    except (OSError,ValueError,KeyError,TypeError) as error:p.exit(2,'Error: '+str(error)+'\n')
if __name__=='__main__':main()
