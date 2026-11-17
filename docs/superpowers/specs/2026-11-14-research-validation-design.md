# NROOP research validation design

User-approved scope: five proposed tracks, with standing authorization to continue natively and autonomously. Success means reviewable, tested local research tools and measured external sleep results, without silently promoting a physiological candidate.

## Constraints
- Offline-by-default; no upload, telemetry, database mutation or BLE commands.
- Existing production scores, baselines, caches, alerts and UI remain unchanged.
- Swift and Kotlin analytical helpers must have compiled Swift literal oracles in Kotlin.
- Lab-plus remains the rollback checkpoint. Research extensions are versioned `nroop-research-v1`.
- Native execution; concrete sources, tools and French guide delivered locally. Android full app remains unverified without SDK.

## 1. Historical evidence
`QualityBaseline.fold(values: [Double?], qualities: [Double?], cfg: MetricCfg)` wraps the existing robust Baselines.update. Unknown, nonfinite or below-0.5 quality becomes a missing night. For admitted quality, blend the incumbent center/spread update by quality; the first admitted seed is not blended against a synthetic midpoint. Full quality is exactly the existing fold. Missing calendar days age the state. Report admitted, unknown, rejected counts and status. Historical quality is only attached from a prior replay with the same owner, recipe and exact observed value, with a referenced input hash; provenance is declared local evidence, not authentication. A stable low or high physiological reading is never itself a quality failure.

## 2. Sensitivity
A new Python CLI runs the real Swift executable over deterministic transformations: identity, reversed rows, extra copies, missing interval, timestamp shift and bounded HR offset. Compare original/candidate values, availability and recovery bands on matched metrics. Ordering/duplicate checks are diagnostic invariants; dropouts/offsets are stress tests with no preset claim that a changing output is wrong. Preserve the source, isolate outputs, enforce subprocess timeout, escape HTML, tag synthetic data, never merge these variants into held-out accuracy evaluation. Write input and executable hashes.

## 3. Civil calendar
A read-only ledger accepts an explicit IANA zone or explicit nonoverlapping contiguous UTC zone intervals. Partition UTC time into civil-day fragments, including 23/25-hour days and repeated dates across travel. Assign each distinct raw timestamp once; conflict HR is excluded, not averaged. Associate each replayed sleep session with the civil date/zone at its final observed second; preserve absolute start/end and duration. Missing travel history cannot be inferred. This ledger does not retrofit variable-length days into the fixed-offset physiological replay or alter stored day keys.

## 4. Explanation
`RecoveryExplanation.describe` exposes the exact five-driver replay recovery calculation: actual score, baseline state, present/missing terms, normalized weights and weighted z contributions. Reuse RecoveryScorer for the actual score; terms sum in composite-z space, never pretend that nonlinear score-point contributions add. Current quality candidate and historical baseline candidate are independent comparisons. Explicitly label the prior-computed, five-driver replay scope, not the entire app's final recovery.

## 5. External sleep evaluation
Reuse existing SleepPSG directly against the public sleep-accel v1.0.0 cohort with PSG labels, with full-cohort counts, confusion matrix, per-stage metrics and stage-fraction biases. Preserve dataset attribution, download/checksum provenance and actual commands. This is a new run of an existing known cohort, not a newly untouched holdout; no coefficients are tuned. Different Apple Watch hardware, no RR and supplied sleep windows prevent claims of WHOOP end-to-end accuracy. DREAMT remains an optional later extension, not a blocker or fabricated result.
