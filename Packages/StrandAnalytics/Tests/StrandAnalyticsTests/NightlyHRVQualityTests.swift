import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class NightlyHRVQualityTests: XCTestCase {
    private func beats(_ count: Int, start: Int = 0, step: Int = 1, halfSwing: Int = 20) -> [RRInterval] {
        (0..<count).map { RRInterval(ts: start + $0 * step, rrMs: 1_000 + ($0 % 2 == 0 ? -halfSwing : halfSwing)) }
    }

    func testDenseCleanWindowsKeepTheMeasuredRMSSD() {
        let result = NightlyHRVQuality.analyze(start: 0, end: 600, rr: beats(600))
        XCTAssertEqual(result.weightedRMSSD ?? -1, 40, accuracy: 1e-9)
        XCTAssertEqual(result.coverage, 1, accuracy: 1e-9)
        XCTAssertEqual(result.usableWindows, 2)
    }

    func testSparseHighWindowCannotHaveTheSameWeightAsFiveMinutesOfCleanBeats() {
        let rr = beats(300) + beats(20, start: 300, halfSwing: 50)
        // Independent arithmetic: (40 * 300 + 100 * 20) / 320 = 43.75, versus the old mean 70.
        XCTAssertEqual(SleepStager.sessionAvgHRV(start: 0, end: 600, rr: rr) ?? -1, 70, accuracy: 1e-9)
        let result = NightlyHRVQuality.analyze(start: 0, end: 600, rr: rr)
        XCTAssertEqual(result.weightedRMSSD ?? -1, 43.75, accuracy: 1e-9)
        XCTAssertEqual(result.coverage, 8.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(result.totalWindows, 2)
    }

    func testShortFinalWindowIsWeightedByEvidenceDuration() {
        let result = NightlyHRVQuality.analyze(start: 0, end: 320,
            rr: beats(300) + beats(20, start: 300, halfSwing: 50))
        XCTAssertEqual(result.weightedRMSSD ?? -1, 43.75, accuracy: 1e-9)
        XCTAssertEqual(result.coverage, 1, accuracy: 1e-9)
    }

    func testLongTimestampGapsDoNotBecomeSuccessiveHeartbeats() {
        let result = NightlyHRVQuality.analyze(start: 0, end: 300, rr: beats(20, step: 15))
        XCTAssertNil(result.weightedRMSSD)
        XCTAssertEqual(result.longGaps, 19)
        XCTAssertEqual(result.usablePairs, 0)
    }

    func testDroppedBeatIsNotSplicedBackIntoTheRMSSD() {
        var rr = beats(30)
        rr[10] = RRInterval(ts: 10, rrMs: 0)
        let result = NightlyHRVQuality.analyze(start: 0, end: 300, rr: rr)
        XCTAssertEqual(result.weightedRMSSD ?? -1, 40, accuracy: 1e-9)
        XCTAssertEqual(result.rejectedBeats, 1)
        XCTAssertEqual(result.usablePairs, 27)
    }

    func testRejectionAndBrokenAdjacencyReduceRelativeWindowWeight() {
        var second = beats(300, start: 300, halfSwing: 50)
        for i in stride(from: 0, to: 300, by: 10) { second[i] = RRInterval(ts: 300 + i, rrMs: 0) }
        let result = NightlyHRVQuality.analyze(start: 0, end: 600, rr: beats(300) + second)
        // Second window: 270 retained beats, 271.5 beat-seconds, 240 adjacent pairs.
        // Its weight is 271.5 * 0.9 * 240/269. Combining 40ms and 100ms gives 189425/2903 ms.
        XCTAssertEqual(result.weightedRMSSD ?? -1, 65.25146400275577, accuracy: 1e-9)
        XCTAssertEqual(result.rejectedBeats, 30)
        XCTAssertEqual(result.usablePairs, 539)
        XCTAssertEqual(result.usableWindows, 2)
    }

    func testOverCountedNightCannotBeResurrectedByTheExperimentalEstimator() {
        let rr = (0..<300).flatMap { i in
            [RRInterval(ts: i, rrMs: 980), RRInterval(ts: i, rrMs: 1_020)]
        }
        let result = NightlyHRVQuality.analyze(start: 0, end: 600, rr: rr)
        XCTAssertNil(result.weightedRMSSD)
        XCTAssertTrue(result.overCounted)
    }

    func testLocalOverCountIsDetectedEvenWhenTheRestOfTheNightIsEmpty() {
        let rr = (0..<150).flatMap { i in
            [RRInterval(ts: i, rrMs: 980), RRInterval(ts: i, rrMs: 1_020)]
        } + beats(20, start: 900)
        let result = NightlyHRVQuality.analyze(start: 0, end: 1_200, rr: rr)
        // The whole span is under-covered; the duplicated first window is still unusable.
        XCTAssertFalse(result.overCounted)
        XCTAssertEqual(result.usableWindows, 1)
        XCTAssertEqual(result.weightedRMSSD ?? -1, 40, accuracy: 1e-9)
    }

    func testUnorderedInputIsStablySortedAndOutsideSamplesAreExcluded() {
        let rr = Array(beats(300).reversed()) + [RRInterval(ts: -1, rrMs: 1_900), RRInterval(ts: 301, rrMs: 1_900)]
        let result = NightlyHRVQuality.analyze(start: 0, end: 300, rr: rr)
        XCTAssertEqual(result.weightedRMSSD ?? -1, 40, accuracy: 1e-9)
        XCTAssertEqual(result.inputBeats, 300)
    }

    func testMissingAndInvalidSessionsHaveNoCandidate() {
        for (start, end) in [(0, 0), (10, 0), (0, 200_000)] {
            XCTAssertNil(NightlyHRVQuality.analyze(start: start, end: end, rr: beats(30)).weightedRMSSD)
        }
        let empty = NightlyHRVQuality.analyze(start: 0, end: 600, rr: [])
        XCTAssertNil(empty.weightedRMSSD)
        XCTAssertEqual(empty.coverage, 0)
        XCTAssertEqual(empty.usableWindows, 0)
    }

    func testSameSecondOrderSurvivesStableSorting() {
        let rr = (0..<300).flatMap { i in
            [RRInterval(ts: i, rrMs: 490), RRInterval(ts: i, rrMs: 510)]
        }
        let result = NightlyHRVQuality.analyze(start: 0, end: 300, rr: rr)
        XCTAssertEqual(result.weightedRMSSD ?? -1, 20, accuracy: 1e-9)
        XCTAssertFalse(result.overCounted)
    }

    func testEnabledTraceReportsCandidateWithoutChangingStoredDailyScores() {
        let day = "2026-07-27"
        let start = AnalyticsEngine.dayStartUtcSeconds(day) + 3_600
        let end = start + 3_600
        let rr = beats(300, start: start) + beats(20, start: start + 300, halfSwing: 50)
        let session = SleepSession(start: start, end: end, efficiency: 1,
            stages: [StageSegment(start: start, end: end, stage: "light")], restingHR: 52, avgHRV: nil)
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")
        let normal = AnalyticsEngine.analyzeDay(day: day, rr: rr, profile: profile, providedSleep: [session])
        var trace: [String] = []
        let diagnostic = AnalyticsEngine.analyzeDay(day: day, rr: rr, profile: profile,
            providedSleep: [session], hrvTraceSink: { trace.append($0) })
        XCTAssertEqual(normal.daily.avgHrv ?? -1, 70, accuracy: 1e-9)
        XCTAssertEqual(normal.daily, diagnostic.daily)
        XCTAssertEqual(normal.recovery, diagnostic.recovery)
        let comparison = trace.filter { $0.contains("hrv quality experimental=true") }
        XCTAssertEqual(comparison.count, 1)
        XCTAssertTrue(comparison.first?.contains("original=70.00ms candidate=43.75ms") == true)
    }
}
