package com.noop.analytics
import com.noop.data.ScoreCalculationEvidenceEntity
internal object ScoreEvidenceBridge {
 fun settings(age:Double,sex:String,maxHR:Double?,deep:Boolean,v2:Boolean,motion:Boolean,cycle:String,hrvEpoch:Double,recoveryEpoch:Double,respEpoch:Double):Map<String,String>? {
  if(!age.isFinite()||age !in 0.0..120.0||maxHR?.let{!it.isFinite()||it !in 30.0..250.0}==true||listOf(hrvEpoch,recoveryEpoch,respEpoch).any{!it.isFinite()||it !in 0.0..4102444800.0})return null
  fun bits(x:Double)=java.lang.Long.toHexString((if(x==0.0)0.0 else x).toRawBits())
  return mapOf("pipeline" to "noop-scoring-v1","age" to bits(age),"sex" to sex.lowercase(java.util.Locale.ROOT),"manualHRmax" to (maxHR?.let{bits(it)}?:"none"),"hrvWindow" to if(deep)"deep"else"whole","sleepStager" to if(v2)"v2"else"v1","motionWake" to if(motion)"1"else"0","dayCycle" to cycle,"hrvEpoch" to bits(hrvEpoch),"recoveryEpoch" to bits(recoveryEpoch),"respEpoch" to bits(respEpoch))
 }
 fun row(recipe:ScoreRecipe?,day:String,source:String,value:Double?,context:Map<String,String>?,now:Long,deviceId:String):ScoreCalculationEvidenceEntity? {
  if(context==null||value==null||!value.isFinite())return null
  val r=recipe?.withContext(context)?:return null
  if(r.sourceId!=source||r.score!=value||r.replay()!=value)return null
  return ScoreCalculationEvidenceEntity(deviceId,day,r.key,r.fingerprint,now,r.sourceId,r.methodId,value,r.payload)
 }
}
