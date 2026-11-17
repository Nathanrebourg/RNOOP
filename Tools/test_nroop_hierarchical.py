import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from nroop_hierarchical import summarize, validate_identity, read_capped_json, bounded_metadata

class HierarchicalSummaryTests(unittest.TestCase):
    def test_unknown_prediction_counts_as_reference_error_not_wake(self):
        result=summarize([{'subject':'one','truth':['wake','deep','light','rem'],'predictions':['unknown','deep','light','rem']}])
        self.assertEqual(result['referenceEpochs'],4)
        self.assertEqual(result['coveredReferenceEpochs'],3)
        self.assertEqual(result['referenceAccuracy'],.75)
        self.assertEqual(result['conditionalAccuracy'],1)
        self.assertEqual(result['meanParticipantReferenceMacroF1'],.75)
        self.assertEqual(result['meanParticipantStageF1']['wake'],0)
    def test_participants_are_equally_weighted_not_night_or_epoch_weighted(self):
        result=summarize([{'subject':'a','truth':['wake','light','deep','rem'],'predictions':['wake','light','deep','rem']},
            {'subject':'b','truth':['wake']*100,'predictions':['light']*100}])
        self.assertEqual(result['meanParticipantReferenceMacroF1'],.5)
        self.assertAlmostEqual(result['referenceAccuracy'],4/104)
    def test_no_observations_has_no_conditional_score(self):
        result=summarize([{'subject':'a','truth':['wake',None],'predictions':['unknown','light']}])
        self.assertEqual(result['referenceEpochs'],1)
        self.assertIsNone(result['conditionalAccuracy'])
        self.assertEqual(result['referenceAccuracy'],0)
    def test_malformed_predictions_are_rejected_instead_of_silently_discarded(self):
        with self.assertRaises(ValueError): summarize([{'subject':'a','truth':['wake'],'predictions':[]}])
        with self.assertRaises(ValueError): summarize([{'subject':'a','truth':['wake'],'predictions':['unrecognized']}])
    def test_subject_and_input_cannot_repeat_across_manifests(self):
        seen_subjects=set();seen_inputs=set()
        validate_identity('a','0'*64,seen_subjects,seen_inputs)
        with self.assertRaises(ValueError): validate_identity('a','1'*64,seen_subjects,seen_inputs)
        with self.assertRaises(ValueError): validate_identity('b','0'*64,seen_subjects,seen_inputs)

    def test_empty_common_support_is_reported_as_unavailable(self):
        result=summarize([{'subject':'one','truth':[None,None],'predictions':['unknown','unknown']}])
        self.assertEqual(result['participants'],1)
        self.assertEqual(result['participantsWithReference'],0)
        self.assertIsNone(result['meanParticipantReferenceMacroF1'])
        self.assertIsNone(result['referenceAccuracy'])

    def test_bounded_reader_rejects_oversized_file_before_json(self):
        with tempfile.TemporaryDirectory() as directory:
            src=Path(directory)/'large.json';src.write_text('{"array":[1,2,3]}')
            with self.assertRaises(ValueError):read_capped_json(src,8)
    def test_bounded_reader_checks_actual_read_after_stale_size(self):
        with tempfile.TemporaryDirectory() as directory:
            src=Path(directory)/'growth.json';src.write_text('{"array":[1,2,3]}')
            with patch.object(Path,'stat',return_value=SimpleNamespace(st_size=1)):
                with self.assertRaises(ValueError):read_capped_json(src,8)
    def test_bounded_reader_accepts_exact_limit_and_hashes_actual_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            src=Path(directory)/'exact.json';src.write_bytes(b'{"a":1}')
            raw,payload=read_capped_json(src,7)
            self.assertEqual(raw,b'{"a":1}')
            self.assertEqual(payload,{'a':1})

    def test_prepared_metadata_drops_sensor_arrays_and_bounds_retained_truth(self):
        source={'subject':'a','night':'a/1','truth':['wake',None],'hr':[{'ts':1,'bpm':60}],'gravity':[{'ts':1,'x':1,'y':0,'z':0}]}
        self.assertEqual(bounded_metadata(source),{'subject':'a','night':'a/1','truth':['wake',None]})
        with self.assertRaises(ValueError):bounded_metadata(source | {'truth':['wake']*2881})
        with self.assertRaises(ValueError):bounded_metadata(source | {'subject':'a'*257})
        with self.assertRaises(ValueError):bounded_metadata(source | {'truth':['garbage']})
