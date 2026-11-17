import Foundation

/// Research-only history fold. Quality describes recording evidence, never the sign of a vital change.
public enum QualityBaseline {
    public struct Result: Sendable {
        public let original: BaselineState
        public let candidate: BaselineState?
        public let admitted: Int, unknown: Int, rejected: Int
        public let status: String
    }
    public static func fold(values: [Double?], qualities: [Double?], cfg: MetricCfg) -> Result {
        let original = Baselines.foldHistory(values, cfg: cfg)
        guard values.count == qualities.count else {
            return .init(original: original,candidate: nil,admitted: 0,unknown: 0,rejected: 0,status: "mismatched-history")
        }
        var state: BaselineState?, admitted = 0, unknown = 0, rejected = 0
        for (value,q) in zip(values,qualities) {
            var usable: Double?
            if q == nil { unknown += 1 }
            else if !q!.isFinite || !(0.5...1).contains(q!) { rejected += 1 }
            else if let v = value, v.isFinite, (cfg.minVal...cfg.maxVal).contains(v) { usable = v; admitted += 1 }
            let next = Baselines.update(state, value: usable, cfg: cfg)
            if let old = state, old.nValid > 0, usable != nil, let q, q < 1 {
                state = .init(baseline: old.baseline + q * (next.baseline - old.baseline),
                    spread: old.spread + q * (next.spread - old.spread), nValid: next.nValid,
                    nightsSinceUpdate: next.nightsSinceUpdate,status: next.status)
            } else { state = next }
        }
        let candidate = state ?? Baselines.foldHistory([],cfg:cfg)
        return .init(original:original,candidate:candidate,admitted:admitted,unknown:unknown,rejected:rejected,
            status:candidate.usable ? "compared" : candidate.status.rawValue)
    }
}
