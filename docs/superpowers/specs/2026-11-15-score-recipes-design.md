# Calculation evidence and learning compatibility — 2026-11-15

Approved: point1 exact score calculation evidence, point2 learning continuity across compatible UI
releases. Travel excluded. Point4 only a documented optional future backup plan; no automatic export,
backup whitelist expansion or restore action in this delivery.

Canonical isolated source /private/tmp/nroop-quality-dev/noop-nathan, immutable12.5 checkpoint
outputs/NROOP-Personnel-sources.zip. No Git metadata, commits, pushes, BLE changes, default score changes,
servers or telemetry. Deliver12.6.0(444), Android source12.6.0/code561; full Android SDK unavailable.

A bounded append-only calculation ledger records Recovery, Rest and Effort sufficient calculation
inputs and exact output. Recovery captures actual final current-inclusive baseline states used in
pass2, not an approximate replay fold. Rest captures the final daily-based composite recipe. Effort
captures exact accumulated TRIMP and log-map parameters plus actual integration-window evidence;
this reproduces the retained final mapping, not discarded HR rows or sensor decoding. No raw PPG copy.
Old/imported/legacy-preserved scores without actual observed recipe remain unknown. Replaying must
match the captured value; do not fabricate a recipe after the fact. Score and recipe current pointer
persist atomically; recalculation can retain revisions and compare changed fields. Retention bounded.

Learning compatibility uses explicit semantic recipe/pipeline versions and scoring-setting context,
not app marketing version. Source and timezone remain separated. Unknown legacy archives stay intact
in their original context, never relabelled as proven-compatible data. Future cosmetic app updates
preserve compatible contexts; changed numerical recipes/settings separate learning. Canonical encodings
and compatibility helpers must match Swift/Kotlin by actual Swift oracle and reverse pins.

Storage contract agreed before parallel work:
public struct ScoreCalculationEvidence: Equatable,Codable,Sendable {
  public let day:String,key:String,sourceId:String,methodId:String,fingerprint:String,payload:String
  public let value:Double,capturedAt:Int
  public init(day:key:sourceId:methodId:fingerprint:payload:value:capturedAt:)
}
GRDB table scoreCalculationEvidence(deviceId TEXT,day TEXT,key TEXT,fingerprint TEXT,capturedAt INTEGER,
 sourceId TEXT,methodId TEXT,value REAL,payload TEXT; PK deviceId,day,key,fingerprint)
GRDB table scoreCalculationHead(deviceId TEXT,day TEXT,key TEXT,fingerprint TEXT;PK deviceId,day,key)
Room same table/column/key order, additive schema migration, no destructive fallback.
WhoopStore.persistComputedScores adds calculationEvidence:[ScoreCalculationEvidence]=[] argument LAST.
Within same write transaction clear current heads for recomputed window (not audit history), validate
supplied evidence against persisted score+metric-specific source provenance, append idempotently;
reject fingerprint collision/different payload; update current heads. Missing evidence clears current
head: an old revision must not masquerade as recipe of a newly written score. Empty daily batch no-op.
Reads: scoreCalculationHistory(deviceId:day:key:limit:) -> [ScoreCalculationEvidence], newest first;
scoreCalculationCurrent(deviceId:day:key:) -> ScoreCalculationEvidence?. Head clear on daily eviction.
Cap8 revisions per cell and12000 per device, current-head-prioritized deterministic ordering and remove dangling heads. Must
not delete daily scores/provenance. Payload max16384 UTF8 bytes, valuefinite0..100, unix1..4102444800,
canonical ISOday and controlled score keys. Android DAO/entity/persistence equivalent same contract.

Pure recipe interface agreed:
public struct ScoreRecipe:Equatable,Sendable {
 public let key:String,sourceId:String,methodId:String,payload:String,fingerprint:String,score:Double
 public static func recovery(daily:DailyMetric,baselines:AnalyticsEngine.ProfileBaselines,source:String)->ScoreRecipe?
 public static func rest(daily:DailyMetric,source:String)->ScoreRecipe?
 public static func effort(hr:[HRSample],maxHR:Double?,restingHR:Double,method:StrainScorer.Method,sex:String,source:String)->ScoreRecipe?
 public static func decode(_ payload:String)->ScoreRecipe?
 public func replay()->Double?
 public func changedFields(from:ScoreRecipe)->[String]
}
Canonical ASCII typed fields (UTF8 strings hex-encoded, Double64 bit hex, sorted fixed keys), explicit
schema and semantic method IDs. No app version/timestamp in fingerprint; source included. Use stable
FNV64 over UTF8 (collision is rejected by store, not an authentication claim). Max16KiB, malformed or
nonfinite input refuses, no missing-to-zero fabrication. Actual Swift/Kotlin transcript parity.
Core semantic version constants may be local to ScoreRecipe; learning context root owns separate
LearningCompatibility pure helper and explicit profile/settings fingerprint. Core agent must send
final exact method IDs before native context integration.

Root owns engine final persistence integration, ledger screen, learning context/preservation, tests,
EN/FR copy and delivery. Recipe worker owns new core files/tests/oracles and actual Effort capture
interfaces in DayResult + both AnalyticsEngine and DayCycleIntelligenceIntegration twins. Storage
worker owns shared storage, migrations/entities/DAO/persistence pass-through and focused store tests.
Do not overlap root IntelligenceEngine orchestrators (Swift/Kotlin) or UI/project files.
