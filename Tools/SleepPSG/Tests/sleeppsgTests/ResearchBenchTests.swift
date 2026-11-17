import XCTest
import WhoopProtocol
import StrandAnalytics
@testable import sleeppsg

final class ResearchBenchTests:XCTestCase {
    func night(_ truth:[String?]=["wake","light",nil,"rem"]) -> ResearchNight {
        let start=SleepAccel.timeBase
        return .init(schema:1,dataset:"bidsleep-1.0.1",reference:"dreem2-expert",origin:"synthetic",subject:"fixture",night:"1",split:"training",start:start,end:start+truth.count*30,
            hr:(0..<(truth.count*6)).map { .init(ts:start+$0*5,bpm:60) },gravity:(0..<(truth.count*30)).map { .init(ts:start+$0,x:0,y:0,z:1) },truth:truth)
    }
    func testShippedVariantIsActualStagerAndUnknownReferenceIsExcluded() throws {
        let n=night();let r=try ResearchBench.evaluate(n,variants:["shipped"])
        let actual=SleepStagerV2.stageSession(start:n.start,end:n.end,grav:n.gravity,hr:n.hr,rr:[],resp:[])
        XCTAssertEqual(r.variants["shipped"]!.predictions,epochLabels(actual,start:n.start,end:n.end))
        XCTAssertEqual(r.variants["shipped"]!.epochs,3)
        XCTAssertEqual(r.variants["shipped"]!.confusion.flatMap{$0}.reduce(0,+),3)
        XCTAssertEqual(r.quality,1,accuracy:1e-12)
    }
    func testUnrequestedVariantsNeverRunAndUnknownRecipeIsRejected() throws {
        let r=try ResearchBench.evaluate(night(),variants:["shipped","awake-020"])
        XCTAssertEqual(Set(r.variants.keys),Set(["shipped","awake-020"]))
        XCTAssertThrowsError(try ResearchBench.evaluate(night(),variants:["unfrozen-candidate"]))
    }
    func testMissingScoredEpochsAndBadLabelsAreNotScoredAsWake() {
        XCTAssertThrowsError(try ResearchBench.evaluate(night([nil,nil]),variants:["shipped"]))
        XCTAssertThrowsError(try ResearchBench.evaluate(night(["unrecognized"]),variants:["shipped"]))
    }
    func testHierarchicalUnknownPredictionsHaveCoverageButNoConditionalAccuracy() throws {
        let base=night(["wake","wake","wake","wake"])
        let n=ResearchNight(schema:base.schema,dataset:base.dataset,reference:base.reference,origin:base.origin,subject:base.subject,night:base.night,split:base.split,start:base.start,end:base.end,hr:[],gravity:[],truth:base.truth)
        let r=try ResearchBench.evaluate(n,variants:["hierarchical-v1"])
        let x=try XCTUnwrap(r.variants["hierarchical-v1"])
        XCTAssertEqual(x.predictions,["unknown","unknown","unknown","unknown"])
        XCTAssertEqual(x.epochs,0)
        XCTAssertNil(x.accuracy)
        XCTAssertNil(x.macroF1)
        XCTAssertEqual(x.coverage?.referenceEpochs,4)
        XCTAssertEqual(x.coverage?.predictedReferenceEpochs,0)
        XCTAssertEqual(x.coverage?.unknownReferenceEpochs,4)
        XCTAssertEqual(x.coverage?.referenceAccuracy,0)
    }

    func testNativeFullReferenceMetricsCountAbstentionAsFalseNegative() throws {
        let base=night(["light","light"])
        let n=ResearchNight(schema:base.schema,dataset:base.dataset,reference:base.reference,origin:base.origin,subject:base.subject,night:base.night,split:base.split,start:base.start,end:base.end,
            hr:[.init(ts:base.start,bpm:60)],gravity:[],truth:base.truth)
        let x=try XCTUnwrap(ResearchBench.evaluate(n,variants:["hierarchical-v1"]).variants["hierarchical-v1"])
        XCTAssertEqual(x.predictions,["light","unknown"])
        XCTAssertEqual(x.accuracy,1)
        XCTAssertEqual(x.macroF1,0.25)
        XCTAssertEqual(x.perStage["light"]?.support,1)
        XCTAssertEqual(x.metricScope,"conditional-on-nonunknown-predictions")
        let full=try XCTUnwrap(x.fullReference)
        XCTAssertEqual(full.epochs,2)
        XCTAssertEqual(full.confusionColumns,["wake","light","deep","rem","unknown"])
        XCTAssertEqual(full.confusion,[[0,0,0,0,0],[0,1,0,0,1],[0,0,0,0,0],[0,0,0,0,0]])
        XCTAssertEqual(full.accuracy,0.5)
        XCTAssertEqual(full.macroF1,1.0/6,accuracy:1e-12)
        XCTAssertEqual(full.perStage["light"]?.support,2)
        XCTAssertEqual(full.perStage["light"]?.precision,1)
        XCTAssertEqual(full.perStage["light"]?.recall,0.5)
        XCTAssertEqual(try XCTUnwrap(full.perStage["light"]?.f1),2.0/3,accuracy:1e-12)
    }

}
