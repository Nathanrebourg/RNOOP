import XCTest
import WhoopStore
import WhoopProtocol
@testable import StrandAnalytics

final class ScoreRecipeTests: XCTestCase {
    func testCompiledOracleReversePin() throws {
        XCTAssertEqual(scoreRecipeTranscript(scoreRecipeFixtures()), Self.swiftOracle)
        for recipe in scoreRecipeFixtures() {
            XCTAssertEqual(ScoreRecipe.decode(recipe.payload), recipe)
            XCTAssertEqual(recipe.replay(), recipe.score)
            XCTAssertEqual(recipe.numericInputs["efficiency"], recipe.key == "sleep_performance" ? 0.9 : nil)
            XCTAssertEqual(recipe.textInputs["source"], recipe.sourceId)
        }
    }
    func testRecoveryMatchesFinalDailyRecipeAndPreservesStaleBaselineState() throws {
        let daily = DailyMetric(day: "2026-11-15", totalSleepMin: 420, efficiency: 0.9,
            deepMin: 60, remMin: 90, lightMin: nil, disturbances: nil, restingHr: 54,
            avgHrv: 61, recovery: nil, strain: nil, exerciseCount: nil, skinTempDevC: -0.2, respRateBpm: 14.2)
        let h = BaselineState(baseline: 55, spread: 8, nValid: 21, nightsSinceUpdate: 0, status: .trusted)
        let stale = BaselineState(baseline: 33, spread: 0.4, nValid: 44, nightsSinceUpdate: 9, status: .stale)
        let recipe = try XCTUnwrap(ScoreRecipe.recovery(daily: daily, baselines: .init(hrv: h, restingHR: stale), source: "strap"))
        let actual = RecoveryScorer.recovery(hrv: 61, rhr: 54, resp: 14.2, hrvBaseline: h,
            rhrBaseline: stale, respBaseline: nil, sleepPerf: AnalyticsEngine.Rest.composite(daily: daily).map { $0 / 100.0 }, skinTempDev: -0.2)
        XCTAssertEqual(recipe.score, actual)
        let revised = BaselineState(baseline: 33, spread: 0.4, nValid: 45, nightsSinceUpdate: 9, status: .stale)
        let other = try XCTUnwrap(ScoreRecipe.recovery(daily: daily, baselines: .init(hrv: h, restingHR: revised), source: "strap"))
        XCTAssertEqual(other.score, recipe.score)
        XCTAssertEqual(other.changedFields(from: recipe), ["rhrNValid"])
        XCTAssertNil(ScoreRecipe.recovery(daily: daily, baselines: .init(hrv: stale), source: "strap"))
    }
    // Verbatim compiled Swift stdout; Kotlin pins the identical literal independently.
    private static let swiftOracle = """
sleep_performance|rest.daily-composite.v1|a8d7abf541faede8|4054428f5c28f5c3|243
recovery|recovery.logistic.v1|a35573149d4acb73|40522cef0c1d2113|705
recovery|recovery.logistic.v1|94eb51d031fe2dfe|4051bfff0286b5dd|599
strain|effort.edwards-hrr-log.v1|dc0070bb3ccc3116|404c83d70a3d70a4|412
strain|effort.edwards-hrr-log.v1|e253c9635a25b5e3|404c83d70a3d70a4|416
strain|effort.banister-sedentary-log.v1|85c960db12bc336a|404b5851eb851eb8|426
strain|effort.banister-sedentary-log.v1|2c6e15eb5d5812e6|404bb33333333333|430
sleep_performance|rest.daily-composite.v1|079fdb31099cc3ff|4054428f5c28f5c3|308
"""
    func testRestReplayCanonicalContextAndRefusals() throws {
        let daily = DailyMetric(day: "2026-11-15", totalSleepMin: 420, efficiency: 0.9, deepMin: 60, remMin: 90, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)
        let recipe = try XCTUnwrap(ScoreRecipe.rest(daily: daily, source: "strap-α-noop"))
        XCTAssertEqual(recipe.replay(), AnalyticsEngine.Rest.composite(daily: daily))
        XCTAssertEqual(ScoreRecipe.decode(recipe.payload), recipe)
        let contextual = try XCTUnwrap(recipe.withContext(["zone": "Europe/Paris", "mode": "sleepOnset"]))
        XCTAssertEqual(contextual.context, ["zone": "Europe/Paris", "mode": "sleepOnset"])
        XCTAssertEqual(contextual.replay(), recipe.score)
        XCTAssertNotEqual(contextual.fingerprint, recipe.fingerprint)
        XCTAssertEqual(contextual.changedFields(from: recipe), ["ctx.mode", "ctx.zone"])
        XCTAssertNil(ScoreRecipe.decode(recipe.payload + "\n"))
        XCTAssertNil(ScoreRecipe.decode(String(repeating: "x", count: 16385)))
        XCTAssertNil(recipe.withContext(["bad key": "x"]))
        XCTAssertNil(ScoreRecipe.rest(daily: DailyMetric(day: "2026-11-15", totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil), source: "x"))
    }
    func testAnalyzeDayRetainsObservedEffortOnlyWithKnownSource() throws {
        let hr = (0..<180).map { HRSample(ts: 1000 + $0 * 30, bpm: 145) }
        let result = AnalyticsEngine.analyzeDay(day: "1970-01-01", hr: hr, profile: UserProfile(), recipeSource: "strap-noop")
        XCTAssertEqual(result.effortRecipe?.score, result.strain)
        XCTAssertEqual(result.effortRecipe?.sourceId, "strap-noop")
        XCTAssertNil(AnalyticsEngine.analyzeDay(day: "1970-01-01", hr: hr, profile: UserProfile()).effortRecipe)
    }
    func testCalendarQueryScopeIsRetainedWithoutChangingEffort() throws {
        let hr = (0..<180).map { HRSample(ts: 1000 + $0 * 30, bpm: 145) }
        let scoped = AnalyticsEngine.analyzeDay(day: "1970-01-01", hr: hr, profile: UserProfile(),
            recipeSource: "strap", recipeWindowStart: 0, recipeWindowEnd: 86400)
        let recipe = try XCTUnwrap(scoped.effortRecipe)
        XCTAssertEqual(recipe.textInputs["windowKind"], "calendar")
        XCTAssertTrue(recipe.payload.contains("windowStart=i0"))
        XCTAssertTrue(recipe.payload.contains("windowEnd=i86400"))
        XCTAssertEqual(recipe.replay(), scoped.strain)
        let original = try XCTUnwrap(ScoreRecipe.effort(hr: hr, maxHR: StrainScorer.tanakaHRmax(age: 30),
            restingHR: StrainScorer.defaultRestingHR, method: .edwards, sex: UserProfile().sex, source: "strap"))
        XCTAssertEqual(recipe.score, original.score)
        XCTAssertEqual(recipe.changedFields(from: original), ["windowEnd", "windowKind", "windowStart"])
        XCTAssertNil(original.withEffortWindow(startInclusive: 0, endExclusive: 86400, kind: "invented"))
    }
    func testActualEffortAndEmptyRefusal() throws {
        let hr = (0..<180).map { HRSample(ts: 1000 + $0 * 30, bpm: 145) }
        for method in [StrainScorer.Method.edwards, .banister] {
            for sex in ["male", "female"] {
                let recipe = try XCTUnwrap(ScoreRecipe.effort(hr: hr, maxHR: 190, restingHR: 55, method: method, sex: sex, source: "strap-noop"))
                XCTAssertEqual(recipe.score, StrainScorer.strain(hr, maxHR: 190, restingHR: 55, method: method, sex: sex))
                XCTAssertEqual(ScoreRecipe.decode(recipe.payload)?.replay(), recipe.score)
            }
        }
        XCTAssertNil(ScoreRecipe.effort(hr: [], maxHR: 190, restingHR: 55, method: .edwards, sex: "male", source: "x"))
    }
}

