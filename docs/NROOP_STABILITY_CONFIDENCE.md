# NROOP stability and confidence research

Four approved tracks, research-only. Current app scoring, database writes, Health output, widgets, alerts and BLE remain unchanged. The immutable prior checkpoint is `NROOP-Recherche-sources.zip`. Swift/Kotlin share an explicit RR snapshot identity contract; Python orchestrates the actual native executables and never substitutes a physiological model.

## Stored RR snapshot identities

The previous synthetic duplicate stress bypassed the SQLite primary key `(deviceId,ts,rrMs,seq)`, which already refuses repeated keys. No real Bluetooth ingestion defect was demonstrated. Replay now accepts optional `rrIdentity=store-key-v1`, declared by the read-only backup converter and generated store-shaped example. Equal beats sharing a second remain distinct when their stored `seq` differs. Exact repeated identities collapse; inconsistent `ord`/source metadata for one identity refuse the snapshot. Canonical order matches the selected-channel store read: timestamp, NULL ord first, ord, interval value, sequence. The helper refuses mixed/unverified transports and invalid identity numeric bounds. It does not change the stored streams or clean physiological artifacts.

Without the declaration, old replay behavior and ordering are retained and reported as `identity-undeclared`. A raw decoder batch whose repeated equal beats still lack stored sequence identities must not be labelled as a store snapshot. The declaration is local editable metadata, not authentication. Historical evidence includes the optional identity mode in its recipe; old and declared modes are not silently mixed.

A real executable regression repeats all 21,600 RR rows in the rich synthetic recording. With the explicit contract, original and candidate recovery match the unique recording exactly, while genuinely distinct seq values remain present. This demonstrates snapshot idempotence, not hardware-level beat accuracy.

## Progressive synchronization simulation

`nroop_stability.py` replays oldest/newest-first 25/50/75/100% of the first-to-last captured timestamp span, retaining a fixed analysis clock and strictly prior baseline history. Reported bounds are explicit. If no current rows exist, the declared day is the fallback span. Derived recordings are synthetic and never enter independent accuracy statistics.

Every partial result is provisional, even if a score exists. 100% means the available-input reference, not proof that the strap has finished collecting or transferring. Actual packet arrival chronology is not recorded by this file format. Matched score/band changes, availability loss/gain, row counts and quality evidence remain descriptive. Missing values do not become zero. A refused variant remains an explicit error; the isolated reference snapshot protects the audit from concurrent source edits.

## Public sleep study

