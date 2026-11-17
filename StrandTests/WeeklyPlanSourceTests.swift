import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

final class WeeklyPlanSourceTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func workout(_ start: String, _ end: String) -> WorkoutRow {
        WorkoutRow(startTs: Int(date(start).timeIntervalSince1970), endTs: Int(date(end).timeIntervalSince1970),
                   sport: "run", source: "manual", durationS: nil, energyKcal: nil, avgHr: nil,
                   maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }
    private func sleep(_ day: String, minutes: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: minutes, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testLocalMidnightUsesStartDayAndIgnoresUnfinishedOrInvalidWorkouts() {
        let now = date("2026-11-12T00:30:00Z") // Paris Thursday 01:30, no 04:00 logical rollover
        let done = workout("2026-11-11T23:10:00Z", "2026-11-12T00:00:00Z")
        let ongoing = workout("2026-11-11T21:00:00Z", "2026-11-12T01:00:00Z")
        let invalid = workout("2026-11-10T12:00:00Z", "2026-11-10T11:00:00Z")
        let rows = WeeklyPlanSource.rows(days: [sleep("2026-11-12", minutes: 480)],
                                        workouts: [done, done, ongoing, invalid], now: now,
                                        timeZone: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertEqual(rows.first(where: \.isToday)?.day, "2026-11-12")
        XCTAssertEqual(rows.filter(\.hasRecordedWorkout).map(\.day), ["2026-11-12"])
        XCTAssertEqual(rows.first(where: \.isToday)?.sleepMinutes, 480)
        let utc = WeeklyPlanSource.rows(days: [], workouts: [done], now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(utc.filter(\.hasRecordedWorkout).map(\.day), ["2026-11-11"])
    }

    func testDSTWeekendRemainsSevenLocalDates() {
        let rows = WeeklyPlanSource.rows(days: [], workouts: [
            workout("2026-03-28T23:30:00Z", "2026-03-29T00:00:00Z"),
            workout("2026-03-29T01:30:00Z", "2026-03-29T02:00:00Z")],
            now: date("2026-03-29T20:00:00Z"), timeZone: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.first?.day, "2026-03-23")
        XCTAssertEqual(rows.filter(\.hasRecordedWorkout).map(\.day), ["2026-03-29"])
    }
}
