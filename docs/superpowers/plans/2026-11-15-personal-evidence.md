# Personal evidence implementation plan

> Execution: inline, preserving the user's explicit autonomous-development instruction.

**Goal:** deliver the four approved analyses as local experimental comparisons and reference records.
**Architecture:** pure Swift/Kotlin kernels, one source-aware Apple data adapter, research hub and
reference view. No physiological-score writes or automatic baseline resets.
**Tech Stack:** Swift/SPM, Kotlin/JUnit, SwiftUI, existing GRDB reads, bounded UI-local UserDefaults.
**Spec:** docs/superpowers/specs/2026-11-15-personal-evidence-design.md

## Global constraints
Offline; no BLE changes; source owner explicit; missing!=zero; today excluded from historical scoring;
Swift/Kotlin numeric parity; iPhone+macOS app compilation; Android SDK unavailable; no commits/pushes.

## Review focus
- Journal unknown answers and context gaps must not become controls or invent matches.
- A future outcome or current-origin record must not train its own forecast.
- Conflicting duplicates and changed source/scale must not improve apparent confidence.
- A measurement used to fit a calibration must never count as independent verification.
- Async source, refresh, date and timezone changes must invalidate rendered results.

## Tasks
- [x] Write failing numerical tests for MatchedJournalComparison, BaselineShiftEvidence,
TrainingResponseForecast and ReferenceValidation under StrandAnalyticsTests. Assert hand-computed
sign p=.0078125 for8 positive pairs, Holm family bounds, unknown/refusal, robust shift and clear
synthetic rolling forecast versus persistence, future/duplicate refusal and validation unit separation.
- [x] Run focused Swift tests and observe missing-type failures. Implement four pure Swift kernels
and matching Kotlin objects under analytics; run meaningful missing/invalid/chronological fixtures.
- [x] Compile actual Swift oracle for all four kernels, capture literal output and pin in both test
languages. Compile and execute Kotlin sources/tests using the existing headless toolchain.
- [x] Test native source-owned daily reads and local reference records, then implement
PersonalEvidenceData and PersonalReferenceStore. Add native tests for wrong-owner exclusion,
strict civil dates, invalid/corrupt record refusal and independent observation separation.
- [x] Add PersonalEvidenceView and PersonalReferenceView from ImprovementsView. Extend the existing
guided-walk result card with explicit Save as verification only; it clears pending capture without
adding a calibration trial. Freeze applied scale and owner at record save, refuse duplicate windows.
- [x] Add sleep start/end manual-reference capture from unedited same-owner computed night; reference
observations are stored separately, never overwrite detected times. Translate new copy EN/FR.
- [x] Review all four contracts and adversarial fixtures; run full Swift analytics, focused native,
Kotlin, source hygiene, Python known-failure comparison, iPhone Release and macOS test builds.
- [x] Freeze source, build12.5.0(443), apply patch against immutable12.4 source checkpoint and compare
all bytes. Package signed-capability-template IPA, source ZIP, patch, French guide, verification and
hashes. Preserve all older releases; update mirror/pointer. Release temporary Mac wake assertion.

## Execution rulings
- Preserve the user's prior autonomous-work instruction; no repeated design/plan approval or Git commit.
- Cached Recovery is rescored using later baselines. Native forecasts therefore consume a separate,
first-capture-only evening archive; no cached backfill can qualify forecasting performance.
- Apple-only reference/archive formats are UI research state excluded from shared backups/wire schemas;
Kotlin twins cover the numerical kernels, not these unshipped Android interfaces.
- Add source-tag/daily rereads: analysisFingerprint witnesses raw streams, not computed-cache updates.
- Independent review findings addressed with regression fixtures: timestamp arithmetic order, signed-zero
parity, future-clock exclusion, midnight crossing, source switch and async-clear races.

Final packaging evidence is recorded in the delivered NROOP-Personnel-verification.txt.
