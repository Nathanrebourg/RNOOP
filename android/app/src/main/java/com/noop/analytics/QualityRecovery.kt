package com.noop.analytics

/** Quality-scaled incumbent vitals/baselines; no experimental RMSSD value is substituted. */
object QualityRecovery {
    data class Quality(val hrv: Double, val rhr: Double, val sleep: Double, val resp: Double = 0.0, val skin: Double = 0.0)
    data class Result(val original: Double?, val candidate: Double?, val status: String)
    fun compare(hrv: Double, rhr: Double, resp: Double? = null,
                hrvBaseline: RecoveryScorer.DriverBaseline?, rhrBaseline: RecoveryScorer.DriverBaseline?,
                respBaseline: RecoveryScorer.DriverBaseline? = null, sleepPerf: Double? = null,
                skinTempDev: Double? = null, baselineUsable: Boolean = true, quality: Quality): Result {
        fun valid(b: RecoveryScorer.DriverBaseline?) = b != null && b.mean.isFinite() && b.spread.isFinite() && b.spread > 0
        if (!hrv.isFinite() || hrv < 0 || !rhr.isFinite() || rhr <= 0 || !valid(hrvBaseline) ||
            (rhrBaseline != null && !valid(rhrBaseline)) || (respBaseline != null && !valid(respBaseline)) ||
            (resp != null && (!resp.isFinite() || resp <= 0)) || (sleepPerf != null && (!sleepPerf.isFinite() || sleepPerf !in 0.0..1.0)) ||
            (skinTempDev != null && !skinTempDev.isFinite())) return Result(null,null,"invalid-input")
        val original = RecoveryScorer.recovery(hrv,rhr,resp,hrvBaseline,rhrBaseline,respBaseline,sleepPerf,skinTempDev,baselineUsable)
        val q = quality
        if (listOf(q.hrv,q.rhr,q.sleep,q.resp,q.skin).any { !it.isFinite() || it !in 0.0..1.0 }) return Result(original,null,"invalid-quality")
        if (!baselineUsable || hrvBaseline == null || rhrBaseline == null || q.hrv < 0.5 || q.rhr < 0.2)
            return Result(original,null,"insufficient-essential-quality")
        val terms = arrayListOf(
            RecoveryScorer.zScore(hrv,hrvBaseline.mean,hrvBaseline.spread) to RecoveryScorer.wHRV * q.hrv,
            RecoveryScorer.zScore(rhrBaseline.mean,rhr,rhrBaseline.spread) to RecoveryScorer.wRHR * q.rhr)
        if (resp != null && respBaseline != null) terms.add(RecoveryScorer.zScore(respBaseline.mean,resp,respBaseline.spread) to RecoveryScorer.wResp * q.resp)
        if (sleepPerf != null) terms.add((sleepPerf - RecoveryScorer.sleepPerfCenter) / RecoveryScorer.sleepPerfScale to RecoveryScorer.wSleep * q.sleep)
        if (skinTempDev != null) terms.add(-kotlin.math.abs(skinTempDev) / RecoveryScorer.skinTempDevScale to RecoveryScorer.wSkinTemp * q.skin)
        val z = terms.sumOf { it.first * it.second } / terms.sumOf { it.second }
        return Result(original,RecoveryScorer.logisticScore(z),"compared")
    }
}
