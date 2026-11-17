# Local longitudinal contributor trends

`LongitudinalTrendsView(repo:)` adds an on-device description of resting heart rate,
HRV, sleep duration and stored steps/motion estimates. It does not derive biological
age, longevity years, pace of aging, disease risk or a confidence score. Existing
Body Age / Fitness Age features remain independent.

## Windows and arithmetic

The reference date and time zone are supplied to the adapter. It uses a Gregorian
`Calendar` in that zone, strict `yyyy-MM-dd` day keys and calendar date components,
not elapsed seconds divided by a nominal day length. Today (age 0), future days and
history older than 180 completed days are excluded.

- Recent: day ages 1–30 inclusive, 30 calendar days.
- Prior comparison: day ages 31–180 inclusive, 150 calendar days, no overlap.
- Context: day ages 1–180 inclusive, 180 calendar days.

Each distinct valid day has equal weight within each period. Means and measured-day
counts are displayed even when the comparison is unavailable. The difference is
`recent mean - prior mean` in the original unit; neither sign is labelled healthy.
The 180-day context is not used as a comparison baseline because it overlaps the
recent period. Coverage is valid distinct days divided by the fixed calendar-day
window, not statistical confidence.

A difference requires at least two measured days in **each** comparison period, to
avoid presenting one isolated reading as a period comparison. This is an explicit
minimum-data presentation rule, not a scientific reliability threshold. The engine
returns a reason (`recentWindowTooSparse`, `priorWindowTooSparse`, or
`bothWindowsTooSparse`) when that rule is not met. There is no minimum-coverage
claim or uncertainty band; sparse counts remain visible beside all available means.

Nil, NaN, infinity and values outside optional caller bounds are excluded. A real
zero remains a reading wherever the metric bounds allow it. Identical valid
same-day duplicates count once; conflicting valid readings exclude that entire day
for that metric, independently of input order. Invalid or missing duplicates do not
erase an otherwise valid day. Conflicting-day counts are exposed and displayed.

The app adapter applies generous storage sanity limits, not diagnostic normal ranges:
RHR 20–250 bpm, HRV 0.001–1000 ms, sleep 0–24 hours, steps/motion 0–1,000,000.
Sleep uses `DailyMetric.totalSleepMin / 60`, RHR uses `restingHr`, HRV uses
`avgHrv`, and steps use nullable `steps`; no missing measurement is synthesized.
These filters cannot establish sensor accuracy or clinical validity.

## Actual history source

The view calls `Repository.mergedHistoryDays(fromDay:toDay:calendar:)` for the entire
180-day window. That facade follows the dashboard daily merge: imported/active strap
history, computed siblings with user-edited sleep precedence, and activity-file step
fallbacks. It does not pretend that the narrower `dailyMetrics(fromDay:toDay:)`
facade includes computed data. It does not depend on the size of `repo.days`.
The central facade and its actual-store regression tests are maintained alongside
Repository by the integrating change.

The existing daily row has no per-field provenance. The screen explicitly identifies
this mixture and its limit; it does not assert that a value came exclusively from
the WHOOP 5.0, was calibrated, or follows a selectable series preference. Source and
calibration changes can affect averages. In particular, WHOOP 5.0 motion ticks are
not validated step counts, and a scale of 1 does not prove calibration. The steps
card is labelled **Steps / motion estimate**, with **steps / ticks** as its unit.

A minute timeline refreshes the load key on local day/time-zone changes; data
revision changes also reload. The store load is keyed by revision, date and zone,
so a minute tick on the same day does not reread the history. Cancelled loads do not
publish stale rows.

## Files and integration

- Swift arithmetic: `Packages/StrandAnalytics/Sources/StrandAnalytics/LongitudinalTrends.swift`.
- Kotlin twin: `android/app/src/main/java/com/noop/analytics/LongitudinalTrends.kt`.
- App adapter and card screen: `Strand/Screens/LongitudinalTrendsView.swift`.
- French catalog merge mapping: `docs/NROOP_LONGITUDINAL_TRENDS.fr.json`.

The UI uses NoopCard, NoopMetrics, StrandFont and StrandPalette tokens. It leaves
navigation, the localization catalog, packaging and signing to the central
integration. The Kotlin engine is ready for consumers; this scope adds the Apple
screen, not a separately wired Android screen.

## Verification

Six Swift analytics tests cover the nonoverlapping window boundaries, absence of
current/future/out-of-range days, missing/invalid/zero values, duplicate conflicts,
order independence, sparse reasons and Paris spring/fall DST day attribution.
Five JVM tests exercise matching behavior. Three app adapter tests check the actual
DailyMetric fields, minutes-to-hours conversion, missing-versus-zero behavior,
per-metric sanity filtering and the exact 180-day calendar window across DST.

Parity is pinned in both directions. The pure Swift implementation was compiled
with `swiftc -O` and run, and its stdout was copied verbatim into the Kotlin test.
The Kotlin twin was compiled with `kotlinc` and run; that stdout was copied verbatim
into the Swift test. The seven fixtures include ages -2 through 183, all three
windows, nil/nonfinite/out-of-bounds values, duplicate conflicts and decimal values
that exercise floating-point rounding. Expected strings encode IEEE-754 bit
patterns for every mean, coverage and delta, plus counts and reasons. The two
executed outputs match exactly.

Standalone XCTest execution passed the six analytics tests and three extracted
adapter tests using the actual DailyMetric declaration and actual adapter source.
Standalone JUnit execution passed all five Kotlin tests. These checks do not compile
the complete SwiftUI view or replace the integrating change's full analytics suite,
macOS/iOS builds and app-target test run. No strap experiment or change to BLE,
firmware, persisted data, network access or existing age formulas is involved.
