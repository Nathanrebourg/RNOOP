# Score recipes and compatibility implementation plan

Execution preserves Nathan's authorized autonomous workflow. Independent recipe and storage modules
are delegated using the dispatching-parallel-agents skill; root implements compatibility, integration,
UI and final review. Spec:docs/superpowers/specs/2026-11-15-score-recipes-design.md.

- [x] Recipe module: failing replay/invalid-input/byte-parity tests, actual scoring snapshots and
Effort capture for calendar/cycle paths; actual Swift literal/Kotlin oracle and reverse pin.
- [x] Storage module: failing transaction/migration tests, additive matching GRDB/Room tables,
atomic score/head/revision persistence, retention and no-op/unknown/head-eviction behavior.
- [x] Compatibility: failing tests showing cosmetic-version independence and numeric-setting/source/
timezone separation; retain unknown legacy era, no invented migration. Native archive captures a
stable documented recipe context instead of marketing version.
- [x] Integrate actual final recipe outputs into both orchestrators, excluding preserved legacy scores
and missing/mismatched evidence. Add source-gated ledger UI with replay equality and field differences.
- [x] Native integration and full analytics/store tests, meaningful Kotlin checks, EN/FR copy, hygiene,
Python known-failure comparison, iPhone Release/macOS hosted tests. No Android full SDK claims.
- [x] Freeze source, actually apply/byte-verify patch against12.5 checkpoint, sign capability-template
IPA12.6(444), preserve prior releases, mirror changes, SHA/copy checks, guide and evidence report.

Review focus: current head must match current value/source; no proof reconstructed for legacy score;
zero/nil and invalid doubles remain distinct; compatibility ignores app build but includes changed
model settings; ledger retention and failures never delete unrelated source scores; UI async owner
changes reject stale reads. Backup remains a future explicit option, not a side effect of this scope.

Final completion evidence is recorded in the delivered NROOP-Recettes-verification.txt.
