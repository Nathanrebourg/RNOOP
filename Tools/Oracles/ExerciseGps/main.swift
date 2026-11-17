import Foundation
import StrandAnalytics
func fixture() -> ExerciseGpsEvidence.Input {
 .init(start:1000,end:2200,sport:"running",owner:"strap",storedDistanceM:nil,
 fixes:(0...120).map{.init(lat:0,lon:Double($0)*0.0003,time:1000+Double($0)*10,accuracyM:5)},
 heartRates:(0...1200).map{.init(time:1000+Double($0),bpm:150,owner:"strap")})
}
func n(_ v:Double?)->String { v.map{String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "nil" }
for i in 0..<12 {
 var x=fixture()
 switch i {
 case 1:x.owner=nil
 case 2:x.fixes=x.fixes.map{.init(lat:$0.lat,lon:$0.lon,time:nil,accuracyM:nil)}
 case 3:x.fixes[20].lat = .nan
 case 4:x.heartRates.removeSubrange(300...700)
 case 5:x.heartRates[50].owner="foreign"
 case 6:x.fixes[20].accuracyM=50
 case 7:x.fixes.removeSubrange(20...40)
 case 8:x.storedDistanceM=100
 case 9:for j in 0...30 {x.fixes[j].lon=0}
 case 10:x.end = .infinity
 case 11:x.heartRates[50].bpm = .nan
 default:break
 }
 let r=ExerciseGpsEvidence.evaluate(x)
 print([n(r.distanceM),n(r.speedMps),n(r.meanHr),n(r.hrCoveredS),n(r.metersPerBeat),r.reasons.joined(separator:",")].joined(separator:"|"))
}
for s in 0...1 {
 let r=ExerciseGpsEvidence.kline(age:40,weightKg:70,sex:s,seconds:900,repeatSeconds:920,fourthQuarterHr:120,confirmed:true)
 print("kline|\(n(r?.litersPerMinute))|\(n(r?.mlKgMin))")
}
