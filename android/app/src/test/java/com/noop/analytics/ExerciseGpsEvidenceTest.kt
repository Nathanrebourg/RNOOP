package com.noop.analytics
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class ExerciseGpsEvidenceTest {
    private fun fixture() = ExerciseGpsEvidence.Input(1000.0,2200.0,"running","strap",null,
        (0..120).map{ExerciseGpsEvidence.Fix(0.0,it*0.0003,1000+it*10.0,5.0)},
        (0..1200).map{ExerciseGpsEvidence.HeartRate(1000+it.toDouble(),150.0,"strap")})
    @Test fun compiledSwiftOracleLiteralAndProtocolGates() {
        fun n(v:Double?)=v?.let{String.format(Locale.ROOT,"%.6f",it)}?:"nil"
        val lines=mutableListOf<String>()
        for(i in 0 until 12) {
            val x=fixture()
            when(i) {
                1 -> x.owner=null
                2 -> x.fixes=x.fixes.map{it.copy(time=null,accuracyM=null)}
                3 -> x.fixes[20].lat=Double.NaN
                4 -> x.heartRates=x.heartRates.filterIndexed{j,_->j !in 300..700}
                5 -> x.heartRates[50].owner="foreign"
                6 -> x.fixes[20].accuracyM=50.0
                7 -> x.fixes=x.fixes.filterIndexed{j,_->j !in 20..40}
                8 -> x.storedDistanceM=100.0
                9 -> for(j in 0..30) x.fixes[j].lon=0.0
                10 -> x.end=Double.POSITIVE_INFINITY
                11 -> x.heartRates[50].bpm=Double.NaN
            }
            val r=ExerciseGpsEvidence.evaluate(x)
            assertNull(r.vo2max)
            lines+=listOf(n(r.distanceM),n(r.speedMps),n(r.meanHr),n(r.hrCoveredS),n(r.metersPerBeat),r.reasons.joinToString(",")).joinToString("|")
        }
        for(s in 0..1) {
            val r=ExerciseGpsEvidence.kline(40.0,70.0,s,900.0,920.0,120.0,true)
            lines+="kline|${n(r?.litersPerMinute)}|${n(r?.mlKgMin)}"
        }
        assertEquals("""
4003.017359|3.335848|150.000000|1200.000000|1.334339|slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-owner-unknown,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-timing-missing,gps-accuracy-missing,gps-coverage,slope-unknown,protocol-unverified
nil|nil|nil|0.000000|nil|gps-invalid,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|798.000000|nil|hr-gap,hr-coverage,slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-owner-mismatch,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-accuracy,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-gap,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|distance-mismatch,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-speed,stops,slope-unknown,protocol-unverified
nil|nil|nil|0.000000|nil|window-invalid,slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-invalid,slope-unknown,protocol-unverified
kline|2.601545|37.164923
kline|3.197045|45.672066
""".trimIndent(),lines.joinToString("\n"))
        assertNull(ExerciseGpsEvidence.kline(40.0,70.0,1,900.0,920.0,120.0,false))
        assertNull(ExerciseGpsEvidence.kline(29.0,70.0,1,900.0,920.0,120.0,true))
        assertNull(ExerciseGpsEvidence.kline(40.0,70.0,1,900.0,931.0,120.0,true))
        assertNull(ExerciseGpsEvidence.kline(40.0,Double.NaN,1,900.0,920.0,120.0,true))
    }
}
