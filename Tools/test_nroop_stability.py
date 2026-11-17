import copy,json,os,tempfile,unittest
from pathlib import Path
from nroop_stability import progressive_input,sync_audit
DAY=1728000000

def recording():
    lo=DAY-108000
    return {'schema':1,'origin':'recorded','caseID':'sync','owner':'strap','dayStart':DAY,'now':DAY+3600,'offset':0,'age':30,
        'hr':[{'ts':lo+i*1000,'bpm':70} for i in range(111)],'rr':[],'gravity':[],'events':[],'band':[],
        'history':[{'dayStart':DAY-86400,'source':'computed','hrv':60}],'historyStreams':[]}
class ProgressiveInputTests(unittest.TestCase):
    def test_fixed_clock_history_and_source_are_preserved(self):
        r=recording();before=copy.deepcopy(r);x=progressive_input(r,0.25,'oldest-first')
        self.assertEqual(r,before);self.assertEqual(x['now'],r['now']);self.assertEqual(x['history'],r['history'])
        self.assertEqual(x['origin'],'synthetic');self.assertLess(len(x['hr']),len(r['hr']))
    def test_opposite_arrival_directions_and_full_input(self):
        r=recording();a=progressive_input(r,.25,'oldest-first');b=progressive_input(r,.25,'newest-first')
        self.assertLess(max(h['ts'] for h in a['hr']),min(h['ts'] for h in b['hr']))
        self.assertEqual(progressive_input(r,1,'newest-first')['hr'],r['hr'])
    def test_recent_hour_percentages_follow_captured_timestamps(self):
        r=recording();r['hr']=[{'ts':DAY+i,'bpm':70} for i in range(3600)]
        x=progressive_input(r,.25,'oldest-first')
        self.assertEqual(len(x['hr']),900)
    def test_invalid_fraction_and_direction_are_refused(self):
        for fraction,direction in [(0,'oldest-first'),(1.1,'oldest-first'),(.5,'guessed')]:
            with self.assertRaises(ValueError):progressive_input(recording(),fraction,direction)
class ActualProgressiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary=Path(os.environ.get('NROOP_REPLAY_BIN','/nonexistent'))
        if not cls.binary.is_file():raise unittest.SkipTest('Set actual NROOP_REPLAY_BIN')
    def test_actual_replay_marks_partial_results_provisional_and_preserves_missing(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'input.json';p.write_text(json.dumps(recording()));raw=p.read_bytes()
            x=sync_audit(p,self.binary,Path(d)/'audit')
            self.assertEqual(p.read_bytes(),raw);self.assertEqual(len(x['steps']),8)
            self.assertTrue(all(v['state']=='provisional' for v in x['steps'] if v['fraction']<1))
            self.assertTrue(all(v['state']=='available-input-reference' for v in x['steps'] if v['fraction']==1))
            self.assertTrue(all(v['strapCollectionComplete'] is None for v in x['steps']))
            self.assertTrue(all(v['comparison']['recovery']['candidateDelta'] is None for v in x['steps']))
            self.assertTrue((Path(d)/'audit/synchronization.html').is_file())
