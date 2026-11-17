package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ManualStepCalibrationTest {
    private fun walk(id: String = "a", steps: Double = 1000.0, ticks: Double = 24000.0, confirmed: Boolean = true) =
        StepCalibration.Trial(id, steps, ticks, confirmed)
    private val repeatedWalks get() = listOf(walk("a"), walk("b", 1100.0, 26400.0), walk("c", 1200.0, 28800.0))

    @Test fun medianUsesIndependentWalksAndPreservesUnroundedFactor() {
        val result = StepCalibration.evaluate(repeatedWalks)
        assertNull(result.issue)
        assertEquals(24.0, result.factor)
        assertEquals(0.0, result.relativeSpread)
        val varied = listOf(walk("a", ticks = 23999.0), walk("b", ticks = 24001.0), walk("c", ticks = 24003.0))
        assertEquals(24.001, StepCalibration.evaluate(varied).factor)
        assertEquals(24.001, StepCalibration.evaluate(varied.reversed()).factor)
    }

    @Test fun rejectsNonFiniteFractionalZeroAndExtremeObservations() {
        for (v in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0, 99.0, 100.5, 10001.0, Double.MAX_VALUE)) {
            assertEquals(StepCalibration.Issue.INVALID_STEPS, StepCalibration.validate(walk(steps = v)))
        }
        for (v in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0, 1.5, 300001.0, Double.MAX_VALUE)) {
            assertEquals(StepCalibration.Issue.INVALID_TICKS, StepCalibration.validate(walk(ticks = v)))
        }
        assertEquals(StepCalibration.Issue.UNSUPPORTED_FACTOR, StepCalibration.validate(walk(ticks = 499.0)))
        assertEquals(StepCalibration.Issue.UNSUPPORTED_FACTOR, StepCalibration.validate(walk(ticks = 30001.0)))
        assertNull(StepCalibration.validate(walk(steps = 100.0, ticks = 50.0)))
        assertNull(StepCalibration.validate(walk(steps = 10000.0, ticks = 300000.0)))
    }

    @Test fun needsThreeDistinctConfirmedWalksAndCapsInput() {
        assertEquals(StepCalibration.Issue.INSUFFICIENT_TRIALS, StepCalibration.evaluate(emptyList()).issue)
        assertEquals(StepCalibration.Issue.INSUFFICIENT_TRIALS, StepCalibration.evaluate(repeatedWalks.take(2)).issue)
        assertEquals(StepCalibration.Issue.DUPLICATE_TRIAL, StepCalibration.evaluate(repeatedWalks + walk("d")).issue)
        assertEquals(StepCalibration.Issue.DUPLICATE_TRIAL, StepCalibration.evaluate(repeatedWalks + walk("a", 1300.0, 31200.0)).issue)
        assertEquals(StepCalibration.Issue.UNCONFIRMED_SOURCE, StepCalibration.validate(walk(confirmed = false)))
        assertEquals(StepCalibration.Issue.INVALID_IDENTITY, StepCalibration.validate(walk("")))
        assertEquals(StepCalibration.Issue.INVALID_IDENTITY, StepCalibration.validate(walk(" \n\t")))
        val eight = (0 until 8).map { walk("$it", 1000.0 + it, 24000.0 + it * 24) }
        assertEquals(24.0, StepCalibration.evaluate(eight).factor)
        assertEquals(StepCalibration.Issue.TOO_MANY_TRIALS, StepCalibration.evaluate(eight + walk("ninth")).issue)
    }

    @Test fun conflictFailsClosedWithoutDroppingOutlierAndEvenMedianIsAveraged() {
        val conflict = StepCalibration.evaluate(listOf(walk("a"), walk("b", ticks = 24500.0), walk("c", ticks = 30000.0)))
        assertEquals(StepCalibration.Issue.INCONSISTENT_TRIALS, conflict.issue)
        assertNull(conflict.factor)
        assertEquals(6 / 24.5, conflict.relativeSpread)
        val even = StepCalibration.evaluate(listOf(walk("a", ticks = 23000.0), walk("b"), walk("c", ticks = 25000.0), walk("d", ticks = 26000.0)))
        assertNull(even.issue)
        assertEquals(24.5, even.factor)
        assertEquals(3 / 24.5, even.relativeSpread)
        assertEquals(10.0, StepCalibration.evaluate(listOf(walk("a", ticks = 9000.0), walk("b", ticks = 10000.0), walk("c", ticks = 11000.0))).factor)
        assertEquals(StepCalibration.Issue.INCONSISTENT_TRIALS, StepCalibration.evaluate(listOf(walk("a", ticks = 9000.0), walk("b", ticks = 10000.0), walk("c", ticks = 11001.0))).issue)
    }

    private fun oracleTranscript(): String {
        val cases = mutableListOf(
            "empty" to emptyList(), "two" to repeatedWalks.take(2), "repeat24" to repeatedWalks,
            "even" to listOf(walk("a", ticks = 23000.0), walk("b"), walk("c", ticks = 25000.0), walk("d", ticks = 26000.0)),
            "edge20" to listOf(walk("a", ticks = 9000.0), walk("b", ticks = 10000.0), walk("c", ticks = 11000.0)),
            "over20" to listOf(walk("a", ticks = 9000.0), walk("b", ticks = 10000.0), walk("c", ticks = 11001.0)),
            "conflict" to listOf(walk("a"), walk("b", ticks = 24500.0), walk("c", ticks = 30000.0)),
            "duplicate-id" to (repeatedWalks + walk("a", 1300.0, 31200.0)),
            "duplicate-pair" to (repeatedWalks + walk("d")),
            "unconfirmed" to listOf(walk(confirmed = false)), "blank-id" to listOf(walk(" \n\t")),
            "floor" to listOf(walk("a", ticks = 500.0), walk("b", 1100.0, 550.0), walk("c", 1200.0, 600.0)),
            "ceiling" to listOf(walk("a", ticks = 30000.0), walk("b", 1100.0, 33000.0), walk("c", 10000.0, 300000.0)),
            "unrounded" to listOf(walk("a", ticks = 23999.0), walk("b", ticks = 24001.0), walk("c", ticks = 24003.0))
        )
        val eight = (0 until 8).map { walk("$it", 1000.0 + it, 24000.0 + it * 24) }
        cases += "eight" to eight
        cases += "nine" to (eight + walk("ninth"))
        for ((i, v) in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0, 99.0, 100.5, 10001.0, Double.MAX_VALUE).withIndex()) {
            cases += "steps$i" to listOf(walk(steps = v))
        }
        for ((i, v) in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0, 1.5, 300001.0, Double.MAX_VALUE, 499.0, 30001.0).withIndex()) {
            cases += "ticks$i" to listOf(walk(ticks = v))
        }
        fun bits(value: Double?) = value?.toRawBits()?.toULong()?.toString(16) ?: "-"
        return cases.joinToString("\n") { (name, trials) ->
            val result = StepCalibration.evaluate(trials)
            "$name|${result.issue?.code ?: "ok"}|${bits(result.factor)}|${bits(result.relativeSpread)}"
        }
    }

    @Test fun compiledSwiftOraclePinsExactDoubleBitsAndRejections() {
        assertEquals(expectedOracle, oracleTranscript())
    }

    companion object {
        // Verbatim stdout of the standalone compiled Swift helper and fixture spread.
        private val expectedOracle = """
            empty|insufficientTrials|-|-
            two|insufficientTrials|-|-
            repeat24|ok|4038000000000000|0
            even|ok|4038800000000000|3fbf58d0fac687d6
            edge20|ok|4024000000000000|3fc999999999999a
            over20|inconsistentTrials|-|3fc99ce075f6fd20
            conflict|inconsistentTrials|-|3fcf58d0fac687d6
            duplicate-id|duplicateTrial|-|-
            duplicate-pair|duplicateTrial|-|-
            unconfirmed|unconfirmedSource|-|-
            blank-id|invalidIdentity|-|-
            floor|ok|3fe0000000000000|0
            ceiling|ok|403e000000000000|0
            unrounded|ok|4038004189374bc7|3f25d82c1d911fbb
            eight|ok|4038000000000000|0
            nine|tooManyTrials|-|-
            steps0|invalidSteps|-|-
            steps1|invalidSteps|-|-
            steps2|invalidSteps|-|-
            steps3|invalidSteps|-|-
            steps4|invalidSteps|-|-
            steps5|invalidSteps|-|-
            steps6|invalidSteps|-|-
            steps7|invalidSteps|-|-
            steps8|invalidSteps|-|-
            ticks0|invalidTicks|-|-
            ticks1|invalidTicks|-|-
            ticks2|invalidTicks|-|-
            ticks3|invalidTicks|-|-
            ticks4|invalidTicks|-|-
            ticks5|invalidTicks|-|-
            ticks6|invalidTicks|-|-
            ticks7|invalidTicks|-|-
            ticks8|unsupportedFactor|-|-
            ticks9|unsupportedFactor|-|-
        """.trimIndent()
    }
}
