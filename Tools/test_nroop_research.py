import copy
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from nroop_research import attach_history, civil_fragments, calendar_ledger, perturbations, compare_reports, run_sensitivity, render_explanation

DAY=1728000000
OWNER=hashlib.sha256(b'strap').hexdigest()
def epoch(s): return int(datetime.fromisoformat(s.replace('Z','+00:00')).timestamp())
def recording():
    return {'schema':1,'origin':'synthetic','caseID':'test','owner':'strap','dayStart':DAY,'now':DAY+3600,'offset':0,'age':30,
        'hr':[{'ts':DAY+i,'bpm':70} for i in range(120)],'rr':[],'gravity':[],'events':[],'band':[],'history':[],'historyStreams':[]}
def report(day=DAY-86400):
    return {'schema':1,'model':'nroop-lab-v1','origin':'synthetic','ownerHash':OWNER,'caseID':'prior','dayStart':day,'inputSHA256':'a'*64,
        'metrics':{'recovery':{'original':40,'candidate':None,'unit':'points/100','status':'missing'}},
        'research':{'version':'nroop-research-v1','recipe':{'useV2':True,'deepWindow':False},
            'observation':{'hrv':60,'rhr':55},'quality':{'hrv':0.9,'rhr':1,'sleep':1},'sessions':[]}}

class HistoricalEvidenceTests(unittest.TestCase):
    def current(self):
        r=recording();r['history']=[{'dayStart':DAY-86400,'source':'computed','hrv':60,'rhr':55}];return r
    def test_attaches_exact_prior_owner_and_values_without_mutating_inputs(self):
        r=self.current();before=copy.deepcopy(r);a=attach_history(r,[report()])
        self.assertEqual(r,before);self.assertNotIn('evidence',r['history'][0])
        self.assertEqual(a['history'][0]['evidence']['hrvQuality'],0.9)
    def test_owner_future_recipe_origin_and_value_mismatches_are_rejected(self):
        for key,value in [('ownerHash','b'*64),('dayStart',DAY),('origin','recorded')]:
            p=report();p[key]=value
            with self.assertRaises(ValueError): attach_history(self.current(),[p])
        for key,value in [('recipe',{'useV2':False,'deepWindow':False}),('observation',{'hrv':61,'rhr':55})]:
            p=report();p['research'][key]=value
            with self.assertRaises(ValueError):attach_history(self.current(),[p])
    def test_null_recipe_options_match_swift_defaults(self):
        r=self.current();r['useV2']=None;r['deepWindow']=None
        self.assertIn('evidence',attach_history(r,[report()])['history'][0])
    def test_duplicate_report_and_invalid_quality_are_rejected(self):
        with self.assertRaises(ValueError):attach_history(self.current(),[report(),report()])
        p=report();p['research']['quality']['hrv']=float('nan')
        with self.assertRaises(ValueError):attach_history(self.current(),[p])
    def test_unwitnessed_history_remains_unknown(self):
        a=attach_history(self.current(),[]);self.assertNotIn('evidence',a['history'][0])

class SensitivityTests(unittest.TestCase):
    def test_transforms_are_deterministic_and_never_modify_source(self):
        r=recording();before=copy.deepcopy(r);a=perturbations(r);b=perturbations(r)
        self.assertEqual(a,b);self.assertEqual(r,before)
        self.assertEqual(a['hr-plus-3']['hr'][0]['bpm'],73)
        self.assertEqual(len(a['duplicated']['hr']),240)
        self.assertEqual(a['reversed']['hr'],list(reversed(r['hr'])))
        self.assertTrue(all(v['origin']=='synthetic' for v in a.values()))
    def test_missing_comparisons_stay_missing_and_thresholds_are_not_invented(self):
        a=report();b=copy.deepcopy(a);b['metrics']['recovery']['original']=45
        x=compare_reports(a,b)
        self.assertEqual(x['recovery']['originalDelta'],5)
        self.assertIsNone(x['recovery']['candidateDelta'])
        self.assertEqual(x['recovery']['candidateAvailability'],'missing-both')
    def test_availability_loss_and_gain_are_named(self):
        a=report();b=copy.deepcopy(a);b['metrics']['recovery']['candidate']=0
        self.assertEqual(compare_reports(a,b)['recovery']['candidateAvailability'],'gained')
        self.assertEqual(compare_reports(b,a)['recovery']['candidateAvailability'],'lost')
    def test_band_changes_come_from_actual_replay_band_fields(self):
        a=report();b=copy.deepcopy(a)
        a['research']['bands']={'recovery':{'original':'red'}}
        b['research']['bands']={'recovery':{'original':'yellow'}}
        x=compare_reports(a,b)['recovery']
        self.assertEqual(x['originalBandChange'],{'from':'red','to':'yellow','changed':True})
        self.assertIsNone(x['candidateBandChange'])
    def test_explanation_escapes_html_and_labels_scope(self):
        p=report();p['caseID']='<script>alert(1)</script>'
        p['research']['explanation']={'status':'explained','score':40,'terms':[{'name':'hrv','z':-1,'normalizedWeight':1,'contributionZ':-1}],'baselines':{},'missing':['resp']}
        h=render_explanation(p)
        self.assertNotIn('<script>',h);self.assertIn('&lt;script&gt;',h)
        self.assertIn('z',h);self.assertIn('five-driver',h)

