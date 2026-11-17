import Foundation
import WhoopProtocol

/// Descriptive same-second HR/RR check, not a sensor diagnosis or score input. Source latency and
/// smoothing can explain discrepancies. One vote per second; repeat deliveries never add evidence.
public enum BeatHRConcordance {
    public struct Result: Sendable {
        public let status: String
        public let matchedSeconds: Int
        public let medianAbsoluteBPM: Double?
        public let medianSignedBPM: Double?
        public let discrepantSeconds: Int
        public func trace(day: String) -> String {
            "lab concordance experimental=true model=nroop-concordance-v1 day=\(day) scope=exact-second-selected-hrv-period "
                + "status=\(status) matchedSec=\(matchedSeconds) medianAbsBpm=\(AlgorithmLab.number(medianAbsoluteBPM)) "
                + "medianSignedBpm=\(AlgorithmLab.number(medianSignedBPM)) aboveToleranceSec=\(discrepantSeconds) toleranceBpm=10 noScoreEffect=true"
        }
    }
    public static func analyze(hr: [HRSample], rr: [RRInterval], start: Int, end: Int, eligible: Bool = true) -> Result {
        func unavailable(_ status: String, _ matched: Int = 0) -> Result {
            .init(status: status, matchedSeconds: matched, medianAbsoluteBPM: nil, medianSignedBPM: nil, discrepantSeconds: 0)
        }
        guard eligible else { return unavailable("ineligible-session") }
        guard end > start, Double(end) - Double(start) <= 172_800 else { return unavailable("invalid-window") }
        let beats = rr.filter { $0.ts >= start && $0.ts < end }
        if beats.contains(where: { ![5,7].contains($0.srcChannel?.rawValue ?? -1) }) { return unavailable("unverified-rr-source") }
        if Set(beats.compactMap { $0.srcChannel?.rawValue }).count > 1 { return unavailable("mixed-rr-source") }
        let hrs = SampleQuality.uniqueHR(hr.filter { $0.ts >= start && $0.ts < end && $0.bpm <= 300 })
        let bySecond = Dictionary(grouping: beats.filter { (300...2000).contains($0.rrMs) }, by: \.ts)
        var deltas: [Double] = []
        for h in hrs {
            guard let values = bySecond[h.ts], !values.isEmpty else { continue }
            // Distinct interval values, median within the timestamp, then one vote for this second.
            let inferred = HRVAnalyzer.median(Set(values.map(\.rrMs)).map { 60_000 / Double($0) })
            deltas.append(Double(h.bpm) - inferred)
        }
        guard deltas.count >= 60 else { return unavailable("insufficient-overlap",deltas.count) }
        return .init(status: "observed", matchedSeconds: deltas.count,
            medianAbsoluteBPM: HRVAnalyzer.median(deltas.map(abs)), medianSignedBPM: HRVAnalyzer.median(deltas),
            discrepantSeconds: deltas.filter { abs($0) > 10 }.count)
    }
}
