import Foundation
import WhoopStore

/// Extra user-chosen weekly goals shown in "My plan" (0 disables a goal). Local only, not in backups.
enum NroopPlanGoals {
    static let dailyStepsKey = "nroop.plan.dailySteps"
    static let stepsDaysKey = "nroop.plan.stepsDays"
    static let strengthMinutesKey = "nroop.plan.strengthWeeklyMinutes"
}

/// NROOP night stress ESTIMATE, not WHOOP's Sleep Stress score. It reads only the night's real 1-minute
/// heart rate: the reference is the night's own calm floor (10th percentile), and each 5-minute window is
/// placed on a 0–3 scale by how far its mean heart rate rises above that floor (+5 % per step).
enum NightStressEstimate {
    struct Point: Equatable { let ts: Int; let level: Double }
    struct Result: Equatable {
        let points: [Point]
        let lowMinutes: Int
        let mediumMinutes: Int
        let highMinutes: Int
        let floorBpm: Double
    }

    static let windowSeconds = 300

    static func compute(_ buckets: [HRBucket]) -> Result? {
        let valid = buckets.filter { $0.bpm.isFinite && $0.bpm >= 25 && $0.bpm <= 230 }.sorted { $0.ts < $1.ts }
        // At least two hours of minutes, so a short fragment never yields a night curve.
        guard valid.count >= 120 else { return nil }
        let sortedBpm = valid.map(\.bpm).sorted()
        let floor = sortedBpm[Int(Double(sortedBpm.count - 1) * 0.10)]
        guard floor > 0 else { return nil }
        var groups: [Int: [Double]] = [:]
        for bucket in valid { groups[bucket.ts / windowSeconds * windowSeconds, default: []].append(bucket.bpm) }
        var points: [Point] = []
        var low = 0, medium = 0, high = 0
        for start in groups.keys.sorted() {
            guard let values = groups[start], values.count >= 3 else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            let level = min(3, max(0, (mean - floor) / floor / 0.05))
            points.append(Point(ts: start, level: level))
            let minutes = values.count
            if level < 1 { low += minutes } else if level < 2 { medium += minutes } else { high += minutes }
        }
        guard points.count >= 12 else { return nil }
        return Result(points: points, lowMinutes: low, mediumMinutes: medium, highMinutes: high, floorBpm: floor)
    }
}
