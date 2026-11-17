# Stability and confidence implementation plan

> **For agentic workers:** Use superpowers:executing-plans, native execution with TDD and one fresh final review.

**Goal:** Complete four authorized research tracks with verified artifacts.
**Architecture:** Mirrored pure RR identity normalizer; additive replay diagnostics; standard-library audit/calibration orchestrators; new public-dataset adapter into the existing guarded sleep benchmark.
**Tech Stack:** Swift5.9+, Kotlin/JVM17, Python3.10+, optional scipy for MAT only.
**Spec:** docs/superpowers/specs/2026-11-15-stability-confidence-design.md

## Global Constraints
Offline analysis; no telemetry/upload/database/BLE changes. App default scores unchanged. New physiological candidate remains instrumentation. Swift/Kotlin helpers require compiled literal parity. Public data stay outside source archives. Source checkpoint: NROOP-Recherche-sources.zip.

## Review Focus
- Same-second equal real beats with distinct seq must survive.
- Identity absence/conflicts must not silently manufacture a clean stream.
- Partial data must not masquerade as final collection or independent validation.
- No held-out participant or labels may influence recipe/threshold selection.
- Missing/synthetic data must not become zero error or a calibrated probability.

### Task1: RR identity
Files: new RRReplayIdentity.swift/.kt and mirrored tests; modify AlgorithmReplay main/Research.swift, nroop_lab.py and nroop_research.py evidence recipe.
Interface normalize(rows,declared)->rows?/duplicates/status; valid unique rows canonicalize only when declared. E.g equal rows seq0/seq1 remain2; exact copies collapse to2.
- [x] Write tests for duplicates, seq multiplicity, conflicting metadata, absent identity and deterministic ordering; run RED then implement.
- [x] Add real CLI regression showing declared rich duplicate replay equals unique input; unknown identity retains previous output.
- [x] Produce standalone compiled Swift vectors, pin Kotlin and Swift; run JVM.

### Task2: Progressive replay
Files new Tools/nroop_stability.py, Tools/test_nroop_stability.py.
Interface sync_audit(recording,replay,new_output)->versioned JSON+HTML and real variant reports.
- [x] RED tests cover fixed now/history, quarter boundaries, both directions, synthetic provenance, explicit provisional/reference states and missing score handling.
- [x] Implement deterministic subsets and actual executable orchestration; run GREEN.

### Task3: Sleep selection
Files new Tools/prepare_bidsleep.py, Tools/SleepPSG/Sources/sleeppsg/ResearchBench.swift and tests; minimal main dispatch.
Interface normalized single-night schema1; benchmark returns named variant metrics/confusion; selector fits training manifest, freezes choice, then evaluates heldout shipped/selected only.
- [x] RED adapter/partition tests pin REM=4,unknown=5, ET conversion, second-floor aggregation, malformed streams and participant isolation.
- [x] Implement and run tests, guarded port equivalence and actual new public data. Verify official file hashes; keep raw cache bounded.
- [x] Freeze training recipe selection before heldout execution; report actual result, no forced improvement.

### Task4: Error calibration
Files new Tools/nroop_confidence.py and tests; reuse public night reports.
Interface calibrate(cases,max_error)->selection+heldout error/coverage/bins; independent participants and named quality recipe required.
- [x] RED tests cover leaked participants, nonfinite/duplicates, synthetic exclusion, no feasible threshold, threshold training-only and absent holdout.
- [x] Implement; demonstrate on public sleep evidence and report nontransferability to recovery.

### Task5: Review, verification and delivery
- [x] One independent review of whole changes; important findings regression RED→GREEN.
- [x] Full Swift analytics/SleepPSG, targeted Kotlin/Python; iPhone/macOS builds and source hygiene.
- [x] Verify portable tools and example hashes; source/patch CRC/applicability and copied SHA256. Retain known7 broad Python pre-existing failures without masking them.
