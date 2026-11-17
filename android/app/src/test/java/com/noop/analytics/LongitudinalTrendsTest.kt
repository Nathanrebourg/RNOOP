package com.noop.analytics

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class LongitudinalTrendsTest {
    @Test fun compiledSwiftOracleBitPatterns() {
        // Captured verbatim from swiftc -O, not a second Kotlin calculation.
        val expected = """
            0,30,nil,0;0,150,nil,0;0,180,nil,0;nil;bothWindowsTooSparse;0
            2,30,402e000000000000,3fb1111111111111;2,150,4044000000000000,3f8b4e81b4e81b4f;4,180,403b800000000000,3f96c16c16c16c17;c039000000000000;nil;0
            0,30,nil,0;0,150,nil,0;0,180,nil,0;nil;bothWindowsTooSparse;0
            1,30,0,3fa1111111111111;2,150,4014000000000000,3f8b4e81b4e81b4f;3,180,400aaaaaaaaaaaab,3f91111111111111;nil;recentWindowTooSparse;1
            1,30,4000000000000000,3fa1111111111111;0,150,nil,0;1,180,4000000000000000,3f76c16c16c16c17;nil;bothWindowsTooSparse;0
            26,30,4036b7d3e3a4a0b1,3febbbbbbbbbbbbc;129,150,4036ef26d11625a1,3feb851eb851eb85;155,180,4036e5df199124cb,3feb8e38e38e38e4;bfcba976b8c27800;nil;0
            2,30,3fc3333333333334,3fb1111111111111;2,150,3fd6666666666666,3f8b4e81b4e81b4f;4,180,3fd0000000000000,3f96c16c16c16c17;bfc9999999999998;nil;0
        """.trimIndent()
        assertEquals(expected, longitudinalOracleLines())
    }

    private fun s(age: Int, value: Double?) = LongitudinalTrends.Sample(age, value)

    @Test fun completedNonoverlappingWindows() {
        val r = LongitudinalTrends.summarize(listOf(s(-1, 999.0), s(0, 999.0), s(1, 10.0), s(30, 20.0), s(31, 30.0), s(180, 50.0), s(181, 999.0)))
        assertEquals(2, r.recent30.count)
        assertEquals(15.0, r.recent30.mean!!, 0.0)
        assertEquals(40.0, r.prior150.mean!!, 0.0)
        assertEquals(27.5, r.context180.mean!!, 0.0)
        assertEquals(-25.0, r.delta!!, 0.0)
        assertEquals(2.0 / 30, r.recent30.coverage, 0.0)
        assertNull(r.insufficientReason)
    }

    @Test fun invalidMissingAndConflictingDuplicatesDoNotAddWeight() {
        val samples = listOf(s(1, null), s(2, 0.0), s(2, 0.0), s(3, 5.0), s(3, 6.0), s(4, Double.NaN), s(5, Double.POSITIVE_INFINITY), s(6, -1.0), s(7, 101.0), s(31, 10.0), s(32, 20.0))
        val r = LongitudinalTrends.summarize(samples, 0.0..100.0)
        assertEquals(1, r.recent30.count)
        assertEquals(0.0, r.recent30.mean!!, 0.0)
        assertEquals(3, r.context180.count)
        assertEquals(1, r.conflictingDays)
        assertNull(r.delta)
        assertEquals(LongitudinalTrends.InsufficientReason.recentWindowTooSparse, r.insufficientReason)
        assertEquals(r, LongitudinalTrends.summarize(samples.reversed(), 0.0..100.0))
    }

    @Test fun sparseWindowReasonsAndInvalidDuplicate() {
        val empty = LongitudinalTrends.summarize(emptyList())
        assertNull(empty.context180.mean)
        assertEquals(LongitudinalTrends.InsufficientReason.bothWindowsTooSparse, empty.insufficientReason)
        val recent = LongitudinalTrends.summarize(listOf(s(1, 2.0), s(2, 4.0)))
        assertEquals(LongitudinalTrends.InsufficientReason.priorWindowTooSparse, recent.insufficientReason)
        assertEquals(3.0, recent.recent30.mean!!, 0.0)
        val duplicate = LongitudinalTrends.summarize(listOf(s(1, Double.NaN), s(1, 4.0), s(1, null)))
        assertEquals(4.0, duplicate.recent30.mean!!, 0.0)
        assertEquals(0, duplicate.conflictingDays)
    }

    @Test fun parisDayAgeAcrossBothDSTTransitionsAndInvalidDates() {
        val zone = ZoneId.of("Europe/Paris")
        val spring = Instant.parse("2026-03-29T22:10:00Z")
        assertEquals(1, LongitudinalTrends.dayAge("2026-03-29", spring, zone))
        assertEquals(0, LongitudinalTrends.dayAge("2026-03-30", spring, zone))
        assertEquals(-1, LongitudinalTrends.dayAge("2026-03-31", spring, zone))
        assertEquals(1, LongitudinalTrends.dayAge("2026-10-25", Instant.parse("2026-10-25T23:10:00Z"), zone))
        assertNull(LongitudinalTrends.dayAge("0000-01-01", spring, zone))
        assertNull(LongitudinalTrends.dayAge("2026-02-30", spring, zone))
        assertNull(LongitudinalTrends.dayAge("2026-3-29", spring, zone))
        assertNull(LongitudinalTrends.dayAge("garbage", spring, zone))
    }
}

// Expected output is captured from the compiled Swift helper, not derived from Kotlin.
internal fun longitudinalOracleLines(): String {
    fun s(age: Int, value: Double?) = LongitudinalTrends.Sample(age, value)
    val fixtures = listOf(
        emptyList(),
        listOf(s(1, 10.0), s(30, 20.0), s(31, 30.0), s(180, 50.0)),
        listOf(s(0, 999.0), s(-1, 999.0), s(181, 999.0), s(1, null)),
        listOf(s(1, 0.0), s(1, 0.0), s(2, 8.0), s(2, 9.0), s(31, 3.0), s(32, 7.0)),
        listOf(s(1, Double.NaN), s(1, 2.0), s(30, Double.POSITIVE_INFINITY), s(31, -1.0), s(32, 101.0)),
        (-2..183).map { s(it, if (it % 7 == 0) null else (it % 17) * 0.37 + 20) },
        listOf(s(1, 0.1), s(2, 0.2), s(31, 0.3), s(32, 0.4)),
    )
    fun bits(v: Double?) = v?.let { java.lang.Long.toHexString(java.lang.Double.doubleToLongBits(it)) } ?: "nil"
    return fixtures.joinToString("\n") { samples ->
        val r = LongitudinalTrends.summarize(samples, 0.0..100.0)
        val windows = listOf(r.recent30, r.prior150, r.context180).joinToString(";") {
            "${it.count},${it.calendarDays},${bits(it.mean)},${bits(it.coverage)}"
        }
        "$windows;${bits(r.delta)};${r.insufficientReason?.name ?: "nil"};${r.conflictingDays}"
    }
}
