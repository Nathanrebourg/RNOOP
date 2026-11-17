package com.noop.analytics

import com.noop.data.HrSample
import org.junit.Assert.*
import org.junit.Test

class EffortCadenceComparisonTest {
    private fun series(count: Int, start: Long = 0, step: Long = 1, bpm: Int = 170) =
        (0 until count).map { HrSample("test", start + it * step, bpm) }

    // Literal stdout from the compiled Swift scorer and cadence experiment on these exact inputs.
    @Test fun matchesCompiledSwiftOracle() {
        val dense = series(601)
        val gapped = series(300) + series(301, 3_600)
        val sparse = series(21, step = 30)
        val switched = series(10) + series(21, 39, 30)
        val unknown = series(20, step = 3_600)
        val duplicated = dense.flatMap { listOf(it, it, it) }
        val conflict = dense + HrSample("test", 300, 180)
        val actual = listOf(dense, gapped, sparse, switched, unknown, duplicated, conflict).map { hr ->
            EffortCadenceComparison.analyze(hr, maxHR = 190.0).trace(StrainScorer.strain(hr, maxHR = 190.0))
        }.toMutableList()
        for (sex in listOf("male", "female")) {
            actual.add(EffortCadenceComparison.analyze(gapped, maxHR = 190.0,
                method = StrainScorer.Method.BANISTER, sex = sex).trace(StrainScorer.strain(gapped,
                maxHR = 190.0, method = StrainScorer.Method.BANISTER, sex = sex)))
        }
        val expected = listOf(
            "effort cadence experimental=true scale=0-100 original=41.83 candidate=41.83 supportedSec=600.00 tailSec=1.00 unsupportedSec=0.00 readings=601 duplicates=0 ambiguous=0 invalid=0 clipped=0 configValid=true",
            "effort cadence experimental=true scale=0-100 original=43.82 candidate=41.85 supportedSec=601.00 tailSec=1.00 unsupportedSec=3299.00 readings=601 duplicates=0 ambiguous=0 invalid=0 clipped=1 configValid=true",
            "effort cadence experimental=true scale=0-100 original=42.35 candidate=42.35 supportedSec=600.00 tailSec=30.00 unsupportedSec=0.00 readings=21 duplicates=0 ambiguous=0 invalid=0 clipped=0 configValid=true",
            "effort cadence experimental=true scale=0-100 original=43.01 candidate=43.01 supportedSec=639.00 tailSec=30.00 unsupportedSec=0.00 readings=31 duplicates=0 ambiguous=0 invalid=0 clipped=0 configValid=true",
            "effort cadence experimental=true scale=0-100 original=57.21 candidate=nil supportedSec=0.00 tailSec=0.00 unsupportedSec=68400.00 readings=20 duplicates=0 ambiguous=0 invalid=0 clipped=19 configValid=true",
            "effort cadence experimental=true scale=0-100 original=54.01 candidate=41.83 supportedSec=600.00 tailSec=1.00 unsupportedSec=0.00 readings=601 duplicates=1202 ambiguous=0 invalid=0 clipped=0 configValid=true",
            "effort cadence experimental=true scale=0-100 original=45.91 candidate=41.83 supportedSec=600.00 tailSec=1.00 unsupportedSec=0.00 readings=600 duplicates=0 ambiguous=1 invalid=0 clipped=0 configValid=true",
            "effort cadence experimental=true scale=0-100 original=40.08 candidate=38.10 supportedSec=601.00 tailSec=1.00 unsupportedSec=3299.00 readings=601 duplicates=0 ambiguous=0 invalid=0 clipped=1 configValid=true",
            "effort cadence experimental=true scale=0-100 original=40.76 candidate=38.78 supportedSec=601.00 tailSec=1.00 unsupportedSec=3299.00 readings=601 duplicates=0 ambiguous=0 invalid=0 clipped=1 configValid=true",
        )
        assertEquals(expected, actual)
    }

    @Test fun regularCadencesKeepTheIncumbentCalculation() {
        for ((count, step) in listOf(601 to 1L, 61 to 10L, 21 to 30L, 21 to 60L)) {
            val hr = series(count, step = step)
            val r = EffortCadenceComparison.analyze(hr, maxHR = 190.0)
            assertEquals(List(count) { step.toDouble() }, r.durationsSeconds)
            assertEquals(StrainScorer.strain(hr, maxHR = 190.0), r.candidateScore)
            assertEquals(0, r.gapsClipped)
        }
    }

    @Test fun denseDropoutCannotCreditTwoMinutesOfHardEffort() {
        val hr = series(300) + series(301, 3_600)
        val r = EffortCadenceComparison.analyze(hr, maxHR = 190.0)
        assertEquals(2.0, r.durationsSeconds[299], 0.0)
        assertEquals(601.0, r.supportedSeconds, 0.0)
        assertEquals(602.0, r.creditedSeconds, 0.0)
        assertEquals(3_299.0, r.unsupportedSeconds, 0.0)
        assertEquals(1, r.gapsClipped)
        assertTrue(r.candidateScore!! < StrainScorer.strain(hr, maxHR = 190.0)!!)
    }

    @Test fun sparseDropoutUsesThirtySecondCadence() {
        val r = EffortCadenceComparison.analyze(series(21, step = 30) + series(21, 3_600, 30), maxHR = 190.0)
        assertEquals(60.0, r.durationsSeconds[20], 0.0)
        assertEquals(30.0, r.durationsSeconds.last(), 0.0)
        assertNotNull(r.candidateScore)
    }

