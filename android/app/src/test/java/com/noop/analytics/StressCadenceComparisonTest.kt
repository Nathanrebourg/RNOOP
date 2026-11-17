package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import org.junit.Assert.*
import org.junit.Test

class StressCadenceComparisonTest {
    private val day = 1_728_000_000L
    private val start get() = day + 6 * 3_600
    private fun hr(hours: Int = 4, spike: Boolean = false) = (0 until hours * 3_600).map {
        HrSample("test", start + it, if (spike && it in (3 * 3_600 + 1_800) until (3 * 3_600 + 2_100)) 100 else 70)
    }
    private fun motion(hours: Int = 4) = (0 until hours * 3_600).map { GravitySample("test", start + it, 0.0, 0.0, 1.0) }
    private fun analyze(h: List<HrSample>, g: List<GravitySample>, now: Long = start + 4 * 3_600, capped: Boolean = false) =
        StressCadenceComparison.analyze(h, g, day, now, readCapped = capped)
    @Test fun denseFlatDayHasFortyEightNonOverlappingBaselineWindows() {
        val r = analyze(hr(), motion())
        assertEquals("compared", r.status)
        val scored = r.points.filter { it.level != null }
        assertEquals(48, scored.size)
        assertTrue(scored.all { it.level == 1.5 && it.end - it.start == 300L })
        assertTrue(scored.zipWithNext().all { (a,b) -> a.end <= b.start })
        assertEquals(0, r.candidateHighMinutes)
    }
    @Test fun fiveMinuteSpikeIsPreservedWithoutSmearingIntoAnHour() {
        val r = analyze(hr(spike = true), motion())
        val peak = r.points.first { it.start == start + 3 * 3_600 + 1_800 }
        assertTrue(peak.level!! > peak.originalLevel!!)
        assertEquals(5, r.candidateHighMinutes)
        assertEquals(1, r.points.count { (it.level ?: 0.0) >= 2 })
        assertEquals(1.5, r.points.first { it.start == peak.end }.level!!, 0.0)
    }
    @Test fun noMotionIsUnavailableInsteadOfCalm() {
        val r = analyze(hr(), emptyList())
        assertEquals("no-motion", r.status)
        assertTrue(r.points.all { it.level == null })
    }
    @Test fun repeatedTimestampCannotInventFiveMinutesOfCoverage() {
        val h = hr().filter { it.ts % 300 == 0L }.flatMap { row -> List(300) { row } }
        assertTrue(analyze(h, motion()).points.all { it.level == null })
    }
    @Test fun conflictingDuplicatesAreExcludedWithoutArbitrarySelection() {
        val h = hr()
        val r = analyze(h + h.filter { it.ts < start + 300 }.map { it.copy(bpm = 200) }, motion())
        assertNull(r.points.first().level)
        assertEquals(47, r.points.drop(1).count { it.level != null })
    }
    @Test fun longInternalGapFailsEvenWhenRawCountIsHighEnough() {
        val h = hr().filter { it.ts !in (start + 120) until (start + 150) }
        val r = analyze(h, motion())
        assertEquals("hr-coverage", r.points.first().status)
        assertNull(r.points.first().level)
    }
    @Test fun sparseMotionCannotProveNoExertion() {
        val r = analyze(hr(), motion().filter { it.ts % 60 == 0L })
        assertTrue(r.points.all { it.level == null })
        assertTrue(r.points.any { it.status == "motion-coverage" })
    }
    @Test fun incompleteAndFutureWindowsNeverScore() {
        val r = analyze(hr(), motion(), now = start + 3 * 3_600 + 299)
        assertEquals(start + 3 * 3_600, r.points.last().end)
        assertEquals(36, r.points.count { it.level != null })
    }
    @Test fun insufficientReferenceDoesNotInventAStableBaseline() {
        val r = analyze(hr(2), motion(2), now = start + 2 * 3_600)
        assertEquals("insufficient-reference", r.status)
        assertTrue(r.points.all { it.level == null })
    }
    @Test fun walkingAndElevatedRecoveryAreMasked() {
        val h = hr().map { it.copy(bpm = if (it.ts >= start + 3_600 && it.ts < start + 3 * 3_600) 100 else 70) }
        val g = motion().mapIndexed { i, s -> s.copy(x = if (i in 3_600 until 7_200 && i % 2 == 0) 1.0 else 0.0) }
        val r = analyze(h,g)
        assertTrue(r.points.filter { it.start >= start + 3_600 && it.start < start + 3 * 3_600 }.all { it.level == null })
        assertTrue(r.points.filter { it.start >= start + 3 * 3_600 }.all { it.level != null })
    }
    @Test fun sameSecondCopiesAndOrderingDoNotChangeTheRead() {
        val clean = analyze(hr(spike = true), motion())
        val r = analyze(hr(spike = true).flatMap { listOf(it,it) }.reversed(), motion().reversed())
        assertEquals(clean.points,r.points)
        assertEquals(clean.candidateHighMinutes,r.candidateHighMinutes)
    }
    @Test fun cappedReadNeverProducesCandidateValues() {
        val r = analyze(hr(),motion(),capped = true)
        assertEquals("read-capped",r.status)
        assertTrue(r.points.all { it.level == null })
    }
    @Test fun existingHourlyScoresAreUnchangedByTheComparison() {
        val h = hr(spike = true); val g = motion()
        val original = DaytimeStress.analyze(h, emptyList(), g, includeTimeline = true)
        analyze(h,g)
        assertEquals(original,DaytimeStress.analyze(h,emptyList(),g,includeTimeline = true))
    }
    @Test fun unrepresentableGravityCannotTrapTheIncumbentFingerprint() {
        val r = analyze(hr(),motion().map { it.copy(x = 1e300) })
        assertEquals("no-motion",r.status)
        assertTrue(r.points.all { it.level == null })
    }

