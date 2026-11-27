import XCTest
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Strand

/// NROOP: the read/write split seen on a WHOOP 5.0 (Nov 2026 strap log). The registry's ACTIVE WHOOP row
/// ("whoop-x" here) holds only a few stray HR rows in the night window's 30 h lookback, while every sample
/// the connected strap banks today is attributed to "my-whoop" (#1881 "Attributing this link to my-whoop").
/// The old first-with-any-data probe handed the day to the active row, so the day read hr=0 and produced no
/// sleep, recovery or strain. Coverage now decides between live WHOOP rows, and still exactly one owner.
final class DayOwnerCoverageTests: XCTestCase {

    func testMostCoveredPicksTheRowWithMoreHR() {
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 34_223), ("my-whoop", 80_000)]), "my-whoop")
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 90_000), ("my-whoop", 80_000)]), "whoop-x")
        // Tie keeps the higher-priority (earlier) row; nobody with rows yields nil.
        XCTAssertEqual(DayOwnerResolver.mostCovered([("whoop-x", 10), ("my-whoop", 10)]), "whoop-x")
        XCTAssertNil(DayOwnerResolver.mostCovered([("whoop-x", 0), ("my-whoop", 0)]))
    }

    private func seed(_ store: WhoopStore, activeId: String, others: [PairedDevice]) throws -> DeviceRegistryStore {
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        let existing = Set(try registry.all().map(\.id))
        for d in others where !existing.contains(d.id) { try registry.add(d) }
        try registry.setActive(activeId)
        return registry
    }

    private func whoop(_ id: String, status: DeviceStatus = .paired, added: Int) -> PairedDevice {
        PairedDevice(id: id, brand: "WHOOP", model: "5.0", sourceKind: .liveBLE, capabilities: [.hr],
                     status: status, addedAt: added, lastSeenAt: added)
    }

    func testActiveRowWithStrayLookbackRowsNoLongerStealsTodayFromTheAttributedStrap() async throws {
        let store = try await WhoopStore.inMemory()
        let registry = try seed(store, activeId: "whoop-x",
                                others: [whoop("my-whoop", added: 1), whoop("whoop-x", added: 2)])
        let dayStart = 1_795_474_800              // a local-midnight-like anchor; only relative times matter
        let from = dayStart - 30 * 3600, to = dayStart + 14 * 3600
        // Active row: a short burst the previous evening, nothing today.
        let stray = stride(from: from + 3600, to: from + 3600 + 1200, by: 1).map { HRSample(ts: $0, bpm: 60) }
        // Attributed strap: the whole of today so far, at 1 Hz.
        let today = stride(from: dayStart, to: to, by: 1).map { HRSample(ts: $0, bpm: 70) }
        _ = try await store.insert(Streams(hr: stray), deviceId: "whoop-x")
        _ = try await store.insert(Streams(hr: today), deviceId: "my-whoop")

        let result = await IntelligenceEngine.resolveDayOwnerExplained(
            day: "2026-11-24", from: from, to: to, store: store, devices: try registry.all(),
            activeId: "whoop-x", registry: registry, fallbackDeviceId: "my-whoop")
        XCTAssertEqual(result.owner, "my-whoop")
        XCTAssertEqual(result.line, "dayOwner coverage day=2026-11-24 picked=my-whoop whoop-x=1200 my-whoop=\(today.count)")
    }

    func testActiveWhoopWithTheMostRowsStillOwnsTheDay() async throws {
        let store = try await WhoopStore.inMemory()
        let registry = try seed(store, activeId: "whoop-x",
                                others: [whoop("my-whoop", added: 1), whoop("whoop-x", added: 2)])
        let from = 1_795_000_000, to = from + 44 * 3600
        _ = try await store.insert(Streams(hr: stride(from: from, to: to, by: 1).map { HRSample(ts: $0, bpm: 60) }),
                                   deviceId: "whoop-x")
        _ = try await store.insert(Streams(hr: [HRSample(ts: from + 10, bpm: 70)]), deviceId: "my-whoop")
        let owner = await IntelligenceEngine.resolveDayOwner(
            day: "2026-11-24", from: from, to: to, store: store, devices: try registry.all(),
            activeId: "whoop-x", registry: registry, fallbackDeviceId: "my-whoop")
        XCTAssertEqual(owner, "whoop-x")
    }
}
