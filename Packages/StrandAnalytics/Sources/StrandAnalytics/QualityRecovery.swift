import Foundation

/// Experimental quality-scaled weights over the SAME incumbent vitals and baselines, not experimental HRV.
/// The quality thresholds are hypotheses. No score can be produced without essential HRV/RHR evidence.
public enum QualityRecovery {
    public struct Quality: Sendable {
        public let hrv: Double, rhr: Double, sleep: Double, resp: Double, skin: Double
        public init(hrv: Double, rhr: Double, sleep: Double, resp: Double = 0, skin: Double = 0) {
            self.hrv = hrv; self.rhr = rhr; self.sleep = sleep; self.resp = resp; self.skin = skin
        }
    }
    public struct Result: Sendable {
        public let original: Double?, candidate: Double?
        public let status: String
    }
    public static func compare(hrv: Double, rhr: Double, resp: Double? = nil,
                               hrvBaseline: RecoveryScorer.DriverBaseline?, rhrBaseline: RecoveryScorer.DriverBaseline?,
                               respBaseline: RecoveryScorer.DriverBaseline? = nil, sleepPerf: Double? = nil,
                               skinTempDev: Double? = nil, baselineUsable: Bool = true, quality q: Quality) -> Result {
        func valid(_ b: RecoveryScorer.DriverBaseline?) -> Bool {
            b.map { $0.mean.isFinite && $0.spread.isFinite && $0.spread > 0 } ?? false
        }
        guard hrv.isFinite, hrv >= 0, rhr.isFinite, rhr > 0, valid(hrvBaseline),
              rhrBaseline == nil || valid(rhrBaseline), respBaseline == nil || valid(respBaseline),
              resp == nil || (resp!.isFinite && resp! > 0), sleepPerf == nil || (sleepPerf!.isFinite && (0...1).contains(sleepPerf!)),
              skinTempDev == nil || skinTempDev!.isFinite else {
            return Result(original: nil, candidate: nil, status: "invalid-input")
        }
        let original = RecoveryScorer.recovery(hrv: hrv, rhr: rhr, resp: resp,
            hrvBaseline: hrvBaseline, rhrBaseline: rhrBaseline, respBaseline: respBaseline,
            sleepPerf: sleepPerf, skinTempDev: skinTempDev, hrvBaselineUsable: baselineUsable)
        guard [q.hrv, q.rhr, q.sleep, q.resp, q.skin].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return Result(original: original, candidate: nil, status: "invalid-quality")
        }
        guard baselineUsable, let hb = hrvBaseline, let rb = rhrBaseline, q.hrv >= 0.5, q.rhr >= 0.2 else {
            return Result(original: original, candidate: nil, status: "insufficient-essential-quality")
        }
        var terms: [(Double, Double)] = [
            (RecoveryScorer.zScore(hrv, mean: hb.mean, spread: hb.spread), RecoveryScorer.wHRV * q.hrv),
            (RecoveryScorer.zScore(rb.mean, mean: rhr, spread: rb.spread), RecoveryScorer.wRHR * q.rhr)]
        if let r = resp, let b = respBaseline { terms.append((RecoveryScorer.zScore(b.mean, mean: r, spread: b.spread), RecoveryScorer.wResp * q.resp)) }
        if let sp = sleepPerf { terms.append(((sp - RecoveryScorer.sleepPerfCenter) / RecoveryScorer.sleepPerfScale, RecoveryScorer.wSleep * q.sleep)) }
        if let t = skinTempDev { terms.append((-abs(t) / RecoveryScorer.skinTempScaleC, RecoveryScorer.wSkinTemp * q.skin)) }
        let total = terms.reduce(0) { $0 + $1.1 }
        let z = terms.reduce(0) { $0 + $1.0 * $1.1 } / total
        return Result(original: original, candidate: RecoveryScorer.logisticScore(compositeZ: z), status: "compared")
    }
}
