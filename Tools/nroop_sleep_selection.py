#!/usr/bin/env python3
"""Frozen training-only sleep recipe selection, then separate-participant EEG evaluation.
Runs existing native stagers. No physiological model is implemented in Python.
"""
from __future__ import annotations
import argparse,hashlib,html,json,statistics,subprocess
from pathlib import Path
from nroop_lab import finite
from nroop_research import checksum,digest,load,page,save_new
from nroop_confidence import fit_calibration,evaluate_calibration

VARIANTS=['shipped','awake-014','awake-020','awake-026','rem-018','rem-016','awake020-rem018']
VERSION='nroop-sleep-selection-v1'
def validate_reports(reports,split):
    seen=set();inputs=set()
    for r in reports:
        if r.get('version')!=VERSION or r.get('dataset')!='bidsleep-1.0.1' or r.get('reference')!='dreem2-expert' or r.get('origin')!='recorded' or r.get('split')!=split:
            raise ValueError('Explicit recorded BIDSleep reference and split required.')
        key=(r.get('subject'),r.get('night'));h=r.get('inputSHA256')
        if not all(key) or not checksum(h) or key in seen or h in inputs:raise ValueError('Duplicate/missing subject-night/input identity.')
        seen.add(key);inputs.add(h)
def choose_variant(reports):
    validate_reports(reports,'training')
    subjects=sorted({r['subject'] for r in reports})
    if len(subjects)<3:raise ValueError('At least3 distinct training participants required.')
    scores={}
    for variant in VARIANTS:
        grouped={}
        for r in reports:
            x=r.get('variants',{}).get(variant,{}).get('macroF1')
            if not finite(x) or not 0<=x<=1:raise ValueError('Every frozen training recipe needs a finite macroF1.')
            grouped.setdefault(r['subject'],[]).append(x)
        scores[variant]=statistics.mean(statistics.mean(v) for v in grouped.values())
    chosen=max(VARIANTS,key=lambda key:scores[key])
    return {'version':VERSION,'chosen':chosen,'selectionMetric':'mean-participant-four-class-macroF1','trainingScores':scores,
        'trainingSubjects':subjects,'trainingInputHashes':[r['inputSHA256'] for r in reports],
        'trainingCases':[r['subject']+'/'+r['night'] for r in reports],
        'interpretation':'Recipe chosen only on training participants; heldout must evaluate shipped and chosen only. EEG reference is not full PSG; hardware is Apple Watch, RR absent.'}
def validate_holdout(selection,reports):
    validate_reports(reports,'holdout')
    if set(r['subject'] for r in reports)&set(selection['trainingSubjects']):raise ValueError('Held-out subject leaked into training.')
    if set(r['inputSHA256'] for r in reports)&set(selection['trainingInputHashes']):raise ValueError('Held-out input duplicates training.')
    expected={'shipped',selection['chosen']}
    if any(set(r['variants'])!=expected for r in reports):raise ValueError('Held-out cases may evaluate only shipped and the frozen choice.')
def calibration_cases(reports,variant):
    return [{'subject':r['subject'],'caseID':r['subject']+'/'+r['night'],'inputSHA256':r['inputSHA256'],'origin':r['origin'],'split':r['split'],
        'metric':'sleep-stage-error','unit':'fraction','qualityMethod':r['qualityMethod'],'model':VERSION+':'+variant,'source':r['reference'],
        'independent':True,'quality':r['quality'],'error':1-r['variants'][variant]['accuracy']} for r in reports]
def aggregate(reports,variant):
    matrix=[[0]*4 for _ in range(4)];grouped={};names=['wake','light','deep','rem'];stages={k:{} for k in names}
    for r in reports:
        x=r['variants'][variant];grouped.setdefault(r['subject'],[]).append(x['macroF1'])
        for i in range(4):
            for j in range(4):matrix[i][j]+=x['confusion'][i][j]
        for name in names:stages[name].setdefault(r['subject'],[]).append(x['perStage'][name]['f1'])
    total=sum(map(sum,matrix))
    return {'participants':len(grouped),'nights':len(reports),'epochs':total,'confusion':matrix,
        'pooledAccuracy':sum(matrix[i][i] for i in range(4))/total if total else None,
        'meanParticipantMacroF1':statistics.mean(statistics.mean(v) for v in grouped.values()) if grouped else None,
        'meanParticipantStageF1':{k:statistics.mean(statistics.mean(nights) for nights in v.values()) if v else None for k,v in stages.items()},
        'pooledStageFractionBiasPP':{name:100*(sum(matrix[row][i] for row in range(4))-sum(matrix[i]))/total if total else None for i,name in enumerate(names)}}
def run_cases(manifest,binary,out,variants,split,manifest_root=Path(".")):
    if any(c['split']!=split for c in manifest['cases']):raise ValueError('Manifest contains wrong split.')
    reports=[]
    for c in manifest['cases']:
        src=Path(c['path']);src=src if src.is_absolute() else manifest_root/src
        raw=src.read_bytes()
        if digest(raw)!=c['inputSHA256']:raise ValueError('Prepared case checksum mismatch.')
        dst=out/(c['subject']+'-'+Path(c['night']).name+'-report.json')
        try:result=subprocess.run([str(binary),'--research-case',str(src),'--research-output',str(dst),'--variants',','.join(variants)],capture_output=True,text=True,timeout=90)
        except (OSError,subprocess.TimeoutExpired) as error:raise ValueError('Native sleep evaluation failed or timed out.') from error
        if result.returncode:raise ValueError(result.stderr[:1000])
        r=load(dst)
        if r['inputSHA256']!=c['inputSHA256'] or r['subject']!=c['subject'] or r['split']!=split:raise ValueError('Native case identity mismatch.')
        reports.append(r);print('EVALUATED',split,c['subject'],flush=True)
    validate_reports(reports,split);return reports

