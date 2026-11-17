import Foundation
import StrandAnalytics
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

print(cases().joined(separator:"\n"))
