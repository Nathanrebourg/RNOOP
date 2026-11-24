import XCTest
@testable import StrandAnalytics

final class DayOwnerResolverTests: XCTestCase {
    func testActiveStrapOwnsDayItHasData() {
        let candidates = [
            DayOwnerResolver.Candidate(deviceId: "my-whoop", priority: 0, hasData: true),
            DayOwnerResolver.Candidate(deviceId: "oura", priority: 2, hasData: true),
        ]
        XCTAssertEqual(
            DayOwnerResolver.resolve(day: "2026-06-15", lockedOwner: nil, candidates: candidates),
            "my-whoop"
        )
    }

    func testImportOnlyFillsGap() {
        let candidates = [
            DayOwnerResolver.Candidate(deviceId: "my-whoop", priority: 0, hasData: false),
            DayOwnerResolver.Candidate(deviceId: "oura", priority: 2, hasData: true),
        ]
        XCTAssertEqual(
            DayOwnerResolver.resolve(day: "2026-06-15", lockedOwner: nil, candidates: candidates),
            "oura"
        )
    }

    func testLockedOwnerAlwaysWins() {
        let candidates = [
            DayOwnerResolver.Candidate(deviceId: "my-whoop", priority: 0, hasData: false),
            DayOwnerResolver.Candidate(deviceId: "oura", priority: 2, hasData: true),
        ]
        XCTAssertEqual(
            DayOwnerResolver.resolve(day: "2026-06-15", lockedOwner: "my-whoop", candidates: candidates),
            "my-whoop"
        )
    }

    func testNoDataYieldsNil() {
        let candidates = [
            DayOwnerResolver.Candidate(deviceId: "my-whoop", priority: 0, hasData: false),
        ]
        XCTAssertNil(
            DayOwnerResolver.resolve(day: "2026-06-15", lockedOwner: nil, candidates: candidates)
        )
    }

    /// NROOP: two live WHOOP rows, the active one holding only stray lookback rows (Nov 2026 log:
    /// 34 223 rows from the previous days, none today) and the attributed strap holding today.
    func testMostCoveredLiveWhoopWins() {
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 34_223), ("my-whoop", 85_000)]), "my-whoop")
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 90_000), ("my-whoop", 85_000)]), "whoop-x")
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 7), ("my-whoop", 7)]), "whoop-x")
        XCTAssertNil(DayOwnerResolver.mostCovered([("whoop-x", 0), ("my-whoop", 0)]))
        XCTAssertNil(DayOwnerResolver.mostCovered([]))
    }
}

