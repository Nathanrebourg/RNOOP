# Manual walking step calibration

`StepCalibrationView` adds a local manual calculator for the existing
`profile.stepTicksPerStep` setting. The intended use is a WHOOP 5/MG owner who can independently
observe an **unscaled tick increase** during a walk and count the actual steps. The @57 motion
counter is not a validated pedometer. There is no new BLE command, raw capture, import, database
schema, background collection, account, server, telemetry, or physiological algorithm.

## Workflow

1. Perform three to eight separate walks with the same strap and placement. Count each walk's
   actual steps, choosing different lengths so an identical observation cannot be submitted twice.
2. Enter the counted steps and complete, unscaled tick increase for each walk. Confirm that this is
   a separate same-device walk with no known missing records, reset, or ambiguous counter wrap.
   The screen does not capture a walk or verify this declaration. Without a reliable local unscaled
   tick observation, keep the current setting. A displayed daily step estimate may already be scaled
   and must not be used as the tick input. A final cumulative counter value alone is not a delta.
3. Review the proposed divisor and repeatability spread. Opening the screen, adding/removing trials,
   and previewing do not change the profile or trigger analysis.
4. Explicitly tap **Apply scale**. This writes only the existing `stepTicksPerStep` preference and
   requests the standard `IntelligenceEngine.analyzeRecent()` then `Repository.refresh()` sequence.
   The default stays 1.0 until explicitly changed. The full calculated Double is saved; the displayed
   divisor is rounded to three decimal places.

Trials live only in view state and disappear when the screen closes. A saved divisor persists using
existing ProfileStore storage and backup behavior. The screen inherits `AppModel` and `ProfileStore`
environment objects and provides its own Done button for sheet presentation on both Apple platforms.

## Calculator contract

`Packages/StrandAnalytics/Sources/StrandAnalytics/StepCalibration.swift` is Foundation-only;
`android/…/analytics/StepCalibration.kt` is its independent Kotlin twin. `Trial` contains an opaque
identifier, manually counted steps, unscaled tick delta, and explicit source declaration. It contains
no raw-counter samples or physiological measurements.

- Three through eight trials are required. Every trial must pass; no outlier is silently dropped.
- Counted steps must be finite whole numbers from 100 through 10,000 inclusive.
- Tick deltas must be finite whole numbers from 1 through 300,000 inclusive.
- Each trial divisor is `rawTicks / countedSteps` and must be in 0.5 through 30 inclusive, matching
  the existing profile bounds. Unsupported observations are rejected, not clamped into range.
- Source confirmation is mandatory. Empty or ASCII-blank identifiers are rejected. Repeated IDs or
  identical `(countedSteps, rawTicks)` observations are rejected as duplicate evidence. If separate
  walks happen to match exactly, another walk length is needed; the calculator does not pretend it
  can establish that two identical manual entries describe independent walks.
- The proposal is the median of **all** trial divisors, averaging the middle pair for an even count.
- Relative spread is `(maximum divisor − minimum divisor) / median`. A spread above 20% withholds
  the proposal. Exactly 20% is accepted. This is a conservative **workflow threshold**, not an
  empirically validated error bound, confidence interval, or accuracy claim.

The user declaration cannot establish sample freshness, ownership, continuity, activity class,
reset/wrap handling, or correct tick extraction. This calculator intentionally does not read a
cumulative u16 baseline/end pair and infer a delta. Those operations need separately validated
source-aware capture. It does not change `StepsCounter` motion/class/plausibility rules. The saved
scale divides ticks retained by that existing pipeline; it cannot restore discarded ticks, fill
missing walks, or establish WHOOP-app parity. Android receives the exact calculator and tests;
this Apple workflow does not replace Android's existing steps-estimate calibration UI.

## Verification

The Swift and Kotlin suites exercise medians, order invariance, bounds, missing confirmations,
duplicate identities/evidence, insufficient/excessive trials, conflicting trials, the exact 20%
threshold, fractional/non-finite/zero/negative/extreme inputs, and unrounded result retention.

The Kotlin test includes a literal transcript produced by actually compiling the Swift helper and
running the same 35-case fixture spread. Numbers are encoded as IEEE-754 Double bits in hexadecimal,
so the oracle tests exact values rather than rounded display strings. Swift pins the same literal
to detect reverse drift. No expected numeric values were inferred by reading the twin source.

Focused verification in the development sandbox:

- Standalone optimized Swift helper plus assertion form of the five Swift test methods: passed.
  The small assertion runner avoids loading the rest of StrandAnalytics/GRDB; package XCTest and
  Apple app builds remain separate checks performed by the integrating task.
- Standalone Kotlin compilation and JUnit 4: five tests passed, including the compiled Swift oracle.
- No live strap or hardware accuracy validation was performed. No such claim follows from these tests.

The shared SwiftUI screen uses `ScreenScaffold`, `NoopCard`, `NoopButtonStyle`, and only
`StrandPalette`, `StrandFont`, and `NoopMetrics` design tokens. French string mappings are supplied
separately for the integrating task's catalog merge.
