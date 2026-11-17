# NROOP algorithm quality and replay laboratory

This lab implements five approved improvement tracks: input evidence, quality-weighted recovery, confirmed HRmax, contextual sleep need, and independent local replay/evaluation. It also adds versioned reports, deterministic replay, descriptive case tables, backup inspection and corrupt-input rejection. Candidate outputs remain default-off instrumentation, not replacements for normal scores, confidence labels, personal baselines, Health writes, widgets or alerts. Earlier HRV/Effort/sleep/stress experiments remain present.

## Capture

The newest processable local day is captured on an actual analysis pass. Workouts & GPS enables availability and maximum-HR reports; Recovery enables the recovery experiment; Sleep & Rest enables contextual need. Master mode enables all. HRV & Autonomic retains the earlier HRV and stress experiments. With modes off, no new capture work is done. The inherited unchanged-input whole-pass gate still applies. Relevant active modes bypass per-day reuse for the newest day and do not cache experiment lines; older days keep reuse. Fresh/cached diagnostic routing shares a domain-aware helper and suppresses disabled lab lines.

All new lines carry `experimental=true model=nroop-lab-v1`. The lab never sends data off-device. The HRmax history collector can add fourteen reads (seven prior days × HR/motion), each capped at 100,000 rows; a manual override avoids those reads. Context reads are limited to the prior thirty computed days and the native journal. Failed/capped HRmax days are counted explicitly. Cancellation remains cooperative. No schema migration or BLE command is added.

## 1. Availability and candidate confidence

`SampleQuality` assumes the timestamped WHOOP 5 HR stream offers one second per recording opportunity. It counts distinct valid seconds over an explicit half-open expected interval, includes leading/trailing gaps, collapses identical copies and excludes conflicting timestamps/nonpositive BPM. It does not discard unique high readings. This is not skin-contact detection; a legitimate sparse stream is intentionally described as sparse under this assumption.

Coverage is observed seconds / expected seconds. Reliability is coverage × (1 − rejected fraction) × min(1, 120 / max(120, longest missing stretch)). Rejected fraction uses conflicting timestamps plus invalid rows. Candidate tier is solid at >=80% coverage, <=120-second longest gap and <=5% rejected evidence; building at >=20% coverage; otherwise calibrating. No existing score means candidate confidence stays calibrating. These are provisional engineering thresholds, not calibrated probabilities. The existing labels are retained.

## 2. Quality-weighted recovery

Use the same current HRV/RHR/respiration/sleep/temperature values and the same final incumbent baselines, never the earlier experimental weighted RMSSD value. Multiply each incumbent weight by its explicit quality and renormalize through the same z-score/logistic helpers. Full quality for all supplied terms reproduces the incumbent; optional terms without a quality witness get zero weight. In the app no calibrated respiration/temperature quality witness is available here, so those qualities are zero, even when the normal score uses the values. This choice must be evaluated, not silently presented as greater accuracy.

Essential gates: usable HRV baseline, usable RHR baseline, HRV quality >=0.5 and RHR quality >=0.2. Invalid inputs/qualities or missing essentials produce no candidate. HRV evidence uses admitted beat-time coverage × up-to-three-window support × retained-beat fraction × continuity. Coverage is relative to the selected whole session or union of deep-stage intervals when deep HRV is selected. Three tiny RR snippets cannot imply whole-night confidence. RHR evidence uses HR availability/continuity; sleep evidence uses timestamped-stage coverage, not a claim of stage accuracy.

Only one detected non-HR-only session can supply evidence. Provided hypnograms, absent/multiple sessions and capped current reads are declined. Evidence is built while raw streams exist, then consumed only after the actual final baseline fold in pass two. Current user sleep edits decline the candidate (`edited-sleep`) rather than reusing stale detector quality. The original shown is recomputed from the same final inputs. Downweighting a bad sleep measurement can raise a candidate; this does not establish better recovery.

## 3. Confirmed maximum HR

A daily peak is the maximum 30-second median in consecutive one-second HR, corroborated by >=24 gravity seconds and >=30% above the existing activity threshold. Calibration admits 30–250 bpm, but does not filter raw Effort peaks or alter stored streams. This can miss cycling/static-wrist effort; absence of a confirmed peak is not a measured low maximum.

