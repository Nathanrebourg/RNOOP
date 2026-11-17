import XCTest
@testable import StrandAnalytics

final class GapEvidenceTests: XCTestCase {
    func testStrengthTotalsDoNotTurnMissingRatingsIntoZeroOrDoubleCountSessions() {
        let rows: [StrengthLoadHistory.Session] = [
            .init(id:"a",dayAge:0,durationSec:3600,rpe:5),
            .init(id:"a",dayAge:0,durationSec:3600,rpe:5),
            .init(id:"b",dayAge:6,durationSec:1800,rpe:nil),
            .init(id:"c",dayAge:7,durationSec:1200,rpe:6),
            .init(id:"d",dayAge:28,durationSec:3600,rpe:10)]
        let r = StrengthLoadHistory.summarize(rows)
        XCTAssertEqual(r.recent7.ratedSessions,1);XCTAssertEqual(r.recent7.unratedSessions,1)
        XCTAssertEqual(r.recent7.loadAU,300);XCTAssertEqual(r.context28.loadAU,420)
        XCTAssertNil(StrengthLoadHistory.summarize([]).recent7.loadAU)
    }
    func testConflictingIdsAndInvalidRatingsCannotInventLoad() {
        let r = StrengthLoadHistory.summarize([
            .init(id:"a",dayAge:0,durationSec:3600,rpe:5),.init(id:"a",dayAge:0,durationSec:3600,rpe:6),
            .init(id:"b",dayAge:1,durationSec:3600,rpe:.infinity),.init(id:"c",dayAge:-1,durationSec:30,rpe:5)])
        XCTAssertEqual(r.conflictingSessions,1);XCTAssertNil(r.context28.loadAU)
        XCTAssertEqual(r.context28.unratedSessions,1)
    }
    func testAlarmEvidenceRequiresSameSourceSameRequestAndActualSend() {
        func status(_ sent:Int?=2000,_ reported:Int?=2000,_ sid:String?="a",_ rid:String?="a",_ sat:Double?=900,_ rat:Double?=950,_ connected:Bool?=true)->String {
            AlarmDeliveryEvidence.status(enabled:true,protocolAllowed:true,plannedEpoch:2000,currentDevice:"a",sentEpoch:sent,reportedEpoch:reported,sentDevice:sid,reportedDevice:rid,sentAt:sat,reportedAt:rat,sentConnected:connected,now:1000)
        }
        XCTAssertEqual(status(),"last-readback-matches")
        XCTAssertEqual(status(2000,2300),"last-readback-differs")
        XCTAssertEqual(status(2000,2000,"b","b"),"different-source")
        XCTAssertEqual(status(1900),"different-request")
        XCTAssertEqual(status(2000,2000,"a","a",900,850),"stale-readback")
        XCTAssertEqual(status(2000,2000,"a","a",900,950,false),"queued-not-sent")
        XCTAssertEqual(status(2000,2000,"a","a",900,1100),"invalid-timestamps")
        XCTAssertEqual(status(nil),"no-send-evidence")
    }
func testReversePinnedActualCompiledOracle() {
var lines:[String]=[]
let rows: [StrengthLoadHistory.Session] = [.init(id:"a",dayAge:0,durationSec:3600,rpe:5),.init(id:"b",dayAge:7,durationSec:1200,rpe:6),.init(id:"c",dayAge:1,durationSec:30,rpe:nil)]
for values in [rows,rows+rows,[],[rows[0],.init(id:"a",dayAge:0,durationSec:3600,rpe:6)]] {
 let r=StrengthLoadHistory.summarize(values)
 lines.append("\(r.recent7.ratedSessions)|\(r.recent7.unratedSessions)|\(r.recent7.loadAU.map{String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "N")|\(r.context28.loadAU.map{String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "N")|\(r.conflictingSessions)")
}
for flag in [true,false] { for delta in [0,120,121,Int.max] {
 lines.append(AlarmDeliveryEvidence.status(enabled:true,protocolAllowed:flag,plannedEpoch:2000,currentDevice:"a",sentEpoch:2000,reportedEpoch:delta==Int.max ? Int.max : 2000+delta,sentDevice:"a",reportedDevice:"a",sentAt:900,reportedAt:950,sentConnected:true,now:1000))
} }
lines.append(AlarmDeliveryEvidence.status(enabled:true,protocolAllowed:true,plannedEpoch:2000,currentDevice:"a",sentEpoch:2000,reportedEpoch:2000,sentDevice:"a",reportedDevice:"a",sentAt:900,reportedAt:950,sentConnected:true,now:.nan))

XCTAssertEqual(lines.joined(separator:"\n"),"""
1|1|300.0|420.0|0
1|1|300.0|420.0|0
0|0|N|N|0
0|0|N|N|1
last-readback-matches
last-readback-matches
last-readback-differs
invalid-timestamps
experimental-blocked
experimental-blocked
experimental-blocked
experimental-blocked
invalid-timestamps
""")
}
}
