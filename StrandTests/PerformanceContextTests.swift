import XCTest
#if !PERFORMANCE_CONTEXT_STANDALONE
@testable import Strand
#endif

final class PerformanceContextTests: XCTestCase {
    func testRejectsInvalidAndNonCanonicalDayKeys() {
        for day in ["2026-02-29", "2026-13-01", "2026-1-01", "2026-11-16T12:00:00Z", ""] {
            XCTAssertNil(PerformanceContext(day: day, domain: .sleep), day)
        }
        XCTAssertNotNil(PerformanceContext(day: "2024-02-29", domain: .sleep))
    }

    func testHistoricalWindowNeverIncludesFutureOrTooOldDays() throws {
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .trend, metric: "hrv", windowDays: 7))
        XCTAssertEqual(context.lowerBound, "2026-11-09")
        XCTAssertTrue(context.contains("2026-11-09"))
        XCTAssertTrue(context.contains("2026-11-15"))
        XCTAssertFalse(context.contains("2026-11-16"))
        XCTAssertFalse(context.contains("2026-11-08"))
        XCTAssertFalse(context.contains("invalid"))
    }

    func testCalendarWindowIsStableAcrossDaylightSavingChange() throws {
        let context = try XCTUnwrap(PerformanceContext(day: "2026-03-30", domain: .recovery, windowDays: 3))
        XCTAssertEqual(context.lowerBound, "2026-03-28")
        XCTAssertEqual(context.shiftedDay(by: -1), "2026-03-29")
        XCTAssertEqual(context.shiftedDay(by: 1), "2026-03-31")
    }

    func testConversationIdentitySeparatesDayDomainMetricAndPeriod() throws {
        let a = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .trend, metric: "hrv", windowDays: 7))
        let b = try XCTUnwrap(PerformanceContext(day: "2026-11-14", domain: .trend, metric: "hrv", windowDays: 7))
        let c = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .trend, metric: "rhr", windowDays: 7))
        let d = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .trend, metric: "hrv", windowDays: 28))
        let e = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .recovery))
        XCTAssertEqual(Set([a.id,b.id,c.id,d.id,e.id]).count, 5)
        XCTAssertEqual(a.id, PerformanceContext(day: a.day, domain: a.domain, metric: a.metric, windowDays: a.windowDays)?.id)
    }

    func testConsentOffRedactsMeasurementPayload() throws {
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .recovery))
        let summary = context.coachEnvelope(measurements: "HRV 58 ms; recovery 67%", dataConsent: false)
        XCTAssertFalse(summary.contains("58"))
        XCTAssertFalse(summary.contains("67"))
        XCTAssertTrue(summary.contains("withheld"))
        XCTAssertTrue(summary.contains("2026-11-15"))
    }

    func testExplicitConsentIncludesDatedPayloadAndNoTodayInstruction() throws {
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .recovery))
        let summary = context.coachEnvelope(measurements: "HRV 58 ms", dataConsent: true)
        XCTAssertTrue(summary.contains("HRV 58 ms"))
        XCTAssertTrue(summary.contains("2026-11-15"))
        XCTAssertTrue(summary.contains("not today's"))
    }

    func testMissingValuesAreNotZeroOrNonFinite() {
        XCTAssertNil(PerformanceContext.finite(nil))
        XCTAssertNil(PerformanceContext.finite(.nan))
        XCTAssertNil(PerformanceContext.finite(.infinity))
        XCTAssertEqual(PerformanceContext.finite(0), 0)
        XCTAssertEqual(PerformanceContext.mean([nil, 40, .nan, 60]), 50)
        XCTAssertNil(PerformanceContext.mean([nil, .nan]))
    }

    func testCannotCreateUnboundedOrNegativeWindow() {
        XCTAssertNil(PerformanceContext(day: "2026-11-15", domain: .trend, windowDays: 0))
        XCTAssertNil(PerformanceContext(day: "2026-11-15", domain: .trend, windowDays: 401))
    }
}
