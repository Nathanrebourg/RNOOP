import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepBaselineComparisonTests: XCTestCase {
    private let day = 1_728_000_000 // UTC midnight
    private func rows(_ w: SleepBaselineComparison.Window, bpm: Int = 55, step: Int = 60) -> [HRSample] {
        stride(from: w.start, to: w.end, by: step).map { HRSample(ts: $0, bpm: bpm) }
    }
    private func history(before: Int, bpm: Int = 55) -> [SleepBaselineComparison.Observation] {
        SleepBaselineComparison.historyWindows(before: before, offset: 0).prefix(3).compactMap {
            SleepBaselineComparison.observation(rows($0, bpm: bpm), window: $0)
        }
    }
    func testHistoryWindowsArePriorDisjointLocalMidnightToSix() {
        for offset in [0, 19_800, -18_000] {
            let w = SleepBaselineComparison.historyWindows(before: day, offset: offset)
            XCTAssertEqual(w.count, 14)
            XCTAssertTrue(w.allSatisfy { $0.end <= day && $0.end - $0.start == 21_600 })
            XCTAssertTrue(w.allSatisfy { ($0.start + offset) % 86_400 == 0 })
            XCTAssertEqual(w[0].start - w[1].start, 86_400)
        }
    }
    func testNightWeightsMinutesRatherThanDeliveryDensity() throws {
        let w = SleepBaselineComparison.historyWindows(before: day, offset: 0)[0]
        let sparse = rows(w, bpm: 50)
        let denseHighFirstHour = (0..<3_600).map { HRSample(ts: w.start + $0, bpm: 100) }
        let r = try XCTUnwrap(SleepBaselineComparison.observation(sparse.filter { $0.ts >= w.start + 3_600 } + denseHighFirstHour, window: w))
        XCTAssertEqual(r.medianBPM, 50)
        XCTAssertEqual(r.minutes, 360)
    }
    func testDuplicatesAndOutsideRowsCannotCreateCoverage() {
        let w = SleepBaselineComparison.historyWindows(before: day, offset: 0)[0]
        let brief = Array(rows(w).prefix(60))
        XCTAssertNil(SleepBaselineComparison.observation(Array(repeating: brief, count: 10).flatMap { $0 } + [HRSample(ts: w.end, bpm: 55)], window: w))
        let invalid = rows(w, bpm: 0)
        XCTAssertNil(SleepBaselineComparison.observation(invalid, window: w))
    }
    func testConflictingTimestampIsExcludedAndCoverageIsRequired() {
        let w = SleepBaselineComparison.historyWindows(before: day, offset: 0)[0]
        let clean = rows(w)
        let conflict = clean.map { HRSample(ts: $0.ts, bpm: 100) }
        XCTAssertNil(SleepBaselineComparison.observation(clean + conflict, window: w))
        XCTAssertNil(SleepBaselineComparison.observation(Array(clean.prefix(180)), window: w)) // only three hours
        XCTAssertEqual(SleepBaselineComparison.observation(clean + clean, window: w)?.minutes, 360)
    }
    func testReferenceNeedsThreeDistinctPriorNightsAndRejectsStaleOrFuture() {
        let h = history(before: day)
        XCTAssertNil(SleepBaselineComparison.reference(history: Array(h.prefix(2)), before: day, offset: 0).bpm)
        XCTAssertNil(SleepBaselineComparison.reference(history: Array(repeating: h[0], count: 3), before: day, offset: 0).bpm)
        let invalid = [SleepBaselineComparison.Observation(end: day + 1, medianBPM: 200, minutes: 360),
                       SleepBaselineComparison.Observation(end: day - 30 * 86_400, medianBPM: 200, minutes: 360)]
        let r = SleepBaselineComparison.reference(history: h + invalid, before: day, offset: 0)
        XCTAssertEqual(r.bpm, 55)
        XCTAssertEqual(r.nights, 3)
    }
    func testMedianOfNightsIsRobustAndKeepsExistingFloor() {
        let h = history(before: day)
        let values = zip(h, [30.0, 35.0, 190.0]).map { SleepBaselineComparison.Observation(end: $0.0.end, medianBPM: $0.1, minutes: 360) }
        XCTAssertEqual(SleepBaselineComparison.reference(history: values, before: day, offset: 0).bpm, 40)
    }
    func testInsufficientHistoryDoesNotInventAZeroCandidate() {
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: day - 108_000, history: [], hr: [], gravity: [])
        XCTAssertNil(r.candidate)
        XCTAssertNil(r.original)
        XCTAssertTrue(r.trace(day: "2024-10-04").contains("status=insufficient-history"))
    }
    func testRealDetectorUsesPersonalReferenceWithoutChangingOriginal() throws {
        let before = day - 108_000
        let start = day + 3_600
        let hr = (0..<5_400).map { HRSample(ts: start + $0, bpm: 65) }
        // Sparse stable posture permits detection but cannot prove the dense-motion relaxed HR band.
        let grav = stride(from: 0, to: 5_400, by: 60).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let original = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertFalse(original.isEmpty)
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: before, history: history(before: before, bpm: 50), hr: hr, gravity: grav)
        XCTAssertEqual(r.original, original)
        XCTAssertEqual(r.candidate, []) // 65 > personal strict band 50 × 1.05
        XCTAssertEqual(r.trace(day: "2024-10-04"), "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=50.00 originalSessions=1 candidateSessions=0 originalInBedSec=5340 candidateInBedSec=0 originalAsleepSec=0 candidateAsleepSec=0 originalWindows=1728003600:1728008940 candidateWindows=none")
        XCTAssertEqual(SleepStager.detectSleep(hr: hr, gravity: grav), original)
    }
    func testLowRateNightAndDenseStillnessArePreserved() throws {
        let before = day - 108_000, start = day + 3_600
        let hr = (0..<5_400).map { HRSample(ts: start + $0, bpm: 50) }
        let grav = (0..<5_400).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: before, history: history(before: before), hr: hr, gravity: grav, useSleepStagerV2: true)
        XCTAssertFalse(try XCTUnwrap(r.candidate).isEmpty)
        XCTAssertEqual(r.original, r.candidate)
    }
    func testExplicitOffWristStillRejectsBothVariants() {
        let before = day - 108_000, start = day + 3_600
        let hr = (0..<5_400).map { HRSample(ts: start + $0, bpm: 50) }
        let grav = (0..<5_400).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: before, history: history(before: before), hr: hr, gravity: grav, wristOff: [(start, start + 5_400)])
        XCTAssertEqual(r.original, [])
        XCTAssertEqual(r.candidate, [])
    }
    func testQualifiedHistoryWithMissingMotionIsExplicitlySkipped() {
        let before = day - 108_000
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: before,
            history: history(before: before), hr: [], gravity: [])
        XCTAssertEqual(r.status, "no-motion")
        XCTAssertEqual(r.reference.bpm, 55)
        XCTAssertNil(r.candidate)
    }
    func testCappedReadCannotProduceAComparison() {
        let before = day - 108_000
        let r = SleepBaselineComparison.compare(dayStart: day, readStart: before,
            history: history(before: before), hr: [], gravity: [], readCapped: true)
        XCTAssertEqual(r.status, "target-read-capped")
        XCTAssertNil(r.candidate)
    }
    func testConflictingHistoryCopiesCannotChooseAnArbitraryBaseline() {
        let h = history(before: day)
        let conflict = SleepBaselineComparison.Observation(end: h[0].end, medianBPM: 90, minutes: 360)
        let r = SleepBaselineComparison.reference(history: h + [conflict], before: day, offset: 0)
        XCTAssertEqual(r.nights, 2)
        XCTAssertNil(r.bpm)
    }
    func testComparisonCannotContaminateDailyScoringThroughMemoization() {
        let before = day - 108_000, start = day + 3_600
        let hr = (0..<5_400).map { HRSample(ts: start + $0, bpm: 65) }
        let grav = stride(from: 0, to: 5_400, by: 60).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let profile = UserProfile(weightKg: 75, heightCm: 180, age: 30, sex: "male")
        let normal = AnalyticsEngine.analyzeDay(day: "2024-10-04", hr: hr, gravity: grav, profile: profile)
        let candidate = SleepBaselineComparison.compare(dayStart: day, readStart: before,
            history: history(before: before, bpm: 50), hr: hr, gravity: grav)
        XCTAssertEqual(candidate.candidate, [])
        let after = AnalyticsEngine.analyzeDay(day: "2024-10-04", hr: hr, gravity: grav, profile: profile)
        XCTAssertEqual(normal.daily, after.daily)
        XCTAssertEqual(normal.sleepSessions, after.sleepSessions)
        XCTAssertEqual(normal.restScore, after.restScore)
        XCTAssertEqual(normal.recovery, after.recovery)
    }

}