// Shared standalone-oracle fixtures. The generated transcript is pinned independently in both test suites.
func scoreRecipeFixtures() -> [ScoreRecipe] {
    let d = DailyMetric(day: "2026-11-15", totalSleepMin: 420, efficiency: 0.9,
        deepMin: 60, remMin: 90, lightMin: nil, disturbances: nil, restingHr: 54,
        avgHrv: 61, recovery: nil, strain: nil, exerciseCount: nil, skinTempDevC: -0.2, respRateBpm: 14.2)
    let h = BaselineState(baseline: 55, spread: 8, nValid: 21, nightsSinceUpdate: 0, status: .trusted)
    let r = BaselineState(baseline: 57, spread: 4, nValid: 15, nightsSinceUpdate: 1, status: .provisional)
    let p = BaselineState(baseline: 14.6, spread: 0.7, nValid: 17, nightsSinceUpdate: 0, status: .trusted)
    let stale = BaselineState(baseline: 33, spread: 0.4, nValid: 44, nightsSinceUpdate: 9, status: .stale)
    var recipes = [ScoreRecipe.rest(daily: d, source: "strap-α")!,
        ScoreRecipe.recovery(daily: d, baselines: .init(hrv: h, restingHR: r, resp: p, skinTemp: stale), source: "strap-α")!,
        ScoreRecipe.recovery(daily: d, baselines: .init(hrv: h, restingHR: stale), source: "strap-α")!]
    let hr = (0..<180).map { HRSample(ts: 1000 + $0 * 30 + ($0 > 100 ? 600 : 0), bpm: [60, 100, 145, 180][$0 % 4]) }
    for method in [StrainScorer.Method.edwards, .banister] {
        for sex in ["male", "female"] {
            recipes.append(ScoreRecipe.effort(hr: hr, maxHR: 190, restingHR: 55, method: method, sex: sex, source: "strap-α")!
                .withEffortWindow(startInclusive: 900, endExclusive: 8000)!)
        }
    }
    recipes.append(recipes[0].withContext(["zone": "Europe/Paris", "setting": "α=\n🫀"])!)
    return recipes
}
func scoreRecipeTranscript(_ recipes: [ScoreRecipe]) -> String {
    recipes.map { "\($0.key)|\($0.methodId)|\($0.fingerprint)|\(String(format: "%016llx", $0.score.bitPattern))|\($0.payload.utf8.count)" }.joined(separator: "\n")
}