    @Test fun coverageThresholdAcceptsDistributedMissingSecondsButRejectsTooFew() {
        val h = hr().filter { it.ts % 5 != 0L }
        assertEquals(48,analyze(h,motion()).points.count { it.level != null })
        assertTrue(analyze(h.filter { it.ts % 300 != 1L },motion()).points.all { it.level == null })
    }
    @Test fun conflictingGravityCannotProveStillness() {
        val g = motion()
        val r = analyze(hr(),g + g.filter { it.ts < start + 300 }.map { it.copy(x = 1.0) })
        assertEquals("motion-coverage",r.points.first().status)
        assertEquals(47,r.points.drop(1).count { it.level != null })
    }
    @Test fun briefWalkHasBoundedUnchainedRecoveryShadow() {
        val h = hr(5).map { it.copy(bpm = if (it.ts >= start + 10_800) 100 else 70) }
        val g = motion(5).mapIndexed { i,s -> s.copy(x = if (i in 10_800 until 11_100 && i % 2 == 0) 1.0 else 0.0) }
        val r = analyze(h,g,now = start + 18_000)
        assertEquals("activity",r.points.first { it.start == start + 10_800 }.status)
        assertEquals("post-activity",r.points.first { it.start == start + 14_400 }.status)
        assertEquals("scored",r.points.first { it.start == start + 14_700 }.status)
    }
    @Test fun localGridSupportsHalfHourOffsetsWithoutChangingLevels() {
        val offset = 19_800L
        val base = analyze(hr(spike = true),motion())
        val shifted = StressCadenceComparison.analyze(hr(spike = true).map { it.copy(ts = it.ts - offset) },
            motion().map { it.copy(ts = it.ts - offset) },day - offset,start + 14_400 - offset,offset)
        assertEquals(base.points.map { it.level },shifted.points.map { it.level })
        assertEquals(start - offset,shifted.points.first().start)
        assertEquals(5,shifted.candidateHighMinutes)
    }

