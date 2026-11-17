import XCTest
@testable import StrandAnalytics

final class StepCalibrationTests: XCTestCase {
    private func walk(_ id: String = "a", steps: Double = 1000, ticks: Double = 24000,
                      confirmed: Bool = true) -> StepCalibration.Trial {
        .init(id: id, countedSteps: steps, rawTicks: ticks, sourceConfirmed: confirmed)
    }

    private var repeatedWalks: [StepCalibration.Trial] {
        [walk("a"), walk("b", steps: 1100, ticks: 26400), walk("c", steps: 1200, ticks: 28800)]
    }

    func testMedianUsesIndependentWalksAndPreservesUnroundedFactor() {
        let result = StepCalibration.evaluate(repeatedWalks)
        XCTAssertNil(result.issue)
        XCTAssertEqual(result.factor, 24)
        XCTAssertEqual(result.relativeSpread, 0)
        let varied = [walk("a", ticks: 23999), walk("b", ticks: 24001), walk("c", ticks: 24003)]
        XCTAssertEqual(StepCalibration.evaluate(varied).factor, 24.001)
        XCTAssertEqual(StepCalibration.evaluate(varied.reversed()).factor, 24.001)
    }

    func testRejectsNonFiniteFractionalZeroAndExtremeObservations() {
        for value in [Double.nan, .infinity, -.infinity, 0, -1, 99, 100.5, 10001, .greatestFiniteMagnitude] {
            XCTAssertEqual(StepCalibration.validate(walk(steps: value)), .invalidSteps)
        }
        for value in [Double.nan, .infinity, -.infinity, 0, -1, 1.5, 300001, .greatestFiniteMagnitude] {
            XCTAssertEqual(StepCalibration.validate(walk(ticks: value)), .invalidTicks)
        }
        XCTAssertEqual(StepCalibration.validate(walk(ticks: 499)), .unsupportedFactor)
        XCTAssertEqual(StepCalibration.validate(walk(ticks: 30001)), .unsupportedFactor)
        XCTAssertNil(StepCalibration.validate(walk(steps: 100, ticks: 50)))
        XCTAssertNil(StepCalibration.validate(walk(steps: 10000, ticks: 300000)))
    }

    func testNeedsThreeDistinctConfirmedWalksAndCapsInput() {
        XCTAssertEqual(StepCalibration.evaluate([]).issue, .insufficientTrials)
        XCTAssertEqual(StepCalibration.evaluate(Array(repeatedWalks.prefix(2))).issue, .insufficientTrials)
        XCTAssertEqual(StepCalibration.evaluate(repeatedWalks + [walk("d")]).issue, .duplicateTrial)
        XCTAssertEqual(StepCalibration.evaluate(repeatedWalks + [walk("a", steps: 1300, ticks: 31200)]).issue, .duplicateTrial)
        XCTAssertEqual(StepCalibration.validate(walk(confirmed: false)), .unconfirmedSource)
        XCTAssertEqual(StepCalibration.validate(walk("")), .invalidIdentity)
        XCTAssertEqual(StepCalibration.validate(walk(" \n\t")), .invalidIdentity)
        let eight = (0..<8).map { walk("\($0)", steps: 1000 + Double($0), ticks: 24000 + Double($0) * 24) }
        XCTAssertEqual(StepCalibration.evaluate(eight).factor, 24)
        XCTAssertEqual(StepCalibration.evaluate(eight + [walk("ninth")]).issue, .tooManyTrials)
    }

    func testConflictFailsClosedWithoutDiscardingOutlierAndEvenMedianIsAveraged() {
        let conflict = StepCalibration.evaluate([walk("a"), walk("b", ticks: 24500), walk("c", ticks: 30000)])
        XCTAssertEqual(conflict.issue, .inconsistentTrials)
        XCTAssertNil(conflict.factor)
        XCTAssertEqual(conflict.relativeSpread, 6 / 24.5)
        let even = StepCalibration.evaluate([walk("a", ticks: 23000), walk("b"), walk("c", ticks: 25000), walk("d", ticks: 26000)])
        XCTAssertNil(even.issue)
        XCTAssertEqual(even.factor, 24.5)
        XCTAssertEqual(even.relativeSpread, 3 / 24.5)
        // Exactly 20% passes; the next integer tick over the limit fails.
        XCTAssertEqual(StepCalibration.evaluate([walk("a", ticks: 9000), walk("b", ticks: 10000), walk("c", ticks: 11000)]).factor, 10)
        XCTAssertEqual(StepCalibration.evaluate([walk("a", ticks: 9000), walk("b", ticks: 10000), walk("c", ticks: 11001)]).issue, .inconsistentTrials)
    }

