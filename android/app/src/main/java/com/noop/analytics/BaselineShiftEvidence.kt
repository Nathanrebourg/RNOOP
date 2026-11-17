package com.noop.analytics
import kotlin.math.*
/** Descriptive shift only; never resets physiological reference values. */
object BaselineShiftEvidence {
 data class Sample(val age:Int,val value:Double?,val era:String)
 data class Result(val status:String,val recentCount:Int,val priorCount:Int,val recentMedian:Double?,val priorMedian:Double?,val scaledDelta:Double?,val shift:Boolean)
 fun analyze(samples:List<Sample>,floor:Double,lower:Double,upper:Double):Result {
  fun out(s:String,a:List<Double> = emptyList(),b:List<Double> = emptyList(),z:Double?=null,flag:Boolean=false)=Result(s,a.size,b.size,PersonalEvidenceMath.median(a),PersonalEvidenceMath.median(b),z,flag)
  if(samples.size>400||!floor.isFinite()||floor<0.000001||floor>100000||!lower.isFinite()||!upper.isFinite()||abs(lower)>100000||abs(upper)>100000||lower>upper)return out("invalid-input")
  val valid=samples.filter{it.age in 1..35}.groupBy{it.age}.values.mapNotNull {g->val a=g.first();if(g.any{it.age!=a.age||it.era!=a.era||!PersonalEvidenceMath.same(it.value,a.value)}||a.value==null||!a.value.isFinite()||a.value !in lower..upper||!PersonalEvidenceMath.ascii(a.era))null else a}
  val a=valid.filter{it.age<=7}.sortedBy{it.age}.mapNotNull{it.value};val b=valid.filter{it.age>7}.sortedBy{it.age}.mapNotNull{it.value}
  if(valid.map{it.era}.toSet().size>1)return out("context-changed",a,b)
  val am=PersonalEvidenceMath.median(a);val bm=PersonalEvidenceMath.median(b)
  if(a.size<5||b.size<20||am==null||bm==null)return out("insufficient-days",a,b)
  val scale=max(floor,1.4826*(PersonalEvidenceMath.median(b.map{abs(it-bm)})?:0.0));val z=(am-bm)/scale
  val directional=a.count{if(z>=0)it-bm>=2*scale else bm-it>=2*scale}
  return out("compared",a,b,z,abs(z)>=2&&directional>=4)
 }
}
