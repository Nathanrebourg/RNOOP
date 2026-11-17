import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Local read-only history collection for the newest day's opt-in sleep detector comparison.
/// Kept outside IntelligenceEngine's main loop; this experiment never persists a candidate.
enum SleepBaselineExperiment {
    static func run(store: WhoopStore, owner: String, day: String, dayStart: Int, readStart: Int,
                    offset: Int, hr: [HRSample], rr: [RRInterval], resp: [RespSample], gravity: [GravitySample],
                    wristOff: [(start: Int, end: Int)], bandSleepState: [(ts: Int, state: Int)],
                    useSleepStagerV2: Bool) async -> String {
        var history: [SleepBaselineComparison.Observation] = []
        for window in SleepBaselineComparison.historyWindows(before: readStart, offset: offset) {
            if Task.isCancelled { return "sleep baseline experimental=true day=\(day) status=cancelled" }
            guard let rows = try? await store.hrSamples(deviceId: owner, from: window.start,
                                                        to: window.end - 1, limit: 50_000),
                  let observation = SleepBaselineComparison.observation(rows, window: window) else { continue }
            history.append(observation)
        }
        return SleepBaselineComparison.compare(dayStart: dayStart, readStart: readStart, history: history,
            hr: hr, rr: rr, resp: resp, gravity: gravity, offset: offset, wristOff: wristOff,
            bandSleepState: bandSleepState, useSleepStagerV2: useSleepStagerV2,
            readCapped: hr.count >= StreamReadCap.hr || rr.count >= StreamReadCap.rr
                || gravity.count >= StreamReadCap.gravity || resp.count >= 200_000).trace(day: day)
    }
}
