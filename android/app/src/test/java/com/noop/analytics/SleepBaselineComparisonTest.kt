package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import org.junit.Assert.*
import org.junit.Test

class SleepBaselineComparisonTest {
    private val day = 1_728_000_000L
    private fun rows(w: SleepBaselineComparison.Window, bpm: Int = 55, step: Long = 60) =
        (w.start until w.end step step).map { HrSample("test", it, bpm) }
    private fun history(before: Long, bpm: Int = 55) = SleepBaselineComparison.historyWindows(before, 0).take(3)
        .mapNotNull { SleepBaselineComparison.observation(rows(it, bpm), it) }
    @Test fun historyWindowsArePriorDisjointLocalMidnightToSix() {
        for (offset in listOf(0L, 19_800L, -18_000L)) {
            val w = SleepBaselineComparison.historyWindows(day, offset)
            assertEquals(14, w.size)
            assertTrue(w.all { it.end <= day && it.end - it.start == 21_600L })
            assertTrue(w.all { (it.start + offset) % 86_400 == 0L })
            assertEquals(86_400L, w[0].start - w[1].start)
        }
    }
    @Test fun nightWeightsMinutesRatherThanDeliveryDensity() {
        val w = SleepBaselineComparison.historyWindows(day, 0)[0]
        val sparse = rows(w, 50).filter { it.ts >= w.start + 3_600 }
        val dense = (0 until 3_600).map { HrSample("test", w.start + it, 100) }
        val r = SleepBaselineComparison.observation(sparse + dense, w)!!
        assertEquals(50.0, r.medianBPM, 0.0)
        assertEquals(360, r.minutes)
    }
    @Test fun duplicatesAndOutsideRowsCannotCreateCoverage() {
        val w = SleepBaselineComparison.historyWindows(day, 0)[0]
        val brief = rows(w).take(60)
        assertNull(SleepBaselineComparison.observation(List(10) { brief }.flatten() + HrSample("test", w.end, 55), w))
        assertNull(SleepBaselineComparison.observation(rows(w, 0), w))
    }
    @Test fun conflictingTimestampIsExcludedAndCoverageIsRequired() {
        val w = SleepBaselineComparison.historyWindows(day, 0)[0]
        val clean = rows(w)
        assertNull(SleepBaselineComparison.observation(clean + clean.map { it.copy(bpm = 100) }, w))
        assertNull(SleepBaselineComparison.observation(clean.take(180), w))
        assertEquals(360, SleepBaselineComparison.observation(clean + clean, w)!!.minutes)
    }
    @Test fun referenceNeedsThreeDistinctPriorNightsAndRejectsStaleOrFuture() {
        val h = history(day)
        assertNull(SleepBaselineComparison.reference(h.take(2), day, 0).bpm)
        assertNull(SleepBaselineComparison.reference(List(3) { h[0] }, day, 0).bpm)
        val invalid = listOf(SleepBaselineComparison.Observation(day + 1, 200.0, 360),
            SleepBaselineComparison.Observation(day - 30 * 86_400, 200.0, 360))
        val r = SleepBaselineComparison.reference(h + invalid, day, 0)
        assertEquals(55.0, r.bpm!!, 0.0)
        assertEquals(3, r.nights)
    }
    @Test fun medianOfNightsIsRobustAndKeepsExistingFloor() {
        val h = history(day).zip(listOf(30.0, 35.0, 190.0)) { o, bpm -> o.copy(medianBPM = bpm) }
        assertEquals(40.0, SleepBaselineComparison.reference(h, day, 0).bpm!!, 0.0)
    }
    @Test fun insufficientHistoryDoesNotInventAZeroCandidate() {
        val r = SleepBaselineComparison.compare(day, day - 108_000, emptyList(), emptyList(), gravity = emptyList())
        assertNull(r.candidate)
        assertNull(r.original)
        assertTrue(r.trace("2024-10-04").contains("status=insufficient-history"))
    }
    @Test fun realDetectorUsesPersonalReferenceWithoutChangingOriginal() {
        val before = day - 108_000; val start = day + 3_600
        val hr = (0 until 5_400).map { HrSample("test", start + it, 65) }
        val grav = (0 until 5_400 step 60).map { GravitySample("test", start + it, 0.0, 0.0, 1.0) }
        val original = SleepStager.detectSleep(hr = hr, gravity = grav)
        assertTrue(original.isNotEmpty())
        val r = SleepBaselineComparison.compare(day, before, history(before, 50), hr, gravity = grav)
        assertEquals(original, r.original)
        assertEquals(emptyList<DetectedSleep>(), r.candidate)
        assertEquals(original, SleepStager.detectSleep(hr = hr, gravity = grav))
    }
    @Test fun lowRateNightAndDenseStillnessArePreserved() {
        val before = day - 108_000; val start = day + 3_600
        val hr = (0 until 5_400).map { HrSample("test", start + it, 50) }
        val grav = (0 until 5_400).map { GravitySample("test", start + it, 0.0, 0.0, 1.0) }
        val r = SleepBaselineComparison.compare(day, before, history(before), hr, gravity = grav, useSleepStagerV2 = true)
        assertTrue(r.candidate!!.isNotEmpty())
        assertEquals(r.original, r.candidate)
    }
    @Test fun explicitOffWristStillRejectsBothVariants() {
        val before = day - 108_000; val start = day + 3_600
        val hr = (0 until 5_400).map { HrSample("test", start + it, 50) }
        val grav = (0 until 5_400).map { GravitySample("test", start + it, 0.0, 0.0, 1.0) }
        val r = SleepBaselineComparison.compare(day, before, history(before), hr, gravity = grav, wristOff = listOf(start to start + 5_400))
        assertEquals(emptyList<DetectedSleep>(), r.original)
        assertEquals(emptyList<DetectedSleep>(), r.candidate)
    }
    @Test fun qualifiedHistoryWithMissingMotionIsExplicitlySkipped() {
        val before = day - 108_000
        val r = SleepBaselineComparison.compare(day, before, history(before), emptyList(), gravity = emptyList())
        assertEquals("no-motion", r.status)
        assertEquals(55.0, r.reference.bpm!!, 0.0)
        assertNull(r.candidate)
    }
    @Test fun cappedReadCannotProduceAComparison() {
        val before = day - 108_000
        val r = SleepBaselineComparison.compare(day, before, history(before), emptyList(), gravity = emptyList(), readCapped = true)
        assertEquals("target-read-capped", r.status)
        assertNull(r.candidate)
    }
    @Test fun conflictingHistoryCopiesCannotChooseAnArbitraryBaseline() {
        val h = history(day)
        val r = SleepBaselineComparison.reference(h + h[0].copy(medianBPM = 90.0), day, 0)
        assertEquals(2, r.nights)
        assertNull(r.bpm)
    }
    @Test fun matchesCompiledSwiftOracle() {
        data class Case(val bpms: List<Int>, val bpm: Int, val step: Int,
                        val v2: Boolean = false, val off: Boolean = false, val capped: Boolean = false)
        val cases = listOf(
            Case(emptyList(), 50, 60), Case(listOf(55,55,55), 50, 0),
            Case(listOf(55,55,55), 50, 60, capped = true), Case(listOf(55,55,55), 50, 60),
            Case(listOf(50,50,50), 65, 60), Case(listOf(50,50,50), 65, 1),
            Case(listOf(30,35,190), 50, 60), Case(listOf(55,55,55), 50, 1, off = true),
            Case(listOf(55,55,55), 50, 1, v2 = true))
        val before = day - 108_000; val start = day + 3_600
        val actual = cases.map { c ->
            val h = SleepBaselineComparison.historyWindows(before, 0).zip(c.bpms) { w, bpm ->
                SleepBaselineComparison.observation(rows(w, bpm), w)!! }
            val hr = (0 until 5_400).map { HrSample("test", start + it, c.bpm) }
            val grav = if (c.step == 0) emptyList() else (0 until 5_400 step c.step)
                .map { GravitySample("test", start + it, 0.0, 0.0, 1.0) }
            SleepBaselineComparison.compare(day, before, h, hr, gravity = grav,
                wristOff = if (c.off) listOf(start to start + 5_400) else emptyList(),
                useSleepStagerV2 = c.v2, readCapped = c.capped).trace("2024-10-04")
        }
        // Literal stdout of the compiled Swift implementation, including the real V1/V2 detectors.
        val expected = listOf(
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=insufficient-history source=local00-06 nights=0 baselineBpm=nil originalSessions=nil candidateSessions=nil originalInBedSec=nil candidateInBedSec=nil originalAsleepSec=nil candidateAsleepSec=nil originalWindows=nil candidateWindows=nil",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=no-motion source=local00-06 nights=3 baselineBpm=55.00 originalSessions=nil candidateSessions=nil originalInBedSec=nil candidateInBedSec=nil originalAsleepSec=nil candidateAsleepSec=nil originalWindows=nil candidateWindows=nil",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=target-read-capped source=local00-06 nights=3 baselineBpm=55.00 originalSessions=nil candidateSessions=nil originalInBedSec=nil candidateInBedSec=nil originalAsleepSec=nil candidateAsleepSec=nil originalWindows=nil candidateWindows=nil",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=55.00 originalSessions=1 candidateSessions=1 originalInBedSec=5340 candidateInBedSec=5340 originalAsleepSec=0 candidateAsleepSec=0 originalWindows=1728003600:1728008940 candidateWindows=1728003600:1728008940",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=50.00 originalSessions=1 candidateSessions=0 originalInBedSec=5340 candidateInBedSec=0 originalAsleepSec=0 candidateAsleepSec=0 originalWindows=1728003600:1728008940 candidateWindows=none",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=50.00 originalSessions=1 candidateSessions=1 originalInBedSec=5399 candidateInBedSec=5399 originalAsleepSec=5399 candidateAsleepSec=5399 originalWindows=1728003600:1728008999 candidateWindows=1728003600:1728008999",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=40.00 originalSessions=1 candidateSessions=0 originalInBedSec=5340 candidateInBedSec=0 originalAsleepSec=0 candidateAsleepSec=0 originalWindows=1728003600:1728008940 candidateWindows=none",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=55.00 originalSessions=0 candidateSessions=0 originalInBedSec=0 candidateInBedSec=0 originalAsleepSec=0 candidateAsleepSec=0 originalWindows=none candidateWindows=none",
            "sleep baseline experimental=true scope=detector day=2024-10-04 status=compared source=local00-06 nights=3 baselineBpm=55.00 originalSessions=1 candidateSessions=1 originalInBedSec=5399 candidateInBedSec=5399 originalAsleepSec=5399 candidateAsleepSec=5399 originalWindows=1728003600:1728008999 candidateWindows=1728003600:1728008999"
        )
        assertEquals(expected, actual)
    }

}
