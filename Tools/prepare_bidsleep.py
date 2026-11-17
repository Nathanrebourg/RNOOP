#!/usr/bin/env python3
"""Offline adapter for BIDSleep1.0.1 expert-reviewed Dreem2 labels and Apple Watch streams.
Requires scipy only to read MATLAB files. Raw datasets stay outside the repository.
"""
from __future__ import annotations
import argparse,csv,hashlib,json,math
from datetime import datetime,timezone
from pathlib import Path
from zoneinfo import ZoneInfo

TIME_BASE=1699999980
DATASET='bidsleep-1.0.1'
def subject_split(subject):
    return 'holdout' if int(hashlib.sha256(('nroop-bidsleep-v1|'+subject).encode()).hexdigest(),16)%5<2 else 'training'
def label_stage(code):
    if type(code) not in (int,float) or not math.isfinite(code) or int(code)!=code or not 0<=code<=5:raise ValueError('Unknown expert stage code.')
    return ['wake','light','light','deep','rem',None][int(code)]
def rec_start_utc(text):
    dt=datetime.strptime(str(text),'%Y-%m-%d %H:%M:%S');zone=ZoneInfo('America/New_York');possible=set()
    for fold in [0,1]:
        aware=dt.replace(tzinfo=zone,fold=fold);utc=aware.astimezone(timezone.utc)
        if utc.astimezone(zone).replace(tzinfo=None)==dt:possible.add(int(utc.timestamp()))
    if len(possible)!=1:raise ValueError('Ambiguous or nonexistent ET recStart; do not infer alignment.')
    return possible.pop()
def rows(path,size):
    with Path(path).open(newline='',encoding='utf-8-sig') as f:
        for number,row in enumerate(csv.reader(f),1):
            if not row:continue
            header=[v.strip().lower() for v in row]
            if number==1 and (header==['timestamp','x','y','z'] or header in [['timestamp','hr'],['timestamp','bpm'],['timestamp','heart_rate']]):continue
            try:values=[float(v) for v in row]
            except ValueError as error:raise ValueError(f'{path.name}:{number} invalid numeric row') from error
            if len(values)!=size or not all(math.isfinite(v) for v in values):raise ValueError(f'{path.name}:{number} invalid numeric shape')
            yield values

def convert_night(directory,*,subject,night):
    try:
        from scipy.io import loadmat
    except ImportError as error:raise ValueError('Install optional scipy to read labels.mat.') from error
    root=Path(directory);m=loadmat(root/'labels.mat')
    if 'expert_label' not in m or 'recStart' not in m:raise ValueError('Explicit expert_label and recStart required.')
    text=m['recStart'].reshape(-1)
    if len(text)!=1:raise ValueError('Unexpected recStart format.')
    origin=rec_start_utc(str(text[0]));raw=m['expert_label'].reshape(-1)
    if not 1<=len(raw)<=2880:raise ValueError('Reference window must be1epoch to24hours.')
    truth=[label_stage(float(v)) for v in raw];duration=len(truth)*30
    if not any(v is not None for v in truth):raise ValueError('No expert-scored reference epochs.')
    hr=[];motion={}
    for t,bpm in rows(root/'hr.csv',2):
        if not 0<=bpm<=300:raise ValueError('Corrupt HR domain; no clipping.')
        sec=math.floor(t-origin)
        if -330<=sec<duration+390 and bpm>0:hr.append({'ts':TIME_BASE+sec,'bpm':math.floor(bpm+.5)})
    for t,x,y,z in rows(root/'motion.csv',4):
        if any(abs(v)>1e6 for v in [x,y,z]):raise ValueError('Corrupt motion domain; no clipping.')
        sec=math.floor(t-origin)
        if -330<=sec<duration+390:
            a=motion.setdefault(sec,[0.,0.,0.,0]);a[0]+=x;a[1]+=y;a[2]+=z;a[3]+=1
    if not hr or not motion:raise ValueError('No overlapping HR/motion; report this night as excluded.')
    gravity=[{'ts':TIME_BASE+s,'x':v[0]/v[3],'y':v[1]/v[3],'z':v[2]/v[3]} for s,v in sorted(motion.items())]
    return {'schema':1,'dataset':DATASET,'reference':'dreem2-expert','origin':'recorded','subject':subject,'night':night,
        'split':subject_split(subject),'start':TIME_BASE,'end':TIME_BASE+duration,'originalStartUTC':origin,
        'hr':sorted(hr,key=lambda h:h['ts']),'gravity':gravity,'truth':truth,
        'sourceSHA256':{n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in ['hr.csv','motion.csv','labels.mat']},
        'mapping':'Relative whole-second floor; motion per-second mean; sparse HR retained; expert REM=4,unknown=5; no RR.'}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('night_directory',type=Path);p.add_argument('--subject',required=True);p.add_argument('--night',required=True);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    try:
        result=convert_night(a.night_directory,subject=a.subject,night=a.night)
        with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,allow_nan=False,separators=(',',':'))
        print('Converted locally; EEG reference is not full PSG and does not establish WHOOP accuracy.')
    except (OSError,ValueError,KeyError,TypeError) as error:p.exit(2,'Error: '+str(error)+'\n')
if __name__=='__main__':main()
