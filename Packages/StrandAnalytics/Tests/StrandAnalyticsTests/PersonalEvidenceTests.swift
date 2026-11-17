import XCTest
@testable import StrandAnalytics

final class PersonalEvidenceTests:XCTestCase {
    func journal(_ delta:Double=10)->[MatchedJournalComparison.Row] {
        (0..<8).flatMap { i in
            [MatchedJournalComparison.Row(day:10000+i*7,context:"same",answer:true,outcome:60+delta),
             .init(day:10001+i*7,context:"same",answer:false,outcome:60)]
        }
    }
    func testMatchedJournalHandComputedSignTestAndFullFamilyHolm() {
        let r=MatchedJournalComparison.analyze([.init(id:"a",rows:journal()),.init(id:"b",rows:journal(0))])
        XCTAssertEqual(r[0].pairs,8);XCTAssertEqual(r[0].medianDelta,10)
        XCTAssertEqual(r[0].p ?? 0,0.0078125,accuracy:1e-12)
        XCTAssertEqual(r[0].adjustedP ?? 0,0.015625,accuracy:1e-12)
        XCTAssertTrue(r[0].association);XCTAssertFalse(r[1].association)
    }
    func testJournalUnknownConflictingAndUnmatchedDaysNeverBecomeControls() {
        var x=journal();x[1] = .init(day:x[1].day,context:"other",answer:false,outcome:60)
        x.append(.init(day:x[3].day,context:"same",answer:true,outcome:60))
        x.append(.init(day:20000,context:"same",answer:nil,outcome:0))
        let r=MatchedJournalComparison.analyze([.init(id:"x",rows:x)])[0]
        XCTAssertEqual(r.pairs,6);XCTAssertNil(r.p);XCTAssertFalse(r.association)
        XCTAssertTrue(MatchedJournalComparison.analyze([.init(id:"x",rows:x),.init(id:"x",rows:x)]).isEmpty)
    }
    func testJournalOnePairPerWeekAndNoCherryPickedLag() {
        let x=(0..<7).map{MatchedJournalComparison.Row(day:10000+$0,context:"same",answer:$0%2==0,outcome:Double($0))}
        XCTAssertLessThanOrEqual(MatchedJournalComparison.analyze([.init(id:"x",rows:x)])[0].pairs,2)
    }
    func shift(_ recent:Double=70)->[BaselineShiftEvidence.Sample] {
        (1...35).map{.init(age:$0,value:$0<=7 ? recent:60,era:"one")}
    }
    func testRobustShiftCountsMissingAndDoesNotResetReference() {
        let r=BaselineShiftEvidence.analyze(shift(),floor:3,bounds:20...250)
        XCTAssertEqual(r.priorMedian,60);XCTAssertEqual(r.recentMedian,70)
        XCTAssertEqual(r.scaledDelta ?? 0,10.0/3,accuracy:1e-12);XCTAssertTrue(r.shift)
        XCTAssertFalse(BaselineShiftEvidence.analyze(shift(60),floor:3,bounds:20...250).shift)
        XCTAssertNil(BaselineShiftEvidence.analyze(Array(shift().dropFirst(4)),floor:3,bounds:20...250).scaledDelta)
    }
    func testShiftConflictsAndEraChangesRefuseComparison() {
        var x=shift();x[0] = .init(age:1,value:70,era:"two")
        XCTAssertEqual(BaselineShiftEvidence.analyze(x,floor:3,bounds:20...250).status,"context-changed")
        x=shift();x.append(.init(age:1,value:80,era:"one"));x.append(.init(age:0,value:200,era:"one"))
        XCTAssertEqual(BaselineShiftEvidence.analyze(x,floor:3,bounds:20...250).recentCount,6)
        XCTAssertNil(BaselineShiftEvidence.analyze(x,floor:.nan,bounds:20...250).scaledDelta)
    }
    func training()->[TrainingResponseForecast.Day] {
        (0...180).map{.init(day:$0,recovery:$0>0 && ($0-1)%3==0 ? 40:80,effort:$0%3==0 ? 100:0,era:"one")}
    }
    func testForecastIsTestedChronologicallyAgainstPersistence() {
        let r=TrainingResponseForecast.analyze(training(),origin:180,horizon:1)
        XCTAssertEqual(r.status,"qualified-experimental");XCTAssertEqual(r.prediction,40)
        XCTAssertGreaterThanOrEqual(r.evaluated,8);XCTAssertEqual(r.modelMAE,0);XCTAssertEqual(r.baselineMAE,40)
        XCTAssertNil(TrainingResponseForecast.analyze(training(),origin:180,horizon:2).prediction)
    }
    func testForecastFutureRowsAndOrderCannotImproveItsPastEvaluation() {
        let x=training(),a=TrainingResponseForecast.analyze(x,origin:180,horizon:1)
        let future=x+[.init(day:181,recovery:100,effort:0,era:"one")]
        let b=TrainingResponseForecast.analyze(future.reversed(),origin:180,horizon:1)
        XCTAssertEqual(a.prediction,b.prediction);XCTAssertEqual(a.modelMAE,b.modelMAE);XCTAssertEqual(a.evaluated,b.evaluated)
        XCTAssertNil(TrainingResponseForecast.analyze(x,origin:180,horizon:0).prediction)
    }
    func testForecastMissingOriginAndForeignEraFailClosed() {
        XCTAssertNil(TrainingResponseForecast.analyze(Array(training().dropLast()),origin:180,horizon:1).prediction)
        var x=training();x[x.count-1] = .init(day:180,recovery:80,effort:100,era:"new")
        XCTAssertNil(TrainingResponseForecast.analyze(x,origin:180,horizon:1).prediction)
        x=training();x.append(.init(day:180,recovery:50,effort:100,era:"one"))
        XCTAssertNil(TrainingResponseForecast.analyze(x,origin:180,horizon:1).prediction)
    }
    func observation(_ id:String,_ estimate:Double,_ reference:Double,_ fitted:Bool=false)->ReferenceValidation.Observation {
        .init(id:id,order:1,method:"scale1",kind:"steps",estimate:estimate,reference:reference,usedForCalibration:fitted)
    }
    func testValidationSeparatesFittingFromVerificationAndUsesSignedBias() {
        let x=[observation("a",110,100),observation("b",80,100),observation("fit",1000,100,true)]
        let r=ReferenceValidation.analyze(x,method:"scale1",kind:"steps")
        XCTAssertEqual(r.count,2);XCTAssertEqual(r.mae,15);XCTAssertEqual(r.bias,-5)
        XCTAssertEqual(r.excluded,1)
    }
    func testValidationConflictingIDsMethodsAndUnitsCannotInflateEvidence() {
        var x=[observation("a",110,100),observation("a",110,100),observation("b",80,100),observation("b",90,100)]
        x.append(.init(id:"c",order:1,method:"other",kind:"steps",estimate:1000,reference:100,usedForCalibration:false))
        x.append(.init(id:"d",order:1,method:"scale1",kind:"sleep-start-minutes",estimate:30,reference:0,usedForCalibration:false))
        let r=ReferenceValidation.analyze(x,method:"scale1",kind:"steps")
        XCTAssertEqual(r.count,1);XCTAssertEqual(r.mae,10)
        XCTAssertEqual(ReferenceValidation.analyze(x,method:"scale1",kind:"sleep-start-minutes").mae,30)
    }
    func testExtremeFiniteBaselineValuesWithholdNonfiniteResult() {
        let r=BaselineShiftEvidence.analyze((1...35).map{.init(age:$0,value:Double.greatestFiniteMagnitude,era:"x")},floor:Double.leastNormalMagnitude,bounds:0...Double.greatestFiniteMagnitude)
        XCTAssertEqual(r.status,"invalid-input");XCTAssertNil(r.scaledDelta)
    }
}
