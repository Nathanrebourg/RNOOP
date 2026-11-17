package com.noop.analytics

/** Exact five-driver replay explanation. Contributions add in z space, not score points. */
object RecoveryExplanation {
    data class Term(val name: String,val z: Double,val normalizedWeight: Double,val contributionZ: Double)
    data class Baseline(val center: Double,val spread: Double,val nights: Int,val missingNights: Int,val status: String) {
        constructor(s: BaselineState):this(s.baseline,s.spread,s.nValid,s.nightsSinceUpdate,s.status.raw)
    }
    data class Result(val score: Double?,val compositeZ: Double?,val terms: List<Term>,val missing: List<String>,val baselines: Map<String,Baseline>,val status: String)
    fun describe(hrv: Double,rhr: Double,resp: Double?,hrvBaseline: BaselineState,rhrBaseline: BaselineState?,respBaseline: BaselineState?,sleepPerf: Double?,skinTempDev: Double?): Result {
        val states=listOf("hrv" to hrvBaseline,"rhr" to rhrBaseline,"resp" to respBaseline).mapNotNull { (k,v)->v?.let { k to it } }.toMap()
        val snapshots=states.mapValues { Baseline(it.value) }
        if (!hrv.isFinite() || hrv<0 || !rhr.isFinite() || rhr<=0 || states.values.any { !it.baseline.isFinite() || !it.spread.isFinite() || it.spread<=0 }
            || (resp!=null && (!resp.isFinite() || resp<=0)) || (sleepPerf!=null && (!sleepPerf.isFinite() || sleepPerf !in 0.0..1.0))
            || (skinTempDev!=null && !skinTempDev.isFinite())) return Result(null,null,emptyList(),emptyList(),emptyMap(),"invalid-input")
        if (!hrvBaseline.usable) return Result(null,null,emptyList(),listOf("hrv-baseline"),snapshots,hrvBaseline.status.raw)
        val raw=mutableListOf(Triple("hrv",RecoveryScorer.zScore(hrv,hrvBaseline.baseline,hrvBaseline.spread),RecoveryScorer.wHRV));val missing=mutableListOf<String>()
        if (rhrBaseline!=null && rhrBaseline.usable) raw.add(Triple("rhr",RecoveryScorer.zScore(rhrBaseline.baseline,rhr,rhrBaseline.spread),RecoveryScorer.wRHR)) else missing.add("rhr")
        if (respBaseline!=null && respBaseline.usable && resp!=null) raw.add(Triple("resp",RecoveryScorer.zScore(respBaseline.baseline,resp,respBaseline.spread),RecoveryScorer.wResp)) else missing.add("resp")
        if (sleepPerf!=null) raw.add(Triple("sleep",(sleepPerf-RecoveryScorer.sleepPerfCenter)/RecoveryScorer.sleepPerfScale,RecoveryScorer.wSleep)) else missing.add("sleep")
        if (skinTempDev!=null) raw.add(Triple("skin",-kotlin.math.abs(skinTempDev)/RecoveryScorer.skinTempDevScale,RecoveryScorer.wSkinTemp)) else missing.add("skin")
        val weight=raw.sumOf { it.third }
        val terms=raw.map { Term(it.first,it.second,it.third/weight,it.second*it.third/weight) }
        val composite=raw.sumOf { it.second*it.third }/weight
        val score=RecoveryScorer.recovery(hrv,rhr,resp,hrvBaseline,rhrBaseline,respBaseline,sleepPerf,skinTempDev)
        return Result(score,composite,terms,missing,snapshots,"explained")
    }
}
