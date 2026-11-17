import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class StressCadenceComparisonTests: XCTestCase {
    private let day = 1_728_000_000
    private var start: Int { day + 6 * 3_600 }
    private func hr(hours: Int = 4, spike: Bool = false) -> [HRSample] {
        (0..<(hours * 3_600)).map { HRSample(ts: start + $0, bpm: spike && $0 >= 3 * 3_600 + 1_800 && $0 < 3 * 3_600 + 2_100 ? 100 : 70) }
    }
    private func motion(hours: Int = 4) -> [GravitySample] {
        (0..<(hours * 3_600)).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
    }
    private func analyze(_ h: [HRSample], _ g: [GravitySample], now: Int? = nil, capped: Bool = false) -> StressCadenceComparison.Result {
        StressCadenceComparison.analyze(hr: h, gravity: g, dayStart: day,
            now: now ?? (start + 4 * 3_600), readCapped: capped)
    }
    func testDenseFlatDayHasFortyEightNonOverlappingBaselineWindows() {
        let r = analyze(hr(), motion())
        XCTAssertEqual(r.status, "compared")
        let scored = r.points.filter { $0.level != nil }
        XCTAssertEqual(scored.count, 48)
        XCTAssertTrue(scored.allSatisfy { $0.level == 1.5 && $0.end - $0.start == 300 })
        XCTAssertEqual(zip(scored, scored.dropFirst()).filter { $0.end > $1.start }.count, 0)
        XCTAssertEqual(r.candidateHighMinutes, 0)
    }
    func testFiveMinuteSpikeIsPreservedWithoutSmearingIntoAnHour() throws {
        let r = analyze(hr(spike: true), motion())
        let peak = try XCTUnwrap(r.points.first { $0.start == start + 3 * 3_600 + 1_800 })
        XCTAssertGreaterThan(try XCTUnwrap(peak.level), try XCTUnwrap(peak.originalLevel))
        XCTAssertEqual(r.candidateHighMinutes, 5)
        XCTAssertEqual(r.lines(day: "2024-10-04").first, "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=48 matched=48 referenceHours=4 referenceBpm=70.00 referenceSpread=1.08 candidateHighMin=5 candidateHighMatchedMin=5 originalHighMatchedMin=60 candidatePeak=3.00 originalPeakMatched=2.73 detail=last12 noAlerts=true")
        XCTAssertEqual(r.points.filter { ($0.level ?? 0) >= 2 }.count, 1)
        XCTAssertEqual(r.points.first { $0.start == peak.end }?.level, 1.5)
    }
    func testNoMotionIsUnavailableInsteadOfCalm() {
        let r = analyze(hr(), [])
        XCTAssertEqual(r.status, "no-motion")
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
    }
    func testRepeatedTimestampCannotInventFiveMinutesOfCoverage() {
        let h = hr().filter { $0.ts % 300 == 0 }.flatMap { Array(repeating: $0, count: 300) }
        let r = analyze(h, motion())
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
    }
    func testConflictingDuplicatesAreExcludedWithoutArbitrarySelection() {
        let clean = hr()
        let conflict = clean.filter { $0.ts < start + 300 }.map { HRSample(ts: $0.ts, bpm: 200) }
        let r = analyze(clean + conflict, motion())
        XCTAssertNil(r.points.first?.level)
        XCTAssertEqual(r.points.dropFirst().filter { $0.level != nil }.count, 47)
    }
    func testLongInternalGapFailsEvenWhenRawCountIsHighEnough() {
        let h = hr().filter { !($0.ts >= start + 120 && $0.ts < start + 150) }
        let r = analyze(h, motion())
        XCTAssertEqual(r.points.first?.status, "hr-coverage")
        XCTAssertNil(r.points.first?.level)
    }
    func testSparseMotionCannotProveNoExertion() {
        let g = motion().filter { $0.ts % 60 == 0 }
        let r = analyze(hr(), g)
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
        XCTAssertTrue(r.points.contains { $0.status == "motion-coverage" })
    }
    func testIncompleteAndFutureWindowsNeverScore() {
        let r = analyze(hr(), motion(), now: start + 3 * 3_600 + 299)
        XCTAssertEqual(r.points.last?.end, start + 3 * 3_600)
        XCTAssertEqual(r.points.filter { $0.level != nil }.count, 36)
    }
    func testInsufficientReferenceDoesNotInventAStableBaseline() {
        let r = analyze(hr(hours: 2), motion(hours: 2), now: start + 2 * 3_600)
        XCTAssertEqual(r.status, "insufficient-reference")
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
    }
    func testWalkingAndElevatedRecoveryAreMasked() {
        let h = hr().map { HRSample(ts: $0.ts, bpm: $0.ts >= start + 3_600 && $0.ts < start + 3 * 3_600 ? 100 : 70) }
        let g = motion().enumerated().map { i, s in
            GravitySample(ts: s.ts, x: i >= 3_600 && i < 7_200 && i % 2 == 0 ? 1 : 0, y: 0, z: 1)
        }
        let r = analyze(h, g)
        XCTAssertTrue(r.points.filter { $0.start >= start + 3_600 && $0.start < start + 3 * 3_600 }.allSatisfy { $0.level == nil })
        XCTAssertTrue(r.points.filter { $0.start >= start + 3 * 3_600 }.allSatisfy { $0.level != nil })
    }
    func testSameSecondCopiesAndOrderingDoNotChangeTheRead() {
        let clean = analyze(hr(spike: true), motion())
        let repeated = analyze(Array(hr(spike: true).flatMap { [$0, $0] }.reversed()), Array(motion().reversed()))
        XCTAssertEqual(clean.points, repeated.points)
        XCTAssertEqual(clean.candidateHighMinutes, repeated.candidateHighMinutes)
    }
    func testCappedReadNeverProducesCandidateValues() {
        let r = analyze(hr(), motion(), capped: true)
        XCTAssertEqual(r.status, "read-capped")
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
    }
    func testExistingHourlyScoresAreUnchangedByTheComparison() {
        let h = hr(spike: true), g = motion()
        let original = DaytimeStress.analyze(hr: h, rr: [], gravity: g, includeTimeline: true)
        _ = analyze(h, g)
        XCTAssertEqual(DaytimeStress.analyze(hr: h, rr: [], gravity: g, includeTimeline: true), original)
    }
    func testUnrepresentableGravityCannotTrapTheIncumbentFingerprint() {
        let invalid = motion().map { GravitySample(ts: $0.ts, x: 1e300, y: 0, z: 1) }
        let r = analyze(hr(), invalid)
        XCTAssertEqual(r.status, "no-motion")
        XCTAssertTrue(r.points.allSatisfy { $0.level == nil })
    }

    func testCoverageThresholdAcceptsDistributedMissingSecondsButRejectsTooFew() {
        let distributed = hr().filter { $0.ts % 5 != 0 }
        XCTAssertEqual(analyze(distributed, motion()).points.filter { $0.level != nil }.count, 48)
        let tooFew = distributed.filter { $0.ts % 300 != 1 }
        XCTAssertTrue(analyze(tooFew, motion()).points.allSatisfy { $0.level == nil })
    }
    func testConflictingGravityCannotProveStillness() {
        let g = motion()
        let conflict = g.filter { $0.ts < start + 300 }.map { GravitySample(ts: $0.ts, x: 1, y: 0, z: 1) }
        let r = analyze(hr(), g + conflict)
        XCTAssertEqual(r.points.first?.status, "motion-coverage")
        XCTAssertEqual(r.points.dropFirst().filter { $0.level != nil }.count, 47)
    }
    func testBriefWalkHasBoundedUnchainedRecoveryShadow() {
        let h = hr(hours: 5).map { HRSample(ts: $0.ts, bpm: $0.ts >= start + 10_800 ? 100 : 70) }
        let g = motion(hours: 5).enumerated().map { i, s in GravitySample(ts: s.ts,
            x: i >= 10_800 && i < 11_100 && i % 2 == 0 ? 1 : 0, y: 0, z: 1) }
        let r = analyze(h, g, now: start + 18_000)
        XCTAssertEqual(r.points.first { $0.start == start + 10_800 }?.status, "activity")
        XCTAssertEqual(r.points.first { $0.start == start + 14_400 }?.status, "post-activity")
        XCTAssertEqual(r.points.first { $0.start == start + 14_700 }?.status, "scored")
    }
    func testLocalGridSupportsHalfHourOffsetsWithoutChangingLevels() {
        let offset = 19_800
        let base = analyze(hr(spike: true), motion())
        let shifted = StressCadenceComparison.analyze(
            hr: hr(spike: true).map { HRSample(ts: $0.ts - offset, bpm: $0.bpm) },
            gravity: motion().map { GravitySample(ts: $0.ts - offset, x: $0.x, y: $0.y, z: $0.z) },
            dayStart: day - offset, now: start + 14_400 - offset, offset: offset)
        XCTAssertEqual(shifted.points.map(\.level), base.points.map(\.level))
        XCTAssertEqual(shifted.points.first?.start, start - offset)
        XCTAssertEqual(shifted.candidateHighMinutes, 5)
    }

}
