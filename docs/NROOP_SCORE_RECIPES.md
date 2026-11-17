# Saved score recipes and learning compatibility —12.6.0

Approved scope: exact recorded calculations and semantic learning continuity. Travel excluded.
Personal reference/forecast archive backup remains an optional future feature. The existing native
whole-database backup contains new ledger tables; the separate Apple UI archives remain excluded.
An explicit calculation-text export is inspection, not a restore format or full learning backup.

## Frozen sufficient evidence

ScoreRecipe records source, semantic method, typed inputs and final-state parameters, encoded as
canonical sorted ASCII fields: finite Double64 bit patterns, integer values, UTF8 text in hex, and
explicit null. The bounded payload has a stable FNV64 identity. It is local editable evidence, not
an authenticated medical record; same-fingerprint/different-content collisions refuse persistence.
Current method IDs:recovery.logistic.v1,rest.daily-composite.v1,effort.edwards-hrr-log.v1,
effort.banister-sedentary-log.v1. Frozen literal replay equations preserve old method meanings when
future live scorers change. Numerical changes require a new method or pipeline version, not a cosmetic
app bump. Live-score equality gates decline evidence if the frozen recipe no longer matches.

Recovery is captured from the post-edit daily and actual final current-inclusive baselines2 used by
IntelligenceEngine, not the separately folded diagnostic replay baseline. Supplied HRV/RHR/respiration/
skin baseline states retain raw center/spread/night counts/missing count/status, including unusable
states. Terms use the actual usability gates. Rest captures the actual final daily composite values.
Effort retains observed TRIMP, mapping denominator, resolved HRmax/RHR/sex, sample count/extent,
credited duration, stable ordered-stream witness and exact calendar or sleep-onset query bounds.
Both fresh and cached cycle loads retain the same observed recipe. This replays the retained final
mapping; it cannot recreate discarded raw HR, sleep staging or sensor decoding from a digest.

Each factory/bridge verifies exact recorded output equality. Preserved legacy Recovery and imported/
otherwise unobserved calculations remain unknown, even when today's profile could generate a similar
number. No fake backfill or assertion of physiological accuracy. The existing scoring formulas and
recommendation inputs are unchanged.

## Atomic storage and retention

GRDB additive v49 and Room43 have identical scoreCalculationEvidence/scoreCalculationHead columns,
order and primary keys. The former stores immutable revisions, the latter references the recipe of
the current persisted score. Score, source provenance, revision and head update in one transaction.
Missing new evidence clears a current head instead of relabeling old evidence as current. Supplied
evidence must match day/key/value/metric-specific source. Empty computed batches remain no-ops.
Duplicate identical recipes retain first capturedAt. Mismatched fingerprint contents roll back all
writes. Daily eviction clears current heads while retaining bounded audit history. Forgetting a
provider removes related evidence even when it lives under a computed namespace.

Caps:8 revisions per cell and12000 per computed device. Current heads are prioritized, then a total
deterministic recency/key ordering. If current heads alone exceed the device cap, oldest heads can
also be evicted and dangling pointers are cleared; old scores themselves remain. Missing/evicted
proof stays unavailable. Swift's stale schema marker18 was corrected to49 (actual prior migrations
already reached48); Android's native schema version43 is independently numbered.

## Learning continuity

The previous12.5 archive keyed contexts using marketing version. New captures derive their context
from validated current Recovery/Effort recipe heads, common captured settings, source and timezone.
The stable manifest is learning.recipe-context.v1. Captured settings include semantic pipeline ID,
age/sex/manualHRmax, HRV window, sleep-stager/motion refinement, day-cycle selection and baseline reset/
respiration-era epochs. Automatic per-night baseline values are not compatibility boundaries.
Marketing/build versions are metadata only. Future UI-only updates preserve compatible learning;
new numeric method/pipeline IDs or changed captured settings separate it. Developers must bump the
semantic ID when those algorithms change; it is not inferred automatically from source text.

Native capture checks heads, decoded source/key/method/fingerprint/replay, current values and source
provenance, with repeated reads. Future-dated evidence and same-day future archive records are refused.
The original evening-only/first-capture/no-backfill/clock/midnight rules remain. Repeated reads are not
an atomic snapshot. Unknown legacy records keep their original era and nil compatibility metadata;
they are never relabeled as known-compatible. A snapshot without trustworthy saved recipes refuses
with a recalculation hint. No record is deleted or rewritten to force compatibility.

## Apple UI

Settings → Local improvements → Calculation history:choose date/score, inspect verified current and
prior source-scoped revisions, compare recorded numeric fields and export one canonical recipe as
local text using the system dialog. Dates are first-observation times. Current data is shown only if
head, actual score and source agree; changed sources or malformed payloads cannot claim exact replay.
Personal evidence shows total/compatible/legacy snapshot counts. Full Android UI/KSP validation is
not delivered; pure recipe/compatibility twins and matching ledger persistence are implemented.

## Verification

Actual Swift/Kotlin canonical recipe transcripts (8 records) and compatibility transcripts (10cases)
are literal-pinned in Kotlin and reverse-pinned in Swift. Production native/Kotlin settings bridges
also compile and produce identical manifests. Tests cover exact replay, invalid inputs, raw baseline
states, context, actual calendar/cycle scopes and cached-cycle retention. Real GRDB tests exercise
migrations, collisions/rollback, score/source validation, idempotence, head clearing,8/12000 caps,
current priority and heads-only overflow. Android production migration/trimSQL run in real SQLite;
production ledger validation compiled headlessly with18 invalid cases. Full app Android build and
real WHOOP/iPhone installation are not claimed. No BLE path, account, telemetry or server is added.
