# NROOP research validation

Version `nroop-research-v1`. Five approved tracks implemented as local research tools, with no default app-score, database, Health, widget, alert or BLE changes. Swift/Kotlin helpers are additive and mirrored; their presence in the shared package does not enable them in the app.

## Historical recording quality

`QualityBaseline.fold` wraps the existing robust EWMA, which already handles extreme values. Unknown/nonfinite/out-of-range or below-0.5 evidence does not feed the candidate. Admitted partial quality scales the existing center/spread update, with an unblended first real seed. Full quality reproduces the incumbent exactly; missing days still age its state. `admitted` counts values admitted by the quality/domain gate, before the inherited robust outlier gate; `candidate.nights` is the fold's actual accepted-night count. A quality gate is not an illness filter. These are unvalidated engineering hypotheses, not calibrated probabilities.

Replay reports retain all previous core metrics/lines, adding a separate `research` object. Its `observation` and `quality` can witness another strictly later recording's historical row. `nroop_research.py attach-history` requires the same owner digest, recipe, origin, exact observed HRV/RHR values and prior day. It refuses duplicate/replaced evidence. Swift validates the embedded witness again. Unknown old-night quality is not reconstructed from summary scores. A source checksum identifies the recording used; editable local JSON is not authenticated provenance.

The historical-baseline candidate changes only the HRV/RHR baselines; respiration reference, current values and existing weights stay the same. It requires both candidate baselines usable and current essential quality gates. It remains separate from the earlier current-quality weight comparison. Baseline and replay scopes are strictly prior-computed, not the app's final current-inclusive baselines. The synthetic example admits six HRV nights and excludes the poorly covered seventh; identical stable observations correctly produce no artificial improvement.

## Sensitivity with the actual executable

`nroop_research.py sensitivity` invokes the real Swift executable on identity, reversed rows, repeated rows, a 300-second dropout, a one-second stream shift and +3 positive-HR readings. The shift's rows past the window end are omitted explicitly by its transform; +3 is a stress input and may be rejected at the numeric domain boundary. A rejected/timeout variant has no score, an explicit error and no fabricated delta; other variants remain visible. A failed baseline aborts the audit. Every derived variant is synthetic, including evidence-origin labels, and is excluded from recorded-reference accuracy evaluation. Raw source data are unchanged.

The manifest stores source, executable and transformed-input hashes. Matched deltas, missing/gained/lost availability and bands exported by the real Swift scorer are reported. Terms add in composite-z space, not nonlinear score points. There is no arbitrary pass/fail accuracy threshold.

The supplied rich synthetic case is intentionally informative: identity/reversed rows retain the scores; adding three BPM changes recovery by about -10.39 points; a one-second shift by +0.12; a 300-second dropout by -0.28. Repeated RR deliveries make current recovery unavailable in this fixture. This is a discovered input-assumption sensitivity, not a repaired default scorer or proof that real database reads contain duplicates. The per-row R-R ordering/provenance must be investigated before any deduplication could become physiological scoring policy.

## Civil calendar and travel

`calendar` consumes an explicit IANA zone or contiguous UTC itinerary intervals. It visits each UTC second once (maximum four-day audit, 32 itinerary intervals), preserving civil-date fragments across DST and travel. Paris spring/fall days correctly have 23/25 elapsed hours. A repeated date across travel is not a duplicate UTC interval. Unique positive HR seconds are counted once; conflicting readings are excluded and counted. Sessions keep their absolute duration and belong to the date/zone at end-1. The report checksum must match the recording.

This is an attribution ledger. It does not rewrite stored day keys, infer past travel or retrofit variable-length days into the original fixed-offset physiological replay. The WHOOP capture converter still uses a declared fixed offset. Calendar output does not certify the correctness of that replay on a DST/travel boundary.

## Exact recovery explanation

`RecoveryExplanation` returns the actual five-driver RecoveryScorer result, baseline center/spread/night counts/status, missing terms, normalized weights and composite-z contributions. It handles computed HRV zero distinctly from absent data and declines invalid inputs or unusable HRV history. CLI/HTML explicitly describe replay scope; no physiological causation or additive score-point attribution is claimed. App recovery can have additional inputs and final baseline rules, so this is not advertised as an explanation of a different headline score.

## External sleep benchmark

Actual full-cohort run: **31 subjects, 26,773 30-second PSG-scored epochs; four-class accuracy 61.14%, pooled Cohen kappa 0.371**. Per-class F1: wake .423, light .684, deep .484, REM .575. Pooled predicted-minus-reference fractions: wake -4.92pp, light -.86pp, deep +1.32pp, REM +4.46pp. Raw matrix and both pooling conventions are in `validation/2026-11-14-sleep-accel.txt`; reproducibility and checksums in its provenance JSON.

Dataset: [PhysioNet sleep-accel v1.0.0](https://physionet.org/content/sleep-accel/1.0.0/), Walch, Huang, Forger and Goldstein, SLEEP 42(12), zsz180 (2019), doi:10.1093/sleep/zsz180. Dataset doi:10.13026/hmhs-py35. Open Data Commons Attribution 1.0; all 125 official member hashes matched. PhysioNet: Goldberger et al., Circulation 101(23), e215 (2000). Data remain outside the source archive.

This known cohort has informed previous recipe choices. No fitting is performed now, and this is not a newly untouched holdout. Existing text claiming otherwise has been corrected. Sensors are Apple Watch, the RR channel is absent and session boundaries are supplied by labels. Thus this tests staging on another device, not WHOOP-specific accuracy, RR improvements or end-to-end sleep detection. Adding RR is not guaranteed to improve agreement. DREAMT was not downloaded or evaluated; reusing the existing public adapter permitted a real complete run first.

## Verification and remaining boundaries

2,253 Swift analytics tests;39 targeted Kotlin/JVM tests (6 new,12 new compiled-Swift literal records pinned in both languages);48 targeted Python tests;33 SleepPSG tests; iPhone Release/macOS Debug builds. The actual CLI was also used for multi-night evidence, portable replay, explanation equality, calendar totals and six rich perturbations. Previous Lab-plus report fields are byte-equivalent when the additive research object is removed.

Broad Python tooling discovery also exposes7 pre-existing failed checks (6 failures+1error), reproduced by test identity on the immutable Lab-plus checkpoint: stale compact parity metadata, macOS /var versus /private/var path assertions, and missing Git metadata in this archive checkout. They are not waived or described as green. Full Android application/bytecode budgets, actual iPhone installation and real WHOOP recordings remain outside these computer-only checks.
