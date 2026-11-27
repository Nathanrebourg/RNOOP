import XCTest
@testable import Strand

/// NROOP: the always-on `sleep-detect today` diagnostic.
final class SleepDetectTodayLineTests: XCTestCase {
    func testGateSummaryKeepsCandidatesAndSkipsBridgeLines() {
        let lines = [
            "gate run=0 spanS=1320 DROPPED gate=minSleepMin spanMin=22",
            "gate run=1 spanS=24720 KEPT gate=accepted spanMin=412",
            "gate run=-1 spanS=0 DROPPED gate=hrConfirm x=1",
            "gate run=2 spanS=100 DROPPED gate=sparseBridge x=1",
        ]
        let s = IntelligenceEngine.sleepGateSummary(lines)
        XCTAssertEqual(s.cand, 2)
        XCTAssertEqual(s.text, "[run0:DROPPED:minSleepMin/22m, run1:KEPT:accepted/412m]")
    }

    func testLineStartsWithGrepPrefixAndShowsEveryId() {
        let line = IntelligenceEngine.sleepDetectTodayLine(
            day: "2026-11-27", owner: "my-whoop", windowFrom: 1_795_000_000, windowTo: 1_795_080_000, tzOffset: 3600,
            perId: [("my-whoop", 0, nil, nil), ("whoop-x", 12, 1_795_000_100, 1_795_000_200)],
            ownerHr: 0, grav: 0, gateLines: [], nightMinutes: nil)
        XCTAssertTrue(line.hasPrefix("sleep-detect today day=2026-11-27 owner=my-whoop "))
        XCTAssertTrue(line.contains("my-whoop hr=0;"))
        XCTAssertTrue(line.contains("whoop-x hr=12 first="))
        XCTAssertTrue(line.hasSuffix("cand=0 gates=[] night=none"))
    }
}
