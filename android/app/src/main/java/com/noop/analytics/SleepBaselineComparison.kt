package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import com.noop.data.RespSample
import com.noop.data.RrInterval
import kotlin.math.roundToLong

/** Measurement-only wiring of the existing personal overnight HR band. Swift twin: SleepBaselineComparison. */
object SleepBaselineComparison {
    data class Window(val start: Long, val end: Long)
    data class Observation(val end: Long, val medianBPM: Double, val minutes: Int)
    data class Reference(val bpm: Double?, val nights: Int)
    data class Result(val reference: Reference, val status: String,
                      val original: List<DetectedSleep>?, val candidate: List<DetectedSleep>?) {
        fun trace(day: String): String {
            fun windows(s: List<DetectedSleep>?): String = when {
                s == null -> "nil"
                s.isEmpty() -> "none"
                else -> s.joinToString(",") { "${it.start}:${it.end}" }
            }
            fun inBed(s: List<DetectedSleep>?) = s?.sumOf { maxOf(0L, it.end - it.start) }?.toString() ?: "nil"
            fun asleep(s: List<DetectedSleep>?) = s?.flatMap { it.stages }
                ?.filter { it.stage in listOf("light", "deep", "rem") }
                ?.sumOf { maxOf(0L, it.end - it.start) }?.toString() ?: "nil"
            val bpm = reference.bpm?.let { value ->
                val n = (value * 100).roundToLong(); val f = n % 100
                "${n / 100}.${if (f < 10) "0" else ""}$f"
            } ?: "nil"
            return "sleep baseline experimental=true scope=detector day=$day status=$status " +
                "source=local00-06 nights=${reference.nights} baselineBpm=$bpm " +
                "originalSessions=${original?.size ?: "nil"} candidateSessions=${candidate?.size ?: "nil"} " +
                "originalInBedSec=${inBed(original)} candidateInBedSec=${inBed(candidate)} " +
                "originalAsleepSec=${asleep(original)} candidateAsleepSec=${asleep(candidate)} " +
                "originalWindows=${windows(original)} candidateWindows=${windows(candidate)}"
        }
    }

    /** Fourteen local 00:00–06:00 windows ending before the entire target read window begins. */
    fun historyWindows(before: Long, offset: Long): List<Window> {
        val local = before + offset
        val midnight = local - ((local % 86_400 + 86_400) % 86_400)
        var end = midnight + 21_600 - offset
        if (end > before) end -= 86_400
        return (0 until 14).map { Window(end - it * 86_400L - 21_600, end - it * 86_400L) }
    }

    /** One vote per occupied minute; conflicting timestamps and capped reads cannot create coverage. */
    fun observation(hr: List<HrSample>, window: Window): Observation? {
        if (hr.size >= 50_000 || window.end - window.start != 21_600L) return null
        val byTimestamp = hr.filter { it.bpm > 0 && it.ts >= window.start && it.ts < window.end }.groupBy { it.ts }
        val byMinute = HashMap<Long, MutableList<Double>>()
        for ((ts, rows) in byTimestamp) {
            val first = rows.first()
            if (rows.any { it.bpm != first.bpm }) continue
            byMinute.getOrPut((ts - window.start) / 60) { ArrayList() }.add(first.bpm.toDouble())
        }
        val keys = byMinute.keys.sorted()
        if (keys.size < 180 || keys.last() - keys.first() < 240) return null
        val medians = keys.map { HrvAnalyzer.median(byMinute.getValue(it)) }
        return Observation(window.end, HrvAnalyzer.median(medians), keys.size)
    }

    /** Three distinct qualified nights; the incumbent adaptive baseline keeps its existing 40 bpm floor. */
    fun reference(history: List<Observation>, before: Long, offset: Long): Reference {
        val allowed = historyWindows(before, offset).map { it.end }.toSet()
        val grouped = history.filter { it.end in allowed && it.minutes in 180..360 && it.medianBPM.isFinite() && it.medianBPM > 0 }
            .groupBy { it.end }
        val medians = grouped.values.mapNotNull { rows ->
            val first = rows.first()
            if (rows.any { it.medianBPM != first.medianBPM }) null else first.medianBPM
        }
        return Reference(if (medians.size >= 3) SleepStager.adaptiveOvernightHRBaseline(medians) else null, medians.size)
    }

    /** Same detector inputs twice, with only the personal HR band changed. Never used for standard scores. */
    fun compare(dayStart: Long, readStart: Long, history: List<Observation>, hr: List<HrSample>,
                rr: List<RrInterval> = emptyList(), resp: List<RespSample> = emptyList(), gravity: List<GravitySample>,
                offset: Long = 0, wristOff: List<Pair<Long, Long>> = emptyList(),
                bandSleepState: List<Pair<Long, Int>> = emptyList(), useSleepStagerV2: Boolean = false,
                readCapped: Boolean = false): Result {
        val ref = reference(history, readStart, offset)
        val baseline = ref.bpm ?: return Result(ref, "insufficient-history", null, null)
        if (readCapped || gravity.size < 2) return Result(ref, if (readCapped) "target-read-capped" else "no-motion", null, null)
        fun detect(personal: Double?) = SleepStager.detectSleep(hr = hr, rr = rr, resp = resp, gravity = gravity,
            tzOffsetSeconds = offset, wristOff = wristOff, bandSleepState = bandSleepState,
            useSleepStagerV2 = useSleepStagerV2, sleepHRBaseline = personal)
            .filter { it.end >= dayStart && it.end < dayStart + 86_400 }
            .sortedWith(compareBy<DetectedSleep> { it.start }.thenBy { it.end })
        return Result(ref, "compared", detect(null), detect(baseline))
    }
}
