# NROOP five-minute stress cadence experiment

This default-off experiment compares a five-minute cardiac stress proxy with the incumbent hourly **day-relative HR-only** calculation on the same normalized input snapshot. It does not replace the daily stress score, the Stress screen's selected lens, a widget, a nudge, recovery, training load, Health writes or any saved score. It does not enable daytime RMSSD scoring. The earlier HRV, Effort and sleep experiments remain independent.

## Capture and scope

Enable Settings → Advanced → Test Centre → HRV & Autonomic (or master mode), then synchronize new data or force an actual analysis. The inherited whole-pass unchanged-input gate can still skip a pass. On the newest processable local day only, the comparison uses the already-read calendar-day HR and gravity streams; it adds no sensor subscription, database read, server, scheduled task or network export.

The active HRV trace bypasses per-day reuse for that newest day, just as the sleep comparison does for the Sleep trace. No experiment DayScan is stored, so activation, passage of a five-minute boundary or changed data cannot replay a stale cached candidate on an actual pass. Older days retain reuse; mode-off eligibility is unchanged. Passage of time alone does not force the inherited whole-pass gate to run.

Reports are emitted on the HRV channel: one `stress cadence experimental=true` daily summary followed by at most twelve `stress cadence point experimental=true` lines describing the latest completed windows. The entire day's candidate grid is calculated, but only the last twelve windows are detailed to bound logging. The existing nightly HRV experiment shares this mode and remains present.

`scope=day-relative-hr-only` is essential. This is not the Stress screen's final daily score or its optional personal daytime-baseline lens. Both comparators deliberately omit R-R, isolating cadence from the uncertain daytime RMSSD term. Current normalization also means `original` is a reconstructed hourly comparator, not a promise of byte equality with an unnormalized displayed curve.

## Evidence and timing

Use completed, non-overlapping local five-minute windows during the incumbent waking-clock band 06:00–22:00. Ignore future samples, samples outside the target day and the current incomplete five-minute window. Use the same captured UTC offset as the incumbent; historical timezone/DST rules are not reconstructed.

Normalize each stream to one reading per timestamp, sorted by time. Discard nonpositive BPM, identical duplicate deliveries beyond the first, and entire timestamps containing conflicting positive BPM or gravity vectors. Discard nonfinite gravity, the zero vector, and any axis whose absolute value exceeds 1,000,000: this last bound protects the incumbent's integer fingerprint conversion, not a physical-motion calibration.

A candidate window requires **at least 240 distinct seconds in each of HR and gravity**, with no internal timestamp gap greater than 15 seconds and no leading/trailing missing stretch greater than 15 seconds. No missing second is filled. HR and motion coverage are checked independently; their availability is not proof of skin contact or time worn. Sparse histories therefore produce unavailable windows, not invented calm values.

## Reference and scoring

Run the real `DaytimeStress.analyze` on the normalized snapshot with `rr=[]` and its default day-relative mode. Reconstruct exactly its hourly HR reference: waking hours with at least the incumbent 300 HR records, excluding directly ambulatory hours while retaining post-activity shadow hours in calibration. Reuse its calm-reference and population-SD helpers and logistic 0–3 mapping. Require at least **three** eligible hourly HR means before a candidate may score.

For each valid five-minute mean HR, apply that same reference and spread. A zero spread follows the incumbent's neutral raw-score rule (level 1.5); it is not evidence of validated calm. Do not derive a new reference or spread from five-minute values. No individual high-HR threshold or peak deletion is added.

This is a retrospective same-snapshot comparison: later samples can revise the day's reference and earlier points, as in the incumbent. It is not a causal, fixed-baseline real-time estimator. A five-minute mean can react differently to a brief event without demonstrating greater physiological accuracy.

## Exertion exclusions

Reuse the real gravity-change activity series and threshold. A sufficiently covered five-minute motion window is directly active when at least 30% of its observed records exceed the existing activity threshold. Such candidate windows are withheld. Also retain the incumbent parent hour's activity/recovery mask.

After a directly active five-minute window, withhold later candidate windows for up to one hour **only while mean HR exceeds the reference by more than the incumbent 8 bpm margin**. Look back at direct activity only; do not chain recovery shadows. This adds finer activity protection while preserving the broader existing exclusions. In particular, a short walk and subsequent cardiac recovery must not be relabelled as psychological stress merely because the original hour was below its activity-fraction cutoff.

## Reading the report

The daily summary includes:

- `status=compared`, or `insufficient-reference`, `no-motion`, `no-heart-rate`, `read-capped`, `no-completed-window`.
- `referenceHours`, `referenceBpm`, `referenceSpread`: hourly calibration evidence.
- `windows`, `scored`, `matched`: completed waking windows, candidate-scored windows, and candidate-scored windows that also have a reconstructed hourly comparator value.
- `candidateHighMin`: number of candidate windows in the high band × five minutes. Windows never overlap, so minutes are not double counted.
- `candidateHighMatchedMin` and `originalHighMatchedMin`: high-band minutes on **the same matched windows**. The original hour's value is assigned to each of its matched five-minute slices; this is not the incumbent's full-day high-minute total.
- `candidatePeak` and `originalPeakMatched`: candidate peak and original peak on matched coverage.
- `detail=last12 noAlerts=true`: bounded detail and no experiment-driven alerts.

Each point names its start/end Unix seconds, `original`, `candidate`, and a status. Unavailable values are `nil`, not zero. Statuses explain HR coverage, motion coverage, direct activity, parent-hour activity, post-activity recovery or insufficient reference. All levels are on the existing 0–3 scale.

## Validation

Swift tests exercise transient versus flat days, non-overlapping minutes, missing/incomplete/future data, duplicates and conflicting HR/gravity, 240-versus-239 coverage, internal gaps, walking and bounded recovery, half-hour timezone offsets, numeric overflow protection and unchanged incumbent scores after comparison. Kotlin tests exercise the actual production comparator, hourly stress math, baselines and motion detector. Twenty-two literal reports from a compiled Swift executable are pinned in Kotlin; a Swift summary is pinned in the reverse direction.

The actual Kotlin cache condition and emission block are separately extracted, compiled and executed with real comparator data: off emits no comparison, active emits thirteen bounded lines, newest-day reuse is disabled, older-day reuse remains eligible. This does not compile the entire Android app or its JaCoCo budget; those require the Android SDK, absent in this environment. Shared iPhone/macOS app builds are required independently.

Test on real WHOOP 5.0 recordings with quiet seated periods, known activity, recovery and disconnections. Cardiac elevation is an autonomic-load proxy, not a measurement of psychological stress, and neither equivalence with WHOOP nor improved clinical accuracy is claimed.
