import Foundation
import WhoopProtocol

/// Measurement-only alternative to the fixed two-minute sample-duration ceiling. Kotlin twin:
/// `EffortCadenceComparison.kt`. No heart-rate values are smoothed or peak-filtered. The candidate
/// never supplies stored Effort, training load, recovery, or the live gauge.
public enum EffortCadenceComparison {
    public static let neighbours = 5
    public static let maximumReferenceGapSeconds = 60.0
    public static let cadenceAllowance = 2.0

    public struct Summary: Sendable {
        public let candidateScore: Double?
        public let candidateTRIMP: Double?
        /// Credited seconds for each unique, unambiguous valid timestamp, in timestamp order.
        public let durationsSeconds: [Double]
        /// Sum before the last reading; excludes the explicitly estimated tail.
        public let supportedSeconds: Double
        public let creditedSeconds: Double
        /// Observed timestamp span minus supportedSeconds; not a direct measure of time off-wrist.
        public let unsupportedSeconds: Double
        public let uniqueReadings: Int
        public let duplicatesRemoved: Int
        public let ambiguousTimestamps: Int
        public let invalidReadings: Int
        public let gapsClipped: Int
        public let configurationValid: Bool

        public func trace(original: Double?) -> String {
            "effort cadence experimental=true scale=0-100 original=\(EffortCadenceComparison.number(original)) "
                + "candidate=\(EffortCadenceComparison.number(candidateScore)) "
                + "supportedSec=\(EffortCadenceComparison.number(supportedSeconds)) "
                + "tailSec=\(EffortCadenceComparison.number(durationsSeconds.last ?? 0)) "
                + "unsupportedSec=\(EffortCadenceComparison.number(unsupportedSeconds)) "
                + "readings=\(uniqueReadings) duplicates=\(duplicatesRemoved) "
                + "ambiguous=\(ambiguousTimestamps) invalid=\(invalidReadings) "
                + "clipped=\(gapsClipped) configValid=\(configurationValid)"
        }
    }

    /// Both a fresh analysis and a cached replay use this routing; disabled comparisons stay absent.
    public static func replayDiagnostic(_ line: String, regularSink: (String) -> Void,
                                        comparisonSink: ((String) -> Void)?) {
        if line.hasPrefix("effort cadence experimental=") { comparisonSink?(line) }
        else { regularSink(line) }
    }

    /// Uses local cadence on either side of a gap, excluding that gap. The slower supported side wins
    /// so a real 1s-to-30s cadence transition is not mistaken for a dropout. Reference gaps above one
    /// minute are excluded; the credit ceiling remains at most the incumbent's two minutes. Both the
    /// allowance and reference neighbourhood are provisional engineering choices, not wear detection.
    public static func analyze(_ hr: [HRSample], maxHR: Double? = nil,
                               restingHR: Double = StrainScorer.defaultRestingHR,
                               method: StrainScorer.Method = .edwards, sex: String = "male",
                               denominator: Double? = nil) -> Summary {
        let invalid = hr.filter { $0.bpm <= 0 }.count
        let sorted = hr.filter { $0.bpm > 0 }.sorted { ($0.ts, $0.bpm) < ($1.ts, $1.bpm) }
        var samples: [HRSample] = []
        var duplicates = 0, ambiguous = 0, cursor = 0
        while cursor < sorted.count {
            let first = cursor
            while cursor < sorted.count && sorted[cursor].ts == sorted[first].ts { cursor += 1 }
            if sorted[first].bpm != sorted[cursor - 1].bpm {
                ambiguous += 1 // no arbitrary choice between conflicting values
            } else {
                samples.append(sorted[first])
                duplicates += cursor - first - 1
            }
        }
        let gaps = samples.indices.dropFirst().map { Double(samples[$0].ts) - Double(samples[$0 - 1].ts) }
        func median(_ range: Range<Int>) -> Double? {
            let valid = gaps[range].filter { $0 > 0 && $0 <= maximumReferenceGapSeconds }.sorted()
            guard !valid.isEmpty else { return nil }
            let middle = valid.count / 2
            return valid.count % 2 == 0 ? (valid[middle - 1] + valid[middle]) / 2 : valid[middle]
        }
        var durations: [Double] = []
        var clipped = 0
        for i in gaps.indices {
            let before = median(max(0, i - neighbours)..<i) ?? 0
            let after = median((i + 1)..<min(gaps.count, i + neighbours + 1)) ?? 0
            let ceiling = min(StrainScorer.maxSampleGapMin * 60, cadenceAllowance * max(before, after))
            let credit = min(gaps[i], ceiling)
            durations.append(credit)
            if credit < gaps[i] { clipped += 1 }
        }
        let supported = durations.reduce(0, +)
        let tail = median(max(0, gaps.count - neighbours)..<gaps.count) ?? 0
        if !samples.isEmpty { durations.append(tail) }
        let credited = supported + tail
        let span = gaps.reduce(0, +)
        let effMax = maxHR ?? Double(StrainScorer.defaultMaxHR())
        let resolvedDenominator = denominator ?? StrainScorer.logMapDenominator(method: method, sex: sex)
        let valid = effMax.isFinite && restingHR.isFinite && effMax > restingHR
            && resolvedDenominator.isFinite && resolvedDenominator > 1
        let enough = samples.count >= StrainScorer.minSparseReadings
            && supported >= Double(StrainScorer.minSpanSeconds)
        var trimp: Double?, score: Double?
        if valid && enough {
            let minutes = durations.map { $0 / 60 }
            switch method {
            case .edwards:
                trimp = StrainScorer.edwardsTRIMP(samples, restingHR: restingHR,
                    hrReserve: effMax - restingHR, durations: minutes)
            case .banister:
                let c = StrainScorer.banisterCoefficients(sexF: sex.lowercased().hasPrefix("f"))
                trimp = StrainScorer.banisterTRIMP(samples, restingHR: restingHR,
                    hrReserve: effMax - restingHR, durations: minutes, c,
                    floorRatePerMinute: StrainScorer.banisterBaselineRatePerMinute(c))
            }
            score = trimp.map { StrainScorer.trimpToStrain($0, denominator: resolvedDenominator) }
        }
        return Summary(candidateScore: score, candidateTRIMP: trimp, durationsSeconds: durations,
            supportedSeconds: supported, creditedSeconds: credited, unsupportedSeconds: max(0, span - supported),
            uniqueReadings: samples.count, duplicatesRemoved: duplicates, ambiguousTimestamps: ambiguous,
            invalidReadings: invalid, gapsClipped: clipped, configurationValid: valid)
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < 1_000_000_000 else { return "nil" }
        let hundredths = Int((value * 100).rounded())
        let fraction = hundredths % 100
        return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}
