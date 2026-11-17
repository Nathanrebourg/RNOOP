import json,os,subprocess,tempfile,unittest
from pathlib import Path
class SleepResearchCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary=Path(os.environ.get('NROOP_SLEEP_BIN','/nonexistent'))
        if not cls.binary.is_file():raise unittest.SkipTest('Set actual NROOP_SLEEP_BIN')
    def test_prepared_case_vectors_without_unit_field_decode_and_score(self):
        start=1699999980
        case={'schema':1,'dataset':'bidsleep-1.0.1','reference':'dreem2-expert','origin':'synthetic','subject':'fixture','night':'1','split':'training',
            'start':start,'end':start+120,'hr':[{'ts':start+i*5,'bpm':60} for i in range(24)],
            'gravity':[{'ts':start+i,'x':0,'y':0,'z':1} for i in range(120)],'truth':['wake','light','deep','rem']}
        with tempfile.TemporaryDirectory() as d:
            src=Path(d)/'case.json';dst=Path(d)/'report.json';src.write_text(json.dumps(case))
            r=subprocess.run([str(self.binary),'--research-case',str(src),'--research-output',str(dst),'--variants','shipped'],capture_output=True,text=True,timeout=15)
            self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(dst.read_text())['variants']['shipped']['epochs'],4)
    def test_corrupt_extreme_timestamp_is_clean_error_not_overflow(self):
        start=(9223372036854775807//30-4)*30
        case={'schema':1,'dataset':'bidsleep-1.0.1','reference':'dreem2-expert','origin':'synthetic','subject':'fixture','night':'1','split':'training',
            'start':start,'end':start+120,'hr':[],'gravity':[],'truth':['wake']*4}
        with tempfile.TemporaryDirectory() as d:
            src=Path(d)/'case.json';dst=Path(d)/'report.json';src.write_text(json.dumps(case));before=src.read_bytes()
            r=subprocess.run([str(self.binary),'--research-case',str(src),'--research-output',str(dst),'--variants','shipped'],capture_output=True,text=True,timeout=15)
            self.assertEqual(src.read_bytes(),before);self.assertEqual(r.returncode,2,r.stderr[-500:]);self.assertFalse(dst.exists())
