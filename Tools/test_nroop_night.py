import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from nroop_night import read_bundle, extract_recording


class NightDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def bundle(self, *, corrupt=False, duplicate=False, extra=False, wrong_format=False):
        entries = {'recording.json': b'{"schema":1,"origin":"recorded","caseID":"night"}',
                   'app-snapshot.json': b'{}', 'replay-baselines.json': b'{}',
                   'coverage.json': b'{}', 'README.txt': b'local'}
        manifest = {'schema': 1, 'format': 'other' if wrong_format else 'nroop-night-diagnostic-v1',
                    'sha256': {k: hashlib.sha256(v).hexdigest() for k, v in entries.items()}}
        if corrupt: entries['recording.json'] += b' '
        path = self.root / 'night.zip'
        with zipfile.ZipFile(path, 'w') as z:
            for k, v in entries.items(): z.writestr(k, v)
            z.writestr('manifest.json', json.dumps(manifest))
            if duplicate: z.writestr('recording.json', b'{}')
            if extra: z.writestr('../outside', b'anything')
        return path, entries['recording.json']
    def test_exact_bytes_roundtrip_and_no_source_mutation(self):
        path, recording = self.bundle(); before = path.read_bytes()
        self.assertEqual(read_bundle(path)['recording.json'], recording)
        target = self.root / 'recording.json'
        extract_recording(path, target)
        self.assertEqual(target.read_bytes(), recording)
        self.assertEqual(path.read_bytes(), before)
    def test_output_never_overwrites_an_existing_file(self):
        path, _ = self.bundle(); target = self.root / 'keep.json'; target.write_text('keep')
        with self.assertRaises(FileExistsError): extract_recording(path, target)
        self.assertEqual(target.read_text(), 'keep')
    def test_all_member_hashes_are_required(self):
        path, _ = self.bundle(corrupt=True)
        with self.assertRaisesRegex(ValueError, 'checksum'): read_bundle(path)
    def test_duplicate_names_are_refused(self):
        path, _ = self.bundle(duplicate=True)
        with self.assertRaisesRegex(ValueError, 'members'): read_bundle(path)
    def test_unlisted_members_are_not_extracted(self):
        path, _ = self.bundle(extra=True)
        with self.assertRaisesRegex(ValueError, 'members'): read_bundle(path)
        self.assertFalse((self.root.parent / 'outside').exists())
    def test_version_is_not_guessed(self):
        path, _ = self.bundle(wrong_format=True)
        with self.assertRaisesRegex(ValueError, 'format'): read_bundle(path)
    def test_oversized_member_is_refused_before_read(self):
        path, _ = self.bundle()
        with self.assertRaisesRegex(ValueError, 'size'): read_bundle(path, max_bytes=10)


if __name__ == '__main__': unittest.main()
