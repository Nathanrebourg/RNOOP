package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.RrInterval
import com.noop.data.DailyMetric
import kotlin.math.roundToLong

/** Default-off diagnostic contract. No score-writing API. */
object AlgorithmLab {
    fun incumbentMaximum(age: Double, manual: Double?) = manual ?: if (age > 0) StrainScorer.tanakaHRmax(age) else StrainScorer.defaultMaxHR().toDouble()
    fun number(v: Double?): String {
        if (v == null || !v.isFinite() || kotlin.math.abs(v) >= 1_000_000_000) return "nil"
        val n = (kotlin.math.abs(v) * 100).roundToLong(); val f = n % 100
        return "${if (v < 0) "-" else ""}${n / 100}.${if (f < 10) "0" else ""}$f"
    }
    fun qualityLine(q: SampleQuality.Evidence, day: String, original: String, hasScore: Boolean) =
        "lab quality experimental=true model=nroop-lab-v1 day=$day scope=elapsed-day-1hz original=$original candidate=${if (hasScore) q.tier else "calibrating"} " +
            "expectedSec=${q.expectedSeconds} observedSec=${q.observedSeconds} coverage=${number(q.coverage)} longestGapSec=${q.longestGap} " +
            "reliability=${number(q.reliability)} duplicates=${q.duplicates} ambiguous=${q.ambiguous} invalid=${q.invalid}"
    fun maximumLine(e: ConfirmedHRmax.Estimate, day: String, original: Double?, readErrors: Int = 0, cappedDays: Int = 0) =
        "lab maxhr experimental=true model=nroop-lab-v1 day=$day scope=calibration-only original=${number(original)} candidate=${number(e.candidate)} " +
            "source=${e.source} confirmedDays=${e.confirmedDays} readErrors=$readErrors cappedDays=$cappedDays"
    fun sleepLine(e: ContextualSleepNeed.Estimate, day: String) =
        "lab sleepneed experimental=true model=nroop-lab-v1 day=$day scope=prior-computed-context original=${number(e.originalHours)} " +
            "candidate=${number(e.candidateHours)} eligibleNights=${e.eligibleNights} status=${if (e.candidateHours == null) "insufficient-context" else "compared"}"
    fun recoveryLine(r: QualityRecovery.Result, q: QualityRecovery.Quality, day: String, scope: String = "final-current-baselines") =
        "lab recovery experimental=true model=nroop-lab-v1 day=$day scope=$scope original=${number(r.original)} candidate=${number(r.candidate)} " +
            "status=${r.status} qHrv=${number(q.hrv)} qRhr=${number(q.rhr)} qSleep=${number(q.sleep)} qResp=${number(q.resp)} qSkin=${number(q.skin)}"
    fun replayDiagnostic(line: String, regularSink: (String)->Unit, workoutSink: ((String)->Unit)?,
                         recoverySink: ((String)->Unit)? = null, sleepSink: ((String)->Unit)? = null) {
        when {
            line.startsWith("lab quality ") || line.startsWith("lab maxhr ") -> workoutSink?.invoke(line)
            line.startsWith("lab recovery ") || line.startsWith("lab concordance ") -> recoverySink?.invoke(line)
            line.startsWith("lab sleepneed ") -> sleepSink?.invoke(line)
            else -> EffortCadenceComparison.replayDiagnostic(line,regularSink,workoutSink)
        }
    }
    fun recoveryEvidence(sessions: List<DetectedSleep>, hr: List<HrSample>, rr: List<RrInterval>, deepWindow: Boolean, detectedOnly: Boolean = true): QualityRecovery.Quality {
        val s = sessions.singleOrNull()
        if (!detectedOnly || s == null || s.hrOnly || s.end <= s.start) return QualityRecovery.Quality(0.0,0.0,0.0)
        val beats = if (deepWindow) rr.filter { r -> s.stages.any { it.stage == "deep" && r.ts >= it.start && r.ts < it.end } } else rr
        val h = NightlyHRVQuality.analyze(s.start,s.end,beats)
        val retained = maxOf(0,h.inputBeats - h.rejectedBeats)
        val intervals = if (deepWindow) s.stages.filter { it.stage == "deep" }
            .map { maxOf(s.start,it.start) to minOf(s.end,it.end) }.filter { it.second > it.first }.sortedBy { it.first }
            else listOf(s.start to s.end)
        var seconds = 0L; var cursor = s.start
        for ((lo,hi) in intervals) { seconds += maxOf(0L,hi - maxOf(cursor,lo)); cursor = maxOf(cursor,hi) }
        val coverage = minOf(1.0,h.coverage * (s.end - s.start) / maxOf(1L,seconds))
        val hrvQ = if (h.overCounted || h.weightedRMSSD == null) 0.0 else coverage * minOf(1.0,h.usableWindows / 3.0) *
            retained.toDouble() / maxOf(1,h.inputBeats) * minOf(1.0,h.usablePairs.toDouble() / maxOf(1,retained - h.usableWindows))
        val q = SampleQuality.analyze(hr,s.start,s.end)
        val staged = s.stages.filter { it.stage in listOf("wake","light","deep","rem") }
            .sumOf { maxOf(0L,minOf(s.end,it.end) - maxOf(s.start,it.start)) }
        return QualityRecovery.Quality(hrvQ,q.reliability,minOf(1.0,staged.toDouble() / (s.end - s.start)))
    }
    fun concordanceLine(sessions: List<DetectedSleep>,hr: List<HrSample>,rr: List<RrInterval>,deepWindow: Boolean,eligible: Boolean,day: String): String {
        val s=sessions.singleOrNull()
        if (s==null || s.hrOnly) return BeatHRConcordance.analyze(emptyList(),emptyList(),0,0,false).trace(day)
        val beats=if (deepWindow) rr.filter { r -> s.stages.any { it.stage=="deep" && r.ts>=it.start && r.ts<it.end } } else rr
        return BeatHRConcordance.analyze(hr,beats,s.start,s.end,eligible).trace(day)
    }
    fun recoveryComparison(daily: DailyMetric, baselines: ProfileBaselines, quality: QualityRecovery.Quality, evidenceStillMatches: Boolean = true): QualityRecovery.Result {
        if (!evidenceStillMatches) return QualityRecovery.Result(daily.recovery,null,"edited-sleep")
        val hrv = daily.avgHrv; val rhr = daily.restingHr; val hb = baselines.hrv
        if (hrv == null || rhr == null || hb == null) return QualityRecovery.Result(null,null,"missing-essential-input")
        val rest = RestScorer.restFromDaily(daily)?.div(100) ?: daily.efficiency
        return QualityRecovery.compare(hrv,rhr.toDouble(),daily.respRateBpm,
            RecoveryScorer.DriverBaseline(hb),baselines.restingHR?.takeIf { it.usable }?.let { RecoveryScorer.DriverBaseline(it) },
            baselines.resp?.takeIf { it.usable }?.let { RecoveryScorer.DriverBaseline(it) },rest,
            daily.skinTempDevC,hb.usable,quality)
    }
}
