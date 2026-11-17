import Foundation
import WhoopProtocol

/// Default-off five-minute HR-only stress-proxy experiment. Kotlin twin: StressCadenceComparison.kt.
/// Uses the incumbent's hourly day-relative HR reference, never a nocturnal reference or daytime RMSSD.
/// Candidate values are diagnostics only: no score, widget, nudge, recovery or training-load writes.
public enum StressCadenceComparison {
    public struct Point: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let level: Double?
        public let originalLevel: Double?
        public let status: String
    }
    public struct Result: Sendable {
        public let status: String
        public let referenceHR: Double?
        public let referenceSpread: Double
        public let referenceHours: Int
        public let points: [Point]
        public var candidateHighMinutes: Int { points.filter { ($0.level ?? -1) >= DaytimeStress.highBandFloor }.count * 5 }

        public func lines(day: String) -> [String] {
            let scored = points.filter { $0.level != nil }
            let matched = scored.filter { $0.originalLevel != nil }
            let oldHigh = matched.filter { ($0.originalLevel ?? -1) >= DaytimeStress.highBandFloor }.count * 5
            let newHigh = matched.filter { ($0.level ?? -1) >= DaytimeStress.highBandFloor }.count * 5
            let summary = "stress cadence experimental=true scope=day-relative-hr-only day=\(day) scale=0-3 "
                + "status=\(status) windowSec=300 windows=\(points.count) scored=\(scored.count) matched=\(matched.count) "
                + "referenceHours=\(referenceHours) referenceBpm=\(StressCadenceComparison.number(referenceHR)) "
                + "referenceSpread=\(StressCadenceComparison.number(referenceSpread)) "
                + "candidateHighMin=\(candidateHighMinutes) candidateHighMatchedMin=\(newHigh) originalHighMatchedMin=\(oldHigh) "
                + "candidatePeak=\(StressCadenceComparison.number(scored.compactMap(\.level).max())) "
                + "originalPeakMatched=\(StressCadenceComparison.number(matched.compactMap(\.originalLevel).max())) detail=last12 noAlerts=true"
            return [summary] + points.suffix(12).map {
                "stress cadence point experimental=true day=\(day) start=\($0.start) end=\($0.end) "
                    + "status=\($0.status) original=\(StressCadenceComparison.number($0.originalLevel)) candidate=\(StressCadenceComparison.number($0.level))"
            }
        }
    }

    /// Completed non-overlapping local five-minute windows only. Coverage requires >=240 distinct
    /// seconds per signal, with no internal or boundary gap above 15 seconds. This proves availability,
    /// not wear/contact. Duplicate deliveries cannot satisfy the gate; conflicting timestamps are excluded.
    public static func analyze(hr: [HRSample], gravity: [GravitySample], dayStart: Int, now: Int,
                               offset: Int = 0, readCapped: Bool = false) -> Result {
        func empty(_ status: String) -> Result {
            Result(status: status, referenceHR: nil, referenceSpread: 0, referenceHours: 0, points: [])
        }
        guard !readCapped else { return empty("read-capped") }
        guard now > dayStart else { return empty("no-completed-window") }
        let limit = min(now, dayStart + 86_400)
        let hs = Dictionary(grouping: hr.filter { $0.bpm > 0 && $0.ts >= dayStart && $0.ts < limit }, by: \.ts)
            .values.compactMap { rows -> HRSample? in
                guard let first = rows.first, rows.allSatisfy({ $0.bpm == first.bpm }) else { return nil }
                return first
            }.sorted { $0.ts < $1.ts }
        guard !hs.isEmpty else { return empty("no-heart-rate") }
        let gs = Dictionary(grouping: gravity.filter {
            $0.ts >= dayStart && $0.ts < limit && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                // Numeric guard before the incumbent cache fingerprint scales axes into integers.
                && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 && abs($0.z) <= 1_000_000
                && ($0.x != 0 || $0.y != 0 || $0.z != 0)
        }, by: \.ts).values.compactMap { rows -> GravitySample? in
            guard let first = rows.first, rows.allSatisfy({ $0.x == first.x && $0.y == first.y && $0.z == first.z }) else { return nil }
            return first
        }.sorted { $0.ts < $1.ts }
        guard !gs.isEmpty else { return empty("no-motion") }
        func bucket(_ ts: Int, _ width: Int) -> Int { DaytimeStress.floorDiv(ts + offset, width) * width - offset }
        let hourly = DaytimeStress.analyze(hr: hs, rr: [], gravity: gs, tzOffsetSeconds: offset)
        let original = Dictionary(uniqueKeysWithValues: hourly.hours.map { ($0.startTs, $0) })
        let activity = WorkoutDetector.activitySeries(gs)
        let hourActivity = Dictionary(grouping: activity, by: { bucket($0.ts, 3_600) })
        func active<T>(_ rows: [T], intensity: (T) -> Double) -> Bool {
            !rows.isEmpty && Double(rows.filter { intensity($0) > WorkoutDetector.motionThreshold }.count) / Double(rows.count)
                >= DaytimeStress.activityMaskFraction
        }
        // The incumbent excludes directly ambulatory hours from calibration, but retains its recovery
        // shadow hours there. Reproduce that distinction rather than deriving a new five-minute baseline.
        let refValues = hourly.hours.filter {
            !active(hourActivity[$0.startTs] ?? [], intensity: { $0.intensity })
        }.compactMap(\.meanHR)
        let ref = DaytimeStress.calmReference(refValues, calmIsLow: true)
        let sd = DaytimeStress.std(refValues, mean: DaytimeStress.mean(refValues))
        let enoughReference = refValues.count >= 3 && ref?.isFinite == true && sd.isFinite
        let hrGrid = Dictionary(grouping: hs, by: { bucket($0.ts, 300) })
        let gravGrid = Dictionary(grouping: gs, by: { bucket($0.ts, 300) })
        let activityGrid = Dictionary(grouping: activity, by: { bucket($0.ts, 300) })
        func covered(_ timestamps: [Int], start: Int) -> Bool {
            guard timestamps.count >= 240, let first = timestamps.first, let last = timestamps.last,
                  first - start <= 15, start + 299 - last <= 15 else { return false }
            return zip(timestamps, timestamps.dropFirst()).allSatisfy { $1 - $0 <= 15 }
        }
        let directlyActive = Set(gravGrid.keys.filter { start in
            covered((gravGrid[start] ?? []).map(\.ts), start: start)
                && active(activityGrid[start] ?? [], intensity: { $0.intensity })
        })
        var points: [Point] = []
        let first = bucket(dayStart, 300)
        for start in stride(from: first, to: limit, by: 300) {
            guard start >= dayStart, start + 300 <= limit,
                  DaytimeStress.isWakingHour(bucket(start, 3_600) + offset) else { continue }
            let rows = hrGrid[start] ?? []
            let mean = DaytimeStress.mean(rows.map { Double($0.bpm) })
            let parent = original[bucket(start, 3_600)]
            var status = "scored"
            if !covered(rows.map(\.ts), start: start) { status = "hr-coverage" }
            else if !covered((gravGrid[start] ?? []).map(\.ts), start: start) { status = "motion-coverage" }
            else if directlyActive.contains(start) { status = "activity" }
            else if parent?.maskedForActivity == true { status = "hour-activity" }
            else if let mean, let ref, mean > ref + DaytimeStress.postActivityShadowBPM,
                    directlyActive.contains(where: { $0 < start && start - $0 <= 3_600 }) { status = "post-activity" }
            else if !enoughReference { status = "insufficient-reference" }
            let level: Double? = status == "scored" ? DaytimeStress.squash(sd > 0.0001 ? ((mean ?? 0) - (ref ?? 0)) / sd : 0) : nil
            points.append(Point(start: start, end: start + 300, level: level, originalLevel: parent?.level, status: status))
        }
        return Result(status: enoughReference ? "compared" : "insufficient-reference", referenceHR: ref,
                      referenceSpread: sd, referenceHours: refValues.count, points: points)
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < 1_000_000_000 else { return "nil" }
        let n = Int((value * 100).rounded()), f = n % 100
        return "\(n / 100).\(f < 10 ? "0" : "")\(f)"
    }
}