    @Test fun matchesCompiledSwiftOracle() {
        val actual = ArrayList<String>()
        for (i in 0 until 10) {
            var h = hr(spike = i == 1 || i == 8); var g = motion(); var now = start + 14_400
            var dayStart = day; var offset = 0L
            when (i) {
                2 -> h = h.filter { it.ts !in (start + 120) until (start + 150) }
                3 -> g = g.filter { it.ts % 60 == 0L }
                4 -> g = emptyList()
                5 -> { h = hr(2); g = motion(2); now = start + 7_200 }
                7 -> {
                    h = hr(5).map { it.copy(bpm = if (it.ts >= start + 10_800) 100 else 70) }
                    g = motion(5).mapIndexed { n,s -> s.copy(x = if (n in 10_800 until 11_100 && n % 2 == 0) 1.0 else 0.0) }
                    now = start + 18_000
                }
                8 -> {
                    offset = 19_800; dayStart -= offset; now -= offset
                    h = h.map { it.copy(ts = it.ts - offset) }; g = g.map { it.copy(ts = it.ts - offset) }
                }
                9 -> g = g.map { it.copy(x = 1e300) }
            }
            val lines = StressCadenceComparison.analyze(h,g,dayStart,now,offset,readCapped = i == 6).lines("2024-10-04")
            actual.add(lines.first())
            if (i == 1) actual.addAll(lines.drop(1))
        }
        // Literal stdout from an executable linked to the real compiled Swift analytics modules.
        val expected = listOf(
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=48 matched=48 referenceHours=4 referenceBpm=70.00 referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=1.50 originalPeakMatched=1.50 detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=48 matched=48 referenceHours=4 referenceBpm=70.00 referenceSpread=1.08 candidateHighMin=5 candidateHighMatchedMin=5 originalHighMatchedMin=60 candidatePeak=3.00 originalPeakMatched=2.73 detail=last12 noAlerts=true",
            "stress cadence point experimental=true day=2024-10-04 start=1728032400 end=1728032700 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728032700 end=1728033000 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728033000 end=1728033300 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728033300 end=1728033600 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728033600 end=1728033900 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728033900 end=1728034200 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728034200 end=1728034500 status=scored original=2.73 candidate=3.00",
            "stress cadence point experimental=true day=2024-10-04 start=1728034500 end=1728034800 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728034800 end=1728035100 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728035100 end=1728035400 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728035400 end=1728035700 status=scored original=2.73 candidate=1.50",
            "stress cadence point experimental=true day=2024-10-04 start=1728035700 end=1728036000 status=scored original=2.73 candidate=1.50",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=47 matched=47 referenceHours=4 referenceBpm=70.00 referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=1.50 originalPeakMatched=1.50 detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=0 matched=0 referenceHours=4 referenceBpm=70.00 referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=nil originalPeakMatched=nil detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=no-motion windowSec=300 windows=0 scored=0 matched=0 referenceHours=0 referenceBpm=nil referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=nil originalPeakMatched=nil detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=insufficient-reference windowSec=300 windows=24 scored=0 matched=0 referenceHours=2 referenceBpm=70.00 referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=nil originalPeakMatched=nil detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=read-capped windowSec=300 windows=0 scored=0 matched=0 referenceHours=0 referenceBpm=nil referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=nil originalPeakMatched=nil detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=60 scored=47 matched=47 referenceHours=5 referenceBpm=70.00 referenceSpread=14.70 candidateHighMin=55 candidateHighMatchedMin=55 originalHighMatchedMin=55 candidatePeak=2.66 originalPeakMatched=2.66 detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=compared windowSec=300 windows=48 scored=48 matched=48 referenceHours=4 referenceBpm=70.00 referenceSpread=1.08 candidateHighMin=5 candidateHighMatchedMin=5 originalHighMatchedMin=60 candidatePeak=3.00 originalPeakMatched=2.73 detail=last12 noAlerts=true",
            "stress cadence experimental=true scope=day-relative-hr-only day=2024-10-04 scale=0-3 status=no-motion windowSec=300 windows=0 scored=0 matched=0 referenceHours=0 referenceBpm=nil referenceSpread=0.00 candidateHighMin=0 candidateHighMatchedMin=0 originalHighMatchedMin=0 candidatePeak=nil originalPeakMatched=nil detail=last12 noAlerts=true"
        )
        assertEquals(expected,actual)
    }

}
