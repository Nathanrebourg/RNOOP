package com.noop.analytics
import com.noop.data.HrSample

/** One-second HR availability evidence; never a contact or clinical-confidence measurement. */
object SampleQuality {
    data class Evidence(val expectedSeconds: Long, val observedSeconds: Int, val longestGap: Long,
                        val duplicates: Int, val ambiguous: Int, val invalid: Int,
                        val coverage: Double, val reliability: Double, val tier: String)
    internal fun uniqueHR(hr: List<HrSample>): List<HrSample> = hr.filter { it.bpm > 0 }.groupBy { it.ts }.values
        .mapNotNull { r -> r.first().takeIf { f -> r.all { it.bpm == f.bpm } } }.sortedBy { it.ts }
    fun analyze(hr: List<HrSample>, start: Long, end: Long): Evidence {
        if (end <= start || end.toDouble() - start.toDouble() > 172_800) return Evidence(0,0,0,0,0,0,0.0,0.0,"calibrating")
        val rows = hr.filter { it.ts >= start && it.ts < end }
        val groups = rows.filter { it.bpm > 0 }.groupBy { it.ts }
        var duplicates = 0; var ambiguous = 0
        for (r in groups.values) if (r.all { it.bpm == r[0].bpm }) duplicates += r.size - 1 else ambiguous++
        val clean = uniqueHR(rows); var cursor = start; var gap = 0L
        for (s in clean) { gap = maxOf(gap,s.ts - cursor); cursor = s.ts + 1 }
        gap = maxOf(gap,end - cursor)
        val invalid = rows.count { it.bpm <= 0 }; val span = end - start
        val coverage = clean.size.toDouble() / span
        val rejection = (ambiguous + invalid).toDouble() / maxOf(1,groups.size + invalid)
        val reliability = coverage * (1 - rejection) * minOf(1.0,120.0 / maxOf(120L,gap))
        val tier = if (coverage >= 0.8 && gap <= 120 && rejection <= 0.05) "solid" else if (coverage >= 0.2) "building" else "calibrating"
        return Evidence(span,clean.size,gap,duplicates,ambiguous,invalid,coverage,reliability,tier)
    }
}