class CivilCalendarTests(unittest.TestCase):
    def test_spring_and_fall_days_have_actual_elapsed_length(self):
        for start,end,hours in [('2026-03-28T23:00:00Z','2026-03-29T22:00:00Z',23),('2026-10-24T22:00:00Z','2026-10-25T23:00:00Z',25)]:
            a,b=epoch(start),epoch(end);f=civil_fragments(a,b,[{'start':a,'end':b,'zone':'Europe/Paris'}])
            self.assertEqual(len(f),1);self.assertEqual(f[0]['seconds'],hours*3600)
    def test_travel_backward_repeated_dates_partition_time_without_duplication(self):
        a=epoch('2026-11-10T00:00:00Z');mid=a+12*3600;b=a+36*3600
        f=civil_fragments(a,b,[{'start':a,'end':mid,'zone':'Pacific/Auckland'},{'start':mid,'end':b,'zone':'America/Los_Angeles'}])
        self.assertEqual(sum(x['seconds'] for x in f),b-a)
        self.assertTrue(all(x['end']==y['start'] for x,y in zip(f,f[1:])))
        self.assertGreaterEqual(sum(x['date']=='2026-11-10' for x in f),2)
    def test_gap_overlap_unknown_zone_and_excessive_range_reject(self):
        for i in [[{'start':DAY+1,'end':DAY+100,'zone':'UTC'}],
            [{'start':DAY,'end':DAY+60,'zone':'UTC'},{'start':DAY+50,'end':DAY+100,'zone':'UTC'}],
            [{'start':DAY,'end':DAY+100,'zone':'Not/AZone'}]]:
            with self.assertRaises(ValueError):civil_fragments(DAY,DAY+100,i)
        with self.assertRaises(ValueError):civil_fragments(DAY,DAY+99999999,[])
    def test_conflicting_hr_is_excluded_and_identical_duplicates_vote_once(self):
        r=recording();r['hr'] += [{'ts':DAY,'bpm':70},{'ts':DAY+1,'bpm':90}]
        out=calendar_ledger(r,[{'start':DAY-108000,'end':r['now'],'zone':'UTC'}])
        self.assertEqual(sum(f['observedHRSeconds'] for f in out['fragments']),119)
        self.assertEqual(out['conflictingHRSeconds'],1)
    def test_sleep_belongs_to_date_at_last_observed_second(self):
        r=recording();r['now']=DAY+86400
        p=report(DAY);p['research']['sessions']=[{'start':DAY+80000,'end':DAY+86400}]
        out=calendar_ledger(r,[{'start':DAY-108000,'end':r['now'],'zone':'UTC'}],p)
        self.assertEqual(out['sessions'][0]['wakeDate'],'2024-10-04')
        self.assertEqual(out['sessions'][0]['seconds'],6400)
    def test_sample_at_exclusive_end_is_not_counted(self):
        r=recording();r['hr'].append({'ts':r['now'],'bpm':70})
        o=calendar_ledger(r,[{'start':DAY-108000,'end':r['now'],'zone':'UTC'}])
        self.assertEqual(sum(x['observedHRSeconds'] for x in o['fragments']),120)
        self.assertEqual(o['endBoundaryRows'],1)

class ActualSensitivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary=Path(os.environ.get('NROOP_REPLAY_BIN','/nonexistent'))
        if not cls.binary.is_file():raise unittest.SkipTest('Build real Swift replay and set NROOP_REPLAY_BIN')
    def test_real_engine_order_and_duplicate_scores_and_source_preservation(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'input.json';p.write_text(json.dumps(recording()));before=p.read_bytes()
            out=Path(d)/'audit';s=run_sensitivity(p,self.binary,out)
            self.assertEqual(p.read_bytes(),before)
            for k in ['reversed','duplicated']:
                for m,v in s['variants'][k]['comparison'].items():
                    self.assertIn(v['originalDelta'],[None,0]);self.assertIn(v['candidateDelta'],[None,0])
            self.assertTrue((out/'sensitivity.html').is_file())
            with self.assertRaises(ValueError):run_sensitivity(p,self.binary,out)
    def test_out_of_domain_stress_variant_is_reported_without_discarding_other_results(self):
        with tempfile.TemporaryDirectory() as d:
            r=recording();r['hr'][0]['bpm']=300
            p=Path(d)/'input.json';p.write_text(json.dumps(r))
            s=run_sensitivity(p,self.binary,Path(d)/'audit')
            self.assertEqual(s['variants']['hr-plus-3']['status'],'rejected')
            self.assertEqual(s['variants']['identity']['status'],'complete')
            self.assertEqual(s['variants']['hr-plus-3']['comparison'],{})
            self.assertIn('rejected',(Path(d)/'audit/sensitivity.html').read_text())
    def test_replay_timeout_or_failure_never_looks_like_zero_error(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'input.json';p.write_text(json.dumps(recording()))
            # A real system executable rejects the replay arguments; no synthetic scoring double.
            with self.assertRaises(ValueError):run_sensitivity(p,Path('/usr/bin/false'),Path(d)/'audit')
