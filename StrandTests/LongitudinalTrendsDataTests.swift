import Foundation
import XCTest
import WhoopStore
@testable import Strand

final class LongitudinalTrendsDataTests: XCTestCase {
    private func metric(_ day: String, rhr: Int? = nil, hrv: Double? = nil,
                        sleep: Double? = nil, steps: Int? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: nil, strain: nil, exerciseCount: nil, steps: steps)
    }

    func testFullWindowUsesCalendarDaysAcrossDST() {
        let calendar = LongitudinalTrendsData.calendar(timeZone: TimeZone(identifier: "Europe/Paris")!)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 0, minute: 10))!
        let window = LongitudinalTrendsData.window(asOf: now, calendar: calendar)
        XCTAssertEqual(window?.from, "2025-10-01")
        XCTAssertEqual(window?.to, "2026-03-29")
    }

    func testAdapterUsesActualDailyFieldsAndNeverInventsMissingReadings() {
        let calendar = LongitudinalTrendsData.calendar(timeZone: TimeZone(identifier: "Europe/Paris")!)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        let data = [metric("2026-03-29", rhr: 60, hrv: 42, sleep: 450, steps: 0),
                    metric("2026-03-28", rhr: 62),
                    metric("2026-03-30", rhr: 200, hrv: 999, sleep: 1440, steps: 999_999),
                    metric("2026-03-31", rhr: 200), metric("bad", rhr: 200)]
        let rows = LongitudinalTrendsData.rows(days: data, asOf: now, calendar: calendar)
        XCTAssertEqual(rows.first { $0.metric == .restingHR }?.summary.recent30.mean, 61)
        XCTAssertEqual(rows.first { $0.metric == .hrv }?.summary.recent30.count, 1)
        XCTAssertEqual(rows.first { $0.metric == .sleepHours }?.summary.recent30.mean, 7.5)
        XCTAssertEqual(rows.first { $0.metric == .steps }?.summary.recent30.mean, 0)
        XCTAssertEqual(rows.first { $0.metric == .steps }?.summary.recent30.count, 1)
    }

    func testInvalidAndConflictingFieldsAreRejectedPerMetric() {
        let calendar = LongitudinalTrendsData.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!
        let rows = LongitudinalTrendsData.rows(days: [
            metric("2026-03-29", rhr: 60, hrv: -1, sleep: 1450, steps: -1),
            metric("2026-03-29", rhr: 61), metric("2026-03-28", rhr: 10)
        ], asOf: now, calendar: calendar)
        XCTAssertEqual(rows.first { $0.metric == .restingHR }?.summary.conflictingDays, 1)
        XCTAssertTrue(rows.allSatisfy { $0.summary.context180.mean == nil })
    }
    func testComputedZeroHRVIsKnownRatherThanMissing() {
        let calendar = LongitudinalTrendsData.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = ISO8601DateFormatter().date(from: "2026-03-30T12:00:00Z")!
        let rows = LongitudinalTrendsData.rows(days: [metric("2026-03-29", hrv: 0)], asOf: now, calendar: calendar)
        let hrv = rows.first { $0.metric == .hrv }!
        XCTAssertEqual(hrv.summary.recent30.count, 1)
        XCTAssertEqual(hrv.summary.recent30.mean, 0)
    }
}
