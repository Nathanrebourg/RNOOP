package com.noop.analytics
import org.junit.Test
import org.junit.Assert.*
class LearningCompatibilityTest {
 @Test fun actualSwiftLiteral() {
  val base=mapOf("pipeline" to "scoring-v1","age" to "30")
  fun make(source:String="strap",zone:String="Europe/Paris",method:String="recovery.logistic.v1",settings:Map<String,String> = base)=LearningCompatibility.manifest(source,zone,method,"effort.edwards-hrr-log.v1",settings)
  val original=make()!!
  val lines=listOf(original.replace("\n","|"),"ordered|${make(settings=mapOf("age" to "30","pipeline" to "scoring-v1"))==original}","source|${make("other")!=original}","zone|${make("strap","UTC")!=original}","method|${make("strap","Europe/Paris","recovery.logistic.v2")!=original}","settings|${make(settings=mapOf("age" to "31","pipeline" to "scoring-v1"))!=original}","cosmetic-rejected|${make(settings=mapOf("pipeline" to "scoring-v1","appVersion" to "12.6.1"))==null}","missing-pipeline|${make(settings=mapOf("age" to "30"))==null}","unicode|${make("bracelet-é")!=null}","delimiter|${make("a|b")!=make("a")}")
  assertEquals(EXPECTED,lines.joinToString("\n"))
 }
 companion object {val EXPECTED="""learning.recipe-context.v1|owner:7374726170|zone:4575726f70652f5061726973|recovery:7265636f766572792e6c6f6769737469632e7631|effort:6566666f72742e656477617264732d6872722d6c6f672e7631|ctx.age:3330|ctx.pipeline:73636f72696e672d7631|
ordered|true
source|true
zone|true
method|true
settings|true
cosmetic-rejected|true
missing-pipeline|true
unicode|true
delimiter|true"""}
}
