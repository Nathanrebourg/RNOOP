package com.noop.analytics
import org.junit.Test
import org.junit.Assert.*
import java.util.Locale
class GapEvidenceTest {
 @Test fun compiledSwiftOracle() {
  fun fmt(v:Double?)=v?.let { String.format(Locale.US,"%.1f",it) }?:"N"
  val rows=listOf(StrengthLoadHistory.Session("a",0,3600,5.0),StrengthLoadHistory.Session("b",7,1200,6.0),StrengthLoadHistory.Session("c",1,30,null))
  val lines=mutableListOf<String>()
  for (values in listOf(rows,rows+rows,emptyList(),listOf(rows[0],rows[0].copy(rpe=6.0)))) {
   val r=StrengthLoadHistory.summarize(values)
   lines.add("${r.recent7.ratedSessions}|${r.recent7.unratedSessions}|${fmt(r.recent7.loadAU)}|${fmt(r.context28.loadAU)}|${r.conflictingSessions}")
  }
  for(flag in listOf(true,false)) for(delta in listOf(0L,120L,121L,Long.MAX_VALUE)) {
   lines.add(AlarmDeliveryEvidence.status(true,flag,2000,"a",2000,if(delta==Long.MAX_VALUE) Long.MAX_VALUE else 2000+delta,"a","a",900.0,950.0,true,1000.0))
  }
  lines.add(AlarmDeliveryEvidence.status(true,true,2000,"a",2000,2000,"a","a",900.0,950.0,true,Double.NaN))
  assertEquals("""
1|1|300.0|420.0|0
1|1|300.0|420.0|0
0|0|N|N|0
0|0|N|N|1
last-readback-matches
last-readback-matches
last-readback-differs
invalid-timestamps
experimental-blocked
experimental-blocked
experimental-blocked
experimental-blocked
invalid-timestamps
""".trim(),lines.joinToString("\n"))
 }
}