Require three distinct prior days. Use the median of their top three peaks, retaining the positive-age Tanaka fallback floor. With fewer days use Tanaka for a known positive age; unknown age has no candidate without confirmed history. Manual override wins and is never overwritten. The original report follows the actual incumbent's age-specific Tanaka, manual override or classic unknown-age fallback. App reads seven prior days; the pure helper admits up to thirty days of explicitly supplied independent peaks. Current/future, stale, misaligned or conflicting duplicate days cannot train the estimator.

## 4. Contextual sleep need

Three optional native journal questions share exact canonical keys on both platforms:

- `Did you wake naturally without an alarm or obligation?`
- `Did you wake feeling rested?`
- `Was your sleep disrupted by an external event?`

Stored question keys are not translated; display labels may be renamed with the existing catalog editor. A night is admitted only with explicit true, true, false answers respectively. Missing answers remain unknown. Only prior computed-night durations, 3–12 hours and within thirty days, are considered. Native answers are used, not imported behaviour labels; source scope is the person's computed namespace, not a claim that every historical duration came from the same physical strap. Seven distinct eligible nights are required. Reuse the existing upper-quartile sleep-need estimator and population floors/cap. No new physiological need is inferred from average short sleep, and the normal sleep target/debt is unchanged.

## 5. Replay and independent evaluation

`Tools/AlgorithmReplay` runs the actual Swift models, not Python copies of their equations. Inputs declare schema, origin, owner, case ID, profile, fixed offset, raw streams, prior computed nights and prior owner-scoped HRmax streams. The executable rejects future/mixed/duplicate history, unsupported transport provenance, excessive rows and corrupt numeric domains before calling the incumbent engine. BPM outside 0–300, RR outside the wire's 0–65,535 ms domain, nonfinite/oversized gravity and invalid offsets are rejected as entire cases, not clipped into apparent improvements. HRV cleaning still decides plausible NN values inside that wire domain.

The CLI folds thirty strictly prior computed calendar days, padding missing days. Its recovery scope is `replay-prior-computed-baselines`; it is deliberately not the app's final current-inclusive baseline recipe or edited/provided sleep. An output includes the model version, input SHA-256, owner digest, baseline scope, original/candidate metrics, statuses and raw diagnostic lines. Identical inputs produce identical reports.

`Tools/nroop_lab.py` offers `inspect`, `capture`, `example` and `evaluate`. Capture reads a checkpointed SQLite file or the single `noop-backup.sqlite` member of a .noopbak archive read-only. It never extracts arbitrary archive paths, modifies the source or guesses old RR units. WHOOP 5 chooses one labelled transport (5 before 7) over the entire current read interval, excludes quarantined beats and preserves timestamp/emission ordering, matching the current strict store policy. Legacy/unlabelled RR is withheld with a warning. Other device families are unsupported. Specify the actual raw owner; use `--computed-id` if the existing computed namespace differs from raw-owner + `-noop`.

Evaluation uses a separate CSV with `caseID,metric,value,source,independent,split`. Allowed external sources are whoop, diary and measured. Only recorded cases, independent=true and split=holdout contribute to paired original/candidate MAE and bias on the same cases. Synthetic and training cases are excluded; unavailable candidates do not become zero. Duplicate case IDs, owner-days, input hashes, nonfinite scores or self-references are refused. WHOOP agreement is a comparator, not ground truth; subjective sleep need has no independently established true value here. The standalone HTML includes descriptive case values even when no eligible accuracy comparison exists. All user text is escaped, no CDN/network is used.

## Verification and limits

Tests exercise gaps, duplication, RR temporal coverage, deep-window denominator, essential gates, full-weight equality, manual/age-zero HRmax handling, explicit context, chronology, provided/edited provenance and domain routing. Kotlin expected reports are literal stdout from a compiled Swift executable. The actual Kotlin capture is separately compiled/executed with repository I/O substituted and production data declarations retained; scoring methods are real. The full Android application and JaCoCo method budget still require an Android SDK and are not validated by these JVM checks.

Swift subprocess regressions show corrupt BPM failing cleanly instead of trapping, and cover source preservation, determinism, history/owner transport rejection and explicit replay scope. SQLite/archive tests check read-only handling and WAL refusal; evaluation tests check matched holdout/provenance, unavailable values, duplicates, nonfinite values and HTML escaping. Shared iPhone/macOS app builds are verified separately. No hardware installation or real-world physiological validation has been performed without user recordings. No threshold should be promoted from passing tests or synthetic examples alone.
