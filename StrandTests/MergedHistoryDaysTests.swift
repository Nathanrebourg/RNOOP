import XCTest
import WhoopStore
@testable import Strand
final class MergedHistoryDaysTests: XCTestCase {
    @MainActor func testComputedOnlyHistoryAndImportPrecedenceWithoutChangingCache() async throws {
        let store=try await WhoopStore.inMemory(), repo=Repository(deviceId:"my-whoop")
        repo.setStoreForTesting(store)
        func row(_ day:String,_ value:Double)->DailyMetric {
            DailyMetric(day:day,totalSleepMin:value,efficiency:nil,deepMin:nil,remMin:nil,lightMin:nil,disturbances:nil,restingHr:nil,avgHrv:nil,recovery:nil,strain:nil,exerciseCount:nil)
        }
        _=try await store.upsertDailyMetrics([row("2026-11-01",420),row("2026-11-02",480)],deviceId:"my-whoop-noop")
        _=try await store.upsertDailyMetrics([row("2026-11-02",500)],deviceId:"my-whoop")
        let result=await repo.mergedHistoryDays(fromDay:"2026-11-01",toDay:"2026-11-02",calendar:Calendar(identifier:.gregorian))
        XCTAssertEqual(result.map(\.totalSleepMin),[420,500])
        XCTAssertTrue(repo.days.isEmpty,"A trend read must not replace the dashboard cache")
    }
}
