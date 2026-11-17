import Foundation
import StrandAnalytics

struct HistoryEvidence: Codable {
    let version: String, origin: String, ownerHash: String, inputSHA256: String
    let dayStart: Int
    let useV2: Bool, deepWindow: Bool
    let rrIdentity: String?
    let hrv: Double?, rhr: Double?
    let hrvQuality: Double, rhrQuality: Double
}
struct ResearchReport: Codable {
    struct Recipe: Codable, Equatable { let deepWindow: Bool, useV2: Bool; let rrIdentity: String? }
    struct Observation: Codable { let hrv: Double?, rhr: Double? }
    struct Quality: Codable { let hrv: Double, rhr: Double, sleep: Double }
    struct Fold: Codable {
        let original: RecoveryExplanation.Baseline, candidate: RecoveryExplanation.Baseline?
        let admitted: Int, unknown: Int, rejected: Int
        let status: String
        init(_ r: QualityBaseline.Result) {
            original = .init(r.original);candidate=r.candidate.map(RecoveryExplanation.Baseline.init)
            admitted=r.admitted;unknown=r.unknown;rejected=r.rejected;status=r.status
        }
    }
    struct BandPair: Codable { let original: String?, candidate: String? }
    struct RRNormalization: Codable { let identity: String?, status: String; let inputRows: Int, outputRows: Int, duplicates: Int }
    struct Session: Codable { let start: Int, end: Int; let signalSupport: SleepSignalCoverage.Result }
    let version: String
    let scope: String
    let recipe: Recipe
    let observation: Observation
    let quality: Quality
    let hrvHistory: Fold, rhrHistory: Fold
    let baselineComparison: Metric
    let explanation: RecoveryExplanation.Result?
    let sessions: [Session]
    let bands: [String:BandPair]
    let rrNormalization: RRNormalization
}
