# NROOP experimental Effort cadence comparison

This is a measurement-only experiment. It compares an adaptive duration-credit calculation with the incumbent daily Effort on the same heart-rate stream and with the same HRmax, resting HR, TRIMP recipe, sex coefficients and logarithmic mapping. It never supplies persisted Effort, the live gauge, workout scores, recovery, personal baselines, training-load models or Apple Health writes.

## Capture

Activate Settings → Advanced → Test Centre → Workouts & GPS. Master mode also activates it. After a subsequent daily analysis, the report contains one `effort cadence experimental=true` line per analyzed day. It is tagged as Workouts on both platforms. The existing always-on Effort funnel is unchanged; this extra computation is skipped when the comparison sink is absent.

`original` is the incumbent computed daily score for that stream, not an imported score or a particular workout's displayed value. `candidate` is the experimental score. Both are on the internal **0–100 scale**, even when the app displays Effort on 0–21. The line ends with `scope=day day=YYYY-MM-DD` to prevent session/day confusion. Captures are local and exported only through the existing report flow.

## Duration rules

- Remove nonpositive BPM readings. Sort by timestamp; identical same-second copies count once. If the same timestamp contains different positive BPM values, exclude that entire timestamp instead of choosing a rate. Report these as ambiguous timestamps, separately from duplicate deliveries.
- For each positive timestamp gap, inspect up to five neighbouring gaps before it and five after it, excluding the gap itself. Compute a median on each side using only reference gaps at most 60 seconds long.
- Use the slower supported side as the reference. This preserves an observed 1-second-to-30-second cadence transition. Credit at most twice this reference, and never more than the incumbent 120-second ceiling. If neither side supplies a reference, credit zero.
- Credit the final sample with the median of the eligible gaps among the last five adjacent gaps. This is an **estimated tail**, reported separately, at most 60 seconds; a final dropout is not copied into that tail.
- Require at least 20 unique unambiguous readings and at least 600 seconds credited between readings, excluding the estimated tail, before emitting a candidate score. A long wall-clock span alone cannot satisfy this gate.

The candidate reuses the incumbent Edwards-style or Banister calculation. Banister's sedentary floor, sex coefficients and method-specific denominator are preserved. No high-BPM threshold, smoothing or peak deletion is introduced: a unique sustained or isolated high reading remains in the experiment. Conflicting same-second readings are excluded because their value is ambiguous, not because one is high.

## Reading the report

`supportedSec` is the sum of the bounded, credited intervals before the final sample. `tailSec` is the estimated final interval. `unsupportedSec` is the observed timestamp span minus supportedSec. These are accounting quantities from the credit model: they do not independently measure skin contact or actual time worn. `readings`, `duplicates`, `ambiguous`, `invalid` and `clipped` explain exclusions and clipped gaps. `configValid` describes arithmetic parameter validity. A missing candidate is `nil`, not zero effort.

Neighbourhood size, the one-minute reference bound and the two-cadence allowance are provisional engineering choices. A regular sparse stream and regular packet loss can look identical without better source metadata. The slower-side rule can retain more time near a cadence boundary than a preceding-only rule; this trade-off is intentional and must be evaluated on real recordings. Cadence above one minute is unsupported by this experiment. Duration estimates depend on the local context of the analyzed stream, so an extracted workout and a full day are not guaranteed identical boundary credits.

## Validation and scope

Compare several real WHOOP 5.0 days containing continuous workouts, intermittent activity, live/history cadence changes and known disconnections. Inspect credited durations as well as score differences. A lower candidate after a gap demonstrates less inferred credit; it does not prove a more accurate physiological load. The existing 0–21 display conversion does not make either score WHOOP-equivalent.

Tests exercise regular cadences, dense and sparse dropouts, cadence changes, unknown cadence, tail handling, duplicate/conflicting timestamps, invalid input, preservation of high readings and both TRIMP recipes. The daily integration test verifies that enabling comparison does not alter returned daily scores. Kotlin golden records are literal output from the compiled Swift implementation.

This build includes the earlier nightly HRV quality experiment. The two comparisons use separate existing Test Centre modes and neither replaces a standard score. Sleep detection and stress algorithms are outside this change.

The per-day cache key includes comparison activation, so enabling the mode invalidates a day previously cached without its comparison. Fresh and cached diagnostics share one routing function; cached comparisons replay on the Workouts channel and are not forwarded when the mode is off. The inherited whole-pass unchanged-input gate still applies until an analysis actually runs.
