# Personal evidence — exploratory v1, NOOP12.5.0

Apple entry:Settings → Local improvements → Personal evidence / My verification measurements.
The three analytical panels are session-local opt-in, separate from daily scores and recommendations.
All four numerical kernels have Kotlin twins. Android screens/full SDK validation are not delivered.
No BLE commands, servers, cloud dependencies, migrations or shared-backup schema changes are added.

## Matched journal

Fixed next-day Recovery association, not a best-lag search. Only native person-level journal answers
are used; their original strap is not recorded. Unlogged days are unknown. A pair has one explicit Yes
and one explicit No in the same civil Monday–Sunday week and the same fixed context: weekday/weekend,
previous-day Effort bucket (<33,<66,otherwise) and same-morning sleep bucket (<360,<480,otherwise).
Among eligible pairs choose the smallest absolute day gap, then earliest minimum day; ties keep the
first pair in sorted yes/no order. At most one pair per week and180 completed exposure days are used.
This reduces repeated daily evidence but does NOT establish independent weeks or control other habits.

Report median Yes-minus-No Recovery and the exact two-sided sign-test nominal p on nonzero paired
differences; at least8 nonzero pairs, at most60. Ties contribute to the descriptive median but not n.
Holm correction includes the entire question family (<=50), treating unavailable tests as p=1.
There is no best-lag/behavior selection before correction. Even corrected nominal p values are not
causal effects, probabilities of correctness or guaranteed error control under dependent observations.
Source-tagged historical scores can be retrospectively recalculated: this panel is association only.
Method references:[NIST paired sign test](https://www.itl.nist.gov/div898/software/dataplot/refman1/auxillar/signtest.htm)
and [R stats p.adjust](https://www.stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html).

## Reference shifts

Last7 versus preceding28 completed civil days, requiring5 and20 valid observations respectively.
Compare medians; scale=max(metric floor,1.4826 × prior median absolute deviation), floor3bpm for RHR,
5ms for HRV. A provisional flag requires |median delta|>=2 scales and at least4 recent observations
beyond the same directional threshold. No automatic reset, illness filtering or adaptive scoring occurs.
Core bounds/floors have finite domain limits to refuse overflow. Duplicate-identical dates collapse;
conflicting dates are excluded. Changed source/era withholds comparison. Native rows require matching
Recovery and sleep source tags; these are computed-row witnesses, not independent per-signal accuracy.
Historical scoring settings/calibration are not recorded, so a shift may be methodological, not physical.

## Forecasts: immutable observations only

The incumbent rescoring engine can recalculate historical Recovery with later final baselines. Thus
historical cached rows must NEVER train or evaluate this forecast. Instead, the user explicitly captures
one evening snapshot per owner/local day, after20:00, storing the actual timestamp, zone, observed
Recovery and partial Effort. First capture only; no overwrite/backfill. Capture must finish within the
same local date and300seconds; future observation times are excluded on clock rollback. The record's
source/capture-app-version/timezone context separates learning; a new version may need new evidence.
The archive is Apple-local bounded UI research state (400records/256KiB), excluded from shared backups.
It is locally editable provenance, not authenticated evidence or a medical measurement.

Frozen contextual median model, horizons1/2/3 civil days. Context uses observed Effort and Recovery
buckets (<33,<66,otherwise), matching era. Historical targets must have a strictly earlier day than
the forecast origin. Training selects at most30 nonoverlapping origins in180days, requiring8 matches.
Predict origin Recovery plus median later-minus-origin Recovery, clamped0..100. Rolling-origin error
uses at most30 nonoverlapping evaluated intervals in90days and fits again using only outcomes available
before each origin. At least8 evaluations and >=10% MAE reduction versus persistence are required;
otherwise prediction is unavailable. [Rolling-origin method](https://otexts.com/fpp3/tscv.html).
The frozen gate is an engineering threshold, not prospective scientific validation. Later Recovery
is whatever is observed at the later capture, not necessarily its original morning score. Remaining
and future exercise are unknown; the forecast is conditional on historical subsequent patterns.
It never becomes an injury prediction, a training prescription or a default recommendation input.

## Personal reference measurements

Guided walking has Save as verification only next to Save this trial. It saves the same inspected
window separately, with counted steps, retained ticks and frozen scale. Estimate uses existing rounded
ticks/scale arithmetic. It clears pending capture but never appends a calibration trial. A window
already saved as verification cannot also enter calibration through this flow, including after an
interrupted draft save. Re-entering the same walk manually elsewhere cannot be detected globally.

Sleep reference captures refer to completed, unedited, attributable sessions, rechecked before save.
The user enters independently noted start/end times; pickers do not copy detected boundaries. Start
and end errors are separate minutes; reports do not edit sessions or validate staging. Manual reports
are subjective references, not PSG or independent laboratory ground truth. Capture app versions form
separate display groups; the original detector/scoring recipe remains unknown.

ReferenceValidation excludes fitted observations, conflicting IDs, invalid values and other methods/
units. It reports count, signed estimate-minus-reference bias, MAE and, when available, latest10 versus
previous10 MAE. Those period comparisons do not establish algorithm-caused improvement. Records are
Apple-local UI state (<=256/128KiB), excluded from backups; all-owner clearing is explicit. No automatic
upload or export is added. Source switches, refresh and async clearing invalidate in-flight saves.

## Verification

Hand-computed cases and actual compiled Swift22-line transcripts are pinned in Kotlin and Swift.
Adversarial fixtures cover unknown answers, family correction, duplicate conflicts, signed zero,
chronology, invalid horizons, source/era changes, constant baselines, nonfinite/extreme inputs, fitted
references and unit/method separation. Native SQLite/UserDefaults tests cover owner isolation,
immutable capture, clock rollback and midnight crossing, malformed records and integer extremes.
A review reproduced two real faults before correction: a corrupt extreme timestamp could trap on
subtraction, and Kotlin data-class signed-zero equality differed from Swift numerical equality.
Both now have regressions. Java's half-up display formatting at .0078125 also differed from Swift
printf nearest/even; the oracle formatter uses exact-binary BigDecimal half-even, without altering
statistical values. Passing these tests is implementation evidence, not physiological validation.
