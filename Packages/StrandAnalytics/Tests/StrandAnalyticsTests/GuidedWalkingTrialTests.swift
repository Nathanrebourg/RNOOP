import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class GuidedWalkingTrialTests: XCTestCase {
    typealias Sample = GuidedWalkingTrial.Sample
    // Hand fixture: 61 one-second samples, two stationary edge intervals, 58 increments of 2.
    func walk(start: Int = 1000, duration: Int = 60, activity: Int? = 1) -> [Sample] {
        (0...duration).map { second in
            Sample(ts: start + second, counter: 100 + max(0, min(second - 1, duration - 2)) * 2,
                   activityClass: activity)
        }
    }
    func result(_ samples: [Sample], start: Int = 1000, end: Int = 1060) -> GuidedWalkingTrial.Result {
        GuidedWalkingTrial.evaluate(startTs: start, endTs: end, samples: samples)
    }
    func replacing(_ samples: [Sample], at index: Int, ts: Int? = nil, counter: Int? = nil,
                   activity: Int? = nil) -> [Sample] {
        var changed = samples
        changed[index] = Sample(ts: ts ?? samples[index].ts, counter: counter ?? samples[index].counter,
                                activityClass: activity ?? samples[index].activityClass)
        return changed
    }

    func testRetainsExactlyIncumbentPipelineTicksAndExposesObservedBounds() {
        for activity in [nil, 1, 2] as [Int?] {
            let samples = walk(activity: activity)
            let checked = result(samples)
            XCTAssertNil(checked.issue)
            XCTAssertEqual(checked.retainedTicks, 116)
            XCTAssertEqual(checked.observedStartTs, 1000)
            XCTAssertEqual(checked.observedEndTs, 1060)
            XCTAssertEqual(checked.sampleCount, 61)
            XCTAssertEqual(checked.usesActivityClasses, activity != nil)
            XCTAssertEqual(checked.retainedTicks, StepsCounter.stepsInWindow(samples.map {
                StepSample(ts: $0.ts, counter: $0.counter, activityClass: $0.activityClass)
            }))
        }
    }

    func testSortsAndDeduplicatesIdenticalRecordsButRejectsCounterOrClassConflicts() {
        let samples = walk()
        XCTAssertEqual(result(Array(samples.reversed()) + [samples[8]]).retainedTicks, 116)
        XCTAssertEqual(result(samples + [Sample(ts: 1008, counter: 999, activityClass: 1)]).issue,
                       .conflictingSample)
        XCTAssertEqual(result(samples + [Sample(ts: 1008, counter: samples[8].counter, activityClass: nil)]).issue,
                       .conflictingSample)
    }

    func testRejectsDropsIncludingPossibleWrapAndAnyPipelineDiscardedMovement() {
        XCTAssertEqual(result(replacing(walk(), at: 20, counter: 1)).issue, .counterDecreased)
        var wrap = walk()
        wrap[0] = Sample(ts: 1000, counter: 65535, activityClass: 1)
        wrap[1] = Sample(ts: 1001, counter: 65535, activityClass: 1)
        XCTAssertEqual(result(wrap).issue, .counterDecreased)
        XCTAssertEqual(result(replacing(walk(), at: 20, counter: 600)).issue, .implausibleIncrement)
        XCTAssertEqual(result(replacing(walk(), at: 20, counter: walk()[19].counter + 5)).issue, .implausibleIncrement)
        for activity in [0, 3, -1] {
            XCTAssertEqual(result(replacing(walk(), at: 20, activity: activity)).issue, .nonWalkingIncrement)
        }
        var unknown = walk()
        unknown[20] = Sample(ts: 1020, counter: unknown[20].counter, activityClass: nil)
        XCTAssertEqual(result(unknown).issue, .nonWalkingIncrement)
        // Still/unknown on a zero interval does not discard movement.
        XCTAssertNil(result(replacing(walk(), at: 60, activity: 0)).issue)
    }

    func testRequiresBoundedDurationCoverageNoLargeGapsAndStationaryEdges() {
        XCTAssertEqual(result(walk(), start: 0).issue, .invalidWindow)
        XCTAssertEqual(result(walk(), start: -1).issue, .invalidWindow)
        XCTAssertEqual(result(walk(), end: Int.max).issue, .invalidWindow)
        XCTAssertEqual(result(walk(), end: 1059).issue, .invalidDuration)
        XCTAssertEqual(result(walk(), end: 4601).issue, .invalidDuration)
        XCTAssertEqual(result([]).issue, .insufficientSamples)
        XCTAssertEqual(result(Array(walk().dropFirst(4))).issue, .incompleteCoverage)
        XCTAssertEqual(result(walk().filter { !(1020...1024).contains($0.ts) }).issue, .sampleGap)
        XCTAssertEqual(result(replacing(walk(), at: 0, counter: 99)).issue, .movingBoundary)
        XCTAssertEqual(result(replacing(walk(), at: 60, counter: 217)).issue, .movingBoundary)
        let edge = walk(start: 1003, duration: 60)
        XCTAssertNil(result(edge, start: 1000, end: 1066).issue)
        let allZero = walk().map { Sample(ts: $0.ts, counter: 100, activityClass: 0) }
        XCTAssertEqual(result(allZero).issue, .noMovement)
    }

    func testValidatesU16AndTimestampAndRestrictsReadWindowToDeclaredInterval() {
        XCTAssertEqual(result(replacing(walk(), at: 20, counter: -1)).issue, .invalidCounter)
        XCTAssertEqual(result(replacing(walk(), at: 20, counter: 65536)).issue, .invalidCounter)
        XCTAssertEqual(result(walk() + [Sample(ts: Int.max, counter: 1, activityClass: 1)]).issue, .invalidTimestamp)
        XCTAssertEqual(result(walk() + [Sample(ts: 999, counter: 999, activityClass: 0)]).retainedTicks, 116)
        XCTAssertEqual(result(walk() + [Sample(ts: 1061, counter: 0, activityClass: 0)]).retainedTicks, 116)
    }
    // Fixture outcomes are independently asserted above; this transcript pins both implementations.
    func oracleTranscript() -> String {
        let base = walk()
        let cases: [(String, Int, Int, [Sample])] = [
            ("classed", 1000, 1060, base),
            ("legacy", 1000, 1060, walk(activity: nil)),
            ("run", 1000, 1060, walk(activity: 2)),
            ("dedup", 1000, 1060, Array(base.reversed()) + [base[8]]),
            ("conflict", 1000, 1060, base + [Sample(ts: 1008, counter: 999, activityClass: 1)]),
            ("invalid-counter", 1000, 1060, replacing(base, at: 20, counter: 65536)),
            ("invalid-ts", 1000, 1060, base + [Sample(ts: 0, counter: 0, activityClass: nil)]),
            ("invalid-window", 0, 1060, base),
            ("short", 1000, 1059, base),
            ("long", 1000, 4601, base),
            ("empty", 1000, 1060, []),
            ("coverage", 1000, 1060, Array(base.dropFirst(4))),
            ("edge3", 1000, 1066, walk(start: 1003)),
            ("gap5", 1000, 1060, base.filter { !(1020...1023).contains($0.ts) }),
            ("gap6", 1000, 1060, base.filter { !(1020...1024).contains($0.ts) }),
            ("drop", 1000, 1060, replacing(base, at: 20, counter: 1)),
            ("rate5", 1000, 1060, replacing(base, at: 20, counter: base[19].counter + 5)),
            ("delta512", 1000, 1060, replacing(base, at: 20, counter: base[19].counter + 512)),
            ("still", 1000, 1060, replacing(base, at: 20, activity: 0)),
            ("moving-start", 1000, 1060, replacing(base, at: 0, counter: 99)),
            ("moving-end", 1000, 1060, replacing(base, at: 60, counter: 217)),
            ("zero", 1000, 1060, base.map { Sample(ts: $0.ts, counter: 100, activityClass: nil) }),
            ("max-duration", 1000, 4600, walk(duration: 3600)),
            ("unix-ceiling", 4102444740, 4102444800, walk(start: 4102444740))
        ]
        return cases.map { name, start, end, samples in
            let value = result(samples, start: start, end: end)
            func field(_ value: Int?) -> String { value.map(String.init) ?? "-" }
            return "\(name)|\(value.issue?.rawValue ?? "ok")|\(field(value.retainedTicks))|\(field(value.observedStartTs))|\(field(value.observedEndTs))|\(value.sampleCount)|\(value.usesActivityClasses ? 1 : 0)"
        }.joined(separator: "\n")
    }

    func testCompiledOracleReversePin() {
        XCTAssertEqual(oracleTranscript(), Self.expectedOracle)
    }
    // Filled from actual standalone Swift stdout, also pinned in the Kotlin test.
    static let expectedOracle = """
    classed|ok|116|1000|1060|61|1
    legacy|ok|116|1000|1060|61|0
    run|ok|116|1000|1060|61|1
    dedup|ok|116|1000|1060|61|1
    conflict|conflictingSample|-|1000|1008|9|0
    invalid-counter|invalidCounter|-|1000|1019|20|0
    invalid-ts|invalidTimestamp|-|-|-|0|0
    invalid-window|invalidWindow|-|-|-|0|0
    short|invalidDuration|-|-|-|0|0
    long|invalidDuration|-|-|-|0|0
    empty|insufficientSamples|-|-|-|0|0
    coverage|incompleteCoverage|-|1004|1060|57|1
    edge3|ok|116|1003|1063|61|1
    gap5|ok|116|1000|1060|57|1
    gap6|sampleGap|-|1000|1060|56|1
    drop|counterDecreased|-|1000|1060|61|1
    rate5|implausibleIncrement|-|1000|1060|61|1
    delta512|implausibleIncrement|-|1000|1060|61|1
    still|nonWalkingIncrement|-|1000|1060|61|1
    moving-start|movingBoundary|-|1000|1060|61|1
    moving-end|movingBoundary|-|1000|1060|61|1
    zero|noMovement|-|1000|1060|61|0
    max-duration|ok|7196|1000|4600|3601|1
    unix-ceiling|ok|116|4102444740|4102444800|61|1
    """

}
