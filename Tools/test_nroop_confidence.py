import copy,unittest
from nroop_confidence import fit_calibration,evaluate_calibration

def case(subject,quality,error,split='training',origin='recorded'):
    suffix=subject+'-'+str(quality)
    import hashlib
    return {'subject':subject,'caseID':suffix,'inputSHA256':hashlib.sha256(suffix.encode()).hexdigest(),'origin':origin,'split':split,
        'metric':'sleep-stage-error','unit':'fraction','qualityMethod':'availability-v1','model':'frozen-model',
        'source':'dreem2-expert','independent':True,'quality':quality,'error':error}
class ConfidenceCalibrationTests(unittest.TestCase):
    def training(self):return [case('a'+str(i),.2,.8) for i in range(3)]+[case('b'+str(i),.8,.1) for i in range(3)]
    def test_threshold_uses_training_error_budget_and_is_frozen(self):
        x=fit_calibration(self.training(),max_error=.2)
        self.assertEqual(x['threshold'],.25)
        y=evaluate_calibration(x,[case('h'+str(i),.8,.9,'holdout') for i in range(3)])
        self.assertEqual(x['threshold'],.25);self.assertFalse(y['selected']['budgetAchieved'])
        self.assertAlmostEqual(y['selected']['meanError'],.9)
    def test_subject_overlap_and_duplicate_recordings_are_rejected(self):
        x=fit_calibration(self.training(),max_error=.2)
        with self.assertRaises(ValueError):evaluate_calibration(x,[case('a0',.9,.1,'holdout')])
        with self.assertRaises(ValueError):fit_calibration(self.training()+[self.training()[0]],max_error=.2)
    def test_synthetic_never_fits_and_missing_is_not_zero_error(self):
        rows=[case('s'+str(i),1,0,origin='synthetic') for i in range(10)]
        self.assertIsNone(fit_calibration(rows,max_error=.2)['threshold'])
        rows=self.training();rows.append(case('missing',None,None))
        self.assertEqual(fit_calibration(rows,max_error=.2)['excludedUnavailable'],1)
    def test_unavailable_training_cases_still_reserve_their_participant_split(self):
        selection=fit_calibration(self.training()+[case('reserved',None,None)],max_error=.2)
        held=[case(subject,.8,.1,'holdout') for subject in ['reserved','h1','h2']]
        with self.assertRaises(ValueError):evaluate_calibration(selection,held)
    def test_no_feasible_threshold_is_explicit(self):
        x=fit_calibration([case('a'+str(i),.8,.9) for i in range(4)],max_error=.1)
        self.assertIsNone(x['threshold']);self.assertEqual(x['status'],'no-threshold-meets-budget')
    def test_invalid_nonfinite_quality_and_mixed_recipes_are_rejected(self):
        for field,value in [('quality',float('nan')),('error',-1),('model','other'),('unit','bpm'),('independent',False)]:
            rows=self.training();rows[-1][field]=value
            with self.assertRaises(ValueError):fit_calibration(rows,max_error=.2)
    def test_holdout_cannot_be_present_during_fitting(self):
        rows=self.training()+[case('future',1,0,'holdout')]
        with self.assertRaises(ValueError):fit_calibration(rows,max_error=.2)
    def test_insufficient_real_participants_does_not_claim_calibration(self):
        x=fit_calibration([case('a',.8,.1),case('b',.9,.1)],max_error=.2)
        self.assertEqual(x['status'],'insufficient-training-participants');self.assertIsNone(x['threshold'])