def run_training(manifest_path,binary,output,max_error):
    binary=Path(binary).resolve();out=Path(output)
    if out.exists():raise ValueError('Choose a new training output directory.')
    out.mkdir(parents=True);manifest=load(manifest_path)
    reports=run_cases(manifest,binary,out,VARIANTS,'training',Path(manifest_path).resolve().parent);selection=choose_variant(reports)
    selection['executableSHA256']=digest(binary.read_bytes());selection['manifestSHA256']=digest(Path(manifest_path).read_bytes())
    selection['excluded']=manifest.get('excluded',[])
    calibration=fit_calibration(calibration_cases(reports,selection['chosen']),max_error=max_error)
    save_new(out/'confidence-selection.json',calibration)
    selection['confidenceSHA256']=digest((out/'confidence-selection.json').read_bytes())
    save_new(out/'selection-frozen.json',selection)
    save_new(out/'training-cases.json',calibration_cases(reports,selection['chosen']))
    return selection

def run_holdout(manifest_path,binary,selection_path,confidence_path,output):
    selection=load(selection_path);confidence=load(confidence_path);binary=Path(binary).resolve();out=Path(output)
    if selection.get('version')!=VERSION or selection['chosen'] not in VARIANTS:raise ValueError('Unknown frozen selection.')
    if digest(binary.read_bytes())!=selection['executableSHA256']:raise ValueError('Executable differs from frozen training binary.')
    if digest(Path(confidence_path).read_bytes())!=selection.get('confidenceSHA256'):
        raise ValueError('Confidence artifact differs from the frozen training run.')
    expected={'metric':'sleep-stage-error','unit':'fraction','qualityMethod':'apple-watch-availability-v1','model':VERSION+':'+selection['chosen'],'source':'dreem2-expert'}
    if confidence.get('context')!=expected or set(confidence.get('trainingParticipants',[]))!=set(selection['trainingSubjects']) or set(confidence.get('trainingInputHashes',[]))!=set(selection['trainingInputHashes']) or set(confidence.get('trainingCaseIDs',[]))!=set(selection.get('trainingCases',[])):
        raise ValueError('Confidence cohort/recipe differs from frozen sleep selection.')
    if out.exists():raise ValueError('Choose a new held-out output directory.')
    manifest=load(manifest_path)
    if {r['subject'] for r in manifest['cases']}&set(selection['trainingSubjects']):raise ValueError('Held-out participant occurs in training manifest.')
    out.mkdir(parents=True);variants=list(dict.fromkeys(['shipped',selection['chosen']]))
    reports=run_cases(manifest,binary,out,variants,'holdout',Path(manifest_path).resolve().parent);validate_holdout(selection,reports)
    cases=calibration_cases(reports,selection['chosen']);calibration=evaluate_calibration(confidence,cases)
    summary={'version':VERSION,'selectionSHA256':digest(Path(selection_path).read_bytes()),'confidenceSHA256':digest(Path(confidence_path).read_bytes()),'chosen':selection['chosen'],
        'interpretation':selection['interpretation'],'excluded':manifest.get('excluded',[]),
        'variants':{v:aggregate(reports,v) for v in variants},'confidence':calibration}
    save_new(out/'holdout-results.json',summary);save_new(out/'holdout-cases.json',cases)
    rows=''.join('<tr><td>'+html.escape(v)+'</td><td>'+str(x['participants'])+'</td><td>'+str(x['epochs'])+'</td><td>'+str(x['pooledAccuracy'])+'</td><td>'+str(x['meanParticipantMacroF1'])+'</td></tr>' for v,x in summary['variants'].items())
    stage_rows=''.join('<tr><td>'+html.escape(v)+'</td><td>'+html.escape(stage)+'</td><td>'+str(x['meanParticipantStageF1'][stage])+'</td><td>'+str(x['pooledStageFractionBiasPP'][stage])+'</td></tr>' for v,x in summary['variants'].items() for stage in ['wake','light','deep','rem'])
    (out/'sleep-evaluation.html').write_text(page('NROOP held-out sleep evaluation','<p>'+html.escape(summary['interpretation'])+'</p><table><tr><th>Frozen recipe</th><th>Participants</th><th>Scored epochs</th><th>Pooled accuracy</th><th>Mean participant macroF1</th></tr>'+rows+'</table><h2>Per-stage agreement and fraction bias</h2><p>Stage F1 averages each participant equally. Fraction bias pools all scored epochs, prediction minus reference, in percentage points.</p><table><tr><th>Recipe</th><th>Stage</th><th>Mean participant F1</th><th>Pooled fraction bias (pp)</th></tr>'+stage_rows+'</table><h2>Recording quality versus error</h2><pre>'+html.escape(json.dumps(calibration,indent=2))+'</pre>'),encoding='utf-8')
    return summary

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    a=sub.add_parser('fit');a.add_argument('manifest',type=Path);a.add_argument('--binary',required=True,type=Path);a.add_argument('--max-error',required=True,type=float);a.add_argument('--output',required=True,type=Path)
    a=sub.add_parser('evaluate');a.add_argument('manifest',type=Path);a.add_argument('--binary',required=True,type=Path);a.add_argument('--selection',required=True,type=Path);a.add_argument('--confidence-selection',required=True,type=Path);a.add_argument('--output',required=True,type=Path)
    a=p.parse_args()
    try:
        if a.command=='fit':run_training(a.manifest,a.binary,a.output,a.max_error)
        else:run_holdout(a.manifest,a.binary,a.selection,a.confidence_selection,a.output)
    except (OSError,ValueError,KeyError,TypeError) as error:p.exit(2,'Error: '+str(error)+'\n')
if __name__=='__main__':main()
