# Local weekly plan

`WeeklyPlanView()` is an offline Apple screen backed by `Repository.days` (the existing merged daily
cache) and `Repository.workoutRows(days: 8)` (the canonical union, natural-key/cross-source dedup,
dismissal filter, and workout reconciliation read). It creates no workouts or physiological scores.
The screen refreshes on repository refresh sequence, device identity, and local calendar day. A minute
TimelineView advances today's provisional snapshot and detects midnight without strap traffic.

## Goals and honest progress

Two independent goals are disabled initially (zero). Users choose the number of nights meeting their
own sleep duration and the number of days with a completed recorded workout. The duration control
starts at 480 minutes as an editable value; it activates no goal by itself. No suggested training
schedule or medically recommended duration is computed.

Accepted input day keys cover 1970–2099, the repository's Unix history horizon; older or later anchors
are rejected identically by both twins to avoid Foundation's historical calendar cutover/era differences.
Week boundaries are Monday through Sunday in the user's current local Gregorian calendar, using
midnight rather than Today's separate 04:00 display rollover. Sleep retains `DailyMetric.day` and
`totalSleepMin` from the merged cache; there is no sleep reclassification, rescore, or nap addition.
Completed workouts count on their local **start** date, with `endTs > startTs` and `endTs <= now`.
Multiple sessions or duplicate rows on one date still contribute one workout day.

Only positive recorded evidence contributes to progress. Missing sleep is `nil`, never zero; an
explicit zero-duration record remains observed but does not meet a duration target. Missing workout
rows are labelled "No completed workout recorded", never "inactive" or a missed goal. Future rows are
"Upcoming" and excluded from totals. Today is provisional; history can also change after an import or
sync. The screen shows sleep observation coverage alongside sleep progress, and waits for the initial
merged cache before rendering history. Workout progress is hidden behind a loading state until its
canonical read finishes for the same refresh/day/device key.

The pure engine defensively rejects non-finite, negative, and greater-than-1440 sleep minutes.
Duplicate sleep estimates use the maximum valid value, never a sum; this is order independent. The
normal app input has already been merged by Repository. No HR-zone goal is claimed: existing zone
reads are per-workout queries, not a proven complete daily zone-minute aggregate for this screen.

## Local preferences and parity

All three values are integers with the same canonical keys in Swift and Kotlin:

| Key | Meaning | Accepted range |
| --- | --- | --- |
| `weeklyPlanSleepMinutes` | User-selected duration | 60–960 minutes |
| `weeklyPlanSleepNights` | Nights goal, zero disables | 0–7 |
| `weeklyPlanWorkoutDays` | Recorded workout-days goal, zero disables | 0–7 |

Values are clamped before display and calculation. These are local UserDefaults preferences, not a
DB migration, and intentionally **not included in `.noopbak`**. Neither platform's backup whitelist
has been extended. Kotlin supplies the pure data/aggregation twin and tests; Android UI wiring is
outside this Apple-screen change. There is no notification or automatic prescription.

## Verification

The implementation is Foundation-only so its exact production source and package XCTest files can
also be tested in a tiny scratch Swift package without rebuilding GRDB. Five XCTest cases cover
calendar/week boundaries, leap day, invalid dates, duplicate order, missing/invalid/future data,
observed totals, goal limits, and the reverse oracle pin. The repository package command remains:

```sh
cd Packages/StrandAnalytics
swift test --filter WeeklyPlan
```

`StrandTests/WeeklyPlanSourceTests.swift` covers the real app bridge's local midnight, completed/ongoing
and invalid workouts, duplicate sessions, source date retention, and Paris DST weekend. It requires
the macOS Strand test target; package tests alone do not validate the SwiftUI screen.

Reproduce the compiled production Swift oracle (compiles standalone, checks its saved stdout):

```sh
Tools/Oracles/WeeklyPlan/verify_swift.sh
```

Its stdout is copied literally into `WeeklyPlanTest.kt` and the reverse Swift
`WeeklyPlanOracleTests.swift`. Kotlin JVM tests also assert duplicate order and missing-data
semantics. Both twins must change together. Android's normal test command is:

```sh
cd android
./gradlew testFullDebugUnitTest --tests 'com.noop.analytics.WeeklyPlanTest'
```

No hardware commands or BLE behavior were changed; no strap validation is claimed by these tests.
