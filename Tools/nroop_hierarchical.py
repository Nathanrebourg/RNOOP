#!/usr/bin/env python3
"""Retrospective, fixed-candidate sleep comparison. Physiology runs in the native Swift executable."""
from __future__ import annotations
import argparse, hashlib, html, json, statistics, subprocess
from pathlib import Path

STAGES=['wake','light','deep','rem']
VARIANTS=['shipped','hierarchical-v1']
def sha(data): return hashlib.sha256(data).hexdigest()
def read_capped_json(path,limit):
    if not isinstance(limit,int) or limit<=0:raise ValueError('Positive JSON byte limit required.')
    if path.stat().st_size>limit:raise ValueError('JSON exceeds byte limit: '+str(path))
    with path.open('rb') as stream:raw=stream.read(limit+1)
    if len(raw)>limit:raise ValueError('JSON exceeds byte limit after size check: '+str(path))
    return raw,json.loads(raw)
def bounded_metadata(case):
    subject=case.get('subject');night=case.get('night');truth=case.get('truth')
    if not isinstance(subject,str) or not 0<len(subject)<=256 or not isinstance(night,str) or not 0<len(night)<=512 or not isinstance(truth,list) or not 0<len(truth)<=2880 or not any(t is not None for t in truth) or any(t is not None and t not in STAGES for t in truth):
        raise ValueError('Malformed or oversized retained case metadata.')
    return {'subject':subject,'night':night,'truth':truth}

def validate_identity(subject,checksum,subjects,inputs):
    if not isinstance(subject,str) or not subject or not isinstance(checksum,str) or len(checksum)!=64 or any(x not in '0123456789abcdef' for x in checksum):
        raise ValueError('Missing participant/checksum identity.')
    if subject in subjects or checksum in inputs: raise ValueError('Participant or input repeated across this first-night benchmark.')
    subjects.add(subject);inputs.add(checksum)
def _matrix(cases):
    m=[[0]*5 for _ in STAGES]
    for case in cases:
        truth=case['truth'];prediction=case['predictions']
        if len(truth)!=len(prediction) or any(t is not None and t not in STAGES for t in truth) or any(p not in STAGES+['unknown'] for p in prediction):
            raise ValueError('Malformed reference/prediction grid.')
        for t,p in zip(truth,prediction):
            if t is not None: m[STAGES.index(t)][4 if p=='unknown' else STAGES.index(p)]+=1
    return m

def _scores(m):
    f1={}
    for i,name in enumerate(STAGES):
        tp=m[i][i];denominator=sum(m[i])+sum(m[j][i] for j in range(4))
        f1[name]=2*tp/denominator if denominator else 0
    total=sum(map(sum,m));covered=sum(sum(row[:4]) for row in m);correct=sum(m[i][i] for i in range(4))
    return {'referenceEpochs':total,'coveredReferenceEpochs':covered,'unknownReferenceEpochs':total-covered,
        'referenceAccuracy':correct/total if total else None,'conditionalAccuracy':correct/covered if covered else None,
        'stageF1':f1,'macroF1':statistics.mean(f1.values()) if total else None}

def summarize(cases):
    if not cases: raise ValueError('No benchmark cases.')
    grouped={}
    for case in cases:
        if not isinstance(case.get('subject'),str) or not case['subject']: raise ValueError('Missing subject.')
        grouped.setdefault(case['subject'],[]).append(case)
    matrix=_matrix(cases);score=_scores(matrix)
    person={subject:_scores(_matrix(nights)) for subject,nights in grouped.items()}
    eligible=[p for p in person.values() if p['referenceEpochs']>0]
    return {k:v for k,v in score.items() if k not in ['stageF1','macroF1']} | {
        'participants':len(person),'participantsWithReference':len(eligible),'nights':len(cases),'confusionColumns':STAGES+['unknown'],'confusion':matrix,
        'meanParticipantReferenceMacroF1':statistics.mean(p['macroF1'] for p in eligible) if eligible else None,
        'meanParticipantStageF1':{name:(statistics.mean(p['stageF1'][name] for p in eligible) if eligible else None) for name in STAGES},
        'perParticipant':person}

