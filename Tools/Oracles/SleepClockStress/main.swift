import Foundation
import StrandAnalytics
import WhoopProtocol
func night(_ day:Int,bed:Int=1430,wake:Int=470)->SleepClockStressComparison.Night {
 let start=day*86400-28800
 return .init(day:day,start:start,end:start+28800,bedtimeMinute:bed,wakeMinute:wake,stages:[.init(start:start,end:start+28800,kind:"light")],sparse:false)
}
func raw(_ n:SleepClockStressComparison.Night,channel:RRSourceChannel = .whoop5Historical,confirmed:Bool=true,capped:Bool=false,dropMotion:Bool=false)->SleepClockStressComparison.Physiology {
 let hr=(n.start..<n.end).map{HRSample(ts:$0,bpm:60)}
 let rr=(n.start..<n.end).map{RRInterval(ts:$0,rrMs:$0%2==0 ? 980:1020,srcChannel:channel)}
 let g=dropMotion ? []:(n.start..<n.end).map{GravitySample(ts:$0,x:0,y:0,z:1)}
 return SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:g,confirmedWhoop5:confirmed,readCapped:capped)
}
func f(_ value:Double?)->String{value.map{String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "nil"}
let target=night(40,bed:10,wake:490),history=[night(39),night(38),night(37)]
let p=raw(target),prior=history.map{raw($0)}
for (phy,base) in [(Optional<SleepClockStressComparison.Physiology>.none,prior),(p,prior),(p,Array(prior.prefix(2))),(p,prior+prior)] {
 let r=SleepClockStressComparison.analyze(target:target,history:history,now:target.end,physiology:phy,priorPhysiology:base)
 print([r.status,f(r.duration),f(r.efficiency),f(r.clock),f(r.calmness),f(r.candidate),String(r.priorNights),String(r.baselineNights),r.stressStatus].joined(separator:"|"))
}
for value in [p,raw(target,confirmed:false),raw(target,capped:true),raw(target,dropMotion:true),raw(target,channel:.whoop5Realtime)] {
 print([value.status,String(value.channel ?? -1),f(value.hr),f(value.rmssd),f(value.coverage),String(value.windows)].joined(separator:"|"))
}
