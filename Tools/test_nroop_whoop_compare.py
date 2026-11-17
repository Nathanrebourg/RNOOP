import tempfile
import unittest
import zipfile
from pathlib import Path

from nroop_whoop_compare import compare, csv_text, rows


class NroopComparisonTests(unittest.TestCase):
    def test_excludes_imports_and_computes_error_from_independent_days(self):
        whoop = ('Cycle start time,Recovery score %,Day Strain,Heart rate variability (ms)\n'
                 '2026-04-10 07:00:00,80,12.0,60\n2026-04-11 07:00:00,50,5.0,40\n')
        nroop = ('Cycle start time,Recovery score %,Day Strain,Heart rate variability (ms),Source\n'
                 '2026-04-10 00:00:00,75,13.0,55,noop (APPROXIMATE)\n'
                 '2026-04-11 00:00:00,50,5.0,40,import\n')
        ref, _, _ = rows(whoop, False)
        candidate, excluded, _ = rows(nroop, True)
        result = compare(ref, candidate)
        self.assertEqual(excluded, 1)
        self.assertEqual(result['recovery']['n'], 1)
        self.assertEqual(result['recovery']['bias'], -5)
        self.assertEqual(result['strain']['mae'], 1)
        self.assertEqual(result['hrv']['mae'], 5)

    def test_french_headers_decimal_comma_and_duplicate_days(self):
        data = ("Heure de début du cycle;Score de récupération %;Effort du jour;Source\n"
                "10/04/2026 06:00;55;12,5;noop (APPROXIMATE)\n"
                "11/04/2026 06:00;45;10,0;noop (APPROXIMATE)\n"
                "11/04/2026 07:00;70;11,0;noop (APPROXIMATE)\n")
        parsed, excluded, duplicates = rows(data, True)
        self.assertEqual(excluded, 0)
        self.assertEqual(duplicates, 1)
        self.assertEqual(parsed['2026-04-10']['strain'], 12.5)
        self.assertNotIn('2026-04-11', parsed)

    def test_unknown_source_is_never_mistaken_for_computed(self):
        with self.assertRaisesRegex(ValueError, 'Source'):
            rows('Cycle start time,Recovery score %\n2026-04-10,50\n', True)
        parsed, excluded, _ = rows('Cycle start time,Recovery score %,Source\n2026-04-10,50,\n', True)
        self.assertEqual(parsed, {})
        self.assertEqual(excluded, 1)

    def test_zip_and_invalid_numbers(self):
        data = ('Cycle start time,Recovery score %,Day Strain,Source\n'
                '2026-04-10,nan,35,noop (APPROXIMATE)\n')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'export.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('export/physiological_cycles.csv', data)
            parsed, _, _ = rows(csv_text(path), True)
        self.assertEqual(parsed['2026-04-10'], {})


if __name__ == '__main__':
    unittest.main()
