package com.noop.analytics
import kotlin.math.*
/** Agreement with personal references, separated by unit/method and excluding fitted observations. */
object ReferenceValidation {
 data class Observation(val id:String,val order:Int,val method:String,val kind:String,val estimate:Double,val reference:Double,val usedForCalibration:Boolean)
 data class Result(val count:Int,val excluded:Int,val mae:Double?,val bias:Double?,val recentMAE:Double?,val priorMAE:Double?)
 fun analyze(rows:List<Observation>,method:String,kind:String):Result {
  fun empty()=Result(0,rows.size,null,null,null,null)
  if(rows.size>256||!PersonalEvidenceMath.ascii(method)||kind !in listOf("steps","sleep-start-minutes","sleep-end-minutes"))return empty()
  val eligible=rows.groupBy{it.id}.values.mapNotNull{g->val a=g.first();if(g.any{it.id!=a.id||it.order!=a.order||it.method!=a.method||it.kind!=a.kind||it.usedForCalibration!=a.usedForCalibration||!PersonalEvidenceMath.same(it.estimate,a.estimate)||!PersonalEvidenceMath.same(it.reference,a.reference)}||!PersonalEvidenceMath.ascii(a.id)||a.order<0||a.method!=method||a.kind!=kind||a.usedForCalibration||!a.estimate.isFinite()||!a.reference.isFinite()||abs(a.estimate)>100000||abs(a.reference)>100000||kind=="steps"&&(a.estimate<0||a.reference<=0))null else a}.sortedWith(compareByDescending<Observation>{it.order}.thenBy{it.id})
  if(eligible.isEmpty())return empty()
  val errors=eligible.map{it.estimate-it.reference}
  fun mae(x:List<Double>):Double?=if(x.isEmpty())null else x.sumOf{abs(it)}/x.size
  return Result(eligible.size,rows.size-eligible.size,mae(errors),errors.sum()/errors.size,if(eligible.size>=10)mae(errors.take(10))else null,if(eligible.size>=20)mae(errors.drop(10).take(10))else null)
 }
}
