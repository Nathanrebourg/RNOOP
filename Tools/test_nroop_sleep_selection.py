import copy,hashlib,unittest
from nroop_sleep_selection import choose_variant,validate_holdout,VARIANTS,VERSION as VERSION_FOR_TEST

def report(subject,split='training'):
    return {'version':'nroop-sleep-selection-v1','dataset':'bidsleep-1.0.1','reference':'dreem2-expert','origin':'recorded',
        'subject':subject,'night':'1','split':split,'inputSHA256':hashlib.sha256(subject.encode()).hexdigest(),
        'variants':{v:{'macroF1':.5 if v=='shipped' else .4} for v in VARIANTS}}
class SleepSelectionTests(unittest.TestCase):
    def test_only_training_participants_can_choose_and_ties_keep_incumbent(self):
        rows=[report('t'+str(i)) for i in range(3)]
        self.assertEqual(choose_variant(rows)['chosen'],'shipped')
        for r in rows:r['variants']['awake-020']['macroF1']=.7
        self.assertEqual(choose_variant(rows)['chosen'],'awake-020')
        with self.assertRaises(ValueError):choose_variant(rows+[report('h','holdout')])
    def test_heldout_overlap_is_refused(self):
        selection=choose_variant([report('t'+str(i)) for i in range(3)])
        with self.assertRaises(ValueError):validate_holdout(selection,[report('t0','holdout')])
    def test_confidence_artifact_from_another_run_is_refused_before_scoring(self):
        import tempfile,json
        from pathlib import Path
        from nroop_sleep_selection import run_holdout
        from nroop_research import digest
        from nroop_confidence import fit_calibration
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);binary=Path('/usr/bin/true')
            selection={'version':VERSION_FOR_TEST,'chosen':'shipped','trainingSubjects':['t0','t1','t2'],'trainingInputHashes':[],
                'executableSHA256':digest(binary.read_bytes()),'confidenceSHA256':'a'*64,'interpretation':'test'}
            confidence=fit_calibration([],max_error=.4)
            for name,value in [('selection.json',selection),('confidence.json',confidence),('manifest.json',{'cases':[]})]:(d/name).write_text(json.dumps(value))
            with self.assertRaises(ValueError):run_holdout(d/'manifest.json',binary,d/'selection.json',d/'confidence.json',d/'result')
    def test_summary_exposes_stage_fraction_bias_alongside_f1(self):
        from nroop_sleep_selection import aggregate
        r=report('t0');x=r['variants']['shipped']
        x.update(confusion=[[5,5,0,0],[0,10,0,0],[0,0,10,0],[0,0,0,10]],epochs=40,accuracy=.875,
            perStage={k:{'f1':v} for k,v in [('wake',2/3),('light',.8),('deep',1),('rem',1)]})
        a=aggregate([r],'shipped')
        self.assertEqual(a['pooledStageFractionBiasPP']['wake'],-12.5)
        self.assertEqual(a['pooledStageFractionBiasPP']['light'],12.5)
        self.assertAlmostEqual(a['meanParticipantStageF1']['wake'],2/3)
    def test_duplicate_input_and_missing_training_recipes_are_not_silent(self):
        with self.assertRaises(ValueError):choose_variant([report('t0')]*3)
        rows=[report('t'+str(i)) for i in range(3)];del rows[0]['variants']['rem-016']
        with self.assertRaises(ValueError):choose_variant(rows)
