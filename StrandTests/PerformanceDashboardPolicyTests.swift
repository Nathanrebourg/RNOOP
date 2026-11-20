import XCTest
@testable import Strand

final class PerformanceDashboardPolicyTests: XCTestCase {
    func testPreviouslyHiddenClassicCardsHaveTheirOwnDestinations() {
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .stepsAverage30), .stepsAverage)
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .bloodOxygen), .metric("spo2"))
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .calories), .metric("active_kcal"))
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .hydration), .hydration)
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .coupled), .coupled)
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .coach), .coach)
    }

    func testSleepCardRepresentsDurationRatherThanAScore() {
        XCTAssertEqual(PerformanceDashboardPolicy.destination(for: .sleep), .metric("sleep_total_min"))
    }
}
