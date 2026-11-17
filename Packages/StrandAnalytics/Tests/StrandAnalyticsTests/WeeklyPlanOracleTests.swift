import XCTest
@testable import StrandAnalytics

/// Reverse pin: keep Swift from drifting after Kotlin has accepted the compiled Swift oracle.
final class WeeklyPlanOracleTests: XCTestCase {
    func testCompiledOracleLiteral() {
        let sleep: [WeeklyPlanSleep] = [
            .init(day: "2026-11-09", minutes: 420), .init(day: "2026-11-09", minutes: 480),
            .init(day: "2026-11-10", minutes: .nan), .init(day: "2026-11-10", minutes: -1),
            .init(day: "2026-11-11", minutes: 0), .init(day: "2026-11-12", minutes: 9999),
            .init(day: "2026-11-13", minutes: 600)]
        let dates = ["2026-11-12", "2026-11-15", "2026-11-16", "2026-01-01", "2024-03-03", "2026-03-29", "2026-10-25", "2026-02-29", "2026-2-03", "0000-01-01", "２０２６-01-01", "0001-01-01", "1500-02-28", "2100-01-01", "9999-12-31"]
        var lines: [String] = []
        for date in dates {
            let rows = WeeklyPlanEngine.build(today: date, sleep: sleep, workoutDays: ["2026-11-09", "2026-11-09", "2026-11-12", "2026-11-13"])
            let p = WeeklyPlanEngine.progress(rows: rows, goals: .init(sleepMinutes: 480, sleepNights: 2, workoutDays: 3))
            let trace = rows.map { "\($0.day):\($0.sleepMinutes.map { String(Int($0)) } ?? "?"):\($0.hasRecordedWorkout ? 1 : 0):\($0.isToday ? 1 : 0):\($0.isFuture ? 1 : 0)" }.joined(separator: ";")
            lines.append("\(date)|\(trace)|\(p.sleepNights),\(p.sleepObservedNights),\(p.workoutDays)")
        }
        for triple in [(Int.min, -8, -2), (Int.max, 90, 80), (480, 0, 0), (421, 2, 3)] {
            let g = WeeklyPlanGoals(sleepMinutes: triple.0, sleepNights: triple.1, workoutDays: triple.2)
            lines.append("goals|\(g.sleepMinutes),\(g.sleepNights),\(g.workoutDays)")
        }
        XCTAssertEqual(lines.joined(separator: "\n"), """
2026-11-12|2026-11-09:480:1:0:0;2026-11-10:?:0:0:0;2026-11-11:0:0:0:0;2026-11-12:?:1:1:0;2026-11-13:?:0:0:1;2026-11-14:?:0:0:1;2026-11-15:?:0:0:1|1,2,2
2026-11-15|2026-11-09:480:1:0:0;2026-11-10:?:0:0:0;2026-11-11:0:0:0:0;2026-11-12:?:1:0:0;2026-11-13:600:1:0:0;2026-11-14:?:0:0:0;2026-11-15:?:0:1:0|2,3,3
2026-11-16|2026-11-16:?:0:1:0;2026-11-17:?:0:0:1;2026-11-18:?:0:0:1;2026-11-19:?:0:0:1;2026-11-20:?:0:0:1;2026-11-21:?:0:0:1;2026-11-22:?:0:0:1|0,0,0
2026-01-01|2025-12-29:?:0:0:0;2025-12-30:?:0:0:0;2025-12-31:?:0:0:0;2026-01-01:?:0:1:0;2026-01-02:?:0:0:1;2026-01-03:?:0:0:1;2026-01-04:?:0:0:1|0,0,0
2024-03-03|2024-02-26:?:0:0:0;2024-02-27:?:0:0:0;2024-02-28:?:0:0:0;2024-02-29:?:0:0:0;2024-03-01:?:0:0:0;2024-03-02:?:0:0:0;2024-03-03:?:0:1:0|0,0,0
2026-03-29|2026-03-23:?:0:0:0;2026-03-24:?:0:0:0;2026-03-25:?:0:0:0;2026-03-26:?:0:0:0;2026-03-27:?:0:0:0;2026-03-28:?:0:0:0;2026-03-29:?:0:1:0|0,0,0
2026-10-25|2026-10-19:?:0:0:0;2026-10-20:?:0:0:0;2026-10-21:?:0:0:0;2026-10-22:?:0:0:0;2026-10-23:?:0:0:0;2026-10-24:?:0:0:0;2026-10-25:?:0:1:0|0,0,0
2026-02-29||0,0,0
2026-2-03||0,0,0
0000-01-01||0,0,0
２０２６-01-01||0,0,0
0001-01-01||0,0,0
1500-02-28||0,0,0
2100-01-01||0,0,0
9999-12-31||0,0,0
goals|60,0,0
goals|960,7,7
goals|480,0,0
goals|421,2,3
""")
    }
}
