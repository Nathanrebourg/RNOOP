package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.RrInterval

/** Descriptive exact-second check; transport latency/smoothing can explain differences. Never scores. */
object BeatHRConcordance {
    data class Result(val status: String,val matchedSeconds: Int,val medianAbsoluteBPM: Double?,
                      val medianSignedBPM: Double?,val discrepantSeconds: Int) {
        fun trace(day: String) = "lab concordance experimental=true model=nroop-concordance-v1 day=$day scope=exact-second-selected-hrv-period " +
            "status=$status matchedSec=$matchedSeconds medianAbsBpm=${AlgorithmLab.number(medianAbsoluteBPM)} " +
            "medianSignedBpm=${AlgorithmLab.number(medianSignedBPM)} aboveToleranceSec=$discrepantSeconds toleranceBpm=10 noScoreEffect=true"
    }
    fun analyze(hr: List<HrSample>,rr: List<RrInterval>,start: Long,end: Long,eligible: Boolean = true): Result {
        fun unavailable(status: String,matched: Int = 0)=Result(status,matched,null,null,0)
        if (!eligible) return unavailable("ineligible-session")
        if (end<=start || end.toDouble()-start.toDouble()>172800) return unavailable("invalid-window")
        val beats=rr.filter { it.ts>=start && it.ts<end }
        if (beats.any { it.srcChannel !in listOf(5,7) }) return unavailable("unverified-rr-source")
        if (beats.mapNotNull { it.srcChannel }.toSet().size>1) return unavailable("mixed-rr-source")
        val hrs=SampleQuality.uniqueHR(hr.filter { it.ts>=start && it.ts<end && it.bpm<=300 })
        val bySecond=beats.filter { it.rrMs in 300..2000 }.groupBy { it.ts }
        val deltas=hrs.mapNotNull { h -> bySecond[h.ts]?.let { values ->
            h.bpm-HrvAnalyzer.median(values.map { it.rrMs }.toSet().map { 60000.0/it })
        } }
        if (deltas.size<60) return unavailable("insufficient-overlap",deltas.size)
        return Result("observed",deltas.size,HrvAnalyzer.median(deltas.map { kotlin.math.abs(it) }),
            HrvAnalyzer.median(deltas),deltas.count { kotlin.math.abs(it)>10 })
    }
}
