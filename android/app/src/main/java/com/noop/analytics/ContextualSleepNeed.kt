package com.noop.analytics

/** Optional exact journal answers only; missing is never interpreted as false. */
object ContextualSleepNeed {
    const val naturalWakeQuestion = "Did you wake naturally without an alarm or obligation?"
    const val restedQuestion = "Did you wake feeling rested?"
    const val disruptedQuestion = "Was your sleep disrupted by an external event?"
    data class Night(val dayStart: Long, val hours: Double, val naturalWake: Boolean? = null,
                     val rested: Boolean? = null, val disrupted: Boolean? = null)
    data class Estimate(val originalHours: Double, val candidateHours: Double?, val eligibleNights: Int)
    fun estimate(nights: List<Night>, before: Long, age: Int?): Estimate {
        val groups = nights.filter { it.dayStart < before && before.toDouble() - it.dayStart.toDouble() <= 30 * 86_400 &&
            (before - it.dayStart) % 86_400 == 0L && it.hours.isFinite() && it.hours in 3.0..12.0 }.groupBy { it.dayStart }
        val unique = groups.values.mapNotNull { r -> r.first().takeIf { f -> r.all { it == f } } }
        val eligible = unique.filter { it.naturalWake == true && it.rested == true && it.disrupted == false }
        return Estimate(RestScorer.personalizedNeedHours(unique.map { it.hours },age),
            if (eligible.size >= 7) RestScorer.personalizedNeedHours(eligible.map { it.hours },age) else null,eligible.size)
    }
}
