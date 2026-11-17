import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepSignalCoverageTests: XCTestCase {
    func testMissingCellsStayUnknownIncludingLeadingAndTrailingEdges() {
        let r = SleepSignalCoverage.analyze(start: 7, end: 101,
            hr: [.init(ts: 31, bpm: 60)], gravity: [.init(ts: 65, x: 0, y: 0, z: 1)])
        XCTAssertEqual(r.intervals.map(\.kind), ["unknown", "hr-only", "motion-only", "unknown"])
        XCTAssertEqual(r.intervals.map(\.start), [7, 30, 60, 90])
        XCTAssertEqual(r.intervals.map(\.end), [30, 60, 90, 101])
        XCTAssertEqual(r.unknownSeconds, 34)
        XCTAssertEqual(r.distinctHRSeconds, 1)
        XCTAssertEqual(r.distinctMotionSeconds, 1)
    }
    func testAvailabilityIsIdempotentAndOutsideSamplesCannotFillEdges() {
        let h: [HRSample] = [.init(ts: 6, bpm: 70), .init(ts: 7, bpm: 60), .init(ts: 60, bpm: 70)]
        let g: [GravitySample] = [.init(ts: 7, x: 0, y: 0, z: 1)]
        let a = SleepSignalCoverage.analyze(start: 7, end: 60, hr: h, gravity: g)
        XCTAssertEqual(a, SleepSignalCoverage.analyze(start: 7, end: 60,
            hr: (h + h).reversed(), gravity: g + g))
        XCTAssertEqual(a.bothSeconds, 23)
        XCTAssertEqual(a.unknownSeconds, 30)
        XCTAssertEqual(a.distinctHRSeconds, 1)
    }
    func testInvalidMeasurementsDoNotInventSupport() {
        let r = SleepSignalCoverage.analyze(start: 0, end: 90,
            hr: [.init(ts: 0, bpm: 0), .init(ts: 1, bpm: 301), .init(ts: 2, bpm: -1)],
            gravity: [.init(ts: 30, x: .nan, y: 0, z: 1), .init(ts: 31, x: 0, y: 0, z: 0),
                      .init(ts: 60, x: .infinity, y: 1, z: 0)])
        XCTAssertEqual(r.unknownSeconds, 90)
        XCTAssertEqual(r.intervals.count, 1)
    }
    func testBoundsAreExplicitRatherThanAllocatingAnUnboundedGrid() {
        for (s, e) in [(0, 0), (5, 4), (-1, 10), (0, 172_801), (Int.max - 1, Int.max)] {
            let r = SleepSignalCoverage.analyze(start: s, end: e, hr: [], gravity: [])
            XCTAssertEqual(r.status, "invalid-window")
            XCTAssertTrue(r.intervals.isEmpty)
        }
    }
    func testUnknownIsNeverConvertedToWakeOrLight() {
        let r = SleepSignalCoverage.analyze(start: 0, end: 60, hr: [], gravity: [])
        XCTAssertEqual(r.intervals.map(\.kind), ["unknown"])
        XCTAssertEqual(r.unknownSeconds, 60)
        XCTAssertEqual(r.bothSeconds + r.hrOnlySeconds + r.motionOnlySeconds, 0)
    }
    func testReversePinnedActualCompiledOracle() {
let h: [HRSample] = [.init(ts: 31, bpm: 60)]
let g: [GravitySample] = [.init(ts:65,x:0,y:0,z:1)]
let cases: [(Int,Int,[HRSample],[GravitySample])] = [
 (7,101,h,g),(7,101,h+h,(g+g).reversed()),(0,60,[],[]),
 (0,30,[.init(ts:0,bpm:300),.init(ts:1,bpm:301)], [.init(ts:1,x:0,y:0,z:1)]),
 (7,30,[.init(ts:6,bpm:60)],[.init(ts:30,x:0,y:0,z:1)]),
 (0,30,[.init(ts:0,bpm:0)],[.init(ts:0,x:.nan,y:0,z:1),.init(ts:1,x:0,y:0,z:0)]),
 (0,172800,[],[]),(-1,10,[],[]),(0,172801,[],[]),(4102444770,4102444800,[],[]),
 (Int.max-1,Int.max,[],[])]
let actual = cases.map { s,e,h,g in SleepSignalCoverage.analyze(start:s,end:e,hr:h,gravity:g).trace }.joined(separator:"\n")

XCTAssertEqual(actual, """
observed|0|30|30|34|1|1|7:30:unknown,30:60:hr-only,60:90:motion-only,90:101:unknown
observed|0|30|30|34|1|1|7:30:unknown,30:60:hr-only,60:90:motion-only,90:101:unknown
observed|0|0|0|60|0|0|0:60:unknown
observed|30|0|0|0|1|1|0:30:both
observed|0|0|0|23|0|0|7:30:unknown
observed|0|0|0|30|0|0|0:30:unknown
observed|0|0|0|172800|0|0|0:172800:unknown
invalid-window|0|0|0|0|0|0|
invalid-window|0|0|0|0|0|0|
observed|0|0|0|30|0|0|4102444770:4102444800:unknown
invalid-window|0|0|0|0|0|0|
""")
    }
}
