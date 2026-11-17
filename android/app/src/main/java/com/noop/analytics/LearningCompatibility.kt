package com.noop.analytics
/** Semantic recipe context; app marketing/build versions are not inputs. */
object LearningCompatibility {
 const val version="learning.recipe-context.v1"
 fun manifest(source:String,zone:String,recoveryMethod:String,effortMethod:String,settings:Map<String,String>):String? {
  fun ascii(s:String,limit:Int)=s.isNotEmpty()&&s.length<=limit&&s.all{it.code in 33..126}
  if(source.isEmpty()||source.toByteArray(Charsets.UTF_8).size>512||zone.isEmpty()||zone.toByteArray(Charsets.UTF_8).size>128||!ascii(recoveryMethod,80)||!ascii(effortMethod,80)||settings.isEmpty()||settings.size>64||settings["pipeline"]==null||settings.keys.any{!ascii(it,64)||it.any{c->!(c in '0'..'9'||c in 'A'..'Z'||c in 'a'..'z'||c in "-._")}}||settings.values.any{it.isEmpty()||it.toByteArray(Charsets.UTF_8).size>512}||settings.keys.any{it in listOf("appVersion","build","theme")})return null
  fun hex(s:String)=s.toByteArray(Charsets.UTF_8).joinToString(""){"%02x".format(it.toInt() and 255)}
  val lines=mutableListOf(version,"owner:"+hex(source),"zone:"+hex(zone),"recovery:"+hex(recoveryMethod),"effort:"+hex(effortMethod))
  lines+=settings.keys.sorted().map{"ctx.$it:"+hex(settings.getValue(it))}
  return lines.joinToString("\n")+"\n"
 }
}
