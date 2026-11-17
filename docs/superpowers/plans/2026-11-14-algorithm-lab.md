# NROOP algorithm quality and validation implementation plan

**Goal:** Deliver the five algorithm improvements approved by Nathan, retaining on-device operation and default-off candidate scoring.
**Execution:** Native implementation in this chat; scope already authorized. Existing isolated local source is retained because synchronized workspace reads can stall. No publishing or remote changes.
**Architecture:** Independent pure Swift/Kotlin helpers for evidence, recovery, HRmax and contextual sleep need; one read-only app capture adapter; actual Swift replay executable plus Python backup conversion/evaluation. Existing score paths stay unchanged. Prior VFC/Effort/sleep/stress experiments remain present.

## Global constraints

Offline; no telemetry, BLE changes or schema migration. Candidate methods must not feed scores, baselines, Health, widgets or alerts. WHOOP 5.0 HR coverage assumes timestamped one-second opportunities and reports that assumption. Context is explicitly answered journal data, never inferred. Separate provenance for computed values and external references; synthetic recordings cannot establish real accuracy. Cross-platform output equality is verified with compiled Swift oracle literals in Kotlin. iPhone and macOS compile; full Android SDK build remains unavailable and must be disclosed.

## Tasks

- [x] Evidence: add SampleQuality helper/twin and real tests for burst-versus-full coverage, duplicates/conflicts, boundaries/gaps and empty inputs. Report coverage, longest gap, reliability and candidate confidence. Keep existing labels.
- [x] Recovery: add QualityRecovery helper/twin using existing z/logistic helpers and same incumbent metrics/baselines. Test full-quality equality, low-quality scaling, missing essential evidence, invalid parameters and unusable baselines. All weighting assumptions remain explicit.
- [x] HRmax: add ConfirmedHRmax helper/twin. Require dense 30-second HR/motion windows and repeated prior-day peaks; preserve Tanaka fallback and explicit manual value. Test isolated spike, sustained peak, repeated-day requirement, missing motion, future/duplicate history, bounds and override. No automatic physiological update.
- [x] Sleep need: add ContextualSleepNeed helper/twin; positive explicit natural-wake/rested answers admit a prior night, disruption excludes it. Reuse incumbent sleep-need percentile/floors after sufficient independent days. Add canonical optional questions to existing journal catalogs without translating storage keys. Test unknown versus false, conflicting answers, future/stale days and insufficient context.
- [x] Capture: one read-only newest-day adapter, domain-gated, route lines through shared fresh/cached diagnostic dispatcher. Reuse current raw streams; bounded past HR/motion reads only for HRmax and journal/computed-night reads only for contextual need. Bypass newest-day reuse when relevant modes are active; do not cache experiment lines.
- [x] Validation: Swift CLI replays actual pure helpers over versioned recordings; Python converter reads local SQLite/backup read-only and creates inputs; evaluator reports baseline/candidate errors only on eligible independent recorded references, refuses duplicate case keys and nonfinite values, clearly labels unavailable results and synthetic cases. Include reproducible synthetic fixture, input guide and tests. No claim of physiological validation without real records.
- [x] Verify: focused red/green, complete Swift suite, actual Kotlin dependencies/tests and compiled oracle, Python tests, app builds, independent code review and fixes.
- [x] Deliver: combined IPA, full sources, incremental patch, French guide, standalone replay tools/examples, archive/signature/content/checksum verification; sync feature files to workspace.

## Review focus

Temporal leakage across midnight/history, source/owner mixing, double-counted samples or duplicate dates, quality weighting being mistaken for clinical confidence, stale cache/diagnostic routing, incomplete reads and unsupported backup formats. Test these at the owning helper/tool and review app wiring independently. Real-world validation remains a user-recording dependency, never substituted by passing unit tests.
