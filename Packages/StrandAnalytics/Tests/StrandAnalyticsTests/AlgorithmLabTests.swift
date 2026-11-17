import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class AlgorithmLabTests: XCTestCase {
    let day = 1_728_000_000
    func hr(_ n: Int, start: Int = 0, bpm: Int = 70) -> [HRSample] {
        (0..<n).map { HRSample(ts: start + $0, bpm: bpm) }
    }
    func grav(_ n: Int, start: Int = 0) -> [GravitySample] {
        (0..<n).map { GravitySample(ts: start + $0, x: $0 % 2 == 0 ? 1 : 0, y: 0, z: 1) }
    }
    func testOneDenseHourCannotClaimAFullDaysCoverage() {
        let q = SampleQuality.analyze(hr(3_600), start: 0, end: 86_400)
        XCTAssertEqual(q.observedSeconds, 3_600)
        XCTAssertEqual(q.longestGap, 82_800)
        XCTAssertEqual(q.tier, "calibrating")
        XCTAssertLessThan(q.reliability, 0.05)
    }
    func testCompleteEvidenceIsSolidAndDuplicatesNeverAddTime() {
        let h = hr(3_600)
        let q = SampleQuality.analyze(h + h, start: 0, end: 3_600)
        XCTAssertEqual(q.observedSeconds, 3_600)
        XCTAssertEqual(q.coverage, 1)
        XCTAssertEqual(q.reliability, 1)
        XCTAssertEqual(q.tier, "solid")
        XCTAssertEqual(q.duplicates, 3_600)
        XCTAssertEqual(AlgorithmLab.qualityLine(SampleQuality.analyze(h,start: 0,end: 3600),day: "2024-10-04",original: "solid",hasScore: true),"lab quality experimental=true model=nroop-lab-v1 day=2024-10-04 scope=elapsed-day-1hz original=solid candidate=solid expectedSec=3600 observedSec=3600 coverage=1.00 longestGapSec=0 reliability=1.00 duplicates=0 ambiguous=0 invalid=0")
    }
    func testConflictsGapsAndInvalidRowsLowerEvidenceWithoutDeletingHighReadings() {
        let h = hr(600, bpm: 190) + [HRSample(ts: 100, bpm: 70), HRSample(ts: 601, bpm: 0)]
        let q = SampleQuality.analyze(h, start: 0, end: 1_200)
        XCTAssertEqual(q.observedSeconds, 599)
        XCTAssertEqual(q.ambiguous, 1)
        XCTAssertEqual(q.invalid, 1)
        XCTAssertEqual(q.longestGap, 600)
        XCTAssertEqual(q.tier, "building")
    }
    func testEmptyAndInvalidIntervalsHaveNoQuality() {
        XCTAssertEqual(SampleQuality.analyze([], start: 0, end: 600).reliability, 0)
        XCTAssertEqual(SampleQuality.analyze(hr(10), start: 10, end: 0).tier, "calibrating")
    }
    func testFullQualityRecoveryMatchesRealIncumbent() throws {
        let h = RecoveryScorer.DriverBaseline(mean: 60, spread: 10)
        let r = RecoveryScorer.DriverBaseline(mean: 55, spread: 5)
        let expected = RecoveryScorer.recovery(hrv: 45, rhr: 60, resp: nil, hrvBaseline: h,
            rhrBaseline: r, respBaseline: nil, sleepPerf: 0.9)
        let c = QualityRecovery.compare(hrv: 45, rhr: 60, hrvBaseline: h, rhrBaseline: r,
            sleepPerf: 0.9, quality: .init(hrv: 1, rhr: 1, sleep: 1))
        XCTAssertEqual(c.original, expected)
        XCTAssertEqual(try XCTUnwrap(c.candidate), try XCTUnwrap(expected), accuracy: 1e-12)
    }
    func testUnreliableEssentialRecoverySignalRefusesCandidate() {
        let b = RecoveryScorer.DriverBaseline(mean: 60, spread: 10)
        let c = QualityRecovery.compare(hrv: 45, rhr: 60, hrvBaseline: b, rhrBaseline: b,
            sleepPerf: 0.9, quality: .init(hrv: 0.1, rhr: 1, sleep: 1))
        XCTAssertNotNil(c.original)
        XCTAssertNil(c.candidate)
        XCTAssertEqual(c.status, "insufficient-essential-quality")
    }
    func testLowerSleepQualityReducesItsInfluenceRatherThanFabricatingSleep() throws {
        let b = RecoveryScorer.DriverBaseline(mean: 60, spread: 10)
        let full = QualityRecovery.compare(hrv: 60, rhr: 60, hrvBaseline: b, rhrBaseline: b,
            sleepPerf: 0.2, quality: .init(hrv: 1, rhr: 1, sleep: 1))
        let poor = QualityRecovery.compare(hrv: 60, rhr: 60, hrvBaseline: b, rhrBaseline: b,
            sleepPerf: 0.2, quality: .init(hrv: 1, rhr: 1, sleep: 0.2))
        XCTAssertGreaterThan(try XCTUnwrap(poor.candidate), try XCTUnwrap(full.candidate))
        XCTAssertEqual(poor.original, full.original)
    }
    func testInvalidQualityAndUnusableBaselineCannotScore() {
        let b = RecoveryScorer.DriverBaseline(mean: 60, spread: 10)
        XCTAssertNil(QualityRecovery.compare(hrv: 60, rhr: 60, hrvBaseline: b, rhrBaseline: b,
            quality: .init(hrv: .nan, rhr: 1, sleep: 1)).candidate)
        XCTAssertNil(QualityRecovery.compare(hrv: 60, rhr: 60, hrvBaseline: b, rhrBaseline: b,
            baselineUsable: false, quality: .init(hrv: 1, rhr: 1, sleep: 1)).candidate)
    }
    func testIsolatedHRPeakDoesNotBecomeConfirmedMaximum() {
        let h = hr(300, bpm: 160) + [HRSample(ts: 150, bpm: 230)]
        XCTAssertEqual(ConfirmedHRmax.dailyPeak(hr: h, gravity: grav(300)), 160)
        XCTAssertNil(ConfirmedHRmax.dailyPeak(hr: hr(10, bpm: 200), gravity: grav(10)))
    }
    func testMaximumNeedsThreeIndependentPriorDaysAndPreservesManualOverride() {
        let history = (1...3).map { ConfirmedHRmax.DayPeak(dayStart: day - $0 * 86_400, bpm: 200) }
        let learned = ConfirmedHRmax.estimate(history: history, before: day, age: 30)
        XCTAssertEqual(learned.candidate, 200)
        XCTAssertEqual(learned.source, "confirmed-history")
        XCTAssertEqual(ConfirmedHRmax.estimate(history: Array(history.prefix(2)), before: day, age: 30).candidate, 187)
        XCTAssertEqual(ConfirmedHRmax.estimate(history: history, before: day, age: 30, manual: 195).candidate, 195)
    }
    func testMaximumRejectsFutureConflictingAndUnconfirmedMotion() {
        XCTAssertNil(ConfirmedHRmax.dailyPeak(hr: hr(300, bpm: 200), gravity: []))
        let p = ConfirmedHRmax.DayPeak(dayStart: day, bpm: 240)
        XCTAssertEqual(ConfirmedHRmax.estimate(history: [p,p,p], before: day, age: 30).candidate, 187)
    }
    func testContextIsExplicitAndOnlyPriorIndependentNightsCount() {
        let unknown = (1...10).map { ContextualSleepNeed.Night(dayStart: day - $0 * 86_400, hours: 9) }
        XCTAssertNil(ContextualSleepNeed.estimate(nights: unknown, before: day, age: 30).candidateHours)
        let known = (1...7).map { ContextualSleepNeed.Night(dayStart: day - $0 * 86_400,
            hours: 9, naturalWake: true, rested: true, disrupted: false) }
        let result = ContextualSleepNeed.estimate(nights: known, before: day, age: 30)
        XCTAssertEqual(result.candidateHours, 9)
        XCTAssertEqual(result.eligibleNights, 7)
    }
    func testDisruptionFalseAndMissingContextAreNotInterchangeable() {
        let h = (1...7).map { ContextualSleepNeed.Night(dayStart: day - $0 * 86_400,
            hours: 9, naturalWake: true, rested: true, disrupted: true) }
        XCTAssertNil(ContextualSleepNeed.estimate(nights: h, before: day, age: 30).candidateHours)
        let future = ContextualSleepNeed.Night(dayStart: day, hours: 12, naturalWake: true, rested: true, disrupted: false)
        XCTAssertNil(ContextualSleepNeed.estimate(nights: Array(repeating: future, count: 7), before: day, age: 30).candidateHours)
    }
    func testThreeTinyRRBurstsCannotClaimWholeNightQuality() {
        let s = SleepSession(start: 0, end: 28_800, efficiency: 1,
            stages: [StageSegment(start: 0, end: 28_800, stage: "light")], restingHR: 60, avgHRV: 30)
        let rr = [0,600,1200].flatMap { start in (0..<20).map { RRInterval(ts: start + $0, rrMs: 1000) } }
        let q = AlgorithmLab.recoveryEvidence(sessions: [s], hr: hr(28_800), rr: rr, deepWindow: false)
        XCTAssertLessThan(q.hrv, 0.01)
    }
    func testDeepOnlyEvidenceUsesDeepDurationInsteadOfWholeNight() {
        let s = SleepSession(start: 0, end: 3_600, efficiency: 1,
            stages: [StageSegment(start: 0, end: 900, stage: "deep"),StageSegment(start: 900,end: 3600,stage: "light")], restingHR: 60, avgHRV: 30)
        let rr = (0..<900).map { RRInterval(ts: $0, rrMs: 1000) }
        let q = AlgorithmLab.recoveryEvidence(sessions: [s], hr: hr(3600), rr: rr, deepWindow: true)
        XCTAssertEqual(q.hrv, 1, accuracy: 0.01)
    }
    func testIncumbentMaximumReportUsesProfileAgeAndManualOverride() {
        XCTAssertEqual(AlgorithmLab.incumbentMaximum(age: 60, manual: nil),166)
        XCTAssertEqual(AlgorithmLab.incumbentMaximum(age: 0, manual: nil),190)
        XCTAssertNil(ConfirmedHRmax.estimate(history: [],before: day,age: 0).candidate)
        XCTAssertEqual(AlgorithmLab.incumbentMaximum(age: 60, manual: 180),180)
    }

    func testUniqueBriefSpikeIsRejectedButSustainedMaximumSurvives() {
        let spike = hr(300,bpm: 160).map { HRSample(ts: $0.ts,bpm: $0.ts == 150 ? 230 : $0.bpm) }
        XCTAssertEqual(ConfirmedHRmax.dailyPeak(hr: spike,gravity: grav(300)),160)
        XCTAssertEqual(ConfirmedHRmax.dailyPeak(hr: hr(300,bpm: 200),gravity: grav(300)),200)
    }
    func testFullQualityWithAllOptionalTermsMatchesTheRealScorer() {
        let b = RecoveryScorer.DriverBaseline(mean: 60,spread: 10)
        let r = RecoveryScorer.DriverBaseline(mean: 55,spread: 5)
        let p = RecoveryScorer.DriverBaseline(mean: 14,spread: 1)
        let c = QualityRecovery.compare(hrv: 45,rhr: 60,resp: 15,hrvBaseline: b,rhrBaseline: r,
            respBaseline: p,sleepPerf: 0.8,skinTempDev: 0.3,quality: .init(hrv: 1,rhr: 1,sleep: 1,resp: 1,skin: 1))
        XCTAssertEqual(c.candidate,c.original)
    }
    func testConflictingHistoryCannotManufactureAnEligibleContextOrMaximum() {
        var h = (1...7).map { ContextualSleepNeed.Night(dayStart: day - $0 * 86400,hours: 9,naturalWake: true,rested: true,disrupted: false) }
        h.append(.init(dayStart: day - 86400,hours: 5,naturalWake: true,rested: true,disrupted: false))
        XCTAssertEqual(ContextualSleepNeed.estimate(nights: h,before: day,age: 30).eligibleNights,6)
        XCTAssertNil(ContextualSleepNeed.estimate(nights: h,before: day,age: 30).candidateHours)
        let p = [ConfirmedHRmax.DayPeak(dayStart: day - 86400,bpm: 200),.init(dayStart: day - 86400,bpm: 220)]
        XCTAssertEqual(ConfirmedHRmax.estimate(history: p,before: day,age: 30).confirmedDays,0)
    }
    func testProvidedOrEditedSleepCannotReuseDetectorQuality() {
        let session = SleepSession(start: 0,end: 900,efficiency: 1,stages: [StageSegment(start: 0,end: 900,stage: "light")],restingHR: 60,avgHRV: 40)
        let rr = (0..<900).map { RRInterval(ts: $0,rrMs: 1000) }
        let q = AlgorithmLab.recoveryEvidence(sessions: [session],hr: hr(900),rr: rr,deepWindow: false,detectedOnly: false)
        XCTAssertEqual(q.hrv,0)
        let daily = AnalyticsEngine.analyzeDay(day: "2024-10-04",profile: .init()).daily
        let r = AlgorithmLab.recoveryComparison(daily: daily,baselines: .init(),quality: .init(hrv: 1,rhr: 1,sleep: 1),evidenceStillMatches: false)
        XCTAssertNil(r.candidate); XCTAssertEqual(r.status,"edited-sleep")
    }
    func testFreshAndCachedDiagnosticsRespectTheirActualModes() {
        let lines = ["lab quality experimental=true", "lab recovery experimental=true", "lab sleepneed experimental=true", "ordinary"]
        for _ in 0..<2 {
            var regular: [String] = [], work: [String] = [], recovery: [String] = [], sleep: [String] = []
            for line in lines { AlgorithmLab.replayDiagnostic(line,regularSink: { regular.append($0) },workoutSink: { work.append($0) },
                recoverySink: { recovery.append($0) },sleepSink: { sleep.append($0) }) }
            XCTAssertEqual(regular,["ordinary"]);XCTAssertEqual(work,[lines[0]]);XCTAssertEqual(recovery,[lines[1]]);XCTAssertEqual(sleep,[lines[2]])
            regular=[]
            for line in lines { AlgorithmLab.replayDiagnostic(line,regularSink: { regular.append($0) },workoutSink: nil) }
            XCTAssertEqual(regular,["ordinary"])
        }
    }

    func testComputedZeroHRVRemainsAValueInsteadOfMissingData() {
        let h=RecoveryScorer.DriverBaseline(mean:60,spread:10),r=RecoveryScorer.DriverBaseline(mean:55,spread:5)
        let expected=RecoveryScorer.recovery(hrv:0,rhr:60,resp:nil,hrvBaseline:h,rhrBaseline:r,respBaseline:nil,sleepPerf:0.8)
        let observed=QualityRecovery.compare(hrv:0,rhr:60,hrvBaseline:h,rhrBaseline:r,sleepPerf:0.8,quality:.init(hrv:1,rhr:1,sleep:1))
        XCTAssertNotNil(expected);XCTAssertEqual(observed.original,expected);XCTAssertEqual(observed.candidate,expected)
        XCTAssertEqual(AlgorithmLab.recoveryLine(observed,q:.init(hrv:1,rhr:1,sleep:1),day:"2024-10-04"),"lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=0.85 candidate=0.85 status=compared qHrv=1.00 qRhr=1.00 qSleep=1.00 qResp=0.00 qSkin=0.00")
    }

}
