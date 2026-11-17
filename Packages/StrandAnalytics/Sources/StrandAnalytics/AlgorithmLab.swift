import Foundation
import WhoopProtocol
import WhoopStore

/// Shared report/routing contract for default-off candidate methods; no score-writing API.
public enum AlgorithmLab {
    public static func incumbentMaximum(age: Double, manual: Double?) -> Double { manual ?? (age > 0 ? StrainScorer.tanakaHRmax(age: age) : Double(StrainScorer.defaultMaxHR())) }
    public static func number(_ v: Double?) -> String {
        guard let v, v.isFinite, abs(v) < 1_000_000_000 else { return "nil" }
        let n = Int((abs(v) * 100).rounded()), f = n % 100
        return "\(v < 0 ? "-" : "")\(n / 100).\(f < 10 ? "0" : "")\(f)"
    }
    public static func qualityLine(_ q: SampleQuality.Evidence, day: String, original: String, hasScore: Bool) -> String {
        "lab quality experimental=true model=nroop-lab-v1 day=\(day) scope=elapsed-day-1hz original=\(original) candidate=\(hasScore ? q.tier : "calibrating") "
            + "expectedSec=\(q.expectedSeconds) observedSec=\(q.observedSeconds) coverage=\(number(q.coverage)) longestGapSec=\(q.longestGap) "
            + "reliability=\(number(q.reliability)) duplicates=\(q.duplicates) ambiguous=\(q.ambiguous) invalid=\(q.invalid)"
    }
    public static func maximumLine(_ e: ConfirmedHRmax.Estimate, day: String, original: Double?, readErrors: Int = 0, cappedDays: Int = 0) -> String {
        "lab maxhr experimental=true model=nroop-lab-v1 day=\(day) scope=calibration-only original=\(number(original)) candidate=\(number(e.candidate)) "
            + "source=\(e.source) confirmedDays=\(e.confirmedDays) readErrors=\(readErrors) cappedDays=\(cappedDays)"
    }
    public static func sleepLine(_ e: ContextualSleepNeed.Estimate, day: String) -> String {
        "lab sleepneed experimental=true model=nroop-lab-v1 day=\(day) scope=prior-computed-context original=\(number(e.originalHours)) "
            + "candidate=\(number(e.candidateHours)) eligibleNights=\(e.eligibleNights) status=\(e.candidateHours == nil ? "insufficient-context" : "compared")"
    }
    public static func recoveryLine(_ r: QualityRecovery.Result, q: QualityRecovery.Quality, day: String, scope: String = "final-current-baselines") -> String {
        "lab recovery experimental=true model=nroop-lab-v1 day=\(day) scope=\(scope) original=\(number(r.original)) candidate=\(number(r.candidate)) "
            + "status=\(r.status) qHrv=\(number(q.hrv)) qRhr=\(number(q.rhr)) qSleep=\(number(q.sleep)) qResp=\(number(q.resp)) qSkin=\(number(q.skin))"
    }
    /// Only explicitly enabled sinks receive lab lines. The old Effort/regular routing is preserved.
    public static func replayDiagnostic(_ line: String, regularSink: (String) -> Void,
                                        workoutSink: ((String) -> Void)?, recoverySink: ((String) -> Void)? = nil,
                                        sleepSink: ((String) -> Void)? = nil) {
        if line.hasPrefix("lab quality ") || line.hasPrefix("lab maxhr ") { workoutSink?(line) }
        else if line.hasPrefix("lab recovery ") || line.hasPrefix("lab concordance ") { recoverySink?(line) }
        else if line.hasPrefix("lab sleepneed ") { sleepSink?(line) }
        else { EffortCadenceComparison.replayDiagnostic(line, regularSink: regularSink, comparisonSink: workoutSink) }
    }
    /// Evidence describes a SINGLE detected session; multiple/absent sessions are deliberately declined.
    /// Keep current RMSSD/RHR values and their incumbent baselines; never substitute weightedRMSSD here.
    public static func recoveryEvidence(sessions: [SleepSession], hr: [HRSample], rr: [RRInterval], deepWindow: Bool, detectedOnly: Bool = true) -> QualityRecovery.Quality {
        guard detectedOnly, sessions.count == 1, let s = sessions.first, !s.hrOnly, s.end > s.start else { return .init(hrv: 0, rhr: 0, sleep: 0) }
        let beats = deepWindow ? rr.filter { r in s.stages.contains { $0.stage == "deep" && r.ts >= $0.start && r.ts < $0.end } } : rr
        let h = NightlyHRVQuality.analyze(start: s.start, end: s.end, rr: beats)
        let retained = max(0, h.inputBeats - h.rejectedBeats)
        let eligibleIntervals = deepWindow ? s.stages.filter { $0.stage == "deep" }.map { (max(s.start,$0.start),min(s.end,$0.end)) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 } : [(s.start,s.end)]
        var eligibleSeconds = 0, cursor = s.start
        for interval in eligibleIntervals { eligibleSeconds += max(0,interval.1 - max(cursor,interval.0)); cursor = max(cursor,interval.1) }
        let evidenceCoverage = min(1,h.coverage * Double(s.end - s.start) / Double(max(1,eligibleSeconds)))
        let hrvQ = h.overCounted || h.weightedRMSSD == nil ? 0 : evidenceCoverage * min(1, Double(h.usableWindows) / 3)
            * Double(retained) / Double(max(1,h.inputBeats)) * min(1,Double(h.usablePairs) / Double(max(1,retained - h.usableWindows)))
        let q = SampleQuality.analyze(hr, start: s.start, end: s.end)
        let stagedSeconds = s.stages.filter { ["wake","light","deep","rem"].contains($0.stage) }
            .reduce(0) { $0 + max(0,min(s.end,$1.end) - max(s.start,$1.start)) }
        let sleepQ = min(1,Double(stagedSeconds) / Double(s.end - s.start))
        // No calibrated reliability witness for respiration/temperature here: do not invent one.
        return .init(hrv: hrvQ, rhr: q.reliability, sleep: sleepQ)
    }
    public static func concordanceLine(sessions: [SleepSession], hr: [HRSample], rr: [RRInterval], deepWindow: Bool, eligible: Bool, day: String) -> String {
        guard sessions.count == 1, let s = sessions.first, !s.hrOnly else {
            return BeatHRConcordance.analyze(hr: [],rr: [],start: 0,end: 0,eligible: false).trace(day: day)
        }
        let beats = deepWindow ? rr.filter { r in s.stages.contains { $0.stage == "deep" && r.ts >= $0.start && r.ts < $0.end } } : rr
        return BeatHRConcordance.analyze(hr: hr,rr: beats,start: s.start,end: s.end,eligible: eligible).trace(day: day)
    }
    public static func recoveryComparison(daily: DailyMetric, baselines b: AnalyticsEngine.ProfileBaselines,
                                          quality: QualityRecovery.Quality, evidenceStillMatches: Bool = true) -> QualityRecovery.Result {
        guard evidenceStillMatches else { return .init(original: daily.recovery, candidate: nil, status: "edited-sleep") }
        guard let hrv = daily.avgHrv, let rhr = daily.restingHr, let hb = b.hrv else {
            return .init(original: nil, candidate: nil, status: "missing-essential-input")
        }
        let rest = AnalyticsEngine.Rest.composite(daily: daily).map { $0 / 100 } ?? daily.efficiency
        return QualityRecovery.compare(hrv: hrv, rhr: Double(rhr), resp: daily.respRateBpm,
            hrvBaseline: RecoveryScorer.DriverBaseline(hb), rhrBaseline: b.restingHR.flatMap { $0.usable ? .init($0) : nil },
            respBaseline: b.resp.flatMap { $0.usable ? .init($0) : nil }, sleepPerf: rest,
            skinTempDev: daily.skinTempDevC, baselineUsable: hb.usable, quality: quality)
    }
}
