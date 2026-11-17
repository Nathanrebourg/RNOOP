package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import kotlin.math.roundToLong

/** Default-off five-minute HR-only experiment. Swift twin: StressCadenceComparison. Diagnostics only. */
object StressCadenceComparison {
    data class Point(val start: Long, val end: Long, val level: Double?, val originalLevel: Double?, val status: String)
    data class Result(val status: String, val referenceHR: Double?, val referenceSpread: Double,
                      val referenceHours: Int, val points: List<Point>) {
        val candidateHighMinutes: Int get() = points.count { (it.level ?: -1.0) >= DaytimeStress.highBandFloor } * 5
        fun lines(day: String): List<String> {
            val scored = points.filter { it.level != null }
            val matched = scored.filter { it.originalLevel != null }
            val oldHigh = matched.count { (it.originalLevel ?: -1.0) >= DaytimeStress.highBandFloor } * 5
            val newHigh = matched.count { (it.level ?: -1.0) >= DaytimeStress.highBandFloor } * 5
            val summary = "stress cadence experimental=true scope=day-relative-hr-only day=$day scale=0-3 " +
                "status=$status windowSec=300 windows=${points.size} scored=${scored.size} matched=${matched.size} " +
                "referenceHours=$referenceHours referenceBpm=${number(referenceHR)} referenceSpread=${number(referenceSpread)} " +
                "candidateHighMin=$candidateHighMinutes candidateHighMatchedMin=$newHigh originalHighMatchedMin=$oldHigh " +
                "candidatePeak=${number(scored.mapNotNull { it.level }.maxOrNull())} " +
                "originalPeakMatched=${number(matched.mapNotNull { it.originalLevel }.maxOrNull())} detail=last12 noAlerts=true"
            return listOf(summary) + points.takeLast(12).map {
                "stress cadence point experimental=true day=$day start=${it.start} end=${it.end} " +
                    "status=${it.status} original=${number(it.originalLevel)} candidate=${number(it.level)}"
            }
        }
    }

    /** Completed non-overlapping windows, >=240 distinct seconds per signal, no gap above 15 seconds. */
    fun analyze(hr: List<HrSample>, gravity: List<GravitySample>, dayStart: Long, now: Long,
                offset: Long = 0, readCapped: Boolean = false): Result {
        fun empty(status: String) = Result(status, null, 0.0, 0, emptyList())
        if (readCapped) return empty("read-capped")
        if (now <= dayStart) return empty("no-completed-window")
        val limit = minOf(now, dayStart + 86_400)
        val hs = hr.filter { it.bpm > 0 && it.ts >= dayStart && it.ts < limit }.groupBy { it.ts }.values
            .mapNotNull { rows -> rows.first().takeIf { first -> rows.all { it.bpm == first.bpm } } }.sortedBy { it.ts }
        if (hs.isEmpty()) return empty("no-heart-rate")
        val gs = gravity.filter { it.ts >= dayStart && it.ts < limit && it.x.isFinite() && it.y.isFinite() && it.z.isFinite() &&
            kotlin.math.abs(it.x) <= 1_000_000 && kotlin.math.abs(it.y) <= 1_000_000 && kotlin.math.abs(it.z) <= 1_000_000 &&
            (it.x != 0.0 || it.y != 0.0 || it.z != 0.0) }.groupBy { it.ts }.values.mapNotNull { rows ->
            rows.first().takeIf { first -> rows.all { it.x == first.x && it.y == first.y && it.z == first.z } }
        }.sortedBy { it.ts }
        if (gs.isEmpty()) return empty("no-motion")
        fun bucket(ts: Long, width: Long) = DaytimeStress.floorDiv(ts + offset, width) * width - offset
        val hourly = DaytimeStress.analyze(hr = hs, rr = emptyList(), gravity = gs, tzOffsetSeconds = offset)
        val original = hourly.hours.associateBy { it.startTs }
        val activity = WorkoutDetector.activitySeries(gs)
        val hourActivity = activity.groupBy { bucket(it.ts, 3_600) }
        fun active(rows: List<ActivityPoint>) = rows.isNotEmpty() &&
            rows.count { it.intensity > WorkoutDetector.motionThreshold }.toDouble() / rows.size >= DaytimeStress.activityMaskFraction
        // Recovery shadows remain in the incumbent's calibration; only directly ambulatory hours leave it.
        val refValues = hourly.hours.filter { !active(hourActivity[it.startTs] ?: emptyList()) }.mapNotNull { it.meanHr }
        val ref = DaytimeStress.calmReference(refValues, calmIsLow = true)
        val sd = DaytimeStress.std(refValues, DaytimeStress.mean(refValues))
        val enoughReference = refValues.size >= 3 && ref?.isFinite() == true && sd.isFinite()
        val hrGrid = hs.groupBy { bucket(it.ts, 300) }
        val gravGrid = gs.groupBy { bucket(it.ts, 300) }
        val activityGrid = activity.groupBy { bucket(it.ts, 300) }
        fun covered(ts: List<Long>, start: Long) = ts.size >= 240 && ts.first() - start <= 15 &&
            start + 299 - ts.last() <= 15 && ts.zipWithNext().all { (a, b) -> b - a <= 15 }
        val directlyActive = gravGrid.keys.filter { start -> covered(gravGrid[start]!!.map { it.ts }, start) &&
            active(activityGrid[start] ?: emptyList()) }.toSet()
        val points = ArrayList<Point>()
        for (start in bucket(dayStart, 300) until limit step 300) {
            if (start < dayStart || start + 300 > limit || !DaytimeStress.isWakingHour(bucket(start, 3_600) + offset)) continue
            val rows = hrGrid[start] ?: emptyList()
            val mean = DaytimeStress.mean(rows.map { it.bpm.toDouble() })
            val parent = original[bucket(start, 3_600)]
            val status = when {
                !covered(rows.map { it.ts }, start) -> "hr-coverage"
                !covered((gravGrid[start] ?: emptyList()).map { it.ts }, start) -> "motion-coverage"
                start in directlyActive -> "activity"
                parent?.maskedForActivity == true -> "hour-activity"
                mean != null && ref != null && mean > ref + DaytimeStress.postActivityShadowBpm &&
                    directlyActive.any { it < start && start - it <= 3_600 } -> "post-activity"
                !enoughReference -> "insufficient-reference"
                else -> "scored"
            }
            val level = if (status == "scored") DaytimeStress.squash(if (sd > 0.0001) ((mean ?: 0.0) - (ref ?: 0.0)) / sd else 0.0) else null
            points.add(Point(start, start + 300, level, parent?.level, status))
        }
        return Result(if (enoughReference) "compared" else "insufficient-reference", ref, sd, refValues.size, points)
    }

    private fun number(value: Double?): String {
        if (value == null || !value.isFinite() || value < 0 || value >= 1_000_000_000) return "nil"
        val n = (value * 100).roundToLong(); val f = n % 100
        return "${n / 100}.${if (f < 10) "0" else ""}$f"
    }
}
