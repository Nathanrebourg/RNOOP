package com.noop.analytics

import com.noop.data.StepSample
import org.junit.Assert.*
import org.junit.Test

class GuidedWalkingTrialTest {
    private fun walk(start: Long = 1000, duration: Int = 60, activity: Int? = 1) = (0..duration).map {
        GuidedWalkingTrial.Sample(start + it, 100 + (it - 1).coerceIn(0, duration - 2) * 2, activity)
    }
    private fun result(samples: List<GuidedWalkingTrial.Sample>, start: Long = 1000, end: Long = 1060) =
        GuidedWalkingTrial.evaluate(start, end, samples)
    private fun replacing(samples: List<GuidedWalkingTrial.Sample>, at: Int, counter: Int? = null,
                          activity: Int? = samples[at].activityClass) = samples.toMutableList().apply {
        this[at] = this[at].copy(counter = counter ?: this[at].counter, activityClass = activity)
    }

    @Test fun retainsExactlyIncumbentPipelineTicksAndExposesObservedBounds() {
        for (activity in listOf(null, 1, 2)) {
            val samples = walk(activity = activity)
            val checked = result(samples)
            assertNull(checked.issue)
            assertEquals(116, checked.retainedTicks)
            assertEquals(1000L, checked.observedStartTs)
            assertEquals(1060L, checked.observedEndTs)
            assertEquals(61, checked.sampleCount)
            assertEquals(activity != null, checked.usesActivityClasses)
            assertEquals(checked.retainedTicks, StepsCounter.stepsInWindow(samples.map {
                StepSample("owner", it.ts, it.counter, it.activityClass)
            }))
        }
    }
    @Test fun sortsDeduplicatesAndRejectsConflictingRecords() {
        val samples = walk()
        assertEquals(116, result(samples.reversed() + samples[8]).retainedTicks)
        assertEquals(GuidedWalkingTrial.Issue.CONFLICTING_SAMPLE,
            result(samples + samples[8].copy(counter = 999)).issue)
        assertEquals(GuidedWalkingTrial.Issue.CONFLICTING_SAMPLE,
            result(samples + samples[8].copy(activityClass = null)).issue)
    }
    @Test fun rejectsAmbiguousDropsAndEveryDiscardedPositiveIncrement() {
        assertEquals(GuidedWalkingTrial.Issue.COUNTER_DECREASED, result(replacing(walk(), 20, counter = 1)).issue)
        val wrap = replacing(replacing(walk(), 0, counter = 65535), 1, counter = 65535)
        assertEquals(GuidedWalkingTrial.Issue.COUNTER_DECREASED, result(wrap).issue)
        for (counter in listOf(600, walk()[19].counter + 5)) {
            assertEquals(GuidedWalkingTrial.Issue.IMPLAUSIBLE_INCREMENT, result(replacing(walk(), 20, counter = counter)).issue)
        }
        for (activity in listOf(0, 3, -1, null)) {
            assertEquals(GuidedWalkingTrial.Issue.NON_WALKING_INCREMENT,
                result(replacing(walk(), 20, activity = activity)).issue)
        }
        assertNull(result(replacing(walk(), 60, activity = 0)).issue)
    }
    @Test fun boundsDurationCoverageGapsAndStationaryEdges() {
        for (start in listOf(0L, -1L)) assertEquals(GuidedWalkingTrial.Issue.INVALID_WINDOW, result(walk(), start = start).issue)
        assertEquals(GuidedWalkingTrial.Issue.INVALID_WINDOW, result(walk(), end = Long.MAX_VALUE).issue)
        for (end in listOf(1059L, 4601L)) assertEquals(GuidedWalkingTrial.Issue.INVALID_DURATION, result(walk(), end = end).issue)
        assertEquals(GuidedWalkingTrial.Issue.INSUFFICIENT_SAMPLES, result(emptyList()).issue)
        assertEquals(GuidedWalkingTrial.Issue.INCOMPLETE_COVERAGE, result(walk().drop(4)).issue)
        assertEquals(GuidedWalkingTrial.Issue.SAMPLE_GAP, result(walk().filter { it.ts !in 1020L..1024L }).issue)
        assertEquals(GuidedWalkingTrial.Issue.MOVING_BOUNDARY, result(replacing(walk(), 0, counter = 99)).issue)
        assertEquals(GuidedWalkingTrial.Issue.MOVING_BOUNDARY, result(replacing(walk(), 60, counter = 217)).issue)
        assertNull(result(walk(start = 1003), start = 1000, end = 1066).issue)
        assertEquals(GuidedWalkingTrial.Issue.NO_MOVEMENT, result(walk().map { it.copy(counter = 100, activityClass = 0) }).issue)
    }
    @Test fun validatesU16AndTimestampAndRestrictsReadWindow() {
        for (counter in listOf(-1, 65536)) assertEquals(GuidedWalkingTrial.Issue.INVALID_COUNTER,
            result(replacing(walk(), 20, counter = counter)).issue)
        assertEquals(GuidedWalkingTrial.Issue.INVALID_TIMESTAMP,
            result(walk() + GuidedWalkingTrial.Sample(Long.MAX_VALUE, 1, 1)).issue)
        assertEquals(116, result(walk() + GuidedWalkingTrial.Sample(999, 999, 0)).retainedTicks)
        assertEquals(116, result(walk() + GuidedWalkingTrial.Sample(1061, 0, 0)).retainedTicks)
    }
    fun oracleTranscript(): String {
        val base = walk()
        data class Case(val name: String, val start: Long = 1000, val end: Long = 1060,
                        val samples: List<GuidedWalkingTrial.Sample>)
        val cases = listOf(
            Case("classed", samples = base),
            Case("legacy", samples = walk(activity = null)),
            Case("run", samples = walk(activity = 2)),
            Case("dedup", samples = base.reversed() + base[8]),
            Case("conflict", samples = base + base[8].copy(counter = 999)),
            Case("invalid-counter", samples = replacing(base, 20, counter = 65536)),
            Case("invalid-ts", samples = base + GuidedWalkingTrial.Sample(0, 0, null)),
            Case("invalid-window", start = 0, samples = base),
            Case("short", end = 1059, samples = base),
            Case("long", end = 4601, samples = base),
            Case("empty", samples = emptyList()),
            Case("coverage", samples = base.drop(4)),
            Case("edge3", end = 1066, samples = walk(start = 1003)),
            Case("gap5", samples = base.filter { it.ts !in 1020L..1023L }),
            Case("gap6", samples = base.filter { it.ts !in 1020L..1024L }),
            Case("drop", samples = replacing(base, 20, counter = 1)),
            Case("rate5", samples = replacing(base, 20, counter = base[19].counter + 5)),
            Case("delta512", samples = replacing(base, 20, counter = base[19].counter + 512)),
            Case("still", samples = replacing(base, 20, activity = 0)),
            Case("moving-start", samples = replacing(base, 0, counter = 99)),
            Case("moving-end", samples = replacing(base, 60, counter = 217)),
            Case("zero", samples = base.map { it.copy(counter = 100, activityClass = null) }),
            Case("max-duration", end = 4600, samples = walk(duration = 3600)),
            Case("unix-ceiling", start = 4102444740, end = 4102444800, samples = walk(start = 4102444740))
        )
        fun issue(value: GuidedWalkingTrial.Issue?): String {
            if (value == null) return "ok"
            val words = value.name.lowercase(java.util.Locale.ROOT).split("_")
            return words.first() + words.drop(1).joinToString("") { it.replaceFirstChar(Char::uppercaseChar) }
        }
        return cases.joinToString("\n") { case ->
            val value = result(case.samples, case.start, case.end)
            "${case.name}|${issue(value.issue)}|${value.retainedTicks ?: "-"}|${value.observedStartTs ?: "-"}|${value.observedEndTs ?: "-"}|${value.sampleCount}|${if (value.usesActivityClasses) 1 else 0}"
        }
    }
    @Test fun compiledSwiftOracle() { assertEquals(EXPECTED_ORACLE, oracleTranscript()) }
    companion object {
        // Actual compiled Swift stdout; Swift reverse-pins the same literal.
        val EXPECTED_ORACLE = """
            classed|ok|116|1000|1060|61|1
            legacy|ok|116|1000|1060|61|0
            run|ok|116|1000|1060|61|1
            dedup|ok|116|1000|1060|61|1
            conflict|conflictingSample|-|1000|1008|9|0
            invalid-counter|invalidCounter|-|1000|1019|20|0
            invalid-ts|invalidTimestamp|-|-|-|0|0
            invalid-window|invalidWindow|-|-|-|0|0
            short|invalidDuration|-|-|-|0|0
            long|invalidDuration|-|-|-|0|0
            empty|insufficientSamples|-|-|-|0|0
            coverage|incompleteCoverage|-|1004|1060|57|1
            edge3|ok|116|1003|1063|61|1
            gap5|ok|116|1000|1060|57|1
            gap6|sampleGap|-|1000|1060|56|1
            drop|counterDecreased|-|1000|1060|61|1
            rate5|implausibleIncrement|-|1000|1060|61|1
            delta512|implausibleIncrement|-|1000|1060|61|1
            still|nonWalkingIncrement|-|1000|1060|61|1
            moving-start|movingBoundary|-|1000|1060|61|1
            moving-end|movingBoundary|-|1000|1060|61|1
            zero|noMovement|-|1000|1060|61|0
            max-duration|ok|7196|1000|4600|3601|1
            unix-ceiling|ok|116|4102444740|4102444800|61|1
        """.trimIndent()
    }

}
