import XCTest
@testable import StrandAnalytics

final class ExerciseGpsEvidenceTests: XCTestCase {
    func fixture(owner: String? = "strap") -> ExerciseGpsEvidence.Input {
        .init(start: 1000, end: 2200, sport: "running", owner: owner, storedDistanceM: nil,
              fixes: (0...120).map { .init(lat: 0, lon: Double($0) * 0.0003, time: 1000 + Double($0) * 10, accuracyM: 5) },
              heartRates: (0...1200).map { .init(time: 1000 + Double($0), bpm: 150, owner: "strap") })
    }
    func testObservedMeasurementsNeverBecomeVO2max() {
        let x = ExerciseGpsEvidence.evaluate(fixture())
        XCTAssertNotNil(x.distanceM)
        guard let distance = x.distanceM, let mean = x.meanHr, let efficiency = x.metersPerBeat else { return }
        XCTAssertEqual(distance, 4003.017359, accuracy: 0.000001)
        XCTAssertEqual(mean, 150)
        XCTAssertEqual(x.hrCoveredS, 1200)
        XCTAssertEqual(efficiency, 1.334339, accuracy: 0.000001)
        XCTAssertEqual(x.reasons, ["slope-unknown", "protocol-unverified"])
        XCTAssertNil(x.vo2max)
    }
    func testUnknownOwnerAndPolylineOnlyCannotProducePairedEvidence() {
        var input = fixture(owner: nil)
        input.fixes = input.fixes.map { .init(lat: $0.lat, lon: $0.lon, time: nil, accuracyM: nil) }
        let x = ExerciseGpsEvidence.evaluate(input)
        XCTAssertNotNil(x.distanceM)
        XCTAssertNil(x.metersPerBeat)
        XCTAssertTrue(x.reasons.contains("gps-timing-missing"))
        XCTAssertTrue(x.reasons.contains("gps-accuracy-missing"))
        XCTAssertTrue(x.reasons.contains("hr-owner-unknown"))
    }
    func testDomainCorruptionNeverLeaksNonfiniteMeasurements() {
        var input = fixture(); input.fixes[20].lat = .nan
        let x = ExerciseGpsEvidence.evaluate(input)
        XCTAssertNil(x.distanceM); XCTAssertNil(x.metersPerBeat)
        XCTAssertTrue(x.reasons.contains("gps-invalid"))
        input = fixture(); input.end = .infinity
        XCTAssertEqual(ExerciseGpsEvidence.evaluate(input).reasons, ["window-invalid", "slope-unknown", "protocol-unverified"])
    }
    func testHRGapsAndForeignOwnerBlockPairing() {
        var input = fixture(); input.heartRates.removeSubrange(300...700)
        let gap = ExerciseGpsEvidence.evaluate(input)
        XCTAssertTrue(gap.reasons.contains("hr-gap")); XCTAssertNil(gap.metersPerBeat)
        input = fixture(); input.heartRates[50].owner = "other"
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("hr-owner-mismatch"))
        input = fixture(); input.heartRates[50].bpm = .nan
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("hr-invalid"))
    }
    func testGpsGapsAccuracyStopsAndDistanceMismatchBlockPairing() {
        var input = fixture(); input.fixes[20].accuracyM = 50
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("gps-accuracy"))
        input = fixture(); input.fixes.removeSubrange(20...40)
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("gps-gap"))
        input = fixture(); input.storedDistanceM = 100
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("distance-mismatch"))
        input = fixture(); for i in 0...30 { input.fixes[i].lon = 0 }
        XCTAssertTrue(ExerciseGpsEvidence.evaluate(input).reasons.contains("stops"))
    }
    func testKlinePublishedUnitsAndExplicitProtocolGate() {
        let x = ExerciseGpsEvidence.kline(age: 40, weightKg: 70, sex: 1, seconds: 900, repeatSeconds: 920, fourthQuarterHr: 120, confirmed: true)
        XCTAssertNotNil(x)
        XCTAssertEqual(x?.litersPerMinute ?? 0, 3.1970446094, accuracy: 0.000001)
        XCTAssertEqual(x?.mlKgMin ?? 0, 45.672065848, accuracy: 0.000001)
        XCTAssertNil(ExerciseGpsEvidence.kline(age: 40, weightKg: 70, sex: 1, seconds: 900, repeatSeconds: 920, fourthQuarterHr: 120, confirmed: false))
        XCTAssertNil(ExerciseGpsEvidence.kline(age: 29, weightKg: 70, sex: 1, seconds: 900, repeatSeconds: 920, fourthQuarterHr: 120, confirmed: true))
        XCTAssertNil(ExerciseGpsEvidence.kline(age: 40, weightKg: 70, sex: 1, seconds: 900, repeatSeconds: 931, fourthQuarterHr: 120, confirmed: true))
        XCTAssertNil(ExerciseGpsEvidence.kline(age: 40, weightKg: .nan, sex: 1, seconds: 900, repeatSeconds: 920, fourthQuarterHr: 120, confirmed: true))
    }
    func testCompiledSwiftOracleAndReversePin() {
        var lines: [String] = []
func fixture() -> ExerciseGpsEvidence.Input {
 .init(start:1000,end:2200,sport:"running",owner:"strap",storedDistanceM:nil,
 fixes:(0...120).map{.init(lat:0,lon:Double($0)*0.0003,time:1000+Double($0)*10,accuracyM:5)},
 heartRates:(0...1200).map{.init(time:1000+Double($0),bpm:150,owner:"strap")})
}
func n(_ v:Double?)->String { v.map{String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "nil" }
for i in 0..<12 {
 var x=fixture()
 switch i {
 case 1:x.owner=nil
 case 2:x.fixes=x.fixes.map{.init(lat:$0.lat,lon:$0.lon,time:nil,accuracyM:nil)}
 case 3:x.fixes[20].lat = .nan
 case 4:x.heartRates.removeSubrange(300...700)
 case 5:x.heartRates[50].owner="foreign"
 case 6:x.fixes[20].accuracyM=50
 case 7:x.fixes.removeSubrange(20...40)
 case 8:x.storedDistanceM=100
 case 9:for j in 0...30 {x.fixes[j].lon=0}
 case 10:x.end = .infinity
 case 11:x.heartRates[50].bpm = .nan
 default:break
 }
 let r=ExerciseGpsEvidence.evaluate(x)
 lines.append([n(r.distanceM),n(r.speedMps),n(r.meanHr),n(r.hrCoveredS),n(r.metersPerBeat),r.reasons.joined(separator:",")].joined(separator:"|"))
}
for s in 0...1 {
 let r=ExerciseGpsEvidence.kline(age:40,weightKg:70,sex:s,seconds:900,repeatSeconds:920,fourthQuarterHr:120,confirmed:true)
 lines.append("kline|\(n(r?.litersPerMinute))|\(n(r?.mlKgMin))")
}
        XCTAssertEqual(lines.joined(separator: "\n"), """
4003.017359|3.335848|150.000000|1200.000000|1.334339|slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-owner-unknown,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-timing-missing,gps-accuracy-missing,gps-coverage,slope-unknown,protocol-unverified
nil|nil|nil|0.000000|nil|gps-invalid,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|798.000000|nil|hr-gap,hr-coverage,slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-owner-mismatch,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-accuracy,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-gap,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|distance-mismatch,slope-unknown,protocol-unverified
4003.017359|3.335848|150.000000|1200.000000|nil|gps-speed,stops,slope-unknown,protocol-unverified
nil|nil|nil|0.000000|nil|window-invalid,slope-unknown,protocol-unverified
4003.017359|3.335848|nil|0.000000|nil|hr-invalid,slope-unknown,protocol-unverified
kline|2.601545|37.164923
kline|3.197045|45.672066
""")
    }
}
