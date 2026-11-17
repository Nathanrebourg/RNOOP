#!/usr/bin/env python3
"""Train-only quality-threshold selection and independent-participant error evaluation, without probability claims."""
from __future__ import annotations
import argparse,math,statistics
from pathlib import Path
from nroop_research import load,save_new,checksum
from nroop_lab import finite

VERSION='nroop-confidence-v1'
THRESHOLDS=[0,.25,.5,.75,.9,1]
UNIT_LIMITS={'fraction':1,'points/100':100,'bpm':300,'hours':24}
CONTEXT=['metric','unit','qualityMethod','model','source']
SOURCES={'whoop','measured','diary','dreem2-expert'}
def validate(records,split):
    context=None;seen=set();hashes=set();usable=[];synthetic=0;unavailable=0
    for row in records:
        if row.get('split')!=split:raise ValueError('Do not mix training and held-out cases.')
        ctx={k:row.get(k) for k in CONTEXT}
        if any(not isinstance(v,str) or not v for v in ctx.values()) or ctx['unit'] not in UNIT_LIMITS or ctx['source'] not in SOURCES:
            raise ValueError('Explicit metric, unit, quality method, model and reference source required.')
        if context is None:context=ctx
        if context!=ctx:raise ValueError('Mixed calibration recipes/units/reference sources.')
        if not isinstance(row.get('subject'),str) or not row['subject'] or not isinstance(row.get('caseID'),str) or not row['caseID'] or not checksum(row.get('inputSHA256')):raise ValueError('Case identity and input hash required.')
        if row['caseID'] in seen or row['inputSHA256'] in hashes:raise ValueError('Duplicate calibration case or recording.')
        seen.add(row['caseID']);hashes.add(row['inputSHA256'])
        if row.get('origin') not in {'recorded','synthetic'} or row.get('independent') is not True:raise ValueError('Explicit origin and independent reference required.')
        if row['origin']=='synthetic':synthetic+=1;continue
        q=row.get('quality');error=row.get('error')
        if q is None or error is None:unavailable+=1;continue
        if not finite(q) or not 0<=q<=1 or not finite(error) or not 0<=error<=UNIT_LIMITS[ctx['unit']]:raise ValueError('Invalid quality/error numeric domain.')
        usable.append(row)
    return context,usable,synthetic,unavailable

def stats(rows,budget):
    groups={}
    for r in rows:groups.setdefault(r['subject'],[]).append(r['error'])
    # Each participant gets one vote, even if later datasets contain unequal numbers of nights.
    error=statistics.mean(statistics.mean(v) for v in groups.values()) if groups else None
    return {'n':len(rows),'participants':len(groups),'meanError':error,'budgetAchieved':error<=budget if error is not None else None}
def fit_calibration(records,*,max_error):
    context,rows,synthetic,unavailable=validate(records,'training')
    if not finite(max_error) or max_error<0 or (context and max_error>UNIT_LIMITS[context['unit']]):raise ValueError('Declare a valid error budget in metric units.')
    participants=sorted({r['subject'] for r in rows});threshold=None
    trials=[{'threshold':t,**stats([r for r in rows if r['quality']>=t],max_error)} for t in THRESHOLDS]
    status='insufficient-training-participants' if len(participants)<3 else 'no-threshold-meets-budget'
    if len(participants)>=3:
        for trial in trials:
            if trial['participants']>=3 and trial['budgetAchieved']:
                threshold=trial['threshold'];status='threshold-frozen';break
    return {'version':VERSION,'context':context,'errorBudget':max_error,'threshold':threshold,'status':status,
        'trainingParticipants':sorted({r['subject'] for r in records if r['origin']=='recorded'}),'trainingEligibleParticipants':participants,
        'trainingInputHashes':[r['inputSHA256'] for r in records if r['origin']=='recorded'],'trainingCaseIDs':[r['caseID'] for r in records if r['origin']=='recorded'],
        'training':stats(rows,max_error),'trials':trials,'excludedSynthetic':synthetic,'excludedUnavailable':unavailable,
        'interpretation':'Recording-quality threshold against declared reference error, selected on training participants only. Not a calibrated probability, clinical validation or evidence that filtering improves everyone.'}
def evaluate_calibration(selection,records):
    if selection.get('version')!=VERSION:raise ValueError('Unknown calibration selection.')
    context,rows,synthetic,unavailable=validate(records,'holdout')
    if context is not None and context!=selection['context']:raise ValueError('Held-out calibration recipe mismatch.')
    declared=[r for r in records if r['origin']=='recorded']
    if set(r['subject'] for r in declared)&set(selection['trainingParticipants']):raise ValueError('Held-out participant leaked into training.')
    if set(r['inputSHA256'] for r in declared)&set(selection['trainingInputHashes']) or set(r['caseID'] for r in declared)&set(selection['trainingCaseIDs']):raise ValueError('Held-out recording/case duplicated training data.')
    budget=selection['errorBudget'];threshold=selection['threshold']
    if threshold is not None and threshold not in THRESHOLDS:raise ValueError('Unknown frozen threshold.')
    enough=len({r['subject'] for r in rows})>=3
    kept=[r for r in rows if r['quality']>=threshold] if threshold is not None and enough else []
    bins=[]
    for lo,hi in [(0,.25),(.25,.5),(.5,.75),(.75,1)]:
        b=[r for r in rows if lo<=r['quality'] and (r['quality']<hi or hi==1 and r['quality']<=hi)]
        bins.append({'fromInclusive':lo,'to':hi,'upperInclusive':hi==1,**stats(b,budget)})
    return {'version':VERSION,'context':context,'threshold':threshold,'status':'evaluated' if enough else 'insufficient-holdout-participants',
        'all':stats(rows,budget),'selected':stats(kept,budget),'retainedFraction':len(kept)/len(rows) if rows else None,'bins':bins,
        'excludedSynthetic':synthetic,'excludedUnavailable':unavailable,'interpretation':selection['interpretation']}
def main():
    p=argparse.ArgumentParser(description=__doc__);s=p.add_subparsers(dest='command',required=True)
    a=s.add_parser('fit');a.add_argument('cases',type=Path);a.add_argument('--max-error',required=True,type=float);a.add_argument('--output',required=True,type=Path)
    a=s.add_parser('evaluate');a.add_argument('selection',type=Path);a.add_argument('cases',type=Path);a.add_argument('--output',required=True,type=Path)
    a=p.parse_args()
    try:
        result=fit_calibration(load(a.cases),max_error=a.max_error) if a.command=='fit' else evaluate_calibration(load(a.selection),load(a.cases))
        save_new(a.output,result);print('Completed locally; no app threshold or score changed.')
    except (OSError,ValueError,KeyError,TypeError) as error:p.exit(2,'Error: '+str(error)+'\n')
if __name__=='__main__':main()
