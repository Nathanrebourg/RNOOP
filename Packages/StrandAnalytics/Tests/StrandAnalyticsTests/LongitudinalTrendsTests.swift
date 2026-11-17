import Foundation
import XCTest
@testable import StrandAnalytics

final class LongitudinalTrendsTests: XCTestCase {
    typealias S = LongitudinalTrends.Sample

    func testCompiledKotlinOracleBitPatterns() {
        // Captured verbatim from kotlinc + kotlin, including the decimal-rounding fixture.
        let expected = """
        0,30,nil,0;0,150,nil,0;0,180,nil,0;nil;bothWindowsTooSparse;0
        2,30,402e000000000000,3fb1111111111111;2,150,4044000000000000,3f8b4e81b4e81b4f;4,180,403b800000000000,3f96c16c16c16c17;c039000000000000;nil;0
        0,30,nil,0;0,150,nil,0;0,180,nil,0;nil;bothWindowsTooSparse;0
        1,30,0,3fa1111111111111;2,150,4014000000000000,3f8b4e81b4e81b4f;3,180,400aaaaaaaaaaaab,3f91111111111111;nil;recentWindowTooSparse;1
        1,30,4000000000000000,3fa1111111111111;0,150,nil,0;1,180,4000000000000000,3f76c16c16c16c17;nil;bothWindowsTooSparse;0
        26,30,4036b7d3e3a4a0b1,3febbbbbbbbbbbbc;129,150,4036ef26d11625a1,3feb851eb851eb85;155,180,4036e5df199124cb,3feb8e38e38e38e4;bfcba976b8c27800;nil;0
        2,30,3fc3333333333334,3fb1111111111111;2,150,3fd6666666666666,3f8b4e81b4e81b4f;4,180,3fd0000000000000,3f96c16c16c16c17;bfc9999999999998;nil;0
        """
        XCTAssertEqual(longitudinalOracleLines(), expected)
    }

    func testNonoverlappingCompletedCalendarDayWindows() {
        let r = LongitudinalTrends.summarize([
            S(dayAge: -1, value: 999), S(dayAge: 0, value: 999),
            S(dayAge: 1, value: 10), S(dayAge: 30, value: 20),
            S(dayAge: 31, value: 30), S(dayAge: 180, value: 50), S(dayAge: 181, value: 999)
        ])
        XCTAssertEqual(r.recent30.count, 2)
        XCTAssertEqual(r.recent30.mean, 15)
        XCTAssertEqual(r.prior150.count, 2)
        XCTAssertEqual(r.prior150.mean, 40)
        XCTAssertEqual(r.context180.mean, 27.5)
        XCTAssertEqual(r.delta, -25)
        XCTAssertNil(r.insufficientReason)
        XCTAssertEqual(r.recent30.coverage, 2.0 / 30)
    }

    func testMissingInvalidAndDuplicateDaysNeverAddWeight() {
        let samples = [S(dayAge: 1, value: nil), S(dayAge: 2, value: 0),
                       S(dayAge: 2, value: 0), S(dayAge: 3, value: 5), S(dayAge: 3, value: 6),
                       S(dayAge: 4, value: .nan), S(dayAge: 5, value: .infinity),
                       S(dayAge: 6, value: -1), S(dayAge: 7, value: 101),
                       S(dayAge: 31, value: 10), S(dayAge: 32, value: 20)]
        let r = LongitudinalTrends.summarize(samples, bounds: 0...100)
        XCTAssertEqual(r.recent30.count, 1)
        XCTAssertEqual(r.recent30.mean, 0)
        XCTAssertEqual(r.conflictingDays, 1)
        XCTAssertEqual(r.context180.count, 3)
        XCTAssertNil(r.delta)
        XCTAssertEqual(r.insufficientReason, .recentWindowTooSparse)
        XCTAssertEqual(LongitudinalTrends.summarize(samples.reversed(), bounds: 0...100), r)
    }

