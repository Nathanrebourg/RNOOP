import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class AICoachScreenContextTests: XCTestCase {
    private func row(_ day: String, _ hrv: Double) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: 0.95, deepMin: 60, remMin: 90,
                    lightMin: 300, disturbances: nil, restingHr: 52, avgHrv: hrv,
                    recovery: 67, strain: 30, exerciseCount: 0)
    }

    func testDatedContextCannotReadNewerRows() async throws {
        let repo = Repository(deviceId: "test-screen-context")
        repo.setStoreForTesting(try await WhoopStore.inMemory())
        repo.days = [row("2026-11-14", 41), row("2026-11-15", 58), row("2026-11-16", 999)]
        let engine = AICoachEngine(repo: repo, persistsConversation: false)
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .recovery))
        let text = await engine.buildScreenContext(context, dataConsent: true)
        XCTAssertTrue(text.contains("2026-11-15"))
        XCTAssertTrue(text.contains("58"))
        XCTAssertFalse(text.contains("999"))
        XCTAssertFalse(text.contains("2026-11-16"))
    }

    func testNoConsentOmitsActualMeasurements() async throws {
        let repo = Repository(deviceId: "test-screen-redaction")
        repo.days = [row("2026-11-15", 58)]
        let engine = AICoachEngine(repo: repo, persistsConversation: false)
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .recovery))
        let text = await engine.buildScreenContext(context, dataConsent: false)
        XCTAssertFalse(text.contains("58"))
        XCTAssertFalse(text.contains("67"))
        XCTAssertTrue(text.contains("withheld"))
    }

    func testScreenWithoutSelectedRowDoesNotCarryAnotherNight() async throws {
        let repo = Repository(deviceId: "test-screen-missing")
        repo.setStoreForTesting(try await WhoopStore.inMemory())
        repo.days = [row("2026-11-14", 444), row("2026-11-16", 999)]
        let engine = AICoachEngine(repo: repo, persistsConversation: false)
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .sleep))
        let text = await engine.buildScreenContext(context, dataConsent: true)
        XCTAssertTrue(text.contains("No daily row"))
        XCTAssertFalse(text.contains("HRV 444"))
        XCTAssertFalse(text.contains("999"))
    }

    func testEphemeralConversationDoesNotLoadPersistedMessages() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.replaceCoachMessages([.init(id: UUID().uuidString, role: "assistant", text: "Saved general chat", provider: "openai", createdAt: Int(Date().timeIntervalSince1970), orderIndex: 0)])
        let repo = Repository(deviceId: "test-screen-history")
        repo.setStoreForTesting(store)
        let engine = AICoachEngine(repo: repo, persistsConversation: false)
        await engine.loadPersistedMessagesIfNeeded()
        XCTAssertTrue(engine.messages.isEmpty)
        engine.clearConversation()
        for _ in 0..<10 { await Task.yield() }
        let retained = try await store.coachMessages()
        XCTAssertEqual(retained.map(\.text), ["Saved general chat"])
    }

    func testRevokingConsentCannotResendPriorBiometricHistory() {
        let engine = AICoachEngine(repo: Repository(deviceId: "test-screen-wire"), persistsConversation: false)
        engine.messages = [.init(role: .assistant, text: "Recovery 67%, HRV 58 ms"), .init(role: .user, text: "Previously shared data 999")]
        let wire = engine.screenWireMessages(context: "Wearable measurements withheld", currentQuestion: "Explain generally", dataConsent: false)
        XCTAssertEqual(wire.count, 1)
        XCTAssertTrue(wire[0].content.contains("Explain generally"))
        XCTAssertFalse(wire[0].content.contains("67"))
        XCTAssertFalse(wire[0].content.contains("58"))
        XCTAssertFalse(wire[0].content.contains("999"))
    }
}
