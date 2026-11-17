package com.noop.analytics
import org.junit.Assert.*
import org.junit.Test
class PersonalEvidenceTest {
 @Test fun signedZeroDuplicatesMatchSwiftNumericEquality() {
  val rows=(0 until 8).flatMap {i->listOf(MatchedJournalComparison.Row(10000+i*7,"x",true,0.0),MatchedJournalComparison.Row(10001+i*7,"x",false,0.0))}+MatchedJournalComparison.Row(10000,"x",true,-0.0)
  assertEquals(8,MatchedJournalComparison.analyze(listOf(MatchedJournalComparison.Experiment("x",rows)))[0].pairs)
  val shift=(1..35).map{BaselineShiftEvidence.Sample(it,0.0,"x")}+BaselineShiftEvidence.Sample(1,-0.0,"x")
  assertEquals(7,BaselineShiftEvidence.analyze(shift,5.0,0.0,1000.0).recentCount)
  val training=(0..180).map{TrainingResponseForecast.Day(it,80.0,0.0,"x")}+TrainingResponseForecast.Day(180,80.0,-0.0,"x")
  assertEquals("no-improvement",TrainingResponseForecast.analyze(training,180,1).status)
  val refs=listOf(ReferenceValidation.Observation("x",1,"m","steps",0.0,100.0,false),ReferenceValidation.Observation("x",1,"m","steps",-0.0,100.0,false))
  assertEquals(1,ReferenceValidation.analyze(refs,"m","steps").count)
 }
 @Test fun actualCompiledSwiftOracle() {
 // Swift printf uses binary nearest/even at exact ties; Java Formatter uses half-up.
 fun n(x:Double?)=x?.let{java.math.BigDecimal(it).setScale(6,java.math.RoundingMode.HALF_EVEN).toPlainString()}?:"nil"
 val lines=mutableListOf<String>()
 fun journal(delta:Double)=(0 until 8).flatMap{i->listOf(MatchedJournalComparison.Row(10000+i*7,"same",true,60+delta),MatchedJournalComparison.Row(10001+i*7,"same",false,60.0))}
 for(index in 0 until 5) {
  var x=journal(if(index==1)0.0 else 10.0).toMutableList()
  if(index==2)x=x.drop(4).toMutableList()
  if(index==3)x[1]=MatchedJournalComparison.Row(x[1].day,"other",false,60.0)
  if(index==4)x.add(MatchedJournalComparison.Row(x[1].day,"same",true,60.0))
  val a=MatchedJournalComparison.analyze(listOf(MatchedJournalComparison.Experiment("a",x),MatchedJournalComparison.Experiment("b",journal(0.0))))[0]
  lines.add("journal|${a.pairs}|${a.nonzero}|${n(a.medianDelta)}|${n(a.p)}|${n(a.adjustedP)}|${if(a.association)1 else 0}")
 }
 for(index in 0 until 5) {
  var x=(1..35).map{BaselineShiftEvidence.Sample(it,if(it<=7)(if(index==1)60.0 else 70.0)else 60.0,"one")}.toMutableList()
  if(index==2)x=x.drop(4).toMutableList()
  if(index==3)x[0]=BaselineShiftEvidence.Sample(1,70.0,"two")
  if(index==4)x.add(BaselineShiftEvidence.Sample(1,80.0,"one"))
  val a=BaselineShiftEvidence.analyze(x,3.0,20.0,250.0)
  lines.add("shift|${a.status}|${a.recentCount}|${a.priorCount}|${n(a.recentMedian)}|${n(a.priorMedian)}|${n(a.scaledDelta)}|${if(a.shift)1 else 0}")
 }
 for(index in 0 until 5) {
  var x=(0..180).map{TrainingResponseForecast.Day(it,if(it>0&&(it-1)%3==0)40.0 else 80.0,if(it%3==0)100.0 else 0.0,"one")}.toMutableList()
  if(index==2)x.removeAt(x.lastIndex)
  if(index==3)x[180]=TrainingResponseForecast.Day(180,80.0,100.0,"two")
  if(index==4){x.add(TrainingResponseForecast.Day(181,100.0,100.0,"one"));x.reverse()}
  val a=TrainingResponseForecast.analyze(x,180,if(index==1)2 else 1)
  lines.add("forecast|${a.status}|${n(a.prediction)}|${a.training}|${a.evaluated}|${n(a.modelMAE)}|${n(a.baselineMAE)}")
 }
 for(index in 0 until 5) {
  var x=(0 until 20).map{ReferenceValidation.Observation("r$it",it,"m","steps",if(it<10)110.0 else 105.0,100.0,false)}.toMutableList()
  if(index==1)x.add(x[0])
  if(index==2)x.add(ReferenceValidation.Observation("r0",0,"m","steps",111.0,100.0,false))
  if(index==3)x=x.map{it.copy(usedForCalibration=true)}.toMutableList()
  if(index==4)x=x.map{it.copy(method="other")}.toMutableList()
  val a=ReferenceValidation.analyze(x,"m","steps")
  lines.add("validation|${a.count}|${a.excluded}|${n(a.mae)}|${n(a.bias)}|${n(a.recentMAE)}|${n(a.priorMAE)}")
 }
 val j=(0 until 8).flatMap{i->listOf(MatchedJournalComparison.Row(10000+i*7,"x",true,0.0),MatchedJournalComparison.Row(10001+i*7,"x",false,0.0))}+MatchedJournalComparison.Row(10000,"x",true,-0.0)
 val a=MatchedJournalComparison.analyze(listOf(MatchedJournalComparison.Experiment("x",j)))[0]
 val b=BaselineShiftEvidence.analyze((1..35).map{BaselineShiftEvidence.Sample(it,0.0,"x")}+BaselineShiftEvidence.Sample(1,-0.0,"x"),5.0,0.0,1000.0)
 val c=TrainingResponseForecast.analyze((0..180).map{TrainingResponseForecast.Day(it,80.0,0.0,"x")}+TrainingResponseForecast.Day(180,80.0,-0.0,"x"),180,1)
 val d=ReferenceValidation.analyze(listOf(ReferenceValidation.Observation("x",1,"m","steps",0.0,100.0,false),ReferenceValidation.Observation("x",1,"m","steps",-0.0,100.0,false)),"m","steps")
 lines.add("signed-zero|${a.pairs}|${b.recentCount}|${c.status}|${d.count}")
 val e=BaselineShiftEvidence.analyze((1..35).map{BaselineShiftEvidence.Sample(it,Double.MAX_VALUE,"x")},java.lang.Double.MIN_NORMAL,0.0,Double.MAX_VALUE)
 lines.add("extreme|${e.status}|${n(e.scaledDelta)}")
 assertEquals(EXPECTED,lines.joinToString("\n"))
 }
 companion object {val EXPECTED="""journal|8|8|10.000000|0.007812|0.015625|1
journal|8|0|0.000000|nil|nil|0
journal|6|6|10.000000|nil|nil|0
journal|7|7|10.000000|nil|nil|0
journal|7|7|10.000000|nil|nil|0
shift|compared|7|28|70.000000|60.000000|3.333333|1
shift|compared|7|28|60.000000|60.000000|0.000000|0
shift|insufficient-days|3|28|70.000000|60.000000|nil|0
shift|context-changed|7|28|70.000000|60.000000|nil|0
shift|compared|6|28|70.000000|60.000000|3.333333|1
forecast|qualified-experimental|40.000000|30|30|0.000000|40.000000
forecast|no-improvement|nil|30|30|0.000000|0.000000
forecast|origin-unavailable|nil|0|0|nil|nil
forecast|insufficient-training|nil|0|0|nil|nil
forecast|qualified-experimental|40.000000|30|30|0.000000|40.000000
validation|20|0|7.500000|7.500000|5.000000|10.000000
validation|20|1|7.500000|7.500000|5.000000|10.000000
validation|19|2|7.368421|7.368421|5.000000|nil
validation|0|20|nil|nil|nil|nil
validation|0|20|nil|nil|nil|nil
signed-zero|8|7|no-improvement|1
extreme|invalid-input|nil"""}
}
