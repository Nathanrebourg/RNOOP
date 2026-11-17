import XCTest
@testable import StrandAnalytics

final class ResearchModelsTests: XCTestCase {
    let cfg = Baselines.hrvCfg
    func testFullQualityIsExactlyTheIncumbentIncludingMissingAndOutliers() {
        let values: [Double?] = [nil,60,62,58,61,59,60,61,60,250,nil]
        let r = QualityBaseline.fold(values: values, qualities: values.map { _ in 1 }, cfg: cfg)
        XCTAssertEqual(r.original, Baselines.foldHistory(values, cfg: cfg))
        XCTAssertEqual(r.candidate, r.original)
    }
    func testUnknownAndLowQualityCannotSeedThePersonalReference() {
        let r = QualityBaseline.fold(values: [200,180,60,62], qualities: [nil,0.1,1,1], cfg: cfg)
        XCTAssertEqual(r.unknown,1); XCTAssertEqual(r.rejected,1)
        XCTAssertEqual(r.candidate, Baselines.foldHistory([nil,nil,60,62],cfg:cfg))
        XCTAssertEqual(r.admitted,2)
    }
    func testPartialQualityDampensAValidNightWithoutCallingItsValueBad() {
        let a = QualityBaseline.fold(values:[60,80],qualities:[1,1],cfg:cfg)
        let b = QualityBaseline.fold(values:[60,80],qualities:[1,0.5],cfg:cfg)
        XCTAssertGreaterThan(b.candidate!.baseline,60)
        XCTAssertLessThan(b.candidate!.baseline,a.candidate!.baseline)
        XCTAssertEqual(b.admitted,2)
    }
    func testMissingNightsAgeAndMalformedWitnessesNeverBecomeGood() {
        let v:[Double?] = [60,61,59,60] + Array(repeating:60,count:15)
        let q:[Double?] = [1,1,1,1] + Array(repeating:nil,count:15)
        XCTAssertEqual(QualityBaseline.fold(values:v,qualities:q,cfg:cfg).candidate!.status,.stale)
        XCTAssertNil(QualityBaseline.fold(values:[60],qualities:[],cfg:cfg).candidate)
        let r = QualityBaseline.fold(values:[60,61,62],qualities:[.nan,-1,2],cfg:cfg)
        XCTAssertEqual(r.candidate!.nValid,0); XCTAssertEqual(r.rejected,3)
    }
    func testFirstAdmittedNightDoesNotBlendWithSyntheticPlaceholder() {
        let r = QualityBaseline.fold(values:[nil,70],qualities:[nil,0.5],cfg:cfg)
        XCTAssertEqual(r.candidate!.baseline,70); XCTAssertEqual(r.candidate!.nValid,1)
    }
    func testExplanationUsesTheRealScorerAndContributionsSumOnlyInZSpace() {
        let h = Baselines.foldHistory(Array(repeating:60,count:15),cfg:cfg)
        let r = Baselines.foldHistory(Array(repeating:55,count:15),cfg:Baselines.metricCfg["resting_hr"]!)
        let x = RecoveryExplanation.describe(hrv:45,rhr:60,resp:nil,hrvBaseline:h,rhrBaseline:r,respBaseline:nil,sleepPerf:0.9,skinTempDev:nil)
        XCTAssertEqual(x.score,RecoveryScorer.recovery(hrv:45,rhr:60,resp:nil,hrvBaseline:h,rhrBaseline:r,respBaseline:nil,sleepPerf:0.9))
        XCTAssertEqual(x.terms.reduce(0){$0+$1.normalizedWeight},1,accuracy:1e-12)
        XCTAssertEqual(x.terms.reduce(0){$0+$1.contributionZ},x.compositeZ!,accuracy:1e-12)
        XCTAssertEqual(x.missing,["resp","skin"])
    }
    func testExplanationRetainsZeroHRVAndDeclinesUnusableOrNonfiniteInputs() {
        let b=Baselines.foldHistory(Array(repeating:60,count:8),cfg:cfg)
        let x=RecoveryExplanation.describe(hrv:0,rhr:60,resp:nil,hrvBaseline:b,rhrBaseline:nil,respBaseline:nil,sleepPerf:nil,skinTempDev:nil)
        XCTAssertNotNil(x.score); XCTAssertEqual(x.terms.count,1)
        let cold=Baselines.foldHistory([60],cfg:cfg)
        XCTAssertNil(RecoveryExplanation.describe(hrv:60,rhr:60,resp:nil,hrvBaseline:cold,rhrBaseline:nil,respBaseline:nil,sleepPerf:nil,skinTempDev:nil).score)
        XCTAssertNil(RecoveryExplanation.describe(hrv:.nan,rhr:60,resp:nil,hrvBaseline:b,rhrBaseline:nil,respBaseline:nil,sleepPerf:nil,skinTempDev:nil).score)
    }
    func testReversePinnedBaselineFixture() {
        let x=QualityBaseline.fold(values:[60,80],qualities:[1,0.5],cfg:cfg)
        XCTAssertEqual(String(format:"%.6f",x.candidate!.baseline),"62.062995")
        XCTAssertEqual(String(format:"%.6f",x.candidate!.spread),"5.176530")
    }

