package com.noop.analytics
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class ResearchModelsTest {
    private val cfg=Baselines.hrvCfg
    @Test fun fullQualityIsExactlyTheRealIncumbent() {
        val v=listOf(null,60.0,62.0,58.0,61.0,59.0,60.0,61.0,60.0,250.0,null)
        val x=QualityBaseline.fold(v,List(v.size){1.0},cfg)
        assertEquals(Baselines.foldHistory(v,cfg),x.original);assertEquals(x.original,x.candidate)
    }
    @Test fun missingLowQualityAndMismatchCannotBuildAUsableReference() {
        val x=QualityBaseline.fold(listOf(200.0,180.0,60.0,62.0),listOf(null,0.1,1.0,1.0),cfg)
        assertEquals(1,x.unknown);assertEquals(1,x.rejected);assertEquals(2,x.admitted)
        assertEquals(Baselines.foldHistory(listOf(null,null,60.0,62.0),cfg),x.candidate)
        assertNull(QualityBaseline.fold(listOf(60.0),emptyList(),cfg).candidate)
    }
    @Test fun partialQualityDampensTheUpdateAndDoesNotBlendFirstSeedAgainstPlaceholder() {
        val a=QualityBaseline.fold(listOf(60.0,80.0),listOf(1.0,1.0),cfg).candidate!!
        val b=QualityBaseline.fold(listOf(60.0,80.0),listOf(1.0,0.5),cfg).candidate!!
        assertTrue(b.baseline>60);assertTrue(b.baseline<a.baseline)
        assertEquals(70.0,QualityBaseline.fold(listOf(null,70.0),listOf(null,0.5),cfg).candidate!!.baseline,0.0)
    }
    @Test fun explanationMatchesRealScorerAndCompositeIsNotAnAdditiveScore() {
        val h=Baselines.foldHistory(List(15){60.0},cfg)
        val r=Baselines.foldHistory(List(15){55.0},Baselines.metricCfg.getValue("resting_hr"))
        val x=RecoveryExplanation.describe(45.0,60.0,null,h,r,null,0.9,null)
        assertEquals(RecoveryScorer.recovery(45.0,60.0,null,h,r,null,0.9),x.score)
        assertEquals(1.0,x.terms.sumOf { it.normalizedWeight },1e-12)
        assertEquals(x.compositeZ!!,x.terms.sumOf { it.contributionZ },1e-12)
        assertEquals(listOf("resp","skin"),x.missing)
    }
    @Test fun nonfiniteInputCannotBecomeAnExplanation() {
        val b=Baselines.foldHistory(List(8){60.0},cfg)
        assertNull(RecoveryExplanation.describe(Double.NaN,60.0,null,b,null,null,null,null).score)
        assertNotNull(RecoveryExplanation.describe(0.0,60.0,null,b,null,null,null,null).score)
    }
    private fun num(x:Double?)=x?.let { String.format(Locale.ROOT,"%.6f",it) }?:"nil"
    @Test fun compiledSwiftReferenceRecordsStayByteIdentical() {
        val values=listOf(listOf(60.0,62.0,58.0,61.0),listOf(200.0,180.0,60.0,62.0),listOf(60.0,80.0),listOf(60.0,80.0),listOf(null,70.0),listOf(60.0,61.0,59.0,60.0)+List(15){60.0},listOf(60.0,61.0,62.0),listOf(60.0))
        val qualities=listOf(listOf(1.0,1.0,1.0,1.0),listOf(null,0.1,1.0,1.0),listOf(1.0,1.0),listOf(1.0,0.5),listOf(null,0.5),listOf(1.0,1.0,1.0,1.0)+List(15){null},listOf(Double.NaN,-1.0,2.0),emptyList())
        val lines=values.zip(qualities).map { (v,q)->
            val x=QualityBaseline.fold(v,q,cfg)
            "baseline|${num(x.candidate?.baseline)}|${num(x.candidate?.spread)}|${x.candidate?.nValid?:-1}|${x.candidate?.nightsSinceUpdate?:-1}|${x.admitted}|${x.unknown}|${x.rejected}|${x.status}"
        }.toMutableList()
        val h=Baselines.foldHistory(List(15){60.0},cfg)
        val r=Baselines.foldHistory(List(15){55.0},Baselines.metricCfg.getValue("resting_hr"))
        val b=Baselines.foldHistory(List(15){14.0},Baselines.metricCfg.getValue("resp"))
        for (i in 0..3) {
            val x=RecoveryExplanation.describe(if(i==1)0.0 else 45.0,60.0,if(i==2)16.0 else null,if(i==3)Baselines.foldHistory(listOf(60.0),cfg) else h,if(i==1)null else r,b,if(i==1)null else 0.9,if(i==2)-0.4 else null)
            lines.add("explain|${num(x.score)}|${num(x.compositeZ)}|${x.status}|${x.missing.joinToString(",")}|"+x.terms.joinToString(";"){"${it.name}:${num(it.z)}:${num(it.normalizedWeight)}:${num(it.contributionZ)}"})
        }
        assertEquals(EXPECTED.trim(),lines.joinToString("\n"))
    }
    companion object {
        // Literal stdout from /private/tmp/nroop-research/oracle.swift linked to actual Swift modules.
        private val EXPECTED="""
baseline|60.138741|5.000000|4|0|4|0|0|compared
baseline|60.412599|5.000000|2|0|2|1|1|calibrating
baseline|64.125989|5.353060|2|0|2|0|0|calibrating
baseline|62.062995|5.176530|2|0|2|0|0|calibrating
baseline|70.000000|5.000000|1|0|1|1|0|calibrating
baseline|59.966221|5.000000|4|15|4|15|0|stale
baseline|127.500000|5.000000|0|3|0|0|3|calibrating
baseline|nil|nil|-1|-1|0|0|0|mismatched-history
explain|6.790370|-1.837091|explained|resp,skin|hrv:-2.394254:0.611111:-1.463155;rhr:-1.995211:0.222222:-0.443380;sleep:0.416667:0.166667:0.069444
explain|0.000030|-9.577015|explained|rhr,resp,sleep,skin|hrv:-9.577015:1.000000:-9.577015
explain|6.831929|-1.832999|explained||hrv:-2.394254:0.550000:-1.316840;rhr:-1.995211:0.200000:-0.399042;resp:-3.192338:0.050000:-0.159617;sleep:0.416667:0.150000:0.062500;skin:-0.400000:0.050000:-0.020000
explain|nil|nil|calibrating|hrv-baseline|
"""
    }
}
