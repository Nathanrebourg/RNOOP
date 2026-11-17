# Guided walking-trial capture

Guided walking capture supplies a local, unscaled tick observation to the existing `StepCalibration`
calculator. It does not validate the strap's motion counter as a pedometer. A user still independently
counts the walk, confirms the observation, completes at least three distinct trials, reviews the
proposal, and explicitly applies the existing `stepTicksPerStep` preference. There is no new BLE
command, firmware operation, database migration, account, server, or telemetry.

## Capture contract

The native adapter freezes the selected live WHOOP 5/MG owner and positive Unix start/end timestamps
when the user begins and finishes. It must reject a changed source/owner and read samples from just
that owner after normal synchronization. A device name, displayed daily steps, or a scaled estimate
is not a raw counter source. The pure kernel receives no owner identifier; source selection and
freshness are adapter responsibilities and cannot be established by a successful kernel result.

The user stands still for several seconds after beginning, walks while counting actual steps, then
stands still for several seconds before finishing. First and last observed intervals must have zero
counter change. The result reports actual observed sample bounds; they can differ from the button
presses by up to three seconds. Stationary observations and edge tolerances reduce boundary ambiguity;
they cannot prove the user's entire counted walk was observed. The user must confirm that count and
window describe the same walk.

## Pure kernel

`Packages/StrandAnalytics/Sources/StrandAnalytics/GuidedWalkingTrial.swift` and
`android/…/analytics/GuidedWalkingTrial.kt` are dependency-free twins. Each accepts its own
`Sample(ts, counter, activityClass)` and a declared `[startTs, endTs]`. It returns `retainedTicks` only
on acceptance, with an issue on refusal, observed start/end timestamps, deduplicated sample count,
and whether the observed window contains activity classes. A result has no certified-source flag.
On early normalization errors, the metadata may describe only the normalized prefix; no refused
result supplies usable ticks.

The following constants are frozen conservative workflow gates, **not measured confidence, accuracy,
or continuity guarantees**:

| Gate | Value |
|---|---|
| Positive Unix timestamps | 1 through 4,102,444,800 inclusive (2100-01-01 UTC) |
| Declared duration | 60 through 3,600 seconds inclusive |
| Maximum missing span at either button boundary | 3 seconds |
| Maximum consecutive observed timestamp gap | 5 seconds |
| Minimum distinct observed samples | 4 |
| Counter domain | integer u16, 0 through 65,535 |
| Positive increment | below 512 and at most 4 ticks per elapsed second |
| First and last observed intervals | zero counter increment |

Every supplied timestamp is validated before filtering. Samples outside the declared interval do not
contribute; the caller should bound its store query as well. Samples within the interval are sorted
by timestamp. Exact duplicates collapse. Conflicting counter or activity-class values at one timestamp
refuse the trial; the kernel never chooses one record arbitrarily. Counter decreases are refused
because a legitimate u16 wrap and a reset cannot be distinguished from these fields. The refusal
means **counter decreased**, not “reset detected.” The maximum duration bounds integer tick totals
and timestamp arithmetic on both platforms.

## Matching the existing step pipeline

A positive increment is attributed to its later sample, exactly as in `StepsCounter`. If any observed
sample has an activity class, all positive increments must end in walk (1) or run (2). Still, unknown,
and absent classes on positive increments refuse the whole trial. Zero intervals remain allowed,
including still or absent classes at stationary edges. Large increments, excessive rates, long gaps,
and ambiguous counter drops likewise withhold all ticks. No rejected increment is silently discarded
and no partial-walk coefficient is offered.

For an accepted trial the retained total equals `StepsCounter.stepsInWindow` over the normalized
trial samples, before applying any personal divisor. Calibrating a raw cumulative difference that
includes motion discarded by that pipeline would produce an incompatible divisor; this flow refuses
such windows instead. The existing daily pipeline and its plausibility/activity filters are unchanged.

The pure kernel also retains the incumbent's wholly unclassed legacy-window behavior for exact
window parity. **The native WHOOP 5/MG guided flow refuses wholly unclassed results.** A day can contain
classed records outside an unclassed trial, causing the daily pipeline to reject nil-class increments
that a trial-only legacy fallback would retain. Requiring a classed guided result avoids that scope
mismatch. Positive increments of an accepted classed trial all pass the daily class filter as well.

The independently counted steps and accepted ticks are passed to `StepCalibration` only after the
user's source/window declaration. That calculator still requires 3–8 distinct trials, 100–10,000
counted steps, a supported divisor, and at most 20% relative spread. It never converts successful
sample checks into a claim of medical validity, algorithm accuracy, or WHOOP-app parity.

## Verification

Independent hand fixtures assert a 60-second stationary-ended walk retains exactly 116 ticks, equals
the incumbent `StepsCounter`, and refuses malformed timestamps/counters, conflicting duplicates,
ambiguous decreases including a possible wrap, outliers, non-walking positive increments, missing
coverage, long gaps, moving boundaries, and no movement. Boundary fixtures cover the inclusive
three-second edge tolerance, five-second sample gap, one-hour duration, and Unix ceiling.

Both suites pin a literal transcript from an actual standalone optimized Swift compilation over
24 cases. A standalone JVM compilation produces the same transcript byte for byte. Swift reverse-pins
the same literal, so either twin drifting fails its suite. These checks establish deterministic
implementation parity and workflow refusal behavior; they do not establish real-strap accuracy or
Bluetooth behavior. Package/app/native adapter checks and hardware observation are separate evidence.

## Native capture and persistence

The Apple screen is accessible from Local improvements → Step calibration → Calibrate with Start
and Finish. A registered live WHOOP 5 source, selected consistently with the registry, is required.
Start records the current timestamp/source; Finish is enabled after 60 seconds. After normal sync,
Inspect reads at most 7200 raw samples from this source/window and checks the records again before
publishing. Reaching the sentinel cap or observing changed rows refuses the read. This is not an
atomic store snapshot or proof of complete Bluetooth delivery; no new sensor stream is started.
The UI then requires the user's counted steps and same-walk/stationary-boundary declaration.
Only explicit Apply writes the existing step coefficient and requests ordinary recent recomputation;
complete historical recomputation is not guaranteed.

A small bounded Apple-only UserDefaults draft preserves button timestamps and accepted counts/ticks
across navigation or app restarts. It is UI-local workflow state, not a shared backup or wire schema;
it is deliberately excluded from exported backup formats. At most eight completed trials are stored.
Corrupt, oversized, duplicate-identifier or out-of-domain drafts fail closed and can be cleared without
changing the already-applied scale. Switching source requires returning to the original source or
clearing this draft. Numeric decisions remain covered by Swift/Kotlin parity; Android capture UI is
not implemented in this phase. App-hosted SQLite tests exercise the actual class-preserving raw read,
source refusal, draft round-trip and invalid draft rejection. Real counted walks remain untested.
