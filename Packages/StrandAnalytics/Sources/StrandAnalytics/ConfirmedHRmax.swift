import Foundation
import WhoopProtocol

/// Experimental calibration only. Confirmed prior-day HR/motion peaks cannot alter profile or Effort.
public enum ConfirmedHRmax {
    public struct DayPeak: Sendable {
        public let dayStart: Int
        public let bpm: Double
        public init(dayStart: Int, bpm: Double) { self.dayStart = dayStart; self.bpm = bpm }
    }
    public struct Estimate: Sendable {
        public let candidate: Double?
        public let source: String
        public let confirmedDays: Int
    }
    /// Maximum 30-second median in continuous HR, corroborated by >=24 gravity seconds and >=30% activity.
    /// This can miss static-wrist exercise; absence is not a measured maximum and retains the fallback.
    public static func dailyPeak(hr: [HRSample], gravity: [GravitySample]) -> Double? {
        let hs = SampleQuality.uniqueHR(hr).filter { (30...250).contains($0.bpm) }
        let gs = Dictionary(grouping: gravity.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 && abs($0.z) <= 1_000_000
            && ($0.x != 0 || $0.y != 0 || $0.z != 0) }, by: \.ts).values.compactMap { r -> GravitySample? in
                let f = r[0]; return r.allSatisfy { $0.x == f.x && $0.y == f.y && $0.z == f.z } ? f : nil
            }.sorted { $0.ts < $1.ts }
        let activity = Dictionary(uniqueKeysWithValues: WorkoutDetector.activitySeries(gs).map { ($0.ts, $0.intensity) })
        var peak: Double?, runStart = 0
        for i in hs.indices {
            if i > 0 && hs[i].ts - hs[i - 1].ts != 1 { runStart = i }
            guard i - runStart >= 29 else { continue }
            let lo = hs[i].ts - 29
            let a = (lo...hs[i].ts).compactMap { activity[$0] }
            guard a.count >= 24, Double(a.filter { $0 > WorkoutDetector.motionThreshold }.count) / Double(a.count) >= 0.3 else { continue }
            let value = HRVAnalyzer.median(hs[(i - 29)...i].map { Double($0.bpm) })
            peak = max(peak ?? value, value)
        }
        return peak
    }
    /// Three separate prior days; the median of the top three limits a single exceptional day.
    /// Do not lower Tanaka merely because no hard exercise was observed. Explicit manual input wins.
    public static func estimate(history: [DayPeak], before: Int, age: Double?, manual: Double? = nil) -> Estimate {
        if let manual {
            return Estimate(candidate: manual.isFinite && (30...250).contains(manual) ? manual : nil,
                source: manual.isFinite && (30...250).contains(manual) ? "manual" : "invalid-manual", confirmedDays: 0)
        }
        let groups = Dictionary(grouping: history.filter {
            $0.dayStart < before && Double(before) - Double($0.dayStart) <= 30 * 86_400
                && (before - $0.dayStart) % 86_400 == 0 && $0.bpm.isFinite && (30...250).contains($0.bpm)
        }, by: \.dayStart)
        let peaks = groups.values.compactMap { r -> Double? in r.allSatisfy { $0.bpm == r[0].bpm } ? r[0].bpm : nil }.sorted(by: >)
        let fallback = age.flatMap { $0.isFinite && (0...120).contains($0) && $0 > 0 ? StrainScorer.tanakaHRmax(age: $0) : nil }
        guard peaks.count >= 3 else { return Estimate(candidate: fallback, source: fallback == nil ? "insufficient-history" : "tanaka", confirmedDays: peaks.count) }
        return Estimate(candidate: max(fallback ?? 0, HRVAnalyzer.median(Array(peaks.prefix(3)))), source: "confirmed-history", confirmedDays: peaks.count)
    }
}
