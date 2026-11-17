import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

final class ExerciseGpsResearchAdapterTests:XCTestCase {
    private func row(_ sport:String = "walk")->WorkoutRow {
        .init(startTs:1000,endTs:1900,sport:sport,source:"GPS",durationS:900,energyKcal:nil,avgHr:nil,maxHr:nil,strain:nil,distanceM:1609.344,zonesJSON:nil,notes:nil,steps:nil)
    }
    func testLegacyPolylineDoesNotInventTimingOrAccuracy() {
        let route=WorkoutRoute(polyline:RouteMath.encode([.init(0,0),.init(0,0.014473)]),distanceM:1609.344)
        let input=ExerciseGpsResearchAdapter.input(row:row(),route:route,owner:nil,heartRates:[])
        XCTAssertEqual(input.sport,"walking")
        XCTAssertEqual(input.fixes.count,2)
        for fix in input.fixes { XCTAssertNil(fix.time);XCTAssertNil(fix.accuracyM) }
        let result=ExerciseGpsEvidence.evaluate(input)
        XCTAssertNil(result.metersPerBeat)
        XCTAssertNil(result.vo2max)
        XCTAssertTrue(result.reasons.contains("gps-timing-missing"))
    }
    func testRecordedWitnessesAndFinalHeartRateGate() {
        let points=(0...90).map {WorkoutRoutePoint(lat:0,lon:Double($0)*0.014473/90,accuracyM:5,tMs:Int64(1000+$0*10)*1000)}
        let route=WorkoutRoute(polyline:"",distanceM:1609.344,points:points)
        let hr=(0...900).map {ExerciseGpsEvidence.HeartRate(time:Double(1000+$0),bpm:120,owner:"strap")}
        let input=ExerciseGpsResearchAdapter.input(row:row(),route:route,owner:"strap",heartRates:hr)
        XCTAssertEqual(input.fixes[1].time,1010)
        XCTAssertEqual(input.fixes[1].accuracyM,5)
        let evidence=ExerciseGpsEvidence.evaluate(input)
        XCTAssertNotNil(evidence.metersPerBeat)
        let estimate=ExerciseGpsResearchAdapter.kline(row:row(),input:input,evidence:evidence,age:40,weightKg:70,sex:1,repeatSeconds:920,confirmed:true)
        XCTAssertEqual(estimate?.litersPerMinute ?? 0,3.1970446094,accuracy:0.000001)
        var missingFinish=input
        missingFinish.heartRates=Array(hr.dropLast(6))
        let stillPaired=ExerciseGpsEvidence.evaluate(missingFinish)
        XCTAssertNotNil(stillPaired.metersPerBeat)
        XCTAssertNil(ExerciseGpsResearchAdapter.kline(row:row(),input:missingFinish,evidence:stillPaired,age:40,weightKg:70,sex:1,repeatSeconds:920,confirmed:true))
        XCTAssertNil(ExerciseGpsResearchAdapter.kline(row:row(),input:input,evidence:evidence,age:40,weightKg:70,sex:1,repeatSeconds:920,confirmed:false))
    }
}
