import XCTest
@testable import Strand

final class PerformanceHomeDataTests: XCTestCase {
    private func point(_ day: String, _ value: Double, _ source: String) -> ResolvedMetricPoint {
        .init(day: day, value: value, source: source, sourceKey: "steps")
    }

    func testMergeUsesFallbackOnlyForMissingDaysAndRejectsNonFiniteOrOutOfWindowValues() {
        let primary = [point("2026-11-15", 3000, "whoop"), point("2026-11-16", .nan, "whoop")]
        let fallback = [point("2026-11-15", 5000, "apple"), point("2026-11-16", 4200, "apple"),
                        point("2026-11-17", 9999, "apple"), point("2026-11-01", 8000, "apple")]
        let result = PerformanceHomeData.merged(primary, fallback: fallback,
                                                from: "2026-11-14", through: "2026-11-16")
        XCTAssertEqual(result.map(\.day), ["2026-11-15", "2026-11-16"])
        XCTAssertEqual(result.map(\.value), [3000, 4200])
        XCTAssertEqual(result.map(\.source), ["whoop", "apple"])
    }

    func testLatestReadingNeverUsesAFutureDayOrInvalidValue() {
        let rows = [point("2026-11-12", 35, "estimate"), point("2026-11-15", 40, "apple"),
                    point("2026-11-16", .nan, "apple"), point("2026-11-17", 99, "future")]
        let latest = PerformanceHomeData.latest(rows, through: "2026-11-16")
        XCTAssertEqual(latest?.day, "2026-11-15")
        XCTAssertEqual(latest?.value, 40)
        XCTAssertNil(PerformanceHomeData.latest(rows, through: "2026-11-10"))
    }

    func testRecentVO2EstimateDoesNotHideAMeasurementOnTheSameDay() {
        let measured = [point("2026-11-12", 36, "apple"), point("2026-11-15", 41, "apple")]
        let estimates = [point("2026-11-14", 39, "estimate"), point("2026-11-15", 43, "estimate")]
        let merged = PerformanceHomeData.merged(measured, fallback: estimates,
                                                from: "0000-01-01", through: "2026-11-15")
        let latest = PerformanceHomeData.latest(merged, through: "2026-11-15")
        XCTAssertEqual(latest?.value, 41)
        XCTAssertEqual(latest?.source, "apple")
    }

    func testStepsPreferARealSameDayCountAndUseAnEstimateOnlyAsFallback() {
        let day = "2026-11-15"
        let measured = [point(day, 4300, "whoop")]
        let estimated = [point(day, 4000, "estimate")]
        XCTAssertEqual(PerformanceHomeData.dailySteps(measured: measured, estimated: estimated, on: day)?.value, 4300)
        XCTAssertEqual(PerformanceHomeData.dailySteps(measured: [], estimated: estimated, on: day)?.value, 4000)
        XCTAssertEqual(PerformanceHomeData.dailySteps(measured: [point(day, -1, "bad")], estimated: estimated, on: day)?.value, 4000)
        XCTAssertNil(PerformanceHomeData.dailySteps(measured: [], estimated: estimated, on: "2026-11-16"))
    }

    func testOxygenCanShowAnImportButNotAComputedOrFutureValue() {
        let rows = [point("2026-11-15", 98, "my-whoop-noop"), point("2026-11-15", 97, "apple-health"),
                    point("2026-11-16", 99, "apple-health")]
        let selected = PerformanceHomeData.importedOxygen(rows, on: "2026-11-15")
        XCTAssertEqual(selected?.source, "apple-health")
        XCTAssertEqual(selected?.value, 97)
        XCTAssertNil(PerformanceHomeData.importedOxygen([rows[0]], on: "2026-11-15"))
        XCTAssertNil(PerformanceHomeData.importedOxygen([rows[2]], on: "2026-11-15"))
        XCTAssertNil(PerformanceHomeData.importedOxygen([point("2026-11-15", 105, "apple-health")], on: "2026-11-15"))
    }
}