def run(binary,manifests,out):
    binary=binary.resolve(strict=True);binary_hash=sha(binary.read_bytes())
    subjects=set();inputs=set();cohorts={};manifest_hashes={}
    for label,manifest in manifests:
        raw,payload=read_capped_json(manifest,1024*1024);manifest_hashes[label]=sha(raw)
        prepared=[]
        items=payload['cases']
        if not isinstance(items,list) or not 0<len(items)<=512:raise ValueError('Manifest case count exceeds bounded benchmark scope.')
        for item in items:
            src=(manifest.parent/item['path']).resolve(strict=True)
            data,case=read_capped_json(src,64*1024*1024);checksum=sha(data)
            if checksum!=item['inputSHA256']:raise ValueError('Prepared source checksum mismatch.')
            if case.get('origin')!='recorded' or case.get('dataset')!='bidsleep-1.0.1' or case.get('reference')!='dreem2-expert' or case.get('subject')!=item['subject'] or case.get('split')!=item['split']:
                raise ValueError('Manifest and recorded research case do not match.')
            validate_identity(case['subject'],checksum,subjects,inputs)
            metadata=bounded_metadata(case)
            prepared.append((src,checksum,metadata))
            del data,case
        if not prepared:raise ValueError('Empty cohort.')
        cohorts[label]=prepared
    out.mkdir(parents=True,exist_ok=False)
    all_cases={v:[] for v in VARIANTS};groups={};identities=[]
    for cohort,prepared in cohorts.items():
        cases={v:[] for v in VARIANTS};common={v:[] for v in VARIANTS}
        for index,(src,checksum,case) in enumerate(prepared):
            dst=out/f'{cohort}-{index:03d}.json'
            result=subprocess.run([str(binary),'--research-case',str(src),'--research-output',str(dst),'--variants',','.join(VARIANTS)],capture_output=True,text=True,timeout=120)
            if result.returncode:raise ValueError('Native model refused input: '+result.stderr[-2000:])
            report_bytes,report=read_capped_json(dst,16*1024*1024)
            if report['inputSHA256']!=checksum or set(report['variants'])!=set(VARIANTS):raise ValueError('Native provenance mismatch.')
            identities.append({'cohort':cohort,'subject':case['subject'],'night':case['night'],'inputSHA256':checksum,'reportSHA256':sha(report_bytes)})
            for variant in VARIANTS:
                entry={'subject':case['subject'],'truth':case['truth'],'predictions':report['variants'][variant]['predictions']}
                cases[variant].append(entry);all_cases[variant].append(entry)
                paired=[t if p!='unknown' else None for t,p in zip(case['truth'],report['variants']['hierarchical-v1']['predictions'])]
                common[variant].append(entry | {'truth':paired})
        groups[cohort]={v:summarize(cases[v]) for v in VARIANTS}
        groups[cohort]['commonSupport']={v:summarize(common[v]) for v in VARIANTS}
    overall={v:summarize(all_cases[v]) for v in VARIANTS}
    delta=overall['hierarchical-v1']['meanParticipantReferenceMacroF1']-overall['shipped']['meanParticipantReferenceMacroF1']
    summary={'version':'nroop-hierarchical-retrospective-v1','binarySHA256':binary_hash,'manifestSHA256':manifest_hashes,
        'candidate':'hierarchical-v1','candidateCount':1,'tunedOnTheseResults':False,
        'scope':'Retrospective benchmark; both cohorts were previously examined. Not a fresh holdout, WHOOP validation or clinical confidence.',
        'reference':'BIDSleep1.0.1 Apple Watch sensors; expert-reviewed Dreem2 labels, provided sleep windows, no RR.',
        'unknownPolicy':'No HR1...300/nonzero finite gravity in 30s cell means unknown. Full-reference F1 counts unknown as false negatives; conditional metrics name their denominator.',
        'promotion':'not-promoted; fresh-participant and WHOOP-specific validation required',
        'benchmarkConclusion':'candidate-worse-on-mean-participant-macroF1' if delta<0 else 'retrospective-improvement-only',
        'meanParticipantMacroF1Delta':delta,'cohorts':groups,'all':overall,'cases':identities}
    if sha(binary.read_bytes())!=binary_hash:raise ValueError('Native executable changed during benchmark.')
    (out/'summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True,allow_nan=False)+'\n')
    rows=[]
    for label,group in list(groups.items())+[('all',overall)]:
        for variant in VARIANTS:
            m=group[variant]
            rows.append('<tr>'+''.join('<td>'+html.escape(str(value))+'</td>' for value in [label,variant,m['participants'],m['referenceEpochs'],f"{m['referenceAccuracy']:.3%}",f"{m['meanParticipantReferenceMacroF1']:.4f}",f"{m['meanParticipantStageF1']['wake']:.4f}",m['unknownReferenceEpochs']])+'</tr>')
    content='<!doctype html><html lang="en"><meta charset="utf-8"><title>NOOP hierarchical sleep experiment</title><style>body{font:16px system-ui;max-width:1100px;margin:3rem auto;padding:0 1rem}td,th{padding:.6rem;text-align:left;border-bottom:1px solid #ccc}table{border-collapse:collapse}p{line-height:1.6}</style><h1>Hierarchical sleep experiment</h1><p>'+html.escape(summary['scope'])+'</p><p>'+html.escape(summary['reference'])+'</p><table><tr><th>Cohort</th><th>Recipe</th><th>Participants</th><th>Reference epochs</th><th>Accuracy</th><th>Person macro F1</th><th>Person wake F1</th><th>Unknown</th></tr>'+''.join(rows)+'</table><p>'+html.escape(summary['promotion'])+'</p><p>'+html.escape(summary['unknownPolicy'])+'</p></html>'
    (out/'summary.html').write_text(content)
    return summary

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--training-manifest',type=Path,required=True)
    parser.add_argument('--previous-holdout-manifest',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:result=run(args.binary,[('previous-training',args.training_manifest),('previous-holdout',args.previous_holdout_manifest)],args.output)
    except (ValueError,OSError,KeyError,TypeError,subprocess.TimeoutExpired) as error:parser.exit(2,f'Hierarchy benchmark failed: {error}\n')
    print(json.dumps({k:result[k] for k in ['benchmarkConclusion','meanParticipantMacroF1Delta','promotion']},indent=2))
if __name__=='__main__':main()
