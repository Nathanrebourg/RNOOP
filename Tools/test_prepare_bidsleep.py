import csv,tempfile,unittest
from pathlib import Path
from prepare_bidsleep import label_stage,rec_start_utc,convert_night,subject_split
class BIDSleepAdapterTests(unittest.TestCase):
    def test_reference_rem_is_four_and_five_is_unknown(self):
        self.assertEqual([label_stage(i) for i in range(6)],['wake','light','light','deep','rem',None])
        with self.assertRaises(ValueError):label_stage(9)
    def test_eastern_local_timestamp_and_ambiguous_clock_are_explicit(self):
        self.assertEqual(rec_start_utc('2021-12-10 22:35:53'),1639193753)
        with self.assertRaises(ValueError):rec_start_utc('2021-11-07 01:30:00')
        with self.assertRaises(ValueError):rec_start_utc('2021-03-14 02:30:00')
    def test_subject_partition_is_stable_and_never_night_based(self):
        self.assertEqual(subject_split('Bidslab00'),'holdout');self.assertEqual(subject_split('Bidslab01'),'training')
    def test_motion_buckets_use_relative_second_floor_and_unknown_reference_stays_missing(self):
        try:
            import numpy as np
            from scipy.io import savemat
        except ImportError:self.skipTest('Optional scipy needed for real MAT fixture')
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);start=1639193753
            savemat(p/'labels.mat',{'recStart':'2021-12-10 22:35:53','expert_label':np.array([[0,4,5]])})
            (p/'hr.csv').write_text(f'{start+.9},60\n{start+5},61\n')
            (p/'motion.csv').write_text(f'Timestamp,x,y,z\n{start+.1},0,0,1\n{start+.9},1,0,0\n{start+1.1},0,1,0\n')
            r=convert_night(p,subject='Bidslab01',night='1')
            self.assertEqual(r['truth'],['wake','rem',None]);self.assertEqual(r['hr'][0]['ts'],r['start'])
            self.assertEqual(r['gravity'][0]['x'],.5);self.assertEqual(len(r['gravity']),2)
            self.assertEqual(r['end']-r['start'],90)
    def test_corrupt_stream_is_not_silently_clipped(self):
        try:
            import numpy as np
            from scipy.io import savemat
        except ImportError:self.skipTest('Optional scipy needed for real MAT fixture')
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);savemat(p/'labels.mat',{'recStart':'2021-12-10 22:35:53','expert_label':np.array([[0]])})
            (p/'hr.csv').write_text('1639193753,999\n');(p/'motion.csv').write_text('1639193753,0,0,1\n')
            with self.assertRaises(ValueError):convert_night(p,subject='Bidslab01',night='1')
