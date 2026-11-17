package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.GravitySample
import org.junit.Assert.*
import org.junit.Test

class SleepSignalCoverageTest {
    private fun h(ts:Long,bpm:Int) = HrSample("test",ts,bpm)
    private fun g(ts:Long,x:Double=0.0,y:Double=0.0,z:Double=1.0)=GravitySample("test",ts,x,y,z)
    @Test fun compiledSwiftOracleIsByteIdentical() {
        data class Case(val s:Long,val e:Long,val h:List<HrSample>,val g:List<GravitySample>)
        val h=listOf(h(31,60));val g=listOf(g(65))
        val cases=listOf(Case(7,101,h,g),Case(7,101,h+h,(g+g).reversed()),Case(0,60,emptyList(),emptyList()),
            Case(0,30,listOf(h(0,300),h(1,301)),listOf(g(1))),
            Case(7,30,listOf(h(6,60)),listOf(g(30))),
            Case(0,30,listOf(h(0,0)),listOf(g(0,Double.NaN),g(1,0.0,0.0,0.0))),
            Case(0,172800,emptyList(),emptyList()),Case(-1,10,emptyList(),emptyList()),
            Case(0,172801,emptyList(),emptyList()),Case(4102444770,4102444800,emptyList(),emptyList()),
            Case(Long.MAX_VALUE-1,Long.MAX_VALUE,emptyList(),emptyList()))
        val actual=cases.joinToString("\n") { SleepSignalCoverage.analyze(it.s,it.e,it.h,it.g).trace }
        assertEquals(EXPECTED.trim(),actual)
    }
    @Test fun partialEdgesDoNotCountOutsideEvidence() {
        val x=SleepSignalCoverage.analyze(7,60,listOf(h(6,70),h(7,60),h(60,70)),listOf(g(7)))
        assertEquals(23L,x.bothSeconds);assertEquals(30L,x.unknownSeconds);assertEquals(1,x.distinctHRSeconds)
        assertEquals(listOf("both","unknown"),x.intervals.map { it.kind })
    }
    companion object {
        // Literal stdout from actual compiled Swift; source in Tools/Oracles/SleepSignalCoverage.
        private val EXPECTED="""
observed|0|30|30|34|1|1|7:30:unknown,30:60:hr-only,60:90:motion-only,90:101:unknown
observed|0|30|30|34|1|1|7:30:unknown,30:60:hr-only,60:90:motion-only,90:101:unknown
observed|0|0|0|60|0|0|0:60:unknown
observed|30|0|0|0|1|1|0:30:both
observed|0|0|0|23|0|0|7:30:unknown
observed|0|0|0|30|0|0|0:30:unknown
observed|0|0|0|172800|0|0|0:172800:unknown
invalid-window|0|0|0|0|0|0|
invalid-window|0|0|0|0|0|0|
observed|0|0|0|30|0|0|4102444770:4102444800:unknown
invalid-window|0|0|0|0|0|0|
"""
    }
}
