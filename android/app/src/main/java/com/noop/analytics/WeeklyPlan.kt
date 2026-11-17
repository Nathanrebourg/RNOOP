package com.noop.analytics

import java.time.LocalDate
import java.time.format.DateTimeParseException

/** Local Int preferences, deliberately outside the .noopbak whitelist. Zero disables a goal. */
data class WeeklyPlanGoals(private val requestedSleepMinutes: Int, private val requestedSleepNights: Int, private val requestedWorkoutDays: Int) {
    val sleepMinutes = requestedSleepMinutes.coerceIn(60, 960)
    val sleepNights = requestedSleepNights.coerceIn(0, 7)
    val workoutDays = requestedWorkoutDays.coerceIn(0, 7)
    companion object {
        const val SLEEP_MINUTES_KEY = "weeklyPlanSleepMinutes"
        const val SLEEP_NIGHTS_KEY = "weeklyPlanSleepNights"
        const val WORKOUT_DAYS_KEY = "weeklyPlanWorkoutDays"
    }
}

data class WeeklyPlanSleep(val day: String, val minutes: Double?)
data class WeeklyPlanDay(val day: String, val sleepMinutes: Double?, val hasRecordedWorkout: Boolean, val isToday: Boolean, val isFuture: Boolean)
data class WeeklyPlanProgress(val sleepNights: Int, val sleepObservedNights: Int, val workoutDays: Int)

/** Pure calendar aggregation; inputs are already local civil dates, not UTC observations.
 * Sleep keeps the existing merged daily row's day. Completed workouts use their local start date.
 * Duplicate sleep estimates use max, never sum; missing observations stay null.
 */
object WeeklyPlanEngine {
    fun build(today: String, sleep: List<WeeklyPlanSleep>, workoutDays: List<String>): List<WeeklyPlanDay> {
        val anchor = date(today) ?: return emptyList()
        val monday = anchor.minusDays((anchor.dayOfWeek.value - 1).toLong())
        val byDay = mutableMapOf<String, Double>()
        sleep.forEach { row ->
            val value = row.minutes
            if (value != null && value.isFinite() && value in 0.0..1440.0 && row.day <= today && date(row.day) != null) {
                byDay[row.day] = maxOf(byDay[row.day] ?: value, value)
            }
        }
        val workouts = workoutDays.toSet()
        return (0..6).map {
            val key = monday.plusDays(it.toLong()).toString()
            val future = key > today
            WeeklyPlanDay(key, if (future) null else byDay[key], !future && key in workouts, key == today, future)
        }
    }

    fun progress(rows: List<WeeklyPlanDay>, goals: WeeklyPlanGoals): WeeklyPlanProgress {
        val observed = rows.filter { !it.isFuture }
        return WeeklyPlanProgress(observed.count { (it.sleepMinutes ?: -1.0) >= goals.sleepMinutes },
            observed.count { it.sleepMinutes != null }, observed.count { it.hasRecordedWorkout })
    }

    private fun date(key: String): LocalDate? {
        if (!key.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")) || key.startsWith("0000")) return null
        return try { LocalDate.parse(key).takeIf { it.year in 1970..2099 } } catch (_: DateTimeParseException) { null }
    }
}
