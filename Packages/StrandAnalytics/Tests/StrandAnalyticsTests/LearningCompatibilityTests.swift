import XCTest
import StrandAnalytics
final class LearningCompatibilityTests:XCTestCase {
func testSemanticContextOracleIgnoresAppReleaseAndSeparatesRealChanges() {
func cases()->[String] {
 let base=["pipeline":"scoring-v1","age":"30"]
 func make(_ source:String="strap",_ zone:String="Europe/Paris",_ method:String="recovery.logistic.v1",_ settings:[String:String]?=nil)->String? {
  LearningCompatibility.manifest(source:source,zone:zone,recoveryMethod:method,effortMethod:"effort.edwards-hrr-log.v1",settings:settings ?? base)
 }
 let original=make()!
 return [original.replacingOccurrences(of:"\n",with:"|"),
         "ordered|\(make("strap","Europe/Paris","recovery.logistic.v1",["age":"30","pipeline":"scoring-v1"])==original)",
         "source|\(make("other") != original)","zone|\(make("strap","UTC") != original)",
         "method|\(make("strap","Europe/Paris","recovery.logistic.v2") != original)",
         "settings|\(make("strap","Europe/Paris","recovery.logistic.v1",["age":"31","pipeline":"scoring-v1"]) != original)",
         "cosmetic-rejected|\(make("strap","Europe/Paris","recovery.logistic.v1",["pipeline":"scoring-v1","appVersion":"12.6.1"])==nil)",
         "missing-pipeline|\(make("strap","Europe/Paris","recovery.logistic.v1",["age":"30"])==nil)",
         "unicode|\(make("bracelet-é") != nil)","delimiter|\(make("a|b") != make("a"))"]
}

XCTAssertEqual(cases().joined(separator:"\n"),"""
learning.recipe-context.v1|owner:7374726170|zone:4575726f70652f5061726973|recovery:7265636f766572792e6c6f6769737469632e7631|effort:6566666f72742e656477617264732d6872722d6c6f672e7631|ctx.age:3330|ctx.pipeline:73636f72696e672d7631|
ordered|true
source|true
zone|true
method|true
settings|true
cosmetic-rejected|true
missing-pipeline|true
unicode|true
delimiter|true
""")
}
}
