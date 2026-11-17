import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

class ReplayExecutableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary=Path(os.environ.get('NROOP_REPLAY_BIN','/nonexistent'))
        if not cls.binary.is_file(): raise unittest.SkipTest('Set NROOP_REPLAY_BIN to the built real Swift executable.')
    def recording(self):
        day=1728000000;start=day+3600
        return {'schema':1,'origin':'synthetic','caseID':'test','owner':'strap','dayStart':day,'now':day+36000,'offset':0,'age':30,
                'hr':[{'ts':start+i,'bpm':70} for i in range(300)],
                'gravity':[{'ts':start+i,'x':0,'y':0,'z':1} for i in range(300)],
                'rr':[],'events':[],'band':[],'history':[],'historyStreams':[]}
    def run_record(self,r,same=False):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'input.json';o=p if same else Path(d)/'report.json'
            p.write_text(json.dumps(r));before=hashlib.sha256(p.read_bytes()).hexdigest()
            result=subprocess.run([str(self.binary),str(p),str(o)],capture_output=True,text=True,timeout=30)
            self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),before)
            output=json.loads(o.read_text()) if result.returncode==0 else None
            return result,output
    def test_actual_engine_replays_and_preserves_synthetic_provenance(self):
        result,r=self.run_record(self.recording())
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(r['origin'],'synthetic');self.assertEqual(r['model'],'nroop-lab-v1')
        self.assertEqual(set(r['metrics']),{'recovery','hrmax','sleep_need'})
        self.assertEqual(len(r['inputSHA256']),64)
    def test_research_is_separate_versioned_and_missing_is_not_zero(self):
        result,r=self.run_record(self.recording())
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(r['research']['version'],'nroop-research-v1')
        self.assertEqual(r['research']['baselineComparison']['status'],'insufficient-history-quality')
        self.assertIsNone(r['research']['baselineComparison'].get('candidate'))
        self.assertEqual(r['research']['recipe'],{'deepWindow':False,'useV2':True})
    def test_history_witness_must_match_its_exact_historical_vital(self):
        r=self.recording()
        r['history']=[{'dayStart':r['dayStart']-86400,'source':'computed','hrv':60,
            'evidence':{'version':'nroop-research-v1','origin':'synthetic','ownerHash':hashlib.sha256(b'strap').hexdigest(),'dayStart':r['dayStart']-86400,'useV2':True,'deepWindow':False,'inputSHA256':'a'*64,'hrv':61,'hrvQuality':1,'rhrQuality':1}}]
        result,_=self.run_record(r)
        self.assertEqual(result.returncode,2)
    def test_out_of_range_historical_quality_is_rejected(self):
        r=self.recording()
        r['history']=[{'dayStart':r['dayStart']-86400,'source':'computed','hrv':60,
            'evidence':{'version':'nroop-research-v1','origin':'synthetic','ownerHash':hashlib.sha256(b'strap').hexdigest(),'dayStart':r['dayStart']-86400,'useV2':True,'deepWindow':False,'inputSHA256':'a'*64,'hrv':60,'hrvQuality':2,'rhrQuality':1}}]
        result,_=self.run_record(r)
        self.assertEqual(result.returncode,2)
    def test_declared_storage_identity_preserves_rich_duplicate_recovery(self):
        from nroop_lab import example
        r=example();r['historyStreams']=[]
        first,a=self.run_record(r);self.assertEqual(first.returncode,0,first.stderr)
        self.assertIsNotNone(a['metrics']['recovery'].get('original'))
        r['rr']=r['rr']*2
        second,b=self.run_record(r);self.assertEqual(second.returncode,0,second.stderr)
        self.assertEqual(a['metrics'],b['metrics'])
        self.assertEqual(b['research']['rrNormalization']['duplicates'],21600)
    def test_conflicting_declared_storage_identity_is_rejected(self):
        r=self.recording();r['rrIdentity']='store-key-v1'
        r['rr']=[{'ts':r['dayStart']+3600,'rrMs':1000,'srcChannel':5,'seq':0,'ord':i} for i in [0,1]]
        result,_=self.run_record(r);self.assertEqual(result.returncode,2)
    def test_identical_recording_has_identical_deterministic_report(self):
        a,first=self.run_record(self.recording());b,second=self.run_record(self.recording())
        self.assertEqual(a.returncode,0,a.stderr);self.assertEqual(b.returncode,0,b.stderr)
        self.assertEqual(first,second)
    def test_corrupt_bpm_is_cleanly_rejected_instead_of_integer_overflow(self):
        r=self.recording();start=r['dayStart']+3600
        r['hr']=[{'ts':start+i,'bpm':9223372036854775807} for i in range(5400)]
        r['gravity']=[{'ts':start+i,'x':0,'y':0,'z':1} for i in range(5400)]
        result,_=self.run_record(r)
        self.assertEqual(result.returncode,2)
    def test_giant_gravity_and_rr_are_clean_errors(self):
        for field in ['gravity','rr']:
            r=self.recording()
            if field=='gravity':r['gravity'][0]['x']=1e300
            else:r['rr']=[{'ts':r['dayStart']+3600,'rrMs':9223372036854775807,'srcChannel':5}]
            result,_=self.run_record(r);self.assertEqual(result.returncode,2)
    def test_future_history_or_mixed_owner_never_trains_a_candidate(self):
        for kind in ['future','owner']:
            r=self.recording()
            if kind=='future':r['history']=[{'dayStart':r['dayStart'],'source':'computed','hours':9}]
            else:r['historyStreams']=[{'owner':'other','dayStart':r['dayStart']-86400,'hr':[],'gravity':[]}]
            result,_=self.run_record(r);self.assertEqual(result.returncode,2)
    def test_legacy_or_mixed_rr_transport_is_refused(self):
        for codes in [[None],[5,7]]:
            r=self.recording();r['rr']=[{'ts':r['dayStart']+3600+i,'rrMs':1000,'srcChannel':c} for i,c in enumerate(codes)]
            result,_=self.run_record(r);self.assertEqual(result.returncode,2)
    def test_existing_outputs_and_symlink_aliases_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'recording.json';p.write_text(json.dumps(self.recording()))
            alias=Path(directory)/'alias.json';alias.symlink_to(p)
            original=p.read_bytes()
            result=subprocess.run([str(self.binary),str(alias),str(p)],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,2)
            self.assertEqual(p.read_bytes(),original)
            output=Path(directory)/'existing.json';output.write_bytes(b'keep')
            result=subprocess.run([str(self.binary),str(p),str(output)],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,2)
            self.assertEqual(output.read_bytes(),b'keep')
    def test_input_cannot_be_overwritten(self):
        result,_=self.run_record(self.recording(),same=True);self.assertEqual(result.returncode,2)
    def test_replay_scope_is_explicitly_prior_computed(self):
        result,r=self.run_record(self.recording());self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('scope=replay-prior-computed-baselines',r['lines'][1])
    def test_invalid_offset_is_error_not_integer_trap(self):
        r=self.recording();r['offset']=-9223372036854775808
        result,_=self.run_record(r);self.assertEqual(result.returncode,2)

if __name__=='__main__':unittest.main()
