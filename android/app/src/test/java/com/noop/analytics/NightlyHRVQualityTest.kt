package com.noop.analytics

import com.noop.data.RrInterval
import org.junit.Assert.*
import org.junit.Test

class NightlyHRVQualityTest {
    private fun beats(n: Int, start: Long = 0, step: Long = 1, halfSwing: Int = 20) =
        (0 until n).map { RrInterval("test", start + it * step, 1_000 + if (it % 2 == 0) -halfSwing else halfSwing) }

    // Literal stdout from the compiled Swift implementation over these six input cases.
    @Test fun matchesCompiledSwiftOracle() {
        val mixed = beats(300) + beats(20, 300, halfSwing = 50)
        val dropped = beats(30).toMutableList().also { it[10] = RrInterval("test", 10, 0) }
        val doubled = (0 until 300).flatMap { listOf(RrInterval("test", it.toLong(), 980), RrInterval("test", it.toLong(), 1_020)) }
        val cases = listOf(Triple(600L, beats(600), 40.0), Triple(600L, mixed, 70.0),
            Triple(320L, mixed, 70.0), Triple(300L, beats(20, step = 15), 40.0),
            Triple(300L, dropped, 40.0), Triple(600L, doubled, 40.0))
        val expected = listOf(
            "hrv quality experimental=true original=40.00ms candidate=40.00ms coveragePct=100 windows=2/2 input=600 rejected=0 pairs=598 longGaps=0 overCounted=false",
            "hrv quality experimental=true original=70.00ms candidate=43.75ms coveragePct=53 windows=2/2 input=320 rejected=0 pairs=318 longGaps=0 overCounted=false",
            "hrv quality experimental=true original=70.00ms candidate=43.75ms coveragePct=100 windows=2/2 input=320 rejected=0 pairs=318 longGaps=0 overCounted=false",
            "hrv quality experimental=true original=40.00ms candidate=nil coveragePct=0 windows=0/1 input=20 rejected=0 pairs=0 longGaps=19 overCounted=false",
            "hrv quality experimental=true original=40.00ms candidate=40.00ms coveragePct=10 windows=1/1 input=30 rejected=1 pairs=27 longGaps=0 overCounted=false",
            "hrv quality experimental=true original=40.00ms candidate=nil coveragePct=0 windows=0/2 input=600 rejected=0 pairs=599 longGaps=0 overCounted=true",
        )
        val actual = cases.map { (end, rr, old) -> NightlyHRVQuality.analyze(0, end, rr).trace(old) }
        assertEquals(expected, actual)
    }

    @Test fun denseCleanWindowsKeepTheMeasuredRMSSD() {
        val r = NightlyHRVQuality.analyze(0, 600, beats(600))
        assertEquals(40.0, r.weightedRMSSD!!, 1e-9)
        assertEquals(1.0, r.coverage, 1e-9)
        assertEquals(2, r.usableWindows)
    }

    @Test fun sparseWindowCannotHaveTheSameWeightAsFiveMinutesOfCleanBeats() {
        val r = NightlyHRVQuality.analyze(0, 600, beats(300) + beats(20, 300, halfSwing = 50))
        assertEquals(43.75, r.weightedRMSSD!!, 1e-9)
        assertEquals(8.0 / 15.0, r.coverage, 1e-9)
    }

    @Test fun shortFinalWindowIsWeightedByEvidenceDuration() {
        val r = NightlyHRVQuality.analyze(0, 320, beats(300) + beats(20, 300, halfSwing = 50))
        assertEquals(43.75, r.weightedRMSSD!!, 1e-9)
        assertEquals(1.0, r.coverage, 1e-9)
    }

    @Test fun longTimestampGapsDoNotBecomeSuccessiveHeartbeats() {
        val r = NightlyHRVQuality.analyze(0, 300, beats(20, step = 15))
        assertNull(r.weightedRMSSD)
        assertEquals(19, r.longGaps)
        assertEquals(0, r.usablePairs)
    }

    @Test fun droppedBeatCannotBeSplicedIntoRMSSD() {
        val rr = beats(30).toMutableList()
        rr[10] = RrInterval("test", 10, 0)
        val r = NightlyHRVQuality.analyze(0, 300, rr)
        assertEquals(40.0, r.weightedRMSSD!!, 1e-9)
        assertEquals(1, r.rejectedBeats)
        assertEquals(27, r.usablePairs)
    }

    @Test fun rejectionAndBrokenAdjacencyReduceRelativeWindowWeight() {
        val second = beats(300, 300, halfSwing = 50).toMutableList()
        for (i in 0 until 300 step 10) second[i] = RrInterval("test", 300L + i, 0)
        val r = NightlyHRVQuality.analyze(0, 600, beats(300) + second)
        // Independent arithmetic: second weight = 271.5 * 0.9 * 240/269;
        // the combined 40ms/100ms estimate is 189425/2903 ms.
        assertEquals(65.25146400275577, r.weightedRMSSD!!, 1e-9)
        assertEquals(30, r.rejectedBeats)
        assertEquals(539, r.usablePairs)
        assertEquals(2, r.usableWindows)
    }

    @Test fun overCountedNightCannotBeResurrected() {
        val rr = (0 until 300).flatMap { listOf(RrInterval("test", it.toLong(), 980), RrInterval("test", it.toLong(), 1_020)) }
        val r = NightlyHRVQuality.analyze(0, 600, rr)
        assertNull(r.weightedRMSSD)
        assertTrue(r.overCounted)
    }

    @Test fun localOverCountIsDetectedDespiteMissingRestOfNight() {
        val rr = (0 until 150).flatMap { listOf(RrInterval("test", it.toLong(), 980), RrInterval("test", it.toLong(), 1_020)) } + beats(20, 900)
        val r = NightlyHRVQuality.analyze(0, 1_200, rr)
        assertFalse(r.overCounted)
        assertEquals(1, r.usableWindows)
        assertEquals(40.0, r.weightedRMSSD!!, 1e-9)
    }

    @Test fun orderingAndBoundsAreAppliedBeforeAnalysis() {
        val rr = beats(300).reversed() + listOf(RrInterval("test", -1, 1_900), RrInterval("test", 301, 1_900))
        val r = NightlyHRVQuality.analyze(0, 300, rr)
        assertEquals(40.0, r.weightedRMSSD!!, 1e-9)
        assertEquals(300, r.inputBeats)
    }

    @Test fun invalidAndEmptySessionsHaveNoCandidate() {
        for ((start, end) in listOf(0L to 0L, 10L to 0L, 0L to 200_000L, Long.MIN_VALUE to Long.MAX_VALUE)) {
            assertNull(NightlyHRVQuality.analyze(start, end, beats(30)).weightedRMSSD)
        }
        assertEquals(0.0, NightlyHRVQuality.analyze(0, 600, emptyList()).coverage, 0.0)
    }

    @Test fun sameSecondOrderSurvivesStableSorting() {
        val rr = (0 until 300).flatMap { listOf(RrInterval("test", it.toLong(), 490), RrInterval("test", it.toLong(), 510)) }
        val r = NightlyHRVQuality.analyze(0, 300, rr)
        assertEquals(20.0, r.weightedRMSSD!!, 1e-9)
        assertFalse(r.overCounted)
    }
}
