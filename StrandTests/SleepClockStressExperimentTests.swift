import XCTest
import WhoopStore
@testable import Strand

final class SleepClockStressExperimentTests:XCTestCase {
    private func store(source:String) async throws -> WhoopStore {
        let store=try await WhoopStore.inMemory()
        let start=1_794_700_800,end=start+28_800
        let stages="[{\"start\":\(start),\"end\":\(end),\"stage\":\"light\"}]"
        _=try await store.upsertSleepSessions([.init(startTs:start,endTs:end,efficiency:1,restingHr:60,avgHrv:40,stagesJSON:stages,stagingSparse:false)],deviceId:"my-whoop-noop")
        let day="2026-11-15"
        let d=DailyMetric(day:day,totalSleepMin:480,efficiency:1,deepMin:nil,remMin:nil,lightMin:480,disturbances:0,restingHr:60,avgHrv:40,recovery:nil,strain:nil,exerciseCount:nil)
        try await store.persistComputedScores(dailyMetrics:[d],metricPoints:[.init(day:day,key:"sleep_performance",value:80)],
            provenance:[.init(day:day,key:"sleep_performance",sourceId:source)],deviceId:"my-whoop-noop",from:day,to:day)
        return store
    }
    func testCanonicalComputedCacheRequiresAndPreservesMatchingOwner() async throws {
        let store=try await store(source:"physical-strap")
        let now=ISO8601DateFormatter().date(from:"2026-11-15T20:00:00Z")!
        let result=try await SleepClockStressExperiment.run(store:store,owner:"physical-strap",selectedDay:nil,now:now,zone:TimeZone(secondsFromGMT:0)!)
        XCTAssertEqual(result.selected.computedSource,"my-whoop-noop")
        XCTAssertEqual(result.incumbent,80)
        XCTAssertNil(result.result.candidate,"Missing raw evidence must not become a complete score")
        let points=try await store.metricSeries(deviceId:"my-whoop-noop",key:"sleep_performance",from:"2026-11-15",to:"2026-11-15")
        XCTAssertEqual(points.first?.value,80,"Research must not persist a candidate")
    }
    func testAnotherOwnersCanonicalNightCannotBeUsedAsCurrentStrapEvidence() async throws {
        let store=try await store(source:"other-strap")
        do {
            _=try await SleepClockStressExperiment.run(store:store,owner:"physical-strap",selectedDay:nil,
                now:ISO8601DateFormatter().date(from:"2026-11-15T20:00:00Z")!,zone:TimeZone(secondsFromGMT:0)!)
            XCTFail("A different input owner was accepted")
        } catch { XCTAssertTrue(error is SleepClockStressExperiment.Failure) }
    }
}
