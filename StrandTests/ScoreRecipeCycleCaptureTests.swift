import XCTest
import StrandAnalytics
import WhoopProtocol
import WhoopStore
@testable import Strand

@MainActor
final class ScoreRecipeCycleCaptureTests: XCTestCase {
    func testActualPhysiologicalWindowRecipeSurvivesCachedLoad() async throws {
        let store = try await WhoopStore.inMemory()
        let onset = 1_700_000_000, end = onset + 43_200
        let day = AnalyticsEngine.dayString(onset + 28_800)
        let hr = (0..<360).map { HRSample(ts: onset + 28_800 + $0 * 30, bpm: 145) }
        _ = try await store.insert(Streams(hr: hr), deviceId: "strap")
        let daily = DailyMetric(day: day, totalSleepMin: 480, efficiency: 0.9,
            deepMin: 60, remMin: 90, lightMin: nil, disturbances: nil, restingHr: 55,
            avgHrv: 60, recovery: nil, strain: nil, exerciseCount: nil)
        let sleep = CachedSleepSession(startTs: onset, endTs: onset + 28_800,
            efficiency: 0.9, restingHr: 55, avgHrv: 60, stagesJSON: nil)
        let cache = DayCycleIntelligenceIntegration.Cache()
        let reader = DayCycleIntelligenceIntegration.BoundaryRecoveryReader(
            sleepSessions: { _, _, _ in [] }, markers: { _, _, _ in [] })
        func compute() async -> DayCycleIntelligenceIntegration.Result {
            await DayCycleIntelligenceIntegration.compute(
                nights: [.init(daily: daily, sleeps: [sleep], workouts: [], owner: "strap")],
                editedRows: [], store: store, candidates: [(owner: "strap", priority: 0)],
                physiologyOwners: ["strap"], workouts: [], windowStart: onset, now: end,
                offsetSec: 0, habitualMidsleepSec: nil, ticksPerStep: 1, mode: .sleepOnset,
                cache: cache, profile: UserProfile(), maxHROverride: 190,
                effortMethod: .edwards, recoveryReader: reader)
        }
        let first = await compute()
        let firstRecipe = try XCTUnwrap(first.recipesByWakeDay[day])
        XCTAssertEqual(firstRecipe.sourceId, "strap")
        XCTAssertEqual(firstRecipe.score, StrainScorer.strain(hr, maxHR: 190, restingHR: 55))
        XCTAssertEqual(firstRecipe.score, first.strainByWakeDay[day])
        XCTAssertEqual(firstRecipe.textInputs["windowKind"], "sleep-onset")
        XCTAssertTrue(firstRecipe.payload.contains("windowStart=i\(onset)"))
        XCTAssertTrue(firstRecipe.payload.contains("windowEnd=i\(end)"))
        let cached = await compute()
        XCTAssertEqual(cached.recipesByWakeDay[day], firstRecipe)
        XCTAssertEqual(cached.strainByWakeDay[day], firstRecipe.score)
    }
}
