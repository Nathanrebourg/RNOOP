import Foundation
import WhoopProtocol

/// Availability evidence on a one-second WHOOP HR grid, not contact detection or clinical confidence.
/// Kotlin twin: SampleQuality.kt. Candidate tiers never replace the incumbent ScoreConfidence labels.
public enum SampleQuality {
    public struct Evidence: Sendable {
        public let expectedSeconds: Int, observedSeconds: Int, longestGap: Int
        public let duplicates: Int, ambiguous: Int, invalid: Int
        public let coverage: Double, reliability: Double
        public let tier: String
    }
    static func uniqueHR(_ hr: [HRSample]) -> [HRSample] {
        Dictionary(grouping: hr.filter { $0.bpm > 0 }, by: \.ts).values.compactMap { rows in
            guard let first = rows.first, rows.allSatisfy({ $0.bpm == first.bpm }) else { return nil }
            return first
        }.sorted { $0.ts < $1.ts }
    }
    public static func analyze(_ hr: [HRSample], start: Int, end: Int) -> Evidence {
        guard end > start, Double(end) - Double(start) <= 172_800 else {
            return Evidence(expectedSeconds: 0, observedSeconds: 0, longestGap: 0, duplicates: 0,
                ambiguous: 0, invalid: 0, coverage: 0, reliability: 0, tier: "calibrating")
        }
        let rows = hr.filter { $0.ts >= start && $0.ts < end }
        let groups = Dictionary(grouping: rows.filter { $0.bpm > 0 }, by: \.ts)
        var duplicates = 0, ambiguous = 0
        for r in groups.values {
            if r.allSatisfy({ $0.bpm == r[0].bpm }) { duplicates += r.count - 1 } else { ambiguous += 1 }
        }
        let clean = uniqueHR(rows)
        var cursor = start, gap = 0
        for s in clean { gap = max(gap, s.ts - cursor); cursor = s.ts + 1 }
        gap = max(gap, end - cursor)
        let invalid = rows.filter { $0.bpm <= 0 }.count
        let span = end - start
        let coverage = Double(clean.count) / Double(span)
        let rejection = Double(ambiguous + invalid) / Double(max(1, groups.count + invalid))
        let continuity = min(1, 120 / Double(max(120, gap)))
        let reliability = coverage * (1 - rejection) * continuity
        let tier = coverage >= 0.8 && gap <= 120 && rejection <= 0.05 ? "solid" : coverage >= 0.2 ? "building" : "calibrating"
        return Evidence(expectedSeconds: span, observedSeconds: clean.count, longestGap: gap,
            duplicates: duplicates, ambiguous: ambiguous, invalid: invalid,
            coverage: coverage, reliability: reliability, tier: tier)
    }
}
