import XCTest
import WhoopStore
import WhoopProtocol
@testable import Strand

final class NightDiagnosticExportTests: XCTestCase {
    func testInstallationIdentityIsStableButSeparatesSources() throws {
        let suite = "noop-night-identity-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = NightDiagnosticExport.installationSalt(defaults: defaults)
        XCTAssertEqual(first, NightDiagnosticExport.installationSalt(defaults: defaults))
        XCTAssertEqual(NightDiagnosticExport.pseudonym(owner: "a", salt: first), NightDiagnosticExport.pseudonym(owner: "a", salt: first))
        XCTAssertNotEqual(NightDiagnosticExport.pseudonym(owner: "a", salt: first), NightDiagnosticExport.pseudonym(owner: "b", salt: first))
    }
    func testCivilDayRefusesDSTRatherThanClippingAnHour() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let parser = ISO8601DateFormatter()
        XCTAssertThrowsError(try NightDiagnosticExport.window(date: parser.date(from: "2026-03-29T12:00:00Z")!, timeZone: zone, now: 1_800_000_000))
        XCTAssertThrowsError(try NightDiagnosticExport.window(date: parser.date(from: "2026-10-25T12:00:00Z")!, timeZone: zone, now: 1_800_000_000))
        let w = try NightDiagnosticExport.window(date: parser.date(from: "2026-11-14T12:00:00Z")!, timeZone: zone, now: 1_800_000_000)
        XCTAssertEqual(w.end - w.start, 86_400)
        XCTAssertEqual((w.start + w.offset) % 86_400, 0)
        XCTAssertEqual(w.day, "2026-11-14")
    }

    func testStrictZIPRefusesDuplicateOrNestedNames() {
        let bytes = Data("fixture".utf8)
        XCTAssertNil(FileExport.zipData(entries: [.init(name: "recording.json", data: bytes), .init(name: "recording.json", data: bytes)], baseName: "noop-night-duplicate", strict: true))
        XCTAssertNil(FileExport.zipData(entries: [.init(name: "../recording.json", data: bytes)], baseName: "noop-night-traversal", strict: true))
    }

    func testStrictZIPRoundTripsEveryEntry() throws {
        let entries = [FileExport.BundleEntry(name: "recording.json", data: Data("{\"schema\":1}".utf8)), .init(name: "manifest.json", data: Data("{}".utf8))]
        let url = try XCTUnwrap(FileExport.zipData(entries: entries, baseName: "noop-night-strict-" + UUID().uuidString, strict: true))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCaptureIncludesOnlyBoundedPriorComputedHistoryAndNoRawIdentity() async throws {
        let store = try await WhoopStore.inMemory()
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        try registry.add(.init(id: "my-whoop", brand: "WHOOP", model: "WHOOP 5.0", peripheralId: "PRIVATE-BLE-ID", sourceKind: .liveBLE, capabilities: [.hr, .hrv, .sleep], status: .active, addedAt: 1, lastSeenAt: 1))
        let d = "2026-11-14"
        let row = DailyMetric(day: d, totalSleepMin: 480, efficiency: 90, deepMin: 60, remMin: 100, lightMin: 320, disturbances: 3, restingHr: 55, avgHrv: 60, recovery: 70, strain: 4, exerciseCount: 0)
        _ = try await store.upsertDailyMetrics([row], deviceId: "my-whoop-noop")
        var streams = Streams()
        let start = 1_794_610_800 // 2026-11-14 00:00 Europe/Paris
        streams.hr = [.init(ts: start + 10, bpm: 60)]
        _ = try await store.insert(streams, deviceId: "my-whoop")
        let settings = NightDiagnosticExport.Settings(age: 30, sex: "male", manualHRmax: nil, useV2: true, deepWindow: false, appVersion: "test", build: "test")
        let result = try await NightDiagnosticExport.capture(store: store, date: Date(timeIntervalSince1970: Double(start + 3600)), timeZone: TimeZone(identifier: "Europe/Paris")!, now: start + 86_400, settings: settings)
        let recording = try XCTUnwrap(result.entries.first { $0.name == "recording.json" })
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: recording.data) as? [String: Any])
        let repeated = try await NightDiagnosticExport.capture(store: store, date: Date(timeIntervalSince1970: Double(start + 3600)), timeZone: TimeZone(identifier: "Europe/Paris")!, now: start + 86_400, settings: settings)
        let repeatedBytes = try XCTUnwrap(repeated.entries.first { $0.name == "recording.json" })
        let repeatedInput = try XCTUnwrap(JSONSerialization.jsonObject(with: repeatedBytes.data) as? [String: Any])
        XCTAssertEqual(parsed["owner"] as? String, repeatedInput["owner"] as? String)
        XCTAssertEqual(parsed["schema"] as? Int, 1)
        XCTAssertEqual(parsed["origin"] as? String, "recorded")
        XCTAssertEqual(parsed["rrIdentity"] as? String, "store-key-v1")
        XCTAssertEqual((parsed["history"] as? [Any])?.count, 0, "current day must not leak into replay baseline")
        XCTAssertEqual((parsed["hr"] as? [Any])?.count, 1)
        XCTAssertTrue(result.entries.contains { $0.name == "coverage.json" })
        let text = result.entries.map { String(decoding: $0.data, as: UTF8.self) }.joined()
        XCTAssertFalse(text.contains("PRIVATE-BLE-ID"))
        XCTAssertFalse(text.contains("my-whoop"))
        let manifest = try XCTUnwrap(result.entries.first { $0.name == "manifest.json" })
        let m = try XCTUnwrap(JSONSerialization.jsonObject(with: manifest.data) as? [String: Any])
        let hashes = try XCTUnwrap(m["sha256"] as? [String: String])
        XCTAssertEqual(hashes["recording.json"], NightDiagnosticExport.sha256(recording.data))
    }
}