    func testCompiledOracleRecordsStayPinned() {
        func num(_ x:Double?)->String { x.map { String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),$0) } ?? "nil" }
        var lines:[String] = []
  let values:[[Double?]]=[[60,62,58,61],[200,180,60,62],[60,80],[60,80],[nil,70],[60,61,59,60]+Array(repeating:60,count:15),[60,61,62],[60]]
  let quality:[[Double?]]=[[1,1,1,1],[nil,0.1,1,1],[1,1],[1,0.5],[nil,0.5],[1,1,1,1]+Array(repeating:nil,count:15),[.nan,-1,2],[]]
  for (v,q) in zip(values,quality) {
   let x=QualityBaseline.fold(values:v,qualities:q,cfg:Baselines.hrvCfg)
   lines.append("baseline|\(num(x.candidate?.baseline))|\(num(x.candidate?.spread))|\(x.candidate?.nValid ?? -1)|\(x.candidate?.nightsSinceUpdate ?? -1)|\(x.admitted)|\(x.unknown)|\(x.rejected)|\(x.status)")
  }
  let h=Baselines.foldHistory(Array(repeating:60,count:15),cfg:Baselines.hrvCfg)
  let r=Baselines.foldHistory(Array(repeating:55,count:15),cfg:Baselines.metricCfg["resting_hr"]!)
  let b=Baselines.foldHistory(Array(repeating:14,count:15),cfg:Baselines.metricCfg["resp"]!)
  for i in 0..<4 {
   let x=RecoveryExplanation.describe(hrv:i==1 ? 0 : 45,rhr:60,resp:i==2 ? 16 : nil,hrvBaseline:i==3 ? Baselines.foldHistory([60],cfg:Baselines.hrvCfg) : h,rhrBaseline:i==1 ? nil : r,respBaseline:b,sleepPerf:i==1 ? nil : 0.9,skinTempDev:i==2 ? -0.4 : nil)
   lines.append("explain|\(num(x.score))|\(num(x.compositeZ))|\(x.status)|\(x.missing.joined(separator:","))|"+x.terms.map { "\($0.name):\(num($0.z)):\(num($0.normalizedWeight)):\(num($0.contributionZ))" }.joined(separator:";"))
  }
        XCTAssertEqual(lines.joined(separator:"\n"),"""
baseline|60.138741|5.000000|4|0|4|0|0|compared
baseline|60.412599|5.000000|2|0|2|1|1|calibrating
baseline|64.125989|5.353060|2|0|2|0|0|calibrating
baseline|62.062995|5.176530|2|0|2|0|0|calibrating
baseline|70.000000|5.000000|1|0|1|1|0|calibrating
baseline|59.966221|5.000000|4|15|4|15|0|stale
baseline|127.500000|5.000000|0|3|0|0|3|calibrating
baseline|nil|nil|-1|-1|0|0|0|mismatched-history
explain|6.790370|-1.837091|explained|resp,skin|hrv:-2.394254:0.611111:-1.463155;rhr:-1.995211:0.222222:-0.443380;sleep:0.416667:0.166667:0.069444
explain|0.000030|-9.577015|explained|rhr,resp,sleep,skin|hrv:-9.577015:1.000000:-9.577015
explain|6.831929|-1.832999|explained||hrv:-2.394254:0.550000:-1.316840;rhr:-1.995211:0.200000:-0.399042;resp:-3.192338:0.050000:-0.159617;sleep:0.416667:0.150000:0.062500;skin:-0.400000:0.050000:-0.020000
explain|nil|nil|calibrating|hrv-baseline|
""")
    }

}
