# Night diagnostic export

The iPhone **More → Data → Night diagnostic** screen prepares a read-only diagnostic for a selected wake date. It previews raw HR/motion availability in persisted NOOP-computed sleep sessions and offers a local ZIP through the system share sheet. No Bluetooth command, re-score, database migration, network request or score write is involved. A random installation identity token is created on the first preparation; it is not included in backups or exports.

This is an Apple export feature, not a cross-platform backup format. Android's analytics and stored metrics are unchanged. The shared availability helper has a Swift/Kotlin twin; the screen and ZIP assembly currently ship on iPhone. Shared source is compiled for macOS too.

## Contents and provenance

`nroop-night-diagnostic-v1`, manifest schema 1, contains exactly six top-level files:

| File | Meaning |
|---|---|
| `recording.json` | AlgorithmReplay schema 1, model `nroop-lab-v1`, currently stored raw HR/motion, a single verified WHOOP 5 R-R transport with storage identity metadata, event names without payloads, band states, and strictly prior computed history. |
| `app-snapshot.json` | Persisted canonical NOOP-computed daily cache and sessions. It is not the merged dashboard or a recalculation. No source IDs are included. |
| `replay-baselines.json` | Actual existing baseline helper folded over the prior 30 fixed calendar days, matching the replay scope. These are explicitly not the app's unpersisted final scoring baselines. |
| `coverage.json` | Availability intervals for computed sessions ending during the selected day, using `SleepSignalCoverage`. Unknown means neither usable HR nor motion was observed in that 30-second cell. R-R alone does not fill a gap. |
| `manifest.json` | Current settings, model IDs, fixed UTC offset/time-zone label, capture time, scope limitations and SHA256 for the other five files. |
| `README.txt` | Local-use instructions and scope/privacy limitations. |

Hashes detect accidental content corruption, not authenticity. The archive is editable and unencrypted. Timestamps, age, sex and physiological measurements remain sensitive. The system destination selected by the user controls whether a file leaves the device.

The source pseudonym is stable for one installation and source, using a random installation token. Repeated exports therefore preserve owner/day deduplication. Changing device, source, preferences or installation may break linkage; this identity is not evidence that two records belong to independent people. The secret token and original source/BLE IDs are omitted.

## Deliberate limits

- Current export-time settings are available; the exact original per-night scoring recipe and final app baseline are not persisted. Replay is a reviewable calculation with explicit inputs, not a promise to reproduce every dashboard score.
- The selected civil day must be 86,400 seconds with unchanged UTC offset. A 23/25-hour or offset-changing day is refused rather than clipped. The previous 30 days use the selected fixed offset, matching the replay model; this is not travel-aware physiological attribution.
- The same registry and per-day owner resolver as the engine select one raw source. This replay version requires confirmed WHOOP 5.0/MG policy and only scorable transport 5 or 7. Historical unverified channels are not converted into beats.
- The raw window is the preceding 108,000 seconds through the selected day's available end. A current day is provisional. HR/motion/R-R share a one-million-row limit, with individual caps of 300,000/300,000/400,000. Events and band states are capped at 50,000/300,000; sessions at 500. A query reaching its extra sentinel row refuses the export. Total uncompressed content is capped at 128 MiB.
- No free-text journal or alarm answers, historical quality witnesses or seven raw HRmax days are exported. Candidates needing those inputs may be unavailable. The prior history contains numeric computed daily rows only.
- Store reads are separate and bounded. Matching change fingerprints and repeated cache reads reject common concurrent changes; this is explicitly not an atomic database snapshot or proof that synchronization has finished.
- Availability counts cell duration with at least one usable sample, not continuously measured seconds, wear state, stage accuracy or confidence. It leaves the incumbent sleep scores and stored stages unchanged. The preview lists the first 20 unknown spans per session; the ZIP preserves all spans.
- Diagnostic ZIP creation is strict: duplicate/nested names fail, entry-write errors clean up the archive, and each member is re-read and compared to its expected bytes before sharing. Existing export callers retain their prior default policy.

## Replay

```sh
python3 Tools/nroop_night.py inspect NOOP-night-YYYY-MM-DD-example.zip
python3 Tools/nroop_night.py replay NOOP-night-YYYY-MM-DD-example.zip report.json \
  --replay /path/to/AlgorithmReplay
```

The tool verifies the expected members, bounds and manifest hashes before invoking the actual native scorer. It neither uploads data nor writes source scores.

## Verification

`StrandTests/NightDiagnosticExportTests.swift` covers DST refusal, strict ZIP naming/completeness, stable installation identity and a real in-memory store capture that excludes the current day from replay history and removes source/BLE identity. Build both `NOOPiOS` and `Strand` when changing the exporter or shared view; pure package tests do not compile these app files. The native export still needs a device check for date selection, inspection, share-sheet presentation and destination handling.
