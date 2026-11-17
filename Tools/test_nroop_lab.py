import csv
import hashlib
import json
import sqlite3
import tempfile
import unittest
import zipfile
from contextlib import contextmanager, closing
from pathlib import Path
from nroop_lab import convert, evaluate, read_references, render_html

class LabToolsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = self.root / 'sample.sqlite'
        with self.connection() as c:
            c.executescript('''CREATE TABLE hrSample(deviceId TEXT,ts INTEGER,bpm INTEGER);
            CREATE TABLE gravitySample(deviceId TEXT,ts INTEGER,x REAL,y REAL,z REAL);
            CREATE TABLE rrInterval(deviceId TEXT,ts INTEGER,rrMs INTEGER,srcChannel INTEGER,tsSuspect INTEGER,ord INTEGER,seq INTEGER);
            CREATE TABLE dailyMetric(deviceId TEXT,day TEXT,totalSleepMin REAL,avgHrv REAL,restingHr INTEGER,respRateBpm REAL);
            CREATE TABLE journal(deviceId TEXT,day TEXT,question TEXT,answeredYes INTEGER);
            CREATE TABLE event(deviceId TEXT,ts INTEGER,kind TEXT);
            CREATE TABLE sleepStateSample(deviceId TEXT,ts INTEGER,state INTEGER);''')
            c.execute('INSERT INTO hrSample VALUES(?,?,?)',('strap',1728003600,70))
            c.executemany('INSERT INTO rrInterval VALUES(?,?,?,?,?,?,?)',[
                ('strap',1728003600,1000,5,None,0,0),('strap',1728003601,900,7,None,0,0),
                ('strap',1728003602,500,None,None,0,0),('strap',1728003603,500,5,1,0,0)])
    @contextmanager
    def connection(self):
        with closing(sqlite3.connect(self.db)) as c:
            with c: yield c
    def tearDown(self): self.tmp.cleanup()
    def snapshot(self,path=None):
        return convert(path or self.db,owner='strap',day='2024-10-04',offset=0,age=30,case_id='one')
    def test_converter_is_read_only_and_never_mixes_sources(self):
        with self.connection() as c: c.execute('INSERT INTO hrSample VALUES(?,?,?)',('other',1728003600,200))
        before = hashlib.sha256(self.db.read_bytes()).hexdigest()
        r = self.snapshot()
        self.assertEqual([x['bpm'] for x in r['hr']],[70])
        self.assertEqual(hashlib.sha256(self.db.read_bytes()).hexdigest(),before)
        self.assertEqual(r['origin'],'recorded')
    def test_rr_uses_one_labelled_whoop5_transport_and_quarantine(self):
        self.assertEqual([x['rrMs'] for x in self.snapshot()['rr']],[1000])
    def test_only_prior_computed_nights_and_explicit_journal_context_are_exported(self):
        with self.connection() as c:
            c.executemany('INSERT INTO dailyMetric VALUES(?,?,?,?,?,?)',[
                ('strap-noop','2024-10-03',540,60,55,14),('strap','2024-10-02',600,60,55,14),
                ('strap-noop','2024-10-04',700,60,55,14)])
        h = self.snapshot()['history']
        self.assertEqual(len(h),1)
        self.assertNotIn('naturalWake',h[0])
        self.assertEqual(h[0]['source'],'computed')
    def test_backup_reads_only_the_expected_database_entry(self):
        p = self.root / 'file.noopbak'
        with zipfile.ZipFile(p,'w') as z:
            z.write(self.db,'noop-backup.sqlite'); z.writestr('../outside','ignore')
        self.assertEqual(self.snapshot(p)['hr'],self.snapshot()['hr'])
        self.assertFalse((self.root.parent / 'outside').exists())
    def test_ambiguous_database_entries_and_active_wal_are_refused(self):
        p = self.root / 'bad.noopbak'
        with zipfile.ZipFile(p,'w') as z: z.write(self.db,'unexpected.sqlite')
        with self.assertRaises(ValueError): self.snapshot(p)
        Path(str(self.db)+'-wal').write_bytes(b'pending')
        with self.assertRaises(ValueError): self.snapshot()
    def test_corrupt_numeric_sensor_values_are_not_exported_to_the_engine(self):
        with self.connection() as c: c.execute('UPDATE hrSample SET bpm=?',(9223372036854775807,))
        with self.assertRaises(ValueError): self.snapshot()
    def report(self,origin='recorded',case='one',day=1728000000):
        return {'schema':1,'model':'nroop-lab-v1','origin':origin,'caseID':case,'ownerHash':'owner','dayStart':day,
                'inputSHA256':'a'*64,'metrics':{'hrmax':{'original':190,'candidate':185,'unit':'bpm','status':'compared'}}}
    def test_evaluation_uses_same_matched_holdout_cases(self):
        refs={('one','hrmax'):{'value':184,'source':'measured','independent':True,'split':'holdout'}}
        summary=evaluate([self.report()],refs)
        self.assertEqual(summary['metrics']['hrmax']['n'],1)
        self.assertEqual(summary['metrics']['hrmax']['original_mae'],6)
        self.assertEqual(summary['metrics']['hrmax']['candidate_mae'],1)
    def test_synthetic_and_training_cases_cannot_claim_real_validation(self):
        refs={('one','hrmax'):{'value':184,'source':'measured','independent':True,'split':'holdout'}}
        self.assertEqual(evaluate([self.report('synthetic')],refs)['metrics'],{})
        refs[('one','hrmax')]['split']='training'
        self.assertEqual(evaluate([self.report()],refs)['metrics'],{})
    def test_missing_candidate_is_not_zero_or_a_better_score(self):
        r=self.report();r['metrics']['hrmax']['candidate']=None
        refs={('one','hrmax'):{'value':184,'source':'measured','independent':True,'split':'holdout'}}
        s=evaluate([r],refs)
        self.assertEqual(s['metrics'],{})
        self.assertEqual(s['unavailable'],1)
    def test_duplicate_owner_day_nonfinite_and_self_reference_are_rejected(self):
        with self.assertRaises(ValueError): evaluate([self.report(),self.report(case='two')],{})
        r=self.report();r['metrics']['hrmax']['candidate']=float('nan')
        with self.assertRaises(ValueError): evaluate([r],{})
        p=self.root/'references.csv'
        p.write_text('caseID,metric,value,source,independent,split\none,hrmax,184,nroop,true,holdout\n')
        with self.assertRaises(ValueError): read_references(p)
    def test_mixed_metric_units_are_rejected_before_error_comparison(self):
        r=self.report();r['metrics']['hrmax']['unit']='hours'
        with self.assertRaises(ValueError): evaluate([r],{})
    def test_descriptive_case_values_remain_visible_without_accuracy_claim(self):
        s=evaluate([self.report('synthetic')],{})
        page=render_html(s)
        self.assertIn('185',page)
        self.assertEqual(s['metrics'],{})
    def test_html_is_standalone_and_escapes_case_identifiers(self):
        r=self.report(case='<script>alert(1)</script>')
        html=render_html(evaluate([r],{}))
        self.assertNotIn('<script>alert(1)</script>',html)
        self.assertIn('&lt;script&gt;',html)
        self.assertNotIn('https://',html)

if __name__=='__main__': unittest.main()
