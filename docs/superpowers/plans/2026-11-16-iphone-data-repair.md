# iPhone data visibility and navigation repair

**Goal:** Keep already-loaded information visible when Nathan navigates, restore access to the app's detailed data, and expand the fused daily record with actually available measurements.

**Evidence:** The user's 40-second iPhone recording shows repeated full-screen measurement loads, a missing recovery score beside available vitals, and sleep efficiency rendered as 1%. His screenshot shows five rows in the fused record. The current snapshot loader re-runs its full capture whenever a view task restarts, resolves 20 metrics sequentially and fetches the complete workout history; the fused adapter explicitly lists only six possible metrics. The previous source and the new source use the same on-device repository/schema, so the UI alone does not establish data loss.

**Constraints:** No account, server, telemetry, BLE command, schema migration, score-formula change, or deletion of the installed app and its data. Never label prior or future values as today's; preserve source precedence and the distinction between a missing score and missing measurements. Use the existing scoring and sleep data. Keep macOS shared code compiling; Android presentation is unchanged in this iPhone delivery. Respect user theme preference.

## Verification focus

- A reappearing screen and a different screen for the same day reuse one snapshot; a new refresh, source, date or temperature preference cannot use an outdated or different person's snapshot.
- A cancelled or racing view cannot overwrite a newer day or prevent another view from completing.
- Fractional and percent sleep-efficiency records show the same valid percentage in both the detail and chart, without changing stored values.
- One source's older day cannot be mixed with today's measurements, and skin temperature deviations are not compared to absolute temperatures.
- Every additional metric represents an actual compatible stored value or an explicitly named existing calculation; missing values remain missing.
- Existing complete metric details remain accessible, with their date scope stated; the selected-day recovery remains empty if the score is genuinely absent.

## Tasks

1. Add store-backed snapshot/cache regression tests, reproduce failures on the existing code, then introduce a repository-owned bounded cache with context rebinding and safe invalidation. Keep same-context values visible while a newer revision loads. Restrict workout reads to the selected local day without changing reconciliation semantics.
2. Reproduce fractional sleep-efficiency rendering with stored fixtures, normalize the read model for both selected values and trends, and fix the empty-score wording without asserting that all measures are missing.
3. Add tests for a richer fused record, exact-day source union, unit formatting and mixed temperature representations. Expand the existing presentation adapter over real available daily fields, and list available existing scores separately rather than fusing unlike scoring formulas. Preserve provenance and existing multi-source compare behavior.
4. Make the prior complete metric-detail screens easy to reach from each score and the historical trend page. Verify all navigation against synthetic records and preserve the selected context in new screens.
5. Review the patch; run focused native tests, the existing applicable test suites and iPhone/macOS builds; inspect key flows on the isolated simulator; produce a new unsigned IPA, source archive, verification report and French guide. The user's physical device and real AI provider remain separate follow-up validation.

## Implementation and review notes

- The fused view resolves actual per-source rows and series for one requested day, including legacy Apple Health daily steps and active energy as fallbacks. Sleep components come from one selected namespace for each source; absolute and relative skin temperatures are never compared against one another. Available existing scores remain separate from fused measurements.
- A repository-scoped bounded snapshot cache shares captures between screens for the same context, keeps visible data during refresh, and invalidates on a real data change. Shared captures are cancelled when no screen needs them. Read failures are surfaced and failed results are not cached as empty health data.
- Sleep efficiency is normalized according to its stored origin, not by blindly multiplying every low value. The original data and analytics formulas remain unchanged. Pillars and trends link to the source-aware full history.
- Review followed the user recording and synthetic store-backed regressions. An isolated French iPhone simulator showed sleep details with 95% efficiency, the full history, expanded fused measurements and separate scores, an earlier day with different values, and an immediately visible sleep page after switching tabs. These are demonstration records, not the user's device data.
- Baseline caveats: the general Python suite had six failures and one error in the previous source delivery; the same seven test identities reproduced on this source. Some existing native caption assertions assume English and must run with an English test language.
