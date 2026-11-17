import Foundation
import WhoopProtocol

/// Availability on a UTC-aligned 30-second grid, not stage accuracy, wear detection or confidence.
/// A cell needs only one plausible HR or finite nonzero gravity vector to be marked supported.
/// Missing cells remain unknown; R-R alone cannot supply the stager's HR/motion features.
public enum SleepSignalCoverage {
    public static let version = "nroop-sleep-support-v1"
    public struct Interval: Codable, Equatable, Sendable {
        public let start: Int, end: Int
        public let kind: String
    }
    public struct Result: Codable, Equatable, Sendable {
        public let status: String
        public let intervals: [Interval]
        /// Duration of cells with this availability, NOT seconds actually sampled.
        public let bothSeconds: Int, hrOnlySeconds: Int, motionOnlySeconds: Int, unknownSeconds: Int
        public let distinctHRSeconds: Int, distinctMotionSeconds: Int
        public var trace: String {
            let cells = intervals.map { "\($0.start):\($0.end):\($0.kind)" }.joined(separator: ",")
            return "\(status)|\(bothSeconds)|\(hrOnlySeconds)|\(motionOnlySeconds)|\(unknownSeconds)|\(distinctHRSeconds)|\(distinctMotionSeconds)|\(cells)"
        }
    }
    public static func analyze(start: Int, end: Int, hr: [HRSample], gravity: [GravitySample]) -> Result {
        // Bounded before subtraction/grid allocation, also identical on 64-bit Kotlin/Swift.
        guard start >= 0, end <= 4_102_444_800, end > start, end - start <= 172_800 else {
            return .init(status: "invalid-window", intervals: [], bothSeconds: 0, hrOnlySeconds: 0,
                         motionOnlySeconds: 0, unknownSeconds: 0, distinctHRSeconds: 0, distinctMotionSeconds: 0)
        }
        let hrs = Set(hr.lazy.filter { $0.ts >= start && $0.ts < end && (1...300).contains($0.bpm) }.map(\.ts))
        let motions = Set(gravity.lazy.filter {
            $0.ts >= start && $0.ts < end && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                && ($0.x != 0 || $0.y != 0 || $0.z != 0)
        }.map(\.ts))
        let hrCells = Set(hrs.map { $0 / 30 }), motionCells = Set(motions.map { $0 / 30 })
        var spans: [Interval] = [], totals = ["both": 0, "hr-only": 0, "motion-only": 0, "unknown": 0]
        var edge = start / 30 * 30
        while edge < end {
            let lo = max(start, edge), hi = min(end, edge + 30)
            let h = hrCells.contains(edge / 30), m = motionCells.contains(edge / 30)
            let kind = h ? (m ? "both" : "hr-only") : (m ? "motion-only" : "unknown")
            totals[kind, default: 0] += hi - lo
            if let last = spans.last, last.kind == kind {
                spans[spans.count - 1] = .init(start: last.start, end: hi, kind: kind)
            } else { spans.append(.init(start: lo, end: hi, kind: kind)) }
            edge += 30
        }
        return .init(status: "observed", intervals: spans, bothSeconds: totals["both"]!,
                     hrOnlySeconds: totals["hr-only"]!, motionOnlySeconds: totals["motion-only"]!,
                     unknownSeconds: totals["unknown"]!, distinctHRSeconds: hrs.count, distinctMotionSeconds: motions.count)
    }
}