    // Compiled Swift oracle; identical literal is pinned in Kotlin's ManualStepCalibrationTest.
    // Hex encodes IEEE-754 bits so numeric agreement is exact, independent of display/locale formatting.
    func oracleTranscript() -> String {
        var cases: [(String, [StepCalibration.Trial])] = [
            ("empty", []), ("two", Array(repeatedWalks.prefix(2))), ("repeat24", repeatedWalks),
            ("even", [walk("a", ticks: 23000), walk("b"), walk("c", ticks: 25000), walk("d", ticks: 26000)]),
            ("edge20", [walk("a", ticks: 9000), walk("b", ticks: 10000), walk("c", ticks: 11000)]),
            ("over20", [walk("a", ticks: 9000), walk("b", ticks: 10000), walk("c", ticks: 11001)]),
            ("conflict", [walk("a"), walk("b", ticks: 24500), walk("c", ticks: 30000)]),
            ("duplicate-id", repeatedWalks + [walk("a", steps: 1300, ticks: 31200)]),
            ("duplicate-pair", repeatedWalks + [walk("d")]),
            ("unconfirmed", [walk(confirmed: false)]), ("blank-id", [walk(" \n\t")]),
            ("floor", [walk("a", ticks: 500), walk("b", steps: 1100, ticks: 550), walk("c", steps: 1200, ticks: 600)]),
            ("ceiling", [walk("a", ticks: 30000), walk("b", steps: 1100, ticks: 33000), walk("c", steps: 10000, ticks: 300000)]),
            ("unrounded", [walk("a", ticks: 23999), walk("b", ticks: 24001), walk("c", ticks: 24003)])
        ]
        let eight = (0..<8).map { walk("\($0)", steps: 1000 + Double($0), ticks: 24000 + Double($0) * 24) }
        cases.append(("eight", eight))
        cases.append(("nine", eight + [walk("ninth")]))
        for (index, value) in [Double.nan, .infinity, -.infinity, 0, -1, 99, 100.5, 10001, .greatestFiniteMagnitude].enumerated() {
            cases.append(("steps\(index)", [walk(steps: value)]))
        }
        for (index, value) in [Double.nan, .infinity, -.infinity, 0, -1, 1.5, 300001, .greatestFiniteMagnitude, 499, 30001].enumerated() {
            cases.append(("ticks\(index)", [walk(ticks: value)]))
        }
        return cases.map { name, trials in
            let result = StepCalibration.evaluate(trials)
            func bits(_ value: Double?) -> String { value.map { String($0.bitPattern, radix: 16) } ?? "-" }
            return "\(name)|\(result.issue?.rawValue ?? "ok")|\(bits(result.factor))|\(bits(result.relativeSpread))"
        }.joined(separator: "\n")
    }

    func testCompiledOracleReversePin() {
        XCTAssertEqual(oracleTranscript(), Self.expectedOracle)
    }

    // Captured stdout of the standalone compiled Swift oracle, never hand-calculated.
    static let expectedOracle = """
    empty|insufficientTrials|-|-
    two|insufficientTrials|-|-
    repeat24|ok|4038000000000000|0
    even|ok|4038800000000000|3fbf58d0fac687d6
    edge20|ok|4024000000000000|3fc999999999999a
    over20|inconsistentTrials|-|3fc99ce075f6fd20
    conflict|inconsistentTrials|-|3fcf58d0fac687d6
    duplicate-id|duplicateTrial|-|-
    duplicate-pair|duplicateTrial|-|-
    unconfirmed|unconfirmedSource|-|-
    blank-id|invalidIdentity|-|-
    floor|ok|3fe0000000000000|0
    ceiling|ok|403e000000000000|0
    unrounded|ok|4038004189374bc7|3f25d82c1d911fbb
    eight|ok|4038000000000000|0
    nine|tooManyTrials|-|-
    steps0|invalidSteps|-|-
    steps1|invalidSteps|-|-
    steps2|invalidSteps|-|-
    steps3|invalidSteps|-|-
    steps4|invalidSteps|-|-
    steps5|invalidSteps|-|-
    steps6|invalidSteps|-|-
    steps7|invalidSteps|-|-
    steps8|invalidSteps|-|-
    ticks0|invalidTicks|-|-
    ticks1|invalidTicks|-|-
    ticks2|invalidTicks|-|-
    ticks3|invalidTicks|-|-
    ticks4|invalidTicks|-|-
    ticks5|invalidTicks|-|-
    ticks6|invalidTicks|-|-
    ticks7|invalidTicks|-|-
    ticks8|unsupportedFactor|-|-
    ticks9|unsupportedFactor|-|-
    """
}
