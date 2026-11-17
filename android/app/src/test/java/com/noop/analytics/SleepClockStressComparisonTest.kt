package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.RrInterval
import com.noop.data.GravitySample
import org.junit.Test
import org.junit.Assert.*
import java.util.Locale
class SleepClockStressComparisonTest {
 private fun night(day:Int,bed:Int=1430,wake:Int=470):SleepClockStressComparison.Night {
  val start=day*86400L-28800
  return SleepClockStressComparison.Night(day,start,start+28800,bed,wake,listOf(SleepClockStressComparison.Stage(start,start+28800,"light")),false)
 }
 private fun raw(n:SleepClockStressComparison.Night,channel:Int=5,confirmed:Boolean=true,capped:Boolean=false,dropMotion:Boolean=false):SleepClockStressComparison.Physiology {
  val hr=(n.start until n.end).map{HrSample("oracle",it,60)}
  val rr=(n.start until n.end).map{RrInterval("oracle",it,if(it%2L==0L)980 else 1020,srcChannel=channel)}
  val g=if(dropMotion) emptyList() else (n.start until n.end).map{GravitySample("oracle",it,0.0,0.0,1.0)}
  return SleepClockStressComparison.physiology(n,hr,rr,g,confirmed,capped)
 }
 @Test fun actualCompiledSwiftRawAndSummaryOracle() {
  fun f(v:Double?)=v?.let{String.format(Locale.US,"%.6f",it)}?:"nil"
  val target=night(40,10,490);val history=listOf(night(39),night(38),night(37))
  val p=raw(target);val prior=history.map{raw(it)};val lines=mutableListOf<String>()
  for((phy,base) in listOf(null to prior,p to prior,p to prior.take(2),p to (prior+prior))) {
   val r=SleepClockStressComparison.analyze(target,history,target.end,phy,base)
   lines.add(listOf(r.status,f(r.duration),f(r.efficiency),f(r.clock),f(r.calmness),f(r.candidate),r.priorNights.toString(),r.baselineNights.toString(),r.stressStatus).joinToString("|"))
  }
  for(v in listOf(p,raw(target,confirmed=false),raw(target,capped=true),raw(target,dropMotion=true),raw(target,channel=6))) {
   lines.add(listOf(v.status,(v.channel?:-1).toString(),f(v.hr),f(v.rmssd),f(v.coverage),v.windows.toString()).joinToString("|"))
  }
  assertEquals("""
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|0|night-stress-provenance-unavailable
compared|1.000000|1.000000|0.833333|0.500000|89.166667|3|3|qualified-nocturnal-activation-proxy
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|2|insufficient-prior-night-baseline
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|0|insufficient-prior-night-baseline
qualified|5|60.000000|40.000000|1.000000|96
unconfirmed-whoop5-source|-1|nil|nil|0.000000|0
read-capped|-1|nil|nil|0.000000|0
insufficient-night-signal|5|nil|nil|0.000000|0
rr-source-unavailable-or-mixed|-1|nil|nil|0.000000|0
""".trimIndent(),lines.joinToString("\n"))
 }
 @Test fun qualifiedLabelCannotBypassCoverageAndSourceGates() {
  val n=night(40);val history=listOf(night(39),night(38),night(37));val p=raw(n);val prior=history.map{raw(it)}
  for(bad in listOf(p.copy(channel=null),p.copy(channel=6),p.copy(coverage=Double.NaN),p.copy(coverage=.5),p.copy(windows=97)))
   assertNull(SleepClockStressComparison.analyze(n,history,n.end,bad,prior).candidate)
 }
}