Predeclared dataset: [BIDSleep 1.0.1](https://physionet.org/content/bidsleep-dataset/1.0.1/), Song, Zhang, Zhou and Dutta (2026), doi:10.13026/rees-1092; related paper doi:10.1109/TBME.2025.3612158. Open Data Commons Attribution 1.0. One lexically first night from each of 47 participants was selected using the official file manifest, before inspecting results. `sha256(nroop-bidsleep-v1|subject)%5<2` assigns 17 heldout and 30 training participants. Any unreadable/misaligned recording is explicitly excluded without substituting another night.

Reference labels are expert-reviewed Dreem 2 EEG, not full polysomnography; inputs are Apple Watch HR and motion, without RR. Expert codes 0/1/2/3/4/5 map to wake/light/light/deep/REM/unknown. Unknown epochs stay outside the scoring denominator. recStart is parsed as explicit U.S. Eastern time; ambiguous/nonexistent local times refuse alignment. Samples are shifted together onto a positive 30-second grid, with relative-second flooring, sparse HR preserved and per-second motion means. The native benchmark reads dataset-native vectors without guessing a unit conversion. Session boundaries are supplied by labels, so this evaluates staging rather than sleep-session detection or WHOOP-specific performance.

`SleepPSG --research-case` calls the actual shipped stager for baseline; variants use the existing knob-for-knob port guarded by epoch equivalence tests. Seven fixed recipes: shipped, awake prior .14/.20/.26, REM prior .18/.16, awake .20+REM .18. The chosen recipe maximizes training mean-per-participant four-class macroF1, with ties retaining the earlier/shipped recipe. It is frozen before any heldout scoring. The heldout path runs only baseline and that frozen choice. Per-stage F1, fraction bias, confusion and both participant and pooled summaries expose tradeoffs; an improvement is not forced or automatically promoted.

## Quality versus independent reference error

`nroop_confidence.py fit` selects a threshold from 0/.25/.5/.75/.9/1 using only training participants and an explicit error budget, keeping the greatest eligible coverage that meets that budget. At least 3 eligible participants are required. No feasible threshold produces an explicit absent selection. `evaluate` applies the frozen choice to separate participants and reports error, retention, counts and quality bins, including worsened results. All declared recorded identities reserve their split even when quality or error is unavailable. Synthetic cases are excluded; missing errors remain unavailable. Metric, unit, reference source, quality method and model may not be mixed.

The sleep demonstration uses error `1-accuracy`, an explicit error budget 0.4, and `apple-watch-availability-v1`: the minimum of motion-second coverage and sparse-HR availability assuming one opportunity per five seconds. This is an engineering proxy, not a probability of correctness or the WHOOP HRV/recovery quality model. Participant means get equal weight. These results cannot calibrate WHOOP recovery thresholds without independent real recovery references.

The frozen sleep selection contains the confidence artifact SHA256; evaluation verifies this hash, the training identities, quality/model/reference recipe and native binary hash before scoring heldout data. Both hashes appear in the result. Metadata files are locally editable provenance, not authenticated evidence.

## Reproduction

The portable package retains prepared public study cases, exact signed binaries, relative manifests, frozen selections, attribution, per-night reports and source hashes. Thus replaying the prepared study is offline. Optional `prepare_bidsleep.py` requires scipy only for the raw MATLAB conversion; the original run used Python 3.13, scipy 1.18.1 and NumPy 2.4.6. All raw source members were checked against the official SHA256 manifest and ZIP CRC during preparation; raw CSV/MAT data are outside the source archive.

```
python3 nroop_stability.py recording.json --replay bin/AlgorithmReplay --output new-sync-audit
python3 nroop_sleep_selection.py fit etude/manifests/training.json --binary bin/sleeppsg --max-error 0.4 --output new-training
python3 nroop_sleep_selection.py evaluate etude/manifests/holdout.json --binary bin/sleeppsg --selection new-training/selection-frozen.json --confidence-selection new-training/confidence-selection.json --output new-holdout
```

Every output directory must be new. The binaries in a frozen run must remain byte-identical; re-signing changes their hash even when code is unchanged.

Actual study results and exclusions are retained in the delivered study report and provenance files. No heldout-driven coefficient retuning or app promotion occurs in this work. Source-level Swift/JVM/Python verification does not constitute hardware validation or a full Android application build; the previously documented general tooling failures remain separate.


## Completed held-out result

All 47 predeclared nights were prepared with no exclusions: 30 training, 17 heldout. Official SHA256 matched all 141 source sensor/label files plus README and licence; archive CRCs were also checked. Heldout contains 14,852 scored 30-second epochs. The training choice was `awake-014`, with mean-participant macroF1 .478100 versus .475981 shipped.

On heldout, shipped pooled accuracy is 60.0727%, candidate 59.8034%; mean-participant macroF1 .538645 versus .537422. Wake F1 rises .378668→.381131 while REM F1 falls .521900→.513949. Deep F1 is unchanged; light F1 changes .649469→.650068. The candidate is **not promoted**. Per-stage fraction biases and full confusion matrices are retained in the validation JSON/HTML.

No training quality threshold met the declared 0.4 error budget. The frozen threshold is absent. Heldout candidate mean participant error is .401309; inspecting heldout bins does not permit choosing a new threshold after seeing those outcomes. This demonstrates calibration machinery and a negative result for this proxy, not validated WHOOP recovery confidence or a reason to label all measurements unreliable.

Exact RR-only repetition leaves core scores unchanged. Repeating every stream retains recovery but leaves a residual -0.02646point shift and a 225-second sleep-boundary change in the synthetic fixture. This residual is retained, rather than extending the RR contract to unrelated streams without validation.

Verification: 2,259 analytics Swift tests, 42 targeted Kotlin/JVM tests with 8 new compiled-Swift reference records pinned both ways, 75 targeted Python tests including actual native binaries, 36 SleepPSG tests, iPhone/macOS builds, and new malformed-time/vector interoperability regressions. The final whole-change review findings were reproduced before their fixes. The known 7 broad Python tooling failures were reproduced by identity; the full tooling suite is not claimed green. Full Android application and actual strap/iPhone hardware remain untested here.

The frozen study binary is delivered byte-identical to its recorded checksum. A later conditional CryptoKit compilation guard preserves baseline/port source compatibility without altering macOS model equations; current source and the frozen binary reproduce the same representative seven-recipe report. Non-macOS execution was not tested and the new JSON hashing mode requires CryptoKit.
