import Foundation

/// Exact five-driver replay explanation. Contributions add in z space, not nonlinear score points.
public enum RecoveryExplanation {
    public struct Term: Codable, Sendable {
        public let name: String
        public let z: Double, normalizedWeight: Double, contributionZ: Double
    }
    public struct Baseline: Codable, Sendable {
        public let center: Double, spread: Double
        public let nights: Int, missingNights: Int
        public let status: String
        public init(_ s: BaselineState) {
            center=s.baseline;spread=s.spread;nights=s.nValid;missingNights=s.nightsSinceUpdate;status=s.status.rawValue
        }
    }
    public struct Result: Codable, Sendable {
        public let score: Double?, compositeZ: Double?
        public let terms: [Term], missing: [String]
        public let baselines: [String:Baseline]
        public let status: String
    }
    public static func describe(hrv: Double,rhr: Double,resp: Double?,hrvBaseline: BaselineState,
                                rhrBaseline: BaselineState?,respBaseline: BaselineState?,sleepPerf: Double?,skinTempDev: Double?) -> Result {
        let states = ["hrv":hrvBaseline,"rhr":rhrBaseline,"resp":respBaseline].compactMapValues { $0 }
        let snapshots = states.mapValues(Baseline.init)
        func good(_ b: BaselineState) -> Bool { b.baseline.isFinite && b.spread.isFinite && b.spread > 0 }
        guard hrv.isFinite, hrv >= 0, rhr.isFinite, rhr > 0, states.values.allSatisfy(good),
              resp == nil || (resp!.isFinite && resp! > 0),
              sleepPerf == nil || (sleepPerf!.isFinite && (0...1).contains(sleepPerf!)),
              skinTempDev == nil || skinTempDev!.isFinite else {
            return .init(score:nil,compositeZ:nil,terms:[],missing:[],baselines:[:],status:"invalid-input")
        }
        guard hrvBaseline.usable else { return .init(score:nil,compositeZ:nil,terms:[],missing:["hrv-baseline"],baselines:snapshots,status:hrvBaseline.status.rawValue) }
        var raw:[(String,Double,Double)] = [("hrv",RecoveryScorer.zScore(hrv,mean:hrvBaseline.baseline,spread:hrvBaseline.spread),RecoveryScorer.wHRV)]
        var missing:[String] = []
        if let b=rhrBaseline, b.usable { raw.append(("rhr",RecoveryScorer.zScore(b.baseline,mean:rhr,spread:b.spread),RecoveryScorer.wRHR)) } else { missing.append("rhr") }
        if let b=respBaseline,b.usable,let r=resp { raw.append(("resp",RecoveryScorer.zScore(b.baseline,mean:r,spread:b.spread),RecoveryScorer.wResp)) } else { missing.append("resp") }
        if let sp=sleepPerf { raw.append(("sleep",(sp-RecoveryScorer.sleepPerfCenter)/RecoveryScorer.sleepPerfScale,RecoveryScorer.wSleep)) } else { missing.append("sleep") }
        if let t=skinTempDev { raw.append(("skin",-abs(t)/RecoveryScorer.skinTempScaleC,RecoveryScorer.wSkinTemp)) } else { missing.append("skin") }
        let weight=raw.reduce(0){$0+$1.2}
        let terms=raw.map { Term(name:$0.0,z:$0.1,normalizedWeight:$0.2/weight,contributionZ:$0.1*$0.2/weight) }
        let composite=raw.reduce(0){$0+$1.1*$1.2}/weight
        let score=RecoveryScorer.recovery(hrv:hrv,rhr:rhr,resp:resp,hrvBaseline:hrvBaseline,rhrBaseline:rhrBaseline,
            respBaseline:respBaseline,sleepPerf:sleepPerf,skinTempDev:skinTempDev)
        return .init(score:score,compositeZ:composite,terms:terms,missing:missing,baselines:snapshots,status:"explained")
    }
}
