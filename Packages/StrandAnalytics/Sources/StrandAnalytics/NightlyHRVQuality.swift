import Foundation
import WhoopProtocol

/// Experimental, measurement-only nightly RMSSD. Never supplies a daily score or personal baseline.
/// Weights five-minute means by usable beat-time, retained fraction and temporal continuity.
/// These weights are an engineering hypothesis, not a validated physiological model. Kotlin twin:
/// `NightlyHRVQuality.kt`. Only the default-off HRV Test Centre trace calls this from the app.
public enum NightlyHRVQuality {
    public static let windowSeconds = 300
    public static let maxSessionSeconds = 172_800

    public struct Summary: Sendable {
        public let weightedRMSSD: Double?
        /// Clean heartbeat seconds in admitted windows divided by the entire requested session.
        public let coverage: Double
        public let totalWindows: Int
        public let usableWindows: Int
        public let inputBeats: Int
        public let rejectedBeats: Int
        public let usablePairs: Int
        public let longGaps: Int
        public let overCounted: Bool

        /// Compact comparison for an explicitly enabled diagnostic report. No timestamps or identifiers.
        public func trace(original: Double?) -> String {
            "hrv quality experimental=true original=\(NightlyHRVQuality.ms(original)) "
                + "candidate=\(NightlyHRVQuality.ms(weightedRMSSD)) "
                + "coveragePct=\(Int((coverage * 100).rounded())) windows=\(usableWindows)/\(totalWindows) "
                + "input=\(inputBeats) rejected=\(rejectedBeats) pairs=\(usablePairs) "
                + "longGaps=\(longGaps) overCounted=\(overCounted)"
        }
    }

    /// Stable timestamp ordering preserves within-second emission order. Bounds match the incumbent:
    /// half-open windows, with the session endpoint included in the final window. A 48-hour bound keeps
    /// corrupt session spans from allocating unbounded work; it is not a sleep-detection threshold.
    public static func analyze(start: Int, end: Int, rr: [RRInterval]) -> Summary {
        let (span, overflow) = end.subtractingReportingOverflow(start)
        guard !overflow, span > 0, span <= maxSessionSeconds else {
            return Summary(weightedRMSSD: nil, coverage: 0, totalWindows: 0, usableWindows: 0,
                           inputBeats: 0, rejectedBeats: 0, usablePairs: 0, longGaps: 0, overCounted: false)
        }
        let samples = rr.enumerated().filter { $0.element.ts >= start && $0.element.ts <= end }
            .sorted { $0.element.ts == $1.element.ts ? $0.offset < $1.offset : $0.element.ts < $1.element.ts }
            .map(\.element)
        let rawCoverage = HRVAnalyzer.rrCoverage(tsSec: samples.map(\.ts), rrMs: samples.map { Double($0.rrMs) })
        let overCounted = !HRVAnalyzer.successiveDiffIsTrustworthy(
            HRVAnalyzer.classifyCoverage(coverage: rawCoverage, collapsed: rawCoverage))
        let totalWindows = (span + windowSeconds - 1) / windowSeconds
        var weightedSum = 0.0, totalWeight = 0.0, acceptedSeconds = 0.0
        var usableWindows = 0, rejected = 0, pairs = 0, longGaps = 0, cursor = 0
        for window in 0..<totalWindows {
            let lo = start + window * windowSeconds
            let duration = min(windowSeconds, end - lo)
            let final = window == totalWindows - 1
            let first = cursor
            while cursor < samples.count && (final || samples[cursor].ts < lo + duration) { cursor += 1 }
            let bucket = Array(samples[first..<cursor])
            guard !bucket.isEmpty else { continue }
            let cleaned = HRVAnalyzer.cleanRRGapAware(bucket.map { Double($0.rrMs) })
            rejected += bucket.count - cleaned.nn.count
            var contiguous = cleaned.contiguous
            var validPairs = 0
            for i in cleaned.nn.indices where i > 0 {
                let dt = Double(bucket[cleaned.sourceIndices[i]].ts - bucket[cleaned.sourceIndices[i - 1]].ts)
                // Seconds-resolution timestamps can repeat. Preserve their array order; only a gap
                // beyond the current interval plus quantization allowance breaks the pair.
                let tooFar = dt > max(2.0, cleaned.nn[i] / 1_000 + 1)
                if tooFar { longGaps += 1; contiguous[i] = false }
                if contiguous[i] { validPairs += 1 }
            }
            pairs += validPairs
            let localCoverage = HRVAnalyzer.rrCoverage(tsSec: bucket.map(\.ts), rrMs: bucket.map { Double($0.rrMs) })
            guard cleaned.nn.count >= HRVAnalyzer.minBeats, validPairs >= HRVAnalyzer.minBeats - 1,
                  localCoverage > 0,
                  HRVAnalyzer.successiveDiffIsTrustworthy(HRVAnalyzer.classifyCoverage(
                    coverage: localCoverage, collapsed: localCoverage)),
                  let rmssd = HRVAnalyzer.rmssdGapAware(cleaned.nn, contiguous), rmssd.isFinite else { continue }
            let seconds = min(Double(duration), cleaned.nn.reduce(0, +) / 1_000)
            let retained = Double(cleaned.nn.count) / Double(bucket.count)
            let continuity = Double(validPairs) / Double(cleaned.nn.count - 1)
            let weight = seconds * retained * continuity
            weightedSum += rmssd * weight
            totalWeight += weight
            acceptedSeconds += seconds
            usableWindows += 1
        }
        return Summary(weightedRMSSD: !overCounted && totalWeight > 0 ? weightedSum / totalWeight : nil,
                       coverage: overCounted ? 0 : min(1, acceptedSeconds / Double(span)),
                       totalWindows: totalWindows, usableWindows: usableWindows, inputBeats: samples.count,
                       rejectedBeats: rejected, usablePairs: pairs, longGaps: longGaps, overCounted: overCounted)
    }

    private static func ms(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < 1_000_000 else { return "nil" }
        let hundredths = Int((value * 100).rounded())
        let fraction = hundredths % 100
        return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)ms"
    }
}
