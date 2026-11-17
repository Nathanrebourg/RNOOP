package com.noop.analytics

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Descriptive daily arithmetic only; mirrors Swift LongitudinalTrends. No health prediction. */
object LongitudinalTrends {
    data class Sample(val dayAge: Int, val value: Double?)
    data class Window(val count: Int, val calendarDays: Int, val mean: Double?) {
        val coverage: Double get() = count.toDouble() / calendarDays
    }
    enum class InsufficientReason { recentWindowTooSparse, priorWindowTooSparse, bothWindowsTooSparse }
    data class Summary(
        val recent30: Window, val prior150: Window, val context180: Window,
        val delta: Double?, val insufficientReason: InsufficientReason?, val conflictingDays: Int,
    )

    /** Each day has equal weight. Conflicting valid duplicates exclude the entire day. */
    fun summarize(samples: List<Sample>, bounds: ClosedFloatingPointRange<Double>? = null): Summary {
        val values = mutableMapOf<Int, Double>()
        val conflicts = mutableSetOf<Int>()
        for (sample in samples) {
            val v = sample.value ?: continue
            if (sample.dayAge !in 1..180 || !v.isFinite() || (bounds != null && v !in bounds)) continue
            val previous = values[sample.dayAge]
            if (previous != null && previous != v) conflicts.add(sample.dayAge)
            else values[sample.dayAge] = v
        }
        val days = values.keys.sorted().filter { it !in conflicts }
        fun window(range: IntRange): Window {
            val selected = days.filter { it in range }.mapNotNull { values[it] }
            val mean = if (selected.isEmpty()) null else selected.fold(0.0) { sum, v -> sum + v / selected.size }
            return Window(selected.size, range.last - range.first + 1, mean)
        }
        val recent = window(1..30)
        val prior = window(31..180)
        val reason = when {
            recent.count < 2 && prior.count < 2 -> InsufficientReason.bothWindowsTooSparse
            recent.count < 2 -> InsufficientReason.recentWindowTooSparse
            prior.count < 2 -> InsufficientReason.priorWindowTooSparse
            else -> null
        }
        return Summary(recent, prior, window(1..180),
            if (reason == null) recent.mean!! - prior.mean!! else null, reason, conflicts.size)
    }

    /** Calendar dates in the supplied zone, never elapsed seconds divided by 86400. */
    fun dayAge(day: String, asOf: Instant, zone: ZoneId): Int? {
        if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(day) || day.startsWith("0000-")) return null
        return try {
            ChronoUnit.DAYS.between(LocalDate.parse(day), asOf.atZone(zone).toLocalDate()).toInt()
        } catch (_: java.time.DateTimeException) { null }
    }
}
