import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

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
