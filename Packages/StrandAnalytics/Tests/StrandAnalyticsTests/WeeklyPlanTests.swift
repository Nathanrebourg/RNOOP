import XCTest
@testable import StrandAnalytics

final class WeeklyPlanTests: XCTestCase {
    func testMondayWeekAcrossYearAndLeapDay() {
        XCTAssertEqual(WeeklyPlanEngine.build(today: "2026-01-01", sleep: [], workoutDays: []).map(\.day),
                       ["2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"])
        XCTAssertEqual(WeeklyPlanEngine.build(today: "2024-03-03", sleep: [], workoutDays: []).first?.day, "2024-02-26")
        for key in ["2026-02-29", "2026-2-03", "2026-13-01", "1500-02-28", "0001-01-01", "2100-01-01", "9999-12-31", "", "２０２６-01-01"] {
            XCTAssertTrue(WeeklyPlanEngine.build(today: key, sleep: [], workoutDays: []).isEmpty)
        }
    }

    func testDuplicateMissingInvalidAndFutureRecordsStayHonest() {
        let sleep: [WeeklyPlanSleep] = [
            .init(day: "2026-11-09", minutes: 420), .init(day: "2026-11-09", minutes: 480),
            .init(day: "2026-11-10", minutes: .nan), .init(day: "2026-11-10", minutes: -1),
            .init(day: "2026-11-11", minutes: 0), .init(day: "2026-11-12", minutes: 9999),
            .init(day: "2026-11-13", minutes: 600), .init(day: "2026-11-08", minutes: 600)]
        let rows = WeeklyPlanEngine.build(today: "2026-11-12", sleep: sleep,
                                          workoutDays: ["2026-11-09", "2026-11-09", "2026-11-12", "2026-11-13"])
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0].sleepMinutes, 480)
        XCTAssertNil(rows[1].sleepMinutes)
        XCTAssertEqual(rows[2].sleepMinutes, 0) // an explicit zero is known, missing is nil
        XCTAssertNil(rows[3].sleepMinutes)
        XCTAssertNil(rows[4].sleepMinutes)
        XCTAssertTrue(rows[3].isToday)
        XCTAssertTrue(rows[4].isFuture)
        XCTAssertFalse(rows[4].hasRecordedWorkout)
        let goals = WeeklyPlanGoals(sleepMinutes: 480, sleepNights: 2, workoutDays: 3)
        let totals = WeeklyPlanEngine.progress(rows: rows, goals: goals)
        XCTAssertEqual(totals.sleepNights, 1)
        XCTAssertEqual(totals.sleepObservedNights, 2)
        XCTAssertEqual(totals.workoutDays, 2)
        XCTAssertEqual(WeeklyPlanEngine.build(today: "2026-11-12", sleep: sleep.reversed(), workoutDays: [] ).map(\.sleepMinutes), rows.map(\.sleepMinutes))
    }

    func testGoalBoundsAndDisabledGoals() {
        let low = WeeklyPlanGoals(sleepMinutes: Int.min, sleepNights: -8, workoutDays: -2)
        XCTAssertEqual(low.sleepMinutes, 60)
        XCTAssertEqual(low.sleepNights, 0)
        XCTAssertEqual(low.workoutDays, 0)
        let high = WeeklyPlanGoals(sleepMinutes: Int.max, sleepNights: 90, workoutDays: 80)
        XCTAssertEqual(high.sleepMinutes, 960)
        XCTAssertEqual(high.sleepNights, 7)
        XCTAssertEqual(high.workoutDays, 7)
    }

    func testSundayAndMondayDoNotBecomeRollingSevenDays() {
        XCTAssertEqual(WeeklyPlanEngine.build(today: "2026-11-15", sleep: [], workoutDays: []).last?.day, "2026-11-15")
        XCTAssertEqual(WeeklyPlanEngine.build(today: "2026-11-16", sleep: [], workoutDays: []).first?.day, "2026-11-16")
    }
}
