import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class EffortCadenceComparisonTests: XCTestCase {
    private func series(_ count: Int, start: Int = 0, step: Int = 1, bpm: Int = 170) -> [HRSample] {
        (0..<count).map { HRSample(ts: start + $0 * step, bpm: bpm) }
    }

    func testRegularCadencesKeepTheIncumbentCalculation() {
        for (count, step) in [(601, 1), (61, 10), (21, 30), (21, 60)] {
            let hr = series(count, step: step)
            let r = EffortCadenceComparison.analyze(hr, maxHR: 190)
            XCTAssertEqual(r.durationsSeconds, Array(repeating: Double(step), count: count))
            XCTAssertEqual(r.candidateScore, StrainScorer.strain(hr, maxHR: 190))
            XCTAssertEqual(r.gapsClipped, 0)
        }
    }

    func testDenseDropoutCannotCreditTwoMinutesOfHardEffort() {
        let hr = series(300) + series(301, start: 3_600)
        let r = EffortCadenceComparison.analyze(hr, maxHR: 190)
        XCTAssertEqual(r.durationsSeconds[299], 2)
        XCTAssertEqual(r.supportedSeconds, 601, accuracy: 1e-9)
        XCTAssertEqual(r.creditedSeconds, 602, accuracy: 1e-9)
        XCTAssertEqual(r.unsupportedSeconds, 3_299, accuracy: 1e-9)
        XCTAssertEqual(r.gapsClipped, 1)
        XCTAssertLessThan(r.candidateScore ?? 100, StrainScorer.strain(hr, maxHR: 190) ?? 0)
    }

    func testSparseDropoutUsesTheLocalThirtySecondCadence() {
        let r = EffortCadenceComparison.analyze(series(21, step: 30) + series(21, start: 3_600, step: 30), maxHR: 190)
        XCTAssertEqual(r.durationsSeconds[20], 60)
        XCTAssertEqual(r.durationsSeconds.last, 30)
        XCTAssertEqual(r.gapsClipped, 1)
        XCTAssertNotNil(r.candidateScore)
    }

    func testCadenceChangeDoesNotEraseTheFollowingSparseBlock() {
        let hr = series(10) + series(21, start: 39, step: 30)
        let r = EffortCadenceComparison.analyze(hr, maxHR: 190)
        XCTAssertEqual(r.durationsSeconds[9], 30)
        XCTAssertEqual(r.durationsSeconds.last, 30)
        XCTAssertEqual(r.gapsClipped, 0)
        XCTAssertEqual(r.candidateScore, StrainScorer.strain(hr, maxHR: 190))
    }

    func testWallClockSpanAloneDoesNotQualifyDisconnectedReadings() {
        let hr = series(20, step: 3_600)
        XCTAssertNotNil(StrainScorer.strain(hr, maxHR: 190))
        let r = EffortCadenceComparison.analyze(hr, maxHR: 190)
        XCTAssertNil(r.candidateScore)
        XCTAssertEqual(r.supportedSeconds, 0)
        XCTAssertEqual(r.creditedSeconds, 0)
    }

    func testTailDoesNotRepeatTheLastDropoutDuration() {
        let r = EffortCadenceComparison.analyze(series(601) + [HRSample(ts: 3_600, bpm: 170)], maxHR: 190)
        XCTAssertEqual(r.durationsSeconds.suffix(2), [2, 1])
        XCTAssertEqual(r.supportedSeconds, 602, accuracy: 1e-9)
    }

    func testDuplicateDeliveriesCannotInventExtraTime() {
        let clean = series(601)
        let r = EffortCadenceComparison.analyze(clean.flatMap { [$0, $0, $0] }, maxHR: 190)
        XCTAssertEqual(r.duplicatesRemoved, 1_202)
        XCTAssertEqual(r.uniqueReadings, 601)
        XCTAssertEqual(r.candidateScore, EffortCadenceComparison.analyze(clean, maxHR: 190).candidateScore)
    }

    func testConflictingTimestampIsExcludedWithoutChoosingAHeartRate() {
        let hr = series(601) + [HRSample(ts: 300, bpm: 180)]
        let r = EffortCadenceComparison.analyze(hr, maxHR: 190)
        XCTAssertEqual(r.ambiguousTimestamps, 1)
        XCTAssertEqual(r.uniqueReadings, 600)
        XCTAssertEqual(r.supportedSeconds, 600, accuracy: 1e-9)
    }

    func testSortingAndInvalidReadingsDoNotChangeCleanEvidence() {
        let r = EffortCadenceComparison.analyze(Array(series(601).reversed()) + [HRSample(ts: 90, bpm: 0)], maxHR: 190)
        XCTAssertEqual(r.invalidReadings, 1)
        XCTAssertEqual(r.candidateScore, EffortCadenceComparison.analyze(series(601), maxHR: 190).candidateScore)
    }

    func testRealSustainedAndIsolatedHighReadingsAreNotSmoothedAway() {
        let sustained = EffortCadenceComparison.analyze(series(301, bpm: 80) + series(300, start: 301), maxHR: 190)
        XCTAssertEqual(sustained.candidateTRIMP ?? -1, 20, accuracy: 1e-9)
        var isolated = series(601, bpm: 80)
        isolated[300] = HRSample(ts: 300, bpm: 170)
        XCTAssertEqual(EffortCadenceComparison.analyze(isolated, maxHR: 190).candidateTRIMP ?? -1, 1.0 / 15.0, accuracy: 1e-9)
    }

    func testBanisterMethodAndSexCalibrationArePreserved() {
        for sex in ["male", "female"] {
            let hr = series(601)
            let r = EffortCadenceComparison.analyze(hr, maxHR: 190, method: .banister, sex: sex)
            XCTAssertEqual(r.candidateScore, StrainScorer.strain(hr, maxHR: 190, method: .banister, sex: sex))
        }
    }

    func testInsufficientEvidenceAndInvalidConfigurationStayUnscored() {
        XCTAssertNil(EffortCadenceComparison.analyze([], maxHR: 190).candidateScore)
        XCTAssertNil(EffortCadenceComparison.analyze(series(20, step: 30), maxHR: 190).candidateScore)
        XCTAssertNil(EffortCadenceComparison.analyze(series(601), maxHR: 60).candidateScore)
        XCTAssertNil(EffortCadenceComparison.analyze(series(601), maxHR: .nan).candidateScore)
        XCTAssertNil(EffortCadenceComparison.analyze(series(601), maxHR: 190, denominator: 1).candidateScore)
    }

    func testEnabledComparisonDoesNotChangeStoredDayValues() {
        let day = "2026-11-14"
        let start = AnalyticsEngine.dayStartUtcSeconds(day)
        let hr = series(300, start: start) + series(301, start: start + 3_600)
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")
        let normal = AnalyticsEngine.analyzeDay(day: day, dayHr: hr, profile: profile, maxHROverride: 190)
        var lines: [String] = []
        let diagnostic = AnalyticsEngine.analyzeDay(day: day, dayHr: hr, profile: profile,
            maxHROverride: 190, effortCadenceSink: { lines.append($0) })
        XCTAssertNotNil(normal.strain)
        XCTAssertEqual(normal.daily, diagnostic.daily)
        XCTAssertEqual(normal.strain, diagnostic.strain)
        XCTAssertEqual(normal.recovery, diagnostic.recovery)
        let comparisons = lines.filter { $0.hasPrefix("effort cadence experimental=true") }
        XCTAssertEqual(comparisons.count, 1)
        XCTAssertTrue(comparisons.first?.contains("supportedSec=601.00") == true)
        XCTAssertTrue(comparisons.first?.contains("scope=day day=2026-11-14") == true)
    }

    func testEnablingComparisonInvalidatesAnUnchangedCachedDayOnlyOnce() {
        func key(_ active: Bool) -> String {
            AnalyzeRecentDayCache.cacheKey(owner: "whoop5", hrCount: 601, hrMaxTs: 3_900,
                skinAnchorRaw: nil, streams: "unchanged|rrAlias5=true", hrvWindowDetail: false,
                effortCadenceTrace: active)
        }
        let off = key(false)
        let on = key(true)
        XCTAssertNotEqual(off, on, "a day cached without the comparison must be analyzed when enabled")
        XCTAssertEqual(on, key(true), "subsequent analyses can reuse the recorded comparison")
        XCTAssertEqual(off, key(false))
        XCTAssertEqual(AnalyzeRecentDayCache.missReason(cachedKey: off, freshKey: on), "effortTrace")
    }

    func testFreshAndCachedComparisonsUseTheSameChannelAndStopWhenDisabled() {
        let line = EffortCadenceComparison.analyze(series(601), maxHR: 190).trace(original: 41.83)
        let stored = [line, "effort score day=2026-11-14"]
        var ordinary: [String] = [], comparison: [String] = []
        for _ in 0..<2 { // first analysis, then a replay of the cached diagnostic snapshot
            ordinary.removeAll(); comparison.removeAll()
            for item in stored {
                EffortCadenceComparison.replayDiagnostic(item, regularSink: { ordinary.append($0) },
                    comparisonSink: { comparison.append($0) })
            }
            XCTAssertEqual(comparison, [line])
            XCTAssertEqual(ordinary, ["effort score day=2026-11-14"])
        }
        ordinary.removeAll()
        for item in stored {
            EffortCadenceComparison.replayDiagnostic(item, regularSink: { ordinary.append($0) }, comparisonSink: nil)
        }
        XCTAssertEqual(ordinary, ["effort score day=2026-11-14"], "a stale comparison must not leak to the ordinary channel")
    }
}
