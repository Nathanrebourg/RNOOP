package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.GravitySample

/** Availability, not confidence: one valid sample supports a UTC-aligned 30-second cell. */
object SleepSignalCoverage {
    const val version = "nroop-sleep-support-v1"
    data class Interval(val start: Long, val end: Long, val kind: String)
    data class Result(val status: String, val intervals: List<Interval>,
        val bothSeconds: Long, val hrOnlySeconds: Long, val motionOnlySeconds: Long, val unknownSeconds: Long,
        val distinctHRSeconds: Int, val distinctMotionSeconds: Int) {
        val trace: String get() = "$status|$bothSeconds|$hrOnlySeconds|$motionOnlySeconds|$unknownSeconds|$distinctHRSeconds|$distinctMotionSeconds|" +
            intervals.joinToString(",") { "${it.start}:${it.end}:${it.kind}" }
    }
    fun analyze(start: Long, end: Long, hr: List<HrSample>, gravity: List<GravitySample>): Result {
        if (start < 0 || end > 4102444800L || end <= start || end - start > 172800)
            return Result("invalid-window", emptyList(), 0, 0, 0, 0, 0, 0)
        val hrs = hr.filter { it.ts >= start && it.ts < end && it.bpm in 1..300 }.map { it.ts }.toSet()
        val motions = gravity.filter { it.ts >= start && it.ts < end && it.x.isFinite() && it.y.isFinite() && it.z.isFinite() &&
            (it.x != 0.0 || it.y != 0.0 || it.z != 0.0) }.map { it.ts }.toSet()
        val hrCells = hrs.map { it / 30 }.toSet(); val motionCells = motions.map { it / 30 }.toSet()
        val spans = mutableListOf<Interval>(); val totals = mutableMapOf<String, Long>()
        var edge = start / 30 * 30
        while (edge < end) {
            val lo = maxOf(start, edge); val hi = minOf(end, edge + 30)
            val h = edge / 30 in hrCells; val m = edge / 30 in motionCells
            val kind = if (h) { if (m) "both" else "hr-only" } else { if (m) "motion-only" else "unknown" }
            totals[kind] = (totals[kind] ?: 0) + hi - lo
            val last = spans.lastOrNull()
            if (last?.kind == kind) spans[spans.lastIndex] = Interval(last.start, hi, kind)
            else spans.add(Interval(lo, hi, kind))
            edge += 30
        }
        return Result("observed", spans, totals["both"] ?: 0, totals["hr-only"] ?: 0,
            totals["motion-only"] ?: 0, totals["unknown"] ?: 0, hrs.size, motions.size)
    }
}
