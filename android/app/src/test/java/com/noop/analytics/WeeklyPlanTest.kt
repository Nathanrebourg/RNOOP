package com.noop.analytics

import org.junit.Assert.*
import org.junit.Test

class WeeklyPlanTest {
    @Test fun compiledSwiftOracle() {
        val sleep = listOf(WeeklyPlanSleep("2026-11-09", 420.0), WeeklyPlanSleep("2026-11-09", 480.0),
            WeeklyPlanSleep("2026-11-10", Double.NaN), WeeklyPlanSleep("2026-11-10", -1.0),
            WeeklyPlanSleep("2026-11-11", 0.0), WeeklyPlanSleep("2026-11-12", 9999.0), WeeklyPlanSleep("2026-11-13", 600.0))
        val dates = listOf("2026-11-12", "2026-11-15", "2026-11-16", "2026-01-01", "2024-03-03", "2026-03-29", "2026-10-25", "2026-02-29", "2026-2-03", "0000-01-01", "２０２６-01-01", "0001-01-01", "1500-02-28", "2100-01-01", "9999-12-31")
        val lines = dates.map { date ->
            val rows = WeeklyPlanEngine.build(date, sleep, listOf("2026-11-09", "2026-11-09", "2026-11-12", "2026-11-13"))
            val p = WeeklyPlanEngine.progress(rows, WeeklyPlanGoals(480, 2, 3))
            val trace = rows.joinToString(";") { "${it.day}:${it.sleepMinutes?.toInt() ?: "?"}:${if (it.hasRecordedWorkout) 1 else 0}:${if (it.isToday) 1 else 0}:${if (it.isFuture) 1 else 0}" }
            "$date|$trace|${p.sleepNights},${p.sleepObservedNights},${p.workoutDays}"
        }.toMutableList()
        listOf(Triple(Int.MIN_VALUE, -8, -2), Triple(Int.MAX_VALUE, 90, 80), Triple(480, 0, 0), Triple(421, 2, 3)).forEach {
            val g = WeeklyPlanGoals(it.first, it.second, it.third)
            lines += "goals|${g.sleepMinutes},${g.sleepNights},${g.workoutDays}"
        }
        // Literal stdout from actual swiftc compilation of production source + Tools/Oracles/WeeklyPlan/main.swift.
        assertEquals("""
2026-11-12|2026-11-09:480:1:0:0;2026-11-10:?:0:0:0;2026-11-11:0:0:0:0;2026-11-12:?:1:1:0;2026-11-13:?:0:0:1;2026-11-14:?:0:0:1;2026-11-15:?:0:0:1|1,2,2
2026-11-15|2026-11-09:480:1:0:0;2026-11-10:?:0:0:0;2026-11-11:0:0:0:0;2026-11-12:?:1:0:0;2026-11-13:600:1:0:0;2026-11-14:?:0:0:0;2026-11-15:?:0:1:0|2,3,3
2026-11-16|2026-11-16:?:0:1:0;2026-11-17:?:0:0:1;2026-11-18:?:0:0:1;2026-11-19:?:0:0:1;2026-11-20:?:0:0:1;2026-11-21:?:0:0:1;2026-11-22:?:0:0:1|0,0,0
2026-01-01|2025-12-29:?:0:0:0;2025-12-30:?:0:0:0;2025-12-31:?:0:0:0;2026-01-01:?:0:1:0;2026-01-02:?:0:0:1;2026-01-03:?:0:0:1;2026-01-04:?:0:0:1|0,0,0
2024-03-03|2024-02-26:?:0:0:0;2024-02-27:?:0:0:0;2024-02-28:?:0:0:0;2024-02-29:?:0:0:0;2024-03-01:?:0:0:0;2024-03-02:?:0:0:0;2024-03-03:?:0:1:0|0,0,0
2026-03-29|2026-03-23:?:0:0:0;2026-03-24:?:0:0:0;2026-03-25:?:0:0:0;2026-03-26:?:0:0:0;2026-03-27:?:0:0:0;2026-03-28:?:0:0:0;2026-03-29:?:0:1:0|0,0,0
2026-10-25|2026-10-19:?:0:0:0;2026-10-20:?:0:0:0;2026-10-21:?:0:0:0;2026-10-22:?:0:0:0;2026-10-23:?:0:0:0;2026-10-24:?:0:0:0;2026-10-25:?:0:1:0|0,0,0
2026-02-29||0,0,0
2026-2-03||0,0,0
0000-01-01||0,0,0
２０２６-01-01||0,0,0
0001-01-01||0,0,0
1500-02-28||0,0,0
2100-01-01||0,0,0
9999-12-31||0,0,0
goals|60,0,0
goals|960,7,7
goals|480,0,0
goals|421,2,3
""".trimIndent(), lines.joinToString("\n"))
    }

    @Test fun duplicateOrderAndMissingAreNotZero() {
        val sleep = listOf(WeeklyPlanSleep("2026-11-09", 480.0), WeeklyPlanSleep("2026-11-09", 420.0), WeeklyPlanSleep("2026-11-10", null))
        val a = WeeklyPlanEngine.build("2026-11-12", sleep, listOf("2026-11-09", "2026-11-09"))
        val b = WeeklyPlanEngine.build("2026-11-12", sleep.reversed(), listOf("2026-11-09"))
        assertEquals(a, b)
        assertNull(a[1].sleepMinutes)
        assertEquals(WeeklyPlanProgress(1, 1, 1), WeeklyPlanEngine.progress(a, WeeklyPlanGoals(480, 2, 3)))
    }
}
