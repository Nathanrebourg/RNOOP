import Foundation
import WhoopProtocol

/// Measurement-only wiring of the existing personal overnight HR band. Kotlin twin:
/// `SleepBaselineComparison.kt`. Historical calendar windows are a proxy for nights, not sleep labels.
public enum SleepBaselineComparison {
    public struct Window: Sendable {
        public let start: Int
        public let end: Int
    }
    public struct Observation: Sendable {
        public let end: Int
        public let medianBPM: Double
        public let minutes: Int
        public init(end: Int, medianBPM: Double, minutes: Int) {
            self.end = end; self.medianBPM = medianBPM; self.minutes = minutes
        }
    }
    public struct Reference: Sendable {
        public let bpm: Double?
        public let nights: Int
    }
    public struct Result: Sendable {
        public let reference: Reference
        public let status: String
        public let original: [SleepSession]?
        public let candidate: [SleepSession]?

        public func trace(day: String) -> String {
            func windows(_ sessions: [SleepSession]?) -> String {
                guard let sessions else { return "nil" }
                return sessions.isEmpty ? "none" : sessions.map { "\($0.start):\($0.end)" }.joined(separator: ",")
            }
            func inBed(_ sessions: [SleepSession]?) -> String {
                sessions.map { String($0.reduce(0) { $0 + max(0, $1.end - $1.start) }) } ?? "nil"
            }
            func asleep(_ sessions: [SleepSession]?) -> String {
                sessions.map { String($0.flatMap(\.stages).filter { ["light", "deep", "rem"].contains($0.stage) }
                    .reduce(0) { $0 + max(0, $1.end - $1.start) }) } ?? "nil"
            }
            let bpm = reference.bpm.map { value -> String in
                let n = Int((value * 100).rounded()); let f = n % 100
                return "\(n / 100).\(f < 10 ? "0" : "")\(f)"
            } ?? "nil"
            return "sleep baseline experimental=true scope=detector day=\(day) status=\(status) "
                + "source=local00-06 nights=\(reference.nights) baselineBpm=\(bpm) "
                + "originalSessions=\(original.map { String($0.count) } ?? "nil") "
                + "candidateSessions=\(candidate.map { String($0.count) } ?? "nil") "
                + "originalInBedSec=\(inBed(original)) candidateInBedSec=\(inBed(candidate)) "
                + "originalAsleepSec=\(asleep(original)) candidateAsleepSec=\(asleep(candidate)) "
                + "originalWindows=\(windows(original)) candidateWindows=\(windows(candidate))"
        }
    }

    /// Fourteen local 00:00–06:00 windows ending before the entire target read window begins.
    /// One captured offset is used, matching the incumbent detector; this does not infer shift schedules.
    public static func historyWindows(before: Int, offset: Int) -> [Window] {
        let local = before + offset
        let midnight = local - ((local % 86_400 + 86_400) % 86_400)
        var end = midnight + 21_600 - offset
        if end > before { end -= 86_400 }
        return (0..<14).map { Window(start: end - $0 * 86_400 - 21_600, end: end - $0 * 86_400) }
    }

    /// A minute has one vote, regardless of packet density. Conflicting same-second values are excluded.
    /// Three hours of occupied minutes spanning at least four hours are required in the six-hour window.
    /// Reads at the service's 50,000-row limit are declined rather than treating a clipped night as complete.
    public static func observation(_ hr: [HRSample], window: Window) -> Observation? {
        guard hr.count < 50_000, window.end - window.start == 21_600 else { return nil }
        let byTimestamp = Dictionary(grouping: hr.filter {
            $0.bpm > 0 && $0.ts >= window.start && $0.ts < window.end
        }, by: \.ts)
        var byMinute: [Int: [Double]] = [:]
        for (ts, rows) in byTimestamp {
            guard let first = rows.first, rows.allSatisfy({ $0.bpm == first.bpm }) else { continue }
            byMinute[(ts - window.start) / 60, default: []].append(Double(first.bpm))
        }
        let keys = byMinute.keys.sorted()
        guard keys.count >= 180, let first = keys.first, let last = keys.last, last - first >= 240 else { return nil }
        let medians = keys.map { HRVAnalyzer.median(byMinute[$0]!) }
        return Observation(end: window.end, medianBPM: HRVAnalyzer.median(medians), minutes: keys.count)
    }

    /// Only distinct, qualified prior calendar nights may train the reference. Conflicting duplicate
    /// observations are excluded. Three nights are a provisional minimum; the existing 40 bpm floor remains.
    public static func reference(history: [Observation], before: Int, offset: Int) -> Reference {
        let allowed = Set(historyWindows(before: before, offset: offset).map(\.end))
        let grouped = Dictionary(grouping: history.filter {
            allowed.contains($0.end) && $0.minutes >= 180 && $0.minutes <= 360
                && $0.medianBPM.isFinite && $0.medianBPM > 0
        }, by: \.end)
        let medians = grouped.values.compactMap { rows -> Double? in
            guard let first = rows.first, rows.allSatisfy({ $0.medianBPM == first.medianBPM }) else { return nil }
            return first.medianBPM
        }
        return Reference(bpm: medians.count >= 3
            ? SleepStager.adaptiveOvernightHRBaseline(recentOvernightMedians: medians) : nil, nights: medians.count)
    }

    /// Runs the real detector twice with identical inputs; only its optional personal HR reference differs.
    /// Outputs are detector sessions ending on this day, before provided hypnograms or wake refinement.
    /// No caller may feed this candidate into persisted sleep, Rest, HRV or recovery.
    public static func compare(dayStart: Int, readStart: Int, history: [Observation], hr: [HRSample],
                               rr: [RRInterval] = [], resp: [RespSample] = [], gravity: [GravitySample],
                               offset: Int = 0, wristOff: [(start: Int, end: Int)] = [],
                               bandSleepState: [(ts: Int, state: Int)] = [], useSleepStagerV2: Bool = false,
                               readCapped: Bool = false) -> Result {
        let ref = reference(history: history, before: readStart, offset: offset)
        guard let baseline = ref.bpm else {
            return Result(reference: ref, status: "insufficient-history", original: nil, candidate: nil)
        }
        guard !readCapped, gravity.count >= 2 else {
            return Result(reference: ref, status: readCapped ? "target-read-capped" : "no-motion", original: nil, candidate: nil)
        }
        func detect(_ personal: Double?) -> [SleepSession] {
            SleepStager.detectSleep(hr: hr, rr: rr, resp: resp, gravity: gravity, tzOffsetSeconds: offset,
                wristOff: wristOff, bandSleepState: bandSleepState, useSleepStagerV2: useSleepStagerV2,
                sleepHRBaseline: personal)
                .filter { $0.end >= dayStart && $0.end < dayStart + 86_400 }
                .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        }
        return Result(reference: ref, status: "compared", original: detect(nil), candidate: detect(baseline))
    }
}
