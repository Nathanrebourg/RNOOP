#!/usr/bin/env python3
"""Compare independent daily NOOP and WHOOP CSV exports locally.

This is a measurement tool, not a way to infer WHOOP's proprietary model. NROOP's
export may contain imported WHOOP data; only explicitly device-computed rows are
eligible, to avoid comparing an imported score with itself. A day-level source
label is not a guarantee of per-field independence, so review provenance too.
"""
from __future__ import annotations

import argparse
import csv
import io
import math
import re
import statistics
import unicodedata
import zipfile
from datetime import datetime
from pathlib import Path


def normalized(value: str) -> str:
    value = unicodedata.normalize('NFKD', value.casefold())
    value = ''.join(ch for ch in value if not unicodedata.combining(ch))
    value = value.replace('%', ' pct ')
    return re.sub(r'[^a-z0-9]+', '_', value).strip('_')


ALIASES = {
    'cycle_start_time': ('cycle_start_time', 'heure_de_debut_du_cycle'),
    'recovery': ('recovery_score_pct', 'score_de_recuperation_pct'),
    'strain': ('day_strain', 'effort_du_jour'),
    'hrv': ('heart_rate_variability_ms', 'heart_rate_variability_rmssd_ms',
            'variabilite_de_la_frequence_cardiaque_ms'),
    'rhr': ('resting_heart_rate_bpm', 'resting_heart_rate', 'frequence_cardiaque_au_repos_bpm'),
    'resp': ('respiratory_rate_rpm', 'respiratory_rate', 'frequence_respiratoire_tr_min'),
    'source': ('source',),
}
METRICS = {
    'recovery': ('Récupération', 'points', 0, 100),
    'strain': ('Effort', 'points / 21', 0, 21),
    'hrv': ('VFC', 'ms', 0.001, 1000),
    'rhr': ('FC repos', 'bpm', 1, 250),
    'resp': ('Respiration', '/ min', 1, 80),
}


def csv_text(path: Path) -> str:
    if path.suffix.casefold() != '.zip':
        return path.read_text(encoding='utf-8-sig')
    with zipfile.ZipFile(path) as archive:
        matches = [n for n in archive.namelist() if Path(n).name.casefold() == 'physiological_cycles.csv']
        if len(matches) != 1:
            raise ValueError('Le ZIP doit contenir un seul physiological_cycles.csv.')
        return archive.read(matches[0]).decode('utf-8-sig')


def day_key(value: str) -> str | None:
    value = value.strip()
    for fmt, width in (('%Y-%m-%d', 10), ('%d/%m/%Y', 10)):
        try:
            return datetime.strptime(value[:width], fmt).date().isoformat()
        except ValueError:
            pass
    return None


def number(raw: str, minimum: float, maximum: float) -> float | None:
    try:
        value = float(raw.strip().replace(',', '.'))
    except ValueError:
        return None
    return value if math.isfinite(value) and minimum <= value <= maximum else None


def rows(text: str, computed_only: bool) -> tuple[dict[str, dict[str, float]], int, int]:
    sample = text[:8192]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=',;\t')
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(io.StringIO(text), dialect=dialect)
    if not reader.fieldnames:
        raise ValueError('Le fichier CSV est vide.')
    columns = {normalized(name): name for name in reader.fieldnames}
    resolved = {key: next((columns[a] for a in names if a in columns), None)
                for key, names in ALIASES.items()}
    if resolved['cycle_start_time'] is None:
        raise ValueError('Colonne de début de cycle introuvable.')
    if computed_only and resolved['source'] is None:
        raise ValueError('La colonne Source est nécessaire pour exclure les données importées.')
    output: dict[str, dict[str, float]] = {}
    duplicate_days: set[str] = set()
    excluded = 0
    for raw in reader:
        day = day_key(raw.get(resolved['cycle_start_time'], '') or '')
        if not day:
            continue
        if computed_only:
            source = (raw.get(resolved['source'], '') or '').strip().casefold()
            if 'noop' not in source or 'approximate' not in source:
                excluded += 1
                continue
        if day in output or day in duplicate_days:
            output.pop(day, None)
            duplicate_days.add(day)
            continue
        values = {}
        for key, (_, _, minimum, maximum) in METRICS.items():
            column = resolved[key]
            if column:
                value = number(raw.get(column, '') or '', minimum, maximum)
                if value is not None:
                    values[key] = value
        output[day] = values
    return output, excluded, len(duplicate_days)


def compare(reference: dict[str, dict[str, float]], candidate: dict[str, dict[str, float]]) -> dict:
    days = sorted(reference.keys() & candidate.keys())
    result = {}
    for key in METRICS:
        differences = [candidate[d][key] - reference[d][key] for d in days
                       if key in candidate[d] and key in reference[d]]
        if differences:
            result[key] = {'n': len(differences), 'bias': statistics.mean(differences),
                           'mae': statistics.mean(map(abs, differences)),
                           'median_absolute_error': statistics.median(map(abs, differences))}
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('whoop', type=Path, help='CSV ou ZIP exporté de WHOOP')
    parser.add_argument('nroop', type=Path, help='CSV ou ZIP exporté de NROOP')
    args = parser.parse_args()
    try:
        reference, _, ref_duplicates = rows(csv_text(args.whoop), computed_only=False)
        candidate, excluded, candidate_duplicates = rows(csv_text(args.nroop), computed_only=True)
        summary = compare(reference, candidate)
    except (OSError, ValueError, zipfile.BadZipFile, UnicodeDecodeError) as error:
        parser.exit(2, f'Erreur : {error}\n')
    print('Comparaison locale, par date de début du cycle. Aucune donnée envoyée.')
    print(f'Jours importés ou de source inconnue exclus : {excluded}. '
          f'Dates en double exclues : {ref_duplicates + candidate_duplicates}.')
    if not summary:
        print('Aucune mesure comparable indépendante trouvée.')
        return
    for key, stats in summary.items():
        name, unit, _, _ = METRICS[key]
        print(f'{name}: n={stats["n"]}, biais NROOP−WHOOP={stats["bias"]:+.2f} {unit}, '
              f'écart absolu moyen={stats["mae"]:.2f} {unit}')
    print('Vérifier la correspondance des dates, la source de chaque mesure et les nuits incomplètes. '
          'Une petite série ne valide pas un algorithme.')


if __name__ == '__main__':
    main()