    func testSparseWindowsExplainWhyDeltaIsAbsent() {
        let empty = LongitudinalTrends.summarize([])
        XCTAssertNil(empty.context180.mean)
        XCTAssertEqual(empty.insufficientReason, .bothWindowsTooSparse)
        let recentOnly = LongitudinalTrends.summarize([S(dayAge: 1, value: 2), S(dayAge: 2, value: 4)])
        XCTAssertEqual(recentOnly.recent30.mean, 3)
        XCTAssertNil(recentOnly.delta)
        XCTAssertEqual(recentOnly.insufficientReason, .priorWindowTooSparse)
    }

    func testInvalidDuplicateDoesNotEraseTheOnlyValidReading() {
        let r = LongitudinalTrends.summarize([S(dayAge: 1, value: .nan), S(dayAge: 1, value: 4), S(dayAge: 1, value: nil)])
        XCTAssertEqual(r.recent30.mean, 4)
        XCTAssertEqual(r.conflictingDays, 0)
    }

    func testCalendarDayAgeAcrossParisDSTAndStrictInvalidDates() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        let spring = c.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 0, minute: 10))!
        XCTAssertEqual(LongitudinalTrends.dayAge(day: "2026-03-29", asOf: spring, calendar: c), 1)
        XCTAssertEqual(LongitudinalTrends.dayAge(day: "2026-03-30", asOf: spring, calendar: c), 0)
        XCTAssertEqual(LongitudinalTrends.dayAge(day: "2026-03-31", asOf: spring, calendar: c), -1)
        let autumn = c.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0, minute: 10))!
        XCTAssertEqual(LongitudinalTrends.dayAge(day: "2026-10-25", asOf: autumn, calendar: c), 1)
        XCTAssertNil(LongitudinalTrends.dayAge(day: "0000-01-01", asOf: spring, calendar: c))
        XCTAssertNil(LongitudinalTrends.dayAge(day: "2026-02-30", asOf: spring, calendar: c))
        XCTAssertNil(LongitudinalTrends.dayAge(day: "2026-3-29", asOf: spring, calendar: c))
        XCTAssertNil(LongitudinalTrends.dayAge(day: "garbage", asOf: spring, calendar: c))
    }
}

// Compiled Kotlin oracle output is pinned below after running the independent twin.
func longitudinalOracleLines() -> String {
    typealias S = LongitudinalTrends.Sample
    let fixtures: [[S]] = [
        [],
        [S(dayAge: 1, value: 10), S(dayAge: 30, value: 20), S(dayAge: 31, value: 30), S(dayAge: 180, value: 50)],
        [S(dayAge: 0, value: 999), S(dayAge: -1, value: 999), S(dayAge: 181, value: 999), S(dayAge: 1, value: nil)],
        [S(dayAge: 1, value: 0), S(dayAge: 1, value: 0), S(dayAge: 2, value: 8), S(dayAge: 2, value: 9), S(dayAge: 31, value: 3), S(dayAge: 32, value: 7)],
        [S(dayAge: 1, value: .nan), S(dayAge: 1, value: 2), S(dayAge: 30, value: .infinity), S(dayAge: 31, value: -1), S(dayAge: 32, value: 101)],
        (-2...183).map { S(dayAge: $0, value: $0 % 7 == 0 ? nil : Double($0 % 17) * 0.37 + 20) },
        [S(dayAge: 1, value: 0.1), S(dayAge: 2, value: 0.2), S(dayAge: 31, value: 0.3), S(dayAge: 32, value: 0.4)]
    ]
    func bits(_ value: Double?) -> String { value.map { String($0.bitPattern, radix: 16) } ?? "nil" }
    return fixtures.map { samples in
        let r = LongitudinalTrends.summarize(samples, bounds: 0...100)
        let windows = [r.recent30, r.prior150, r.context180].map {
            "\($0.count),\($0.calendarDays),\(bits($0.mean)),\(bits($0.coverage))"
        }.joined(separator: ";")
        return "\(windows);\(bits(r.delta));\(r.insufficientReason?.rawValue ?? "nil");\(r.conflictingDays)"
    }.joined(separator: "\n")
}
