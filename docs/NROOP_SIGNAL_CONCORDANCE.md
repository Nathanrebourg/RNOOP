# Descriptive beat/heart-rate concordance observer

Autonomous follow-up to the completed five-track lab. This observer adds evidence only; it does not change any score, quality weight, baseline, profile, widget or alert. Its version is `nroop-concordance-v1`, separate from the existing `nroop-lab-v1` metrics.

## Capture

Recovery test mode (or master mode) adds `lab concordance experimental=true` to the same newest-day, uncached lab capture. The replay CLI appends the same observation after its existing four diagnostic lines. All earlier metrics retain their equations and units.

In-app observations describe raw detector periods **before manual sleep edits**, not the edited/final displayed night. Only a single detected non-HR-only session is eligible; provided hypnograms, missing/multiple sessions and capped reads are declined. If deep HRV is selected, only RR timestamps in the detected deep periods are compared. Whole HR data may remain in memory but only timestamps with selected RR observations match. The report's `scope=exact-second-selected-hrv-period` names this limited lens.

## Calculation

- Match timestamps exactly; do not invent an alignment, interpolate through gaps or shift either stream.
- Require one verified WHOOP 5 RR transport, code 5 or 7. Mixed or unverified provenance is unavailable.
- Normalize HR to one positive reading per second, excluding conflicting positive values. HR outside the observer's 0–300 domain is not used; raw data is unchanged.
- Keep RR values in the incumbent HRV plausibility range 300–2000 ms. Within each second, deduplicate equal interval values and take the median of their implied BPM (`60000 / RR`). This is a descriptive convention, not a new RR cleaner or an input to RMSSD.
- Compare that value with the second's HR. Every matched second has one vote, independent of repeated deliveries or burst size. At least sixty independent matched seconds are required for medians.

`medianSignedBpm` is **recorded HR minus RR-implied HR**. Positive means recorded HR is higher. `medianAbsBpm` ignores direction. `aboveToleranceSec` counts matched seconds whose absolute difference is strictly above ten BPM. Ten is an uncalibrated descriptive tolerance, not an accuracy or clinical threshold. `matchedSec` describes the observed subset only; even status `observed` does not establish representative coverage of the entire night.

Transport latency, smoothing, sparse sampling, timestamp quantization or genuine rapid changes can explain discrepancies. The observer cannot establish which signal is correct or diagnose a defective sensor. These values must not automatically downweight the recovery model without real-recording validation.

## Tests and parity

Cases cover agreement, positive and negative discrepancies, strict tolerance, duplicates, conflicting HR, missing overlap, unknown/mixed transports, burst delivery with one vote per second, deep-period wrapper selection and Recovery-only routing. Eight literal records from the actual compiled Swift observer are pinned in Kotlin; a matching Swift record is pinned in the reverse direction. Existing algorithm tests, Python replay/evaluation tests and iPhone/macOS builds are rerun. The same full Android SDK and hardware-validation limits as the preceding lab still apply.

## Additional value-versus-absence regression

The follow-up also preserves a mathematically computed zero HRV value in the quality recovery comparator, matching the incumbent scorer. It is distinct from absent HRV (nil/null). The same real-scorer regression is tested in Swift and Kotlin; no recovery equation, weight or default scoring path changes.
