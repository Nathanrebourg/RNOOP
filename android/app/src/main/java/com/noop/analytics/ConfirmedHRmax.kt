package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.GravitySample

/** Experimental calibration only. Cannot update a profile, Effort, zones or Health. */
object ConfirmedHRmax {
    data class DayPeak(val dayStart: Long, val bpm: Double)
    data class Estimate(val candidate: Double?, val source: String, val confirmedDays: Int)
    fun dailyPeak(hr: List<HrSample>, gravity: List<GravitySample>): Double? {
        val hs = SampleQuality.uniqueHR(hr).filter { it.bpm in 30..250 }
        val gs = gravity.filter { it.x.isFinite() && it.y.isFinite() && it.z.isFinite() &&
            kotlin.math.abs(it.x) <= 1_000_000 && kotlin.math.abs(it.y) <= 1_000_000 && kotlin.math.abs(it.z) <= 1_000_000 &&
            (it.x != 0.0 || it.y != 0.0 || it.z != 0.0) }.groupBy { it.ts }.values.mapNotNull { r ->
                r.first().takeIf { f -> r.all { it.x == f.x && it.y == f.y && it.z == f.z } }
            }.sortedBy { it.ts }
        val activity = WorkoutDetector.activitySeries(gs).associate { it.ts to it.intensity }
        var peak: Double? = null; var runStart = 0
        for (i in hs.indices) {
            if (i > 0 && hs[i].ts - hs[i-1].ts != 1L) runStart = i
            if (i - runStart < 29) continue
            val a = ((hs[i].ts - 29)..hs[i].ts).mapNotNull { activity[it] }
            if (a.size < 24 || a.count { it > WorkoutDetector.motionThreshold }.toDouble() / a.size < 0.3) continue
            val v = HrvAnalyzer.median(hs.subList(i-29,i+1).map { it.bpm.toDouble() })
            peak = maxOf(peak ?: v,v)
        }
        return peak
    }
    fun estimate(history: List<DayPeak>, before: Long, age: Double?, manual: Double? = null): Estimate {
        if (manual != null) {
            val ok = manual.isFinite() && manual in 30.0..250.0
            return Estimate(if (ok) manual else null,if (ok) "manual" else "invalid-manual",0)
        }
        val groups = history.filter { it.dayStart < before && before.toDouble() - it.dayStart.toDouble() <= 30 * 86_400 &&
            (before - it.dayStart) % 86_400 == 0L && it.bpm.isFinite() && it.bpm in 30.0..250.0 }.groupBy { it.dayStart }
        val peaks = groups.values.mapNotNull { r -> if (r.all { it.bpm == r[0].bpm }) r[0].bpm else null }.sortedDescending()
        val fallback = age?.takeIf { it.isFinite() && it > 0 && it <= 120 }?.let { StrainScorer.tanakaHRmax(it) }
        if (peaks.size < 3) return Estimate(fallback,if (fallback == null) "insufficient-history" else "tanaka",peaks.size)
        return Estimate(maxOf(fallback ?: 0.0,HrvAnalyzer.median(peaks.take(3))),"confirmed-history",peaks.size)
    }
}
