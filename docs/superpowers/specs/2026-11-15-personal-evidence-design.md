# Personal evidence design — 2026-11-15

Nathan authorized all four proposed improvements and ongoing autonomous development. This is an
additive architectural change split into four independently tested kernels and two Apple screens.
Existing scores, BLE paths, backup schemas and default recommendation inputs remain unchanged.
Canonical isolated source has no Git metadata; immutable baseline is NROOP-Capture-sources.zip.

1. MatchedJournalComparison: fixed next-day Recovery outcome, one deterministic yes/no pair per civil
Monday–Sunday week, matched on weekend/weekday, previous-day Effort bucket and same-morning sleep
bucket. Unlogged is unknown. No best-lag search. Median paired difference, exact paired sign-test
nominal p, Holm correction over the entire displayed question family (<=50 questions,180 days).
Eight nonzero weekly pairs are required for a nominal association flag. Co-occurring behaviors and
residual dependence remain uncontrolled: no causal claim or calibrated probability of correctness.

2. BaselineShiftEvidence: recent7 versus prior28 completed calendar days, recent>=5 and prior>=20;
medians and MAD with metric-specific scale floors. A provisional shift requires median displacement
>=2 robust scales and >=4 recent observations beyond that same directional threshold. Source/era
changes refuse the shift. Show observed values and gaps; never reset/learn away illness automatically.

3. TrainingResponseForecast: frozen observed evening Effort/Recovery context buckets, horizons1/2/3 days,
median later-observation-minus-origin-Recovery. Strictly prior mature outcomes and nonoverlapping
training origins only. Rolling-origin evaluation uses only history available at each origin. Need8
training examples and8 historical predictions in current context; require >=10% MAE reduction versus
persistence before displaying a forecast. Only first-captured evening observations (20:00–23:59), saved on their actual local date, may train or evaluate the model. Mutable computed caches cannot validate historical forecasting because the incumbent can rescore them using later baselines. Snapshots are one per owner/day, immutable, without backfill; source/capture-version/timezone separate eras, and future capture timestamps are excluded after clock rollback. Capture crossing midnight or taking over five minutes is refused. Current Effort is partial and Recovery is the value observed at capture, not guaranteed original morning Recovery. Future activity follows historical patterns, not known plans.
No injury/disease prediction and no recommendation promotion from this exploratory screen.

4. ReferenceValidation: same-method, same-unit local observations, MAE/signed bias and split recent/
prior descriptive error. Counted verification walks are saved separately from calibration trials and
never enter its divisor fit. Save raw ticks, manually counted reference and frozen applied scale.
Add independent manual bedtime/wake observations for unedited attributable stored nights; user reports
are not PSG truth. UI-local bounded Apple records excluded from backup/wire formats; no server/export
without user action. Changes in method/scale are separate groups, never retroactively re-evaluated.

Apple adapter reads180 completed civil days from source-tagged computed caches only, not dashboard
source unions. Matching Recovery and sleep source tags gate relevant row values, strain own tag.
Native journal is person-level noop-journal, explicitly labelled; its historical strap is unknown.
Conflicting same-day cache values fail closed. Strict dates, chronology, source changes, cancellation,
refresh, local midnight/timezone and before/after fingerprint guards apply. Fingerprint is not an atomic
snapshot. New UIs default off except explicit reference capture; existing algorithms stay intact.

Numeric Swift/Kotlin twins, actual compiled Swift oracle literals and reverse pins; native SQLite and
local record tests; full analytics, app iPhone/macOS builds and source hygiene before12.5(443)delivery.
No Android UI/full SDK build or real WHOOP/iPhone accuracy claim. Primary method references:
NIST paired sign test; R stats p.adjust Holm; Hyndman/Athanasopoulos rolling-origin cross validation.
