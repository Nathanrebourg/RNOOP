import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class BeatHRConcordanceTests: XCTestCase {
    func h(_ bpm: Int=60)->[HRSample] { (0..<120).map { .init(ts:$0,bpm:bpm) } }
    func rr(_ ms: Int=1000)->[RRInterval] { (0..<120).map { .init(ts:$0,rrMs:ms,srcChannel:RRSourceChannel(rawValue:5)) } }
    func testMatchingIndependentSignalsHaveNoDiscrepancy() {
        let r=BeatHRConcordance.analyze(hr:h(),rr:rr(),start:0,end:120)
        XCTAssertEqual(r.status,"observed");XCTAssertEqual(r.matchedSeconds,120)
        XCTAssertEqual(r.medianAbsoluteBPM,0);XCTAssertEqual(r.discrepantSeconds,0)
        XCTAssertEqual(r.trace(day:"2024-10-04"),"lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=observed matchedSec=120 medianAbsBpm=0.00 medianSignedBpm=0.00 aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true")
    }
    func testSystematicMismatchIsDescribedWithoutChangingEitherStream() {
        let h=h(100), beats=rr()
        let r=BeatHRConcordance.analyze(hr:h,rr:beats,start:0,end:120)
        XCTAssertEqual(r.medianAbsoluteBPM,40);XCTAssertEqual(r.medianSignedBPM,40)
        XCTAssertEqual(r.discrepantSeconds,120);XCTAssertEqual(h.first?.bpm,100);XCTAssertEqual(beats.first?.rrMs,1000)
    }
    func testDuplicateDeliveriesCannotInflateIndependentSeconds() {
        let h=h(),beats=rr()
        let r=BeatHRConcordance.analyze(hr:h+h,rr:beats+beats,start:0,end:120)
        XCTAssertEqual(r.matchedSeconds,120);XCTAssertEqual(r.medianAbsoluteBPM,0)
    }
    func testConflictingHeartRatesAndTooLittleOverlapCannotScore() {
        let r=BeatHRConcordance.analyze(hr:h()+h(100),rr:rr(),start:0,end:120)
        XCTAssertNil(r.medianAbsoluteBPM);XCTAssertEqual(r.matchedSeconds,0)
        let sparse=BeatHRConcordance.analyze(hr:Array(h().prefix(59)),rr:rr(),start:0,end:120)
        XCTAssertEqual(sparse.status,"insufficient-overlap");XCTAssertNil(sparse.medianAbsoluteBPM)
    }
    func testTransportAndSessionProvenanceAreRequired() {
        let unknown=rr().map { RRInterval(ts:$0.ts,rrMs:$0.rrMs) }
        XCTAssertEqual(BeatHRConcordance.analyze(hr:h(),rr:unknown,start:0,end:120).status,"unverified-rr-source")
        XCTAssertEqual(BeatHRConcordance.analyze(hr:h(),rr:rr(),start:0,end:120,eligible:false).status,"ineligible-session")
        let mixed=rr()+[RRInterval(ts:0,rrMs:1000,srcChannel:RRSourceChannel(rawValue:7))]
        XCTAssertEqual(BeatHRConcordance.analyze(hr:h(),rr:mixed,start:0,end:120).status,"mixed-rr-source")
    }
    func testNonmatchingTimestampsAndOutOfWindowDataAreNotInvented() {
        let shifted=rr().map { RRInterval(ts:$0.ts+1000,rrMs:1000,srcChannel:RRSourceChannel(rawValue:5)) }
        let r=BeatHRConcordance.analyze(hr:h(),rr:shifted,start:0,end:120)
        XCTAssertEqual(r.matchedSeconds,0);XCTAssertNil(r.medianAbsoluteBPM)
    }
    func testBurstDeliveryHasOnlyOneVotePerSecond() {
        let burst=Array(repeating: RRInterval(ts:0,rrMs:500,srcChannel:RRSourceChannel(rawValue:5)),count:1000)
        let r=BeatHRConcordance.analyze(hr:h(),rr:rr()+burst,start:0,end:120)
        XCTAssertEqual(r.matchedSeconds,120);XCTAssertEqual(r.medianAbsoluteBPM,0);XCTAssertEqual(r.discrepantSeconds,1)
    }
    func testSignedDiscrepancyAndStrictToleranceRemainDescriptive() {
        let r=BeatHRConcordance.analyze(hr:h(50),rr:rr(),start:0,end:120)
        XCTAssertEqual(r.medianSignedBPM,-10);XCTAssertEqual(r.discrepantSeconds,0)
        XCTAssertTrue(r.trace(day:"2024-10-04").contains("noScoreEffect=true"))
        var regular:[String]=[],recovery:[String]=[]
        AlgorithmLab.replayDiagnostic(r.trace(day:"2024-10-04"),regularSink:{regular.append($0)},workoutSink:nil,recoverySink:{recovery.append($0)})
        XCTAssertTrue(regular.isEmpty);XCTAssertEqual(recovery.count,1)
    }

    func testDeepWindowWrapperKeepsOnlyItsOwnPeriods() {
        let hr=(0..<240).map { HRSample(ts:$0,bpm:$0<120 ? 60 : 100) }
        let rr=(0..<240).map { RRInterval(ts:$0,rrMs:1000,srcChannel:RRSourceChannel(rawValue:5)) }
        let s=SleepSession(start:0,end:240,efficiency:1,stages:[StageSegment(start:0,end:120,stage:"deep"),StageSegment(start:120,end:240,stage:"light")],restingHR:60,avgHRV:40)
        let deep=AlgorithmLab.concordanceLine(sessions:[s],hr:hr,rr:rr,deepWindow:true,eligible:true,day:"2024-10-04")
        let whole=AlgorithmLab.concordanceLine(sessions:[s],hr:hr,rr:rr,deepWindow:false,eligible:true,day:"2024-10-04")
        XCTAssertTrue(deep.contains("matchedSec=120 medianAbsBpm=0.00"))
        XCTAssertTrue(whole.contains("matchedSec=240 medianAbsBpm=20.00"))
    }

}
