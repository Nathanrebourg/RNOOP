import Foundation
import StrandAnalytics
import WhoopStore

/// Read-only conversion of the actual stored route. Missing witnesses stay missing.
enum ExerciseGpsResearchAdapter {
    static func sport(_ value:String)->String {
        switch value.lowercased() {case "run","running":return "running";case "walk","walking":return "walking";default:return value.lowercased()}
    }
    static func input(row: WorkoutRow, route: WorkoutRoute?, owner: String?, heartRates: [ExerciseGpsEvidence.HeartRate]) -> ExerciseGpsEvidence.Input {
        let fixes: [ExerciseGpsEvidence.Fix]
        if let points = route?.points, !points.isEmpty {
            fixes = points.map { .init(lat: $0.lat, lon: $0.lon, time: Double($0.tMs)/1000, accuracyM: $0.accuracyM) }
        } else {
            fixes = RouteMath.decode(route?.polyline ?? "").map { .init(lat: $0.lat, lon: $0.lon, time: nil, accuracyM: nil) }
        }
        return .init(start: Double(row.startTs), end: Double(row.endTs), sport: sport(row.sport), owner: owner,
                     storedDistanceM: route?.distanceM ?? row.distanceM, fixes: fixes, heartRates: heartRates)
    }

    static func kline(row: WorkoutRow, input: ExerciseGpsEvidence.Input, evidence: ExerciseGpsEvidence.Result,
                      age: Double, weightKg: Double, sex: Int, repeatSeconds: Double, confirmed: Bool) -> ExerciseGpsEvidence.KlineEstimate? {
        guard input.sport == "walking", evidence.metersPerBeat != nil,
              let distance = evidence.distanceM, abs(distance-1609.344) <= 1609.344*0.03,
              let last = input.heartRates.last, input.end-last.time <= 5 else { return nil }
        return ExerciseGpsEvidence.kline(age: age, weightKg: weightKg, sex: sex, seconds: input.end-input.start,
                                         repeatSeconds: repeatSeconds, fourthQuarterHr: last.bpm, confirmed: confirmed)
    }
}
