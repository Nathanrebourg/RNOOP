# Research validation implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native task-by-task execution. Steps use checkbox syntax for tracking.

**Goal:** Deliver all five approved research tracks with real replay/PSG evidence and no production score promotion.
**Architecture:** Two mirrored pure analytical helpers feed versioned optional replay research outputs; a standard-library Python CLI orchestrates replay, historical evidence and civil calendar audit. Existing SleepPSG supplies external evaluation.
**Tech Stack:** Swift 5.9+, Kotlin/JVM17, Python3.10+ zoneinfo, existing SwiftPM packages.
**Spec:** docs/superpowers/specs/2026-11-14-research-validation-design.md

## Global Constraints
Offline-by-default; no upload, telemetry, database mutation or BLE commands. Existing production scores, baselines, caches, alerts and UI remain unchanged. Swift and Kotlin analytical helpers must have compiled Swift literal oracles in Kotlin. Lab-plus remains the rollback checkpoint. Research extensions are versioned `nroop-research-v1`. Native execution.

## Review Focus
- Quality from another owner/night/recipe must not train a baseline.
- Unknown quality must not count as a good night; missing days must age the baseline.
- DST folds and repeated travel dates must never double-count elapsed seconds.
- A declined score must stay missing in sensitivity summaries, never become zero.
- External dataset agreement must not be called WHOOP validation or independent new holdout accuracy.

### Task 1: Quality-aware baseline and recovery explanation
Files: create QualityBaseline.swift/.kt, RecoveryExplanation.swift/.kt and matching Swift/JVM tests.
Interface: fold(values,qualities,cfg) -> original/candidate BaselineState and counts. describe(hrv,rhr,resp,hrvBaseline,rhrBaseline,respBaseline,sleepPerf,skinTempDev) -> Codable snapshot of actual score, baseline states, term z/normalized weight/contribution and missing names.
- [x] Write tests: full-quality exact incumbent equality, unknown and low quality omitted, valid atypical night admitted, partial quality dampens update, stale/mismatched history, cold start; explanation equals real score, missing optional renormalization, composite sums, zero-HRV value.
- [x] Run focused tests and observe missing-helper compile failure.
- [x] Implement wrappers with existing Baselines/RecoveryScorer, then run focused tests.
- [x] Compile Swift executable fixtures; paste literal outputs in Kotlin tests and pin reverse fixture in Swift; compile/run targeted JVM tests.

### Task 2: Versioned replay research output and historical evidence
Files: modify Tools/AlgorithmReplay/Sources/AlgorithmReplay/main.swift; create Research.swift, Tools/nroop_research.py; extend replay subprocess tests.
Interface: old schema1 core metrics unchanged; optional Night quality+evidence; new report.research(version, recipe, observation, quality, baselineComparison, explanation, sessions). attach-history reads independently replayed prior reports and attaches matching night evidence only.
- [x] Test actual CLI research output, original unchanged, cold-start unavailability and mismatched evidence/values.
- [x] Observe RED, implement and run actual subprocess tests.
- [x] Historical attach tests cover owner/date/recipe/origin, duplicate evidence, exact values and source-file preservation; observe RED then implement.

### Task 3: Real-engine sensitivity harness
Files: Tools/nroop_research.py; Tools/test_nroop_research.py.
Interface: sensitivity RECORDING --replay EXECUTABLE --output NEW_DIR produces deterministic summary JSON+escaped HTML and isolated variant input/report pairs.
- [x] Test deterministic transforms, no source overwrite, unavailable !=0, known HR shift, order/duplicates on real engine, timeout/failed replay propagation.
- [x] Observe RED, implement transforms and subprocess runner with hashes; run all research tests.

### Task 4: Civil calendar and travel ledger
Files: Tools/nroop_research.py and tests.
Interface: calendar RECORDING --zone IANA or --itinerary JSON --output NEW_FILE; optional --report for actual replay sessions. UTC fragments partition each covered second once; timestamps are assigned by instant; wake day is end-1.
- [x] Test Paris spring/fall, travel backward repeated day, gap/overlap rejection, duplicate/conflicting HR, exact end boundary, sleeping across midnight and missing zones.
- [x] Observe RED, implement bounded civil-day partitioning with zoneinfo, run tests.

### Task 5: External evaluation and delivery
Files: docs/NROOP_RESEARCH_VALIDATION.md, French guide, portable tool archive, full sources+incremental patch; raw dataset outside sources.
- [x] Download official sleep-accel archive, verify integrity and record SHA256.
- [x] Run existing SleepPSG tests and full-cohort actual-stager baseline; retain raw report and attributed interpretation.
- [x] Run full analytics, Python and targeted Kotlin suites; build iPhone/macOS and CLI.
- [x] Obtain one fresh independent whole-change review, fix important findings with regressions.
- [x] Verify portable binary replay and archive byte correspondence; deliver verified sources/tools/guide, without redundant phone rebuild delivery for tools-only changes.
