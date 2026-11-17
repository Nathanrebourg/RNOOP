package com.noop.analytics

/** Research-only history fold; a vital's direction never determines recording quality. */
object QualityBaseline {
    data class Result(val original: BaselineState,val candidate: BaselineState?,val admitted: Int,val unknown: Int,val rejected: Int,val status: String)
    fun fold(values: List<Double?>,qualities: List<Double?>,cfg: MetricCfg): Result {
        val original=Baselines.foldHistory(values,cfg)
        if (values.size!=qualities.size) return Result(original,null,0,0,0,"mismatched-history")
        var state: BaselineState?=null;var admitted=0;var unknown=0;var rejected=0
        for ((value,q) in values.zip(qualities)) {
            var usable: Double?=null
            if (q==null) unknown++
            else if (!q.isFinite() || q !in 0.5..1.0) rejected++
            else if (value!=null && value.isFinite() && value in cfg.minVal..cfg.maxVal) { usable=value;admitted++ }
            val old=state;val next=Baselines.update(old,usable,cfg)
            state=if (old!=null && old.nValid>0 && usable!=null && q!=null && q<1) {
                BaselineState(old.baseline+q*(next.baseline-old.baseline),old.spread+q*(next.spread-old.spread),next.nValid,next.nightsSinceUpdate,next.status)
            } else next
        }
        val candidate=state?:Baselines.foldHistory(emptyList(),cfg)
        return Result(original,candidate,admitted,unknown,rejected,if (candidate.usable) "compared" else candidate.status.raw)
    }
}
