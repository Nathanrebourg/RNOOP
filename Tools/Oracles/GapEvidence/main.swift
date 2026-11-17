import Foundation
let rows: [StrengthLoadHistory.Session] = [.init(id:"a",dayAge:0,durationSec:3600,rpe:5),.init(id:"b",dayAge:7,durationSec:1200,rpe:6),.init(id:"c",dayAge:1,durationSec:30,rpe:nil)]
for values in [rows,rows+rows,[],[rows[0],.init(id:"a",dayAge:0,durationSec:3600,rpe:6)]] {
 let r=StrengthLoadHistory.summarize(values)
 print("\(r.recent7.ratedSessions)|\(r.recent7.unratedSessions)|\(r.recent7.loadAU.map{String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "N")|\(r.context28.loadAU.map{String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "N")|\(r.conflictingSessions)")
}
for flag in [true,false] { for delta in [0,120,121,Int.max] {
 print(AlarmDeliveryEvidence.status(enabled:true,protocolAllowed:flag,plannedEpoch:2000,currentDevice:"a",sentEpoch:2000,reportedEpoch:delta==Int.max ? Int.max : 2000+delta,sentDevice:"a",reportedDevice:"a",sentAt:900,reportedAt:950,sentConnected:true,now:1000))
} }
print(AlarmDeliveryEvidence.status(enabled:true,protocolAllowed:true,plannedEpoch:2000,currentDevice:"a",sentEpoch:2000,reportedEpoch:2000,sentDevice:"a",reportedDevice:"a",sentAt:900,reportedAt:950,sentConnected:true,now:.nan))
