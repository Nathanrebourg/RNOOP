# Local improvements over the WHOOP gap audit

This phase adds five reviewable local surfaces under iPhone More → Insights → Local improvements.
No proprietary WHOOP formula is claimed, no sensor firmware/command is introduced, and no new recovery,
sleep, age or Effort score is enabled. Android receives numeric twins and oracle tests; the new screens
are currently Apple UI source, with the navigation entry on iPhone.

- Weekly plan: opt-in user goals for nights reaching chosen recorded sleep duration and days with a
  completed recorded workout. Monday–Sunday local dates; missing data is explicit and today provisional.
- Step calibration: 3–8 manually attested walking trials, entered unscaled counter ticks and counted
  steps, bounded median factor, repeatability check, explicit Apply to the existing scale preference.
  No automated raw-counter capture, wrap/reset validation or WHOOP-equivalent motion filtering is claimed.
- Long-term trends: means/counts for 30 completed days, preceding150 days and the full180-day context.
  The explicit range reads the same import/computed/edit/activity precedence as the dashboard without
  narrowing its cache. A computed zero HRV remains known; sparse/invalid/conflicting values are explained.
  These are descriptive contributors, not WHOOP Age/Pace or a new biological-age model.
- Lifting load history: existing Foster session-RPE × minutes across logged finished sessions, with
  rated/unrated counts over7/28 local calendar days, overnight attribution by end date, and conflicts
  excluded. It remains separate from cardiovascular Effort and cannot isolate muscular strain. Missing,
  zero or invalid RPE is excluded from this positive-rated-load summary. No injury ratios or invented
  exercise/muscle coefficients are introduced.
- Alarm delivery evidence: reads existing request/readback timestamps, strap IDs and ready-channel
  witness. Queued, stale, cross-strap, previous-request and missing evidence cannot display a matching
  response. An attributable matching readback still does not establish a future vibration. WHOOP5.0
  protocol opt-in and the existing experimental arm path remain unchanged; no extra command is sent.

Numeric helpers are paired Swift/Kotlin, with actual compiled Swift output pinned in Kotlin and reverse
Swift tests. Native source adapters require app tests and both app target builds. UI refresh keys account
for local midnight/timezone, owner changes and saved lifting sessions; canceled reads must not republish
old results. All new strings have English/French catalog entries.

Original gaps remain partly open: automatic motion-to-step validation, sensor-derived muscular load,
repeatable hardware5.0 alarm verification and a validated longitudinal age construct need independent
measurements. The new manual calibration/diagnostics do not close these by assertion.
