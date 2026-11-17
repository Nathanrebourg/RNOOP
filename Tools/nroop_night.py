#!/usr/bin/env python3
"""Verify and replay a local NOOP iPhone night diagnostic ZIP. No upload or database writes."""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

MEMBERS = frozenset(('manifest.json', 'recording.json', 'app-snapshot.json',
                     'replay-baselines.json', 'coverage.json', 'README.txt'))
MAX_BYTES = 128 * 1024 * 1024


def decode(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result: raise ValueError('Duplicate JSON key.')
            result[key] = value
        return result
    def invalid(_): raise ValueError('Nonfinite JSON number.')
    return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid)


def read_bundle(path, *, max_bytes=MAX_BYTES):
    """Read exact known members in memory after bounds checks; never extract archive paths."""
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        if len(infos) != len(MEMBERS) or set(i.filename for i in infos) != MEMBERS:
            raise ValueError('Diagnostic members must be unique and match the format exactly.')
        if any(i.is_dir() or i.flag_bits & 1 or i.file_size < 0 for i in infos):
            raise ValueError('Unsupported diagnostic member.')
        if sum(i.file_size for i in infos) > max_bytes or z.getinfo('manifest.json').file_size > 1024 * 1024:
            raise ValueError('Diagnostic size exceeds the local bound.')
        entries = {}
        remaining = max_bytes
        for info in infos:
            with z.open(info) as source: data = source.read(min(info.file_size, remaining) + 1)
            if len(data) != info.file_size or len(data) > remaining:
                raise ValueError('Diagnostic size does not match its declaration.')
            remaining -= len(data); entries[info.filename] = data
    manifest = decode(entries['manifest.json'])
    if not isinstance(manifest, dict) or manifest.get('format') != 'nroop-night-diagnostic-v1' or type(manifest.get('schema')) is not int or manifest['schema'] != 1:
        raise ValueError('Unsupported diagnostic format.')
    hashes = manifest.get('sha256')
    if not isinstance(hashes, dict) or set(hashes) != MEMBERS - {'manifest.json'}:
        raise ValueError('Diagnostic checksum roster is incomplete.')
    for name, digest in hashes.items():
        if digest != hashlib.sha256(entries[name]).hexdigest():
            raise ValueError('Diagnostic checksum mismatch: ' + name)
    recording = decode(entries['recording.json'])
    if not isinstance(recording, dict) or type(recording.get('schema')) is not int or recording['schema'] != 1 or recording.get('origin') != 'recorded':
        raise ValueError('Unsupported recording format; native replay performs further validation.')
    return entries


def extract_recording(path, output):
    entries = read_bundle(path)
    with Path(output).open('xb') as target: target.write(entries['recording.json'])


def replay(path, output, executable):
    entries = read_bundle(path)
    output = Path(output)
    if output.exists(): raise FileExistsError('Replay output already exists.')
    with tempfile.TemporaryDirectory(prefix='noop-night-') as directory:
        source = Path(directory) / 'recording.json'; report = Path(directory) / 'report.json'
        source.write_bytes(entries['recording.json'])
        subprocess.run([str(Path(executable).resolve()), str(source), str(report)], check=True, timeout=300)
        # Native CLI validates physiological schema/bounds; copy the exact resulting report only on success.
        with output.open('xb') as target: target.write(report.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('inspect'); p.add_argument('bundle', type=Path)
    for name in ('extract', 'replay'):
        p = sub.add_parser(name); p.add_argument('bundle', type=Path); p.add_argument('output', type=Path)
        if name == 'replay': p.add_argument('--replay', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'inspect':
            entries = read_bundle(args.bundle)
            manifest = decode(entries['manifest.json'])
            print(json.dumps({'format': manifest['format'], 'day': manifest.get('day'),
                              'verifiedMembers': len(entries) - 1, 'warnings': manifest.get('warnings', [])}, indent=2))
        elif args.command == 'extract': extract_recording(args.bundle, args.output)
        else: replay(args.bundle, args.output, args.replay)
        print('Completed locally; no upload or source score writes.')
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(2, f'Error: {error}\n')


if __name__ == '__main__': main()
