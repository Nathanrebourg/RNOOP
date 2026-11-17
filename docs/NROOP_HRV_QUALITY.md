# NROOP experimental nightly HRV comparison

This experiment compares a quality-weighted nightly RMSSD with the existing per-session HRV. It is instrumentation, not a validated replacement model. It never supplies recovery, daily HRV, baseline updates, Apple Health writes, sleep stages, or a user-facing score.

## Enable and read the comparison

Open Settings → Advanced → Test Centre → HRV & Autonomic and activate that test mode. It is off by default; the existing Master mode also activates it. After an analysis pass, export the Test Centre report or inspect its HRV log. Each matched session emits a line beginning `day=… session=… hrv quality experimental=true`.

The line reports `original` (the incumbent session HRV, which may be a cached or provided value), `candidate`, accepted beat-time coverage, admitted/total windows, input and rejected beats, temporally contiguous clean pairs, long gaps, and the whole-session over-count verdict. The comparison is per session: it is not the final daily pooled HRV, and it does not follow the optional deep-only daily HRV setting. A missing candidate stays `nil`.

## Experimental estimator

1. Restrict records to the requested session, preserving emission order within equal timestamps. Sort out-of-order timestamps stably.
2. Partition into five-minute windows, including the session endpoint only in the last window. Reject invalid spans or spans longer than 48 hours to bound work on corrupt timestamps.
3. Reuse the existing range and Malik-style cleaning. Retain each survivor's original index so removing a beat cannot join its two neighbours into a new successive difference.
4. Also exclude a pair separated by more than `max(2 seconds, current RR seconds + 1 second)`. This provisional allowance accounts for coarse timestamp resolution; same-second ordered beats remain valid.
5. Require at least 20 clean intervals and 19 valid adjacent differences. Reuse the existing 1.10 over-count ceiling for the entire session and for each window. Missing data is not interpolated.
6. For each admitted window, calculate gap-aware RMSSD and weight it by:

   `min(window duration, sum(clean RR seconds)) × clean/input fraction × valid-pair/(clean−1) fraction`

The candidate is the weighted arithmetic mean of these window RMSSDs. It is not a pooled whole-night RMSSD. Duration weighting prevents a short final window receiving the weight of a full five minutes. Accepted beat-time coverage is an accounting proxy, not an independent measurement of skin contact or a calibrated probability of correctness.

The continuity allowance and weights are engineering hypotheses. Movement is not included as an uncalibrated penalty. Clean input may still be physiological noise, and rejected input may include real variation. Swift and Kotlin implement the same calculation.

## Validation before promoting a model

Use several real WHOOP 5.0 nights with varying HRV, signal gaps and movement. Compare the candidate with the incumbent on the same source data; exclude imported WHOOP-derived daily values from any claim of independent validation. Review coverage and exclusions alongside numerical differences. A lower or smoother result is not itself evidence of greater accuracy.

Recovery evaluation must use a separate reference history built with the same candidate estimator. Substituting one candidate night into the incumbent HRV baseline would mix two estimators. This implementation deliberately does not do that. A physiological-accuracy claim also needs an independent reference measurement.

The tests cover dense and sparse windows, short final windows, dropped beats, long timestamp gaps, over-counts, ordering, bounds, and unchanged daily outputs when tracing is enabled. Cross-language numerical fixtures are pinned to output from the compiled Swift implementation.
