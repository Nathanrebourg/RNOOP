import XCTest
import StrandAnalytics
import WhoopProtocol
@testable import sleeppsg

final class HierarchicalRecipeTests: XCTestCase {
    // A max-of-sleep classifier would incorrectly call this wake. The binary model must marginalize.
    func testBinaryGateMarginalizesThreeSleepEmissions() {
        let labels = HierarchicalRecipe.decode([["deep": -0.4, "rem": -0.4, "light": -0.4, "awake": 0]], minutes: [120])
        XCTAssertEqual(labels, ["deep"])
    }
    func testDecisiveWakeDoesNotGetReclassifiedBySecondStage() {
        let emissions = [["deep": -50.0, "rem": -50.0, "light": -50.0, "awake": 50.0],
                         ["deep": -50.0, "rem": 50.0, "light": -50.0, "awake": -50.0]]
        XCTAssertEqual(HierarchicalRecipe.decode(emissions, minutes: [0, 120]), ["wake", "rem"])
    }
    func testNoSensorInputAbstainsForEveryEpoch() {
        let labels = HierarchicalRecipe.predict(start: 1_699_999_980, end: 1_700_000_100, grav: [], hr: [], rr: [])
        XCTAssertEqual(labels, ["unknown", "unknown", "unknown", "unknown"])
    }
    func testInteriorAndBoundaryGapsAreNotFilledByAdjacentStages() {
        let t = 1_699_999_980
        let labels = HierarchicalRecipe.predict(start: t, end: t+150, grav: [],
            hr: [.init(ts:t+30,bpm:60), .init(ts:t+90,bpm:60)], rr: [])
        XCTAssertEqual(labels.count, 5)
        guard labels.count == 5 else { return }
        XCTAssertEqual(labels[0], "unknown")
        XCTAssertNotEqual(labels[1], "unknown")
        XCTAssertEqual(labels[2], "unknown")
        XCTAssertNotEqual(labels[3], "unknown")
        XCTAssertEqual(labels[4], "unknown")
    }
    func testZeroHeartRateIsMissingNotSleeping() {
        let t = 1_699_999_980
        XCTAssertEqual(HierarchicalRecipe.predict(start:t,end:t+30,grav:[],hr:[.init(ts:t,bpm:0)],rr:[]),["unknown"])
    }
    func testZeroMotionVectorIsMissing() {
        let t = 1_699_999_980
        XCTAssertEqual(HierarchicalRecipe.predict(start:t,end:t+30,grav:[.init(ts:t,x:0,y:0,z:0)],hr:[],rr:[]),["unknown"])
    }
    func testEmptyAndMismatchedEmissionSequenceDoNotCrash() {
        XCTAssertEqual(HierarchicalRecipe.decode([], minutes: []), [])
        XCTAssertEqual(HierarchicalRecipe.decode([["deep":0,"rem":0,"light":0,"awake":0]], minutes: []), [])
    }
    func testGapResetsSequenceInferenceBetweenObservedBlocks() {
        func feature(_ start:Int,_ motion:Double,_ hr:Double) -> V2Recipe.Epoch {
            .init(start:start,hr:hr,hrVar:hr/50,hrFlat11:hr/60,moveFrac:motion,jerkMax:motion*100,respReg:nil,clock:0.5,jerkScale:1,minutesSinceOnset:Double(start)/60)
        }
        let first=[feature(0,1,100),feature(30,1,110),feature(60,0.7,90)]
        let second=[feature(120,0,55),feature(150,0,56),feature(180,0.2,58)]
        XCTAssertEqual(HierarchicalRecipe.labels(first+second),HierarchicalRecipe.labels(first)+HierarchicalRecipe.labels(second))
    }

}