    @Test fun cadenceChangeKeepsTheFollowingSparseBlock() {
        val hr = series(10) + series(21, 39, 30)
        val r = EffortCadenceComparison.analyze(hr, maxHR = 190.0)
        assertEquals(30.0, r.durationsSeconds[9], 0.0)
        assertEquals(0, r.gapsClipped)
        assertEquals(StrainScorer.strain(hr, maxHR = 190.0), r.candidateScore)
    }

    @Test fun elapsedSpanAloneDoesNotQualifyDisconnectedReadings() {
        val hr = series(20, step = 3_600)
        assertNotNull(StrainScorer.strain(hr, maxHR = 190.0))
        val r = EffortCadenceComparison.analyze(hr, maxHR = 190.0)
        assertNull(r.candidateScore)
        assertEquals(0.0, r.creditedSeconds, 0.0)
    }

    @Test fun tailDoesNotRepeatTheDropoutDuration() {
        val r = EffortCadenceComparison.analyze(series(601) + HrSample("test", 3_600, 170), maxHR = 190.0)
        assertEquals(listOf(2.0, 1.0), r.durationsSeconds.takeLast(2))
        assertEquals(602.0, r.supportedSeconds, 0.0)
    }

    @Test fun duplicateDeliveriesDoNotInventTime() {
        val clean = series(601)
        val r = EffortCadenceComparison.analyze(clean.flatMap { listOf(it, it, it) }, maxHR = 190.0)
        assertEquals(1_202, r.duplicatesRemoved)
        assertEquals(601, r.uniqueReadings)
        assertEquals(EffortCadenceComparison.analyze(clean, maxHR = 190.0).candidateScore, r.candidateScore)
    }

    @Test fun conflictingTimestampIsExcluded() {
        val r = EffortCadenceComparison.analyze(series(601) + HrSample("test", 300, 180), maxHR = 190.0)
        assertEquals(1, r.ambiguousTimestamps)
        assertEquals(600, r.uniqueReadings)
        assertEquals(600.0, r.supportedSeconds, 0.0)
    }

    @Test fun sortingAndInvalidReadingsDoNotChangeCleanEvidence() {
        val r = EffortCadenceComparison.analyze(series(601).reversed() + HrSample("test", 90, 0), maxHR = 190.0)
        assertEquals(1, r.invalidReadings)
        assertEquals(EffortCadenceComparison.analyze(series(601), maxHR = 190.0).candidateScore, r.candidateScore)
    }

    @Test fun realHighReadingsAreNotSmoothedAway() {
        val sustained = EffortCadenceComparison.analyze(series(301, bpm = 80) + series(300, 301), maxHR = 190.0)
        assertEquals(20.0, sustained.candidateTRIMP!!, 1e-9)
        val isolated = series(601, bpm = 80).toMutableList().also { it[300] = HrSample("test", 300, 170) }
        assertEquals(1.0 / 15.0, EffortCadenceComparison.analyze(isolated, maxHR = 190.0).candidateTRIMP!!, 1e-9)
    }

    @Test fun banisterSexCalibrationIsPreserved() {
        for (sex in listOf("male", "female")) {
            val hr = series(601)
            assertEquals(StrainScorer.strain(hr, maxHR = 190.0, method = StrainScorer.Method.BANISTER, sex = sex),
                EffortCadenceComparison.analyze(hr, maxHR = 190.0, method = StrainScorer.Method.BANISTER, sex = sex).candidateScore)
        }
    }

    @Test fun insufficientAndInvalidInputStayUnscored() {
        assertNull(EffortCadenceComparison.analyze(emptyList(), maxHR = 190.0).candidateScore)
        assertNull(EffortCadenceComparison.analyze(series(20, step = 30), maxHR = 190.0).candidateScore)
        assertNull(EffortCadenceComparison.analyze(series(601), maxHR = 60.0).candidateScore)
        assertNull(EffortCadenceComparison.analyze(series(601), maxHR = Double.NaN).candidateScore)
        assertNull(EffortCadenceComparison.analyze(series(601), maxHR = 190.0, denominator = 1.0).candidateScore)
    }

    @Test fun enablingComparisonInvalidatesAnUnchangedCachedDayOnlyOnce() {
        fun key(active: Boolean) = AnalyzeRecentDayCache.cacheKey("whoop5", 601, 3_900, null,
            "unchanged|rrAlias5=true", false, effortCadenceTrace = active)
        val off = key(false)
        val on = key(true)
        assertNotEquals(off, on)
        assertEquals(on, key(true))
        assertEquals(off, key(false))
        assertEquals("effortTrace", AnalyzeRecentDayCache.missReason(off, on))
    }

    @Test fun freshAndCachedComparisonsUseTheSameChannelAndStopWhenDisabled() {
        val line = EffortCadenceComparison.analyze(series(601), maxHR = 190.0).trace(41.83)
        val stored = listOf(line, "effort score day=2026-11-14")
        val ordinary = ArrayList<String>()
        val comparison = ArrayList<String>()
        repeat(2) {
            ordinary.clear(); comparison.clear()
            stored.forEach { EffortCadenceComparison.replayDiagnostic(it, { ordinary.add(it) }, { comparison.add(it) }) }
            assertEquals(listOf(line), comparison)
            assertEquals(listOf("effort score day=2026-11-14"), ordinary)
        }
        ordinary.clear()
        stored.forEach { EffortCadenceComparison.replayDiagnostic(it, { ordinary.add(it) }, null) }
        assertEquals(listOf("effort score day=2026-11-14"), ordinary)
    }
}
