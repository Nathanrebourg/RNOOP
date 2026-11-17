import XCTest
import GRDB
@testable import WhoopStore

final class ScoreCalculationEvidenceTests: XCTestCase {
    private let device = "strap-noop", day = "2026-11-15"
    private func daily(_ value: Double = 71) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: value, strain: 42, exerciseCount: nil)
    }
    private func evidence(_ fingerprint: String = "a", value: Double = 71, payload: String = "recipe", time: Int = 1_800_000_000,
                          day: String = "2026-11-15", key: String = "recovery", source: String = "strap") -> ScoreCalculationEvidence {
        .init(day: day, key: key, sourceId: source, methodId: "recovery.logistic.v1", fingerprint: fingerprint,
              payload: payload, value: value, capturedAt: time)
    }
    private func save(_ store: WhoopStore, _ rows: [ScoreCalculationEvidence], value: Double = 71) async throws {
        try await store.persistComputedScores(dailyMetrics: [daily(value)],
            metricPoints: [.init(day: day, key: "sleep_performance", value: 83)],
            provenance: [.init(day: day, key: "recovery", sourceId: "strap"),
                         .init(day: day, key: "strain", sourceId: "strap"),
                         .init(day: day, key: "sleep_performance", sourceId: "strap")],
            deviceId: device, from: day, to: day, calculationEvidence: rows)
    }
    func testCurrentIsAtomicIdempotentAndMissingRecipeClearsHeadOnly() async throws {
        let store = try await WhoopStore.inMemory()
        try await save(store, [evidence()])
        try await save(store, [evidence(time: 1_800_000_001)])
        let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        let history = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: 99)
        XCTAssertEqual(current, evidence())
        XCTAssertEqual(history, [evidence()])
        try await save(store, [])
        let cleared = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        let retained = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: 99)
        XCTAssertNil(cleared)
        XCTAssertEqual(retained, [evidence()])
    }
    func testCollisionAndInvalidEvidenceRollBackScoresProvenanceAndHead() async throws {
        let store = try await WhoopStore.inMemory()
        try await save(store, [evidence()])
        let invalid = [evidence(value: 72), evidence(payload: "different"), evidence(source: "other"),
                       evidence(payload: String(repeating: "é", count: 8193)), evidence(time: 0),
                       evidence(time: 4_102_444_801), evidence(day: "2026-02-30"), evidence(day: "2026-1-15"),
                       evidence(key: "unknown"), evidence(value: .nan), evidence(value: 101)]
        for row in invalid {
            do { try await save(store, [row], value: row.value.isFinite ? row.value : 72); XCTFail("accepted invalid evidence") }
            catch { }
            let stored = try await store.dailyMetrics(deviceId: device, from: day, to: day)
            let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
            XCTAssertEqual(stored.first?.recovery, 71)
            XCTAssertEqual(current, evidence())
        }
    }
    func testAllScoreKeysRequireSuppliedMetricSpecificSourceAndValue() async throws {
        let store = try await WhoopStore.inMemory()
        try await save(store, [evidence("rest", value: 83, key: "sleep_performance"), evidence("effort", value: 42, key: "strain")])
        let rest = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "sleep_performance")
        XCTAssertEqual(rest?.value, 83)
        do { try await save(store, [evidence("bad", value: 84, key: "sleep_performance")]); XCTFail("value mismatch") } catch { }
        do {
            try await store.persistComputedScores(dailyMetrics: [daily()], metricPoints: [], provenance: [], deviceId: device,
                from: day, to: day, calculationEvidence: [evidence()])
            XCTFail("stale provenance accepted")
        } catch { }
    }
    func testPerCellRetentionIsDeterministicAndDailyEvictionRetainsAudit() async throws {
        let store = try await WhoopStore.inMemory()
        for index in 0..<12 { try await save(store, [evidence(String(format: "%02d", index), time: 1_800_000_000 + index)]) }
        let rows = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: 100)
        XCTAssertEqual(rows.map(\.fingerprint), (4..<12).reversed().map { String(format: "%02d", $0) })
        _ = try await store.deleteDailyMetrics(deviceId: device, from: day, to: day)
        let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        let history = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: 100)
        XCTAssertNil(current)
        XCTAssertEqual(history, rows)
    }
    func testSelectingOldestRevisionKeepsCurrentRecipeWhenCellPrunes() async throws {
        let store = try await WhoopStore.inMemory()
        for index in 0..<8 { try await save(store, [evidence(String(index), time: 1_800_000_000 + index)]) }
        // The ninth computation selects an observed older recipe after recording another revision.
        // Its original capture time is deliberately preserved by idempotent insertion.
        try await save(store, [evidence("new", time: 1_800_000_100), evidence("0", time: 1_800_000_101)])
        let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        let history = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: 8)
        XCTAssertEqual(current, evidence("0"))
        XCTAssertEqual(history.count, 8)
        XCTAssertTrue(history.contains(evidence("0")))
        XCTAssertFalse(history.contains(where: { $0.fingerprint == "1" }))
    }
    func testDeviceCapProtectsOldCurrentHeadWithoutDeletingScoresOrProvenance() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.syncWrite { db in
            for index in 0..<12_005 {
                let fingerprint = String(format: "%05d", index)
                try db.execute(sql: "INSERT INTO scoreCalculationEvidence VALUES (?,date('1980-01-01',? || ' days'),'recovery',?,?,?,?,?,?)",
                    arguments: [device, index, fingerprint, index + 1, "strap", "old", 71, "recipe"])
            }
            try db.execute(sql: "INSERT INTO scoreCalculationHead VALUES (?,?,?,?)", arguments: [device, "1980-01-01", "recovery", "00000"])
        }
        try await save(store, [evidence()])
        let counts = try await store.syncRead { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationEvidence WHERE deviceId = ?", arguments: [device]),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationHead WHERE day = '1980-01-01'"))
        }
        XCTAssertEqual(counts.0, 12_000)
        XCTAssertEqual(counts.1, 1)
        let scores = try await store.dailyMetrics(deviceId: device, from: day, to: day)
        let source = try await store.scoreInputSource(deviceId: device, day: day, key: "recovery")
        XCTAssertEqual(scores.first?.recovery, 71)
        XCTAssertEqual(source, "strap")
    }
    func testDeviceCapClearsOldestHeadsWhenCurrentRecipesAloneExceedCap() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.syncWrite { db in
            for index in 0..<12_001 {
                try db.execute(sql: "INSERT INTO scoreCalculationEvidence VALUES (?,date('1980-01-01',? || ' days'),'recovery','head',?,'strap','old',71,'recipe')",
                    arguments: [device, index, index + 1])
            }
            try db.execute(sql: "INSERT INTO scoreCalculationHead SELECT deviceId,day,key,fingerprint FROM scoreCalculationEvidence")
        }
        try await save(store, [evidence()])
        try await store.syncRead { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationEvidence"), 12_000)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationHead"), 12_000)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationHead WHERE day = '1980-01-01'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationHead h WHERE NOT EXISTS (SELECT 1 FROM scoreCalculationEvidence e WHERE e.deviceId=h.deviceId AND e.day=h.day AND e.key=h.key AND e.fingerprint=h.fingerprint)"), 0)
        }
        let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        XCTAssertEqual(current, evidence())
    }
    func testEmptyPassAndZeroReadLimitLeaveCurrentUntouched() async throws {
        let store = try await WhoopStore.inMemory()
        try await save(store, [evidence()])
        try await store.persistComputedScores(dailyMetrics: [], metricPoints: [], provenance: [], deviceId: device, from: day, to: day)
        let current = try await store.scoreCalculationCurrent(deviceId: device, day: day, key: "recovery")
        let history = try await store.scoreCalculationHistory(deviceId: device, day: day, key: "recovery", limit: -1)
        XCTAssertEqual(current, evidence())
        XCTAssertEqual(history, [])
    }
    func testForgettingInputProviderRemovesItsEvidenceAcrossComputedNamespaces() throws {
        let queue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO dailyMetric(deviceId,day,recovery) VALUES ('computed','2026-11-15',71)")
            for (fingerprint, source) in [("owned", "strap"), ("other", "other-strap")] {
                try db.execute(sql: "INSERT INTO scoreCalculationEvidence VALUES ('computed','2026-11-15','recovery',?,100,?,'method',71,'recipe')", arguments: [fingerprint,source])
            }
            try db.execute(sql: "INSERT INTO scoreCalculationHead VALUES ('computed','2026-11-15','recovery','owned')")
        }
        try DeviceRegistryStore(dbQueue: queue).deleteAllData(deviceId: "strap")
        try queue.read { db in
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT fingerprint FROM scoreCalculationEvidence"), ["other"])
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scoreCalculationHead"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT recovery FROM dailyMetric"), 71)
        }
    }
    func testAdditiveMigrationFromV48PreservesDailyAndExactSchema() throws {
        let queue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(queue, upTo: "v48-ecg-waveform")
        try queue.write { db in try db.execute(sql: "INSERT INTO dailyMetric(deviceId,day,recovery) VALUES ('strap-noop','2026-11-15',71)") }
        try WhoopStore.makeMigrator().migrate(queue)
        try queue.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT recovery FROM dailyMetric"), 71)
            XCTAssertEqual(try db.columns(in: "scoreCalculationEvidence").map(\.name),
                           ["deviceId","day","key","fingerprint","capturedAt","sourceId","methodId","value","payload"])
            XCTAssertEqual(try db.primaryKey("scoreCalculationEvidence").columns, ["deviceId","day","key","fingerprint"])
            XCTAssertEqual(try db.columns(in: "scoreCalculationHead").map(\.name), ["deviceId","day","key","fingerprint"])
        }
    }
}
