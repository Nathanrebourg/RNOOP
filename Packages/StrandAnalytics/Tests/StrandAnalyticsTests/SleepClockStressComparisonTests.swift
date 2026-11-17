import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepClockStressComparisonTests: XCTestCase {
    private func night(_ day: Int, bed: Int = 1430, wake: Int = 470,
                       stages: [SleepClockStressComparison.Stage]? = nil) -> SleepClockStressComparison.Night {
        let start = day * 86_400 - 28_800
        return .init(day: day, start: start, end: start + 28_800, bedtimeMinute: bed, wakeMinute: wake,
                     stages: stages ?? [.init(start: start, end: start + 28_800, kind: "light")], sparse: false)
    }
    func testWrapAndNoFutureLeakage() throws {
        let target = night(40, bed: 10, wake: 490)
        let r = SleepClockStressComparison.analyze(target: target,
            history: [night(39), night(38), night(37), night(41, bed: 720), night(40, bed: 720)], now: target.end)
        XCTAssertEqual(r.priorNights, 3)
        XCTAssertEqual(try XCTUnwrap(r.clock), 5.0 / 6, accuracy: 0.000001)
        XCTAssertEqual(r.duration, 1)
        XCTAssertEqual(r.efficiency, 1)
        XCTAssertNil(r.candidate)
        XCTAssertEqual(r.stressStatus, "night-stress-provenance-unavailable")
    }
    func testDuplicatesDoNotCreateHistoryAndConflictsExcludeDate() {
        let r = SleepClockStressComparison.analyze(target: night(40),
            history: [night(39), night(39), night(38), night(38, bed: 10), night(37)], now: 40 * 86_400)
        XCTAssertEqual(r.priorNights, 2)
        XCTAssertNil(r.clock)
    }
    func testCoverageOverlapMalformedAndMissingStagesWithholdComponents() {
        let n = night(40), s = n.start
        for stages in [[], [.init(start: s, end: s + 20_000, kind: "light")],
                       [.init(start: s, end: s + 28_800, kind: "unknown")],
                       [.init(start: s, end: s + 28_800, kind: "light"), .init(start: s + 100, end: s + 200, kind: "awake")],
                       [.init(start: s + 100, end: s, kind: "light")]] as [[SleepClockStressComparison.Stage]] {
            let bad = SleepClockStressComparison.Night(day: 40, start: s, end: n.end, bedtimeMinute: 1430,
                                                       wakeMinute: 470, stages: stages, sparse: false)
            let r = SleepClockStressComparison.analyze(target: bad, history: [], now: n.end)
            XCTAssertNil(r.duration); XCTAssertNil(r.efficiency); XCTAssertNil(r.candidate)
        }
    }
    func testAwakeDurationAndDuplicateStages() throws {
        let n = night(40), s = n.start
        let stages: [SleepClockStressComparison.Stage] = [.init(start:s,end:s+7_200,kind:"awake"),
            .init(start:s+7_200,end:n.end,kind:"light"), .init(start:s+7_200,end:n.end,kind:"light")]
        let mixed = SleepClockStressComparison.Night(day:40,start:s,end:n.end,bedtimeMinute:1430,wakeMinute:470,stages:stages,sparse:false)
        let r = SleepClockStressComparison.analyze(target:mixed,history:[],now:n.end)
        XCTAssertEqual(try XCTUnwrap(r.duration),0.75,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(r.efficiency),0.75,accuracy:0.000001)
        XCTAssertEqual(r.coverage,1)
    }
    func testInvalidClockIncompleteAndSparse() {
        let n = night(40)
        let bad = SleepClockStressComparison.Night(day:40,start:n.start,end:n.end,bedtimeMinute:1440,wakeMinute:470,stages:n.stages,sparse:false)
        XCTAssertEqual(SleepClockStressComparison.analyze(target:bad,history:[],now:n.end).status,"invalid-night")
        XCTAssertEqual(SleepClockStressComparison.analyze(target:n,history:[],now:n.end-1).status,"unfinished-night")
        let sparse = SleepClockStressComparison.Night(day:40,start:n.start,end:n.end,bedtimeMinute:1430,wakeMinute:470,stages:n.stages,sparse:true)
        XCTAssertNil(SleepClockStressComparison.analyze(target:sparse,history:[],now:n.end).duration)
    }
    func testCircularBoundaryAndReverseOracle() {
        XCTAssertEqual([SleepClockStressComparison.circularDistance(1430,10),
                        SleepClockStressComparison.circularDistance(0,720),
                        SleepClockStressComparison.circularDistance(15,15)], [20,720,0])
        XCTAssertEqual(oracle(),"20,720,0|1.000000,1.000000,0.833333,1.000000,3,nil|2,nil")
    }
    private func oracle()->String {
        let n=night(40,bed:10,wake:490)
        let r=SleepClockStressComparison.analyze(target:n,history:[night(39),night(38),night(37)],now:n.end)
        let q=SleepClockStressComparison.analyze(target:n,history:[night(39),night(39),night(38)],now:n.end)
        func f(_ x:Double?)->String{x.map{String(format:"%.6f",$0)} ?? "nil"}
        return "20,720,0|\(f(r.duration)),\(f(r.efficiency)),\(f(r.clock)),\(f(r.coverage)),\(r.priorNights),\(f(r.candidate))|\(q.priorNights),\(f(q.clock))"
    }
    func testRichRawWitnessAndHonestFailureGates() throws {
        let n=night(40)
        let hr=(n.start..<n.end).map {HRSample(ts:$0,bpm:60)}
        let rr=(n.start..<n.end).map {RRInterval(ts:$0,rrMs:$0%2 == 0 ? 980:1020,srcChannel:.whoop5Historical)}
        let gravity=(n.start..<n.end).map {GravitySample(ts:$0,x:0,y:0,z:1)}
        let p=SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:gravity,confirmedWhoop5:true)
        XCTAssertEqual(p.status,"qualified");XCTAssertEqual(p.coverage,1);XCTAssertEqual(p.windows,96)
        let priors=[night(39),night(38),night(37)]
        let ps=priors.map {SleepClockStressComparison.Physiology(day:$0.day,start:$0.start,end:$0.end,channel:p.channel,hr:p.hr,rmssd:p.rmssd,coverage:p.coverage,windows:p.windows,status:p.status)}
        let r=SleepClockStressComparison.analyze(target:n,history:priors,now:n.end,physiology:p,priorPhysiology:ps)
        XCTAssertEqual(try XCTUnwrap(r.candidate),92.5,accuracy:0.000001)
        XCTAssertEqual(r.calmness,0.5)
        XCTAssertEqual(SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:gravity,confirmedWhoop5:false).status,"unconfirmed-whoop5-source")
        XCTAssertEqual(SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:gravity,confirmedWhoop5:true,readCapped:true).status,"read-capped")
        XCTAssertNil(SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:[],confirmedWhoop5:true).rmssd)
        let duplicates=SleepClockStressComparison.physiology(night:n,hr:hr+hr,rr:rr+rr,gravity:gravity+gravity,confirmedWhoop5:true)
        XCTAssertEqual(duplicates.status,p.status);XCTAssertEqual(duplicates.rmssd,p.rmssd)
        let conflict=RRInterval(ts:n.start,rrMs:980,srcChannel:.whoop5Historical,ord:1)
        XCTAssertEqual(SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr+[conflict],gravity:gravity,confirmedWhoop5:true).status,"conflicting-rr-identity")
        let mixed=RRInterval(ts:n.start,rrMs:980,srcChannel:.whoop5Realtime)
        XCTAssertEqual(SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr+[mixed],gravity:gravity,confirmedWhoop5:true).status,"rr-source-unavailable-or-mixed")
        let sparseHR=hr.filter{$0.ts%60 == 0}
        XCTAssertNil(SleepClockStressComparison.physiology(night:n,hr:sparseHR,rr:rr,gravity:gravity,confirmedWhoop5:true).hr)
    }

    func testQualifiedLabelAloneCannotSubstituteForValidCoverageOrChannel() {
        let n=night(40),prior=[night(39),night(38),night(37)]
        let ps=prior.map{SleepClockStressComparison.Physiology(day:$0.day,start:$0.start,end:$0.end,channel:5,hr:60,rmssd:40,coverage:1,windows:96,status:"qualified")}
        for (channel,cov,windows) in [(Optional<Int>.none,1.0,96),(Optional(6),1.0,96),(Optional(5),Double.nan,96),(Optional(5),0.5,96),(Optional(5),1.0,97)] {
            let p=SleepClockStressComparison.Physiology(day:n.day,start:n.start,end:n.end,channel:channel,hr:60,rmssd:40,coverage:cov,windows:windows,status:"qualified")
            XCTAssertNil(SleepClockStressComparison.analyze(target:n,history:prior,now:n.end,physiology:p,priorPhysiology:ps).candidate)
        }
    }
    func testActualCompiledRawOracleReversePin() {
        var lines:[String]=[]
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
 lines.append([r.status,f(r.duration),f(r.efficiency),f(r.clock),f(r.calmness),f(r.candidate),String(r.priorNights),String(r.baselineNights),r.stressStatus].joined(separator:"|"))
}
for value in [p,raw(target,confirmed:false),raw(target,capped:true),raw(target,dropMotion:true),raw(target,channel:.whoop5Realtime)] {
 lines.append([value.status,String(value.channel ?? -1),f(value.hr),f(value.rmssd),f(value.coverage),String(value.windows)].joined(separator:"|"))
}

XCTAssertEqual(lines.joined(separator:"\n"),"""
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|0|night-stress-provenance-unavailable
compared|1.000000|1.000000|0.833333|0.500000|89.166667|3|3|qualified-nocturnal-activation-proxy
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|2|insufficient-prior-night-baseline
candidate-withheld|1.000000|1.000000|0.833333|nil|nil|3|0|insufficient-prior-night-baseline
qualified|5|60.000000|40.000000|1.000000|96
unconfirmed-whoop5-source|-1|nil|nil|0.000000|0
read-capped|-1|nil|nil|0.000000|0
insufficient-night-signal|5|nil|nil|0.000000|0
rr-source-unavailable-or-mixed|-1|nil|nil|0.000000|0
""")
    }
}
