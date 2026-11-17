import Foundation
import WhoopProtocol
import WhoopStore

/// Versioned sufficient calculation evidence. No raw sensor rows are retained.
/// The v1 replay branches are frozen; a numerical change requires a new method ID.
public struct ScoreRecipe: Equatable, Sendable {
    public static let recoveryMethod = "recovery.logistic.v1"
    public static let restMethod = "rest.daily-composite.v1"
    public static let edwardsMethod = "effort.edwards-hrr-log.v1"
    public static let banisterMethod = "effort.banister-sedentary-log.v1"
    public let key: String, sourceId: String, methodId: String, payload: String, fingerprint: String
    public let score: Double
    private let fields: [String: String]
    public var numericInputs: [String: Double] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { key, value in
            guard value.first == "d", let bits = UInt64(value.dropFirst(), radix: 16) else { return nil }
            let number = Double(bitPattern: bits)
            return number.isFinite ? (key, number) : nil
        })
    }
    public var textInputs: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { key, value in
            Self.text(value).map { (key, $0) }
        })
    }
    public var context: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { k, v in
            guard k.hasPrefix("ctx."), let s = Self.text(v) else { return nil }
            return (String(k.dropFirst(4)), s)
        })
    }
    public func withContext(_ context: [String: String]) -> ScoreRecipe? {
        guard context.keys.allSatisfy(Self.validName) else { return nil }
        var f = fields.filter { !$0.key.hasPrefix("ctx.") }
        for (k, v) in context { f["ctx." + k] = Self.string(v) }
        return Self.make(f)
    }
    public func withEffortWindow(startInclusive: Int, endExclusive: Int, kind: String = "sleep-onset") -> ScoreRecipe? {
        guard key == "strain" else { return nil }
        var f = fields
        f["windowStart"] = Self.integer(startInclusive); f["windowEnd"] = Self.integer(endExclusive)
        f["windowKind"] = Self.string(kind)
        return Self.make(f)
    }
    public func changedFields(from previous: ScoreRecipe) -> [String] {
        Set(fields.keys).union(previous.fields.keys).filter { fields[$0] != previous.fields[$0] }.sorted()
    }
    public static func recovery(daily d: DailyMetric, baselines b: AnalyticsEngine.ProfileBaselines,
                                source: String) -> ScoreRecipe? {
        guard let h = d.avgHrv, let r = d.restingHr, let hb = b.hrv, hb.usable else { return nil }
        var f = base("recovery", source, recoveryMethod)
        f["hrv"] = number(h); f["rhr"] = number(Double(r))
        f["resp"] = number(d.respRateBpm); f["skin"] = number(d.skinTempDevC)
        f["sleep"] = number(AnalyticsEngine.Rest.composite(daily: d).map { $0 / 100.0 } ?? d.efficiency)
        for (name, state) in [("hrv", b.hrv), ("rhr", b.restingHR), ("resp", b.resp), ("skin", b.skinTemp)] {
            f[name + "Mean"] = number(state.map { $0.baseline })
            f[name + "Spread"] = number(state.map { $0.spread })
            f[name + "NValid"] = state.map { integer($0.nValid) } ?? "n"
            f[name + "NightsSinceUpdate"] = state.map { integer($0.nightsSinceUpdate) } ?? "n"
            f[name + "Status"] = state.map { string($0.status.rawValue) } ?? "n"
        }
        return make(f)
    }
    public static func rest(daily d: DailyMetric, source: String) -> ScoreRecipe? {
        guard let t = d.totalSleepMin, t > 0, let e = d.efficiency else { return nil }
        var f = base("sleep_performance", source, restMethod)
        f["minutes"] = number(t); f["efficiency"] = number(e)
        // Preserve absence as absence; the frozen daily-composite method applies its documented zero fallback.
        f["deepMinutes"] = number(d.deepMin); f["remMinutes"] = number(d.remMin)
        return make(f)
    }
    public static func effort(hr: [HRSample], maxHR: Double?, restingHR: Double,
                              method: StrainScorer.Method, sex: String, source: String) -> ScoreRecipe? {
        guard !hr.isEmpty, let actual = StrainScorer.strain(hr, maxHR: maxHR, restingHR: restingHR,
            method: method, sex: sex), actual.isFinite else { return nil }
        let maximum = maxHR ?? Double(StrainScorer.defaultMaxHR())
        guard maximum.isFinite, restingHR.isFinite, maximum > restingHR else { return nil }
        let durations = StrainScorer.sampleDurationsMinutes(hr)
        let reserve = maximum - restingHR
        let trimp: Double
        switch method {
        case .edwards: trimp = StrainScorer.edwardsTRIMP(hr, restingHR: restingHR, hrReserve: reserve, durations: durations)
        case .banister:
            let c = StrainScorer.banisterCoefficients(sexF: sex.lowercased().hasPrefix("f"))
            trimp = StrainScorer.banisterTRIMP(hr, restingHR: restingHR, hrReserve: reserve, durations: durations, c,
                floorRatePerMinute: StrainScorer.banisterBaselineRatePerMinute(c))
        }
        var f = base("strain", source, method == .edwards ? edwardsMethod : banisterMethod)
        f["trimp"] = number(trimp); f["denominator"] = number(StrainScorer.logMapDenominator(method: method, sex: sex))
        f["maxHR"] = number(maximum); f["restingHR"] = number(restingHR)
        f["sex"] = string(sex.lowercased().hasPrefix("f") ? "female" : "male")
        f["count"] = integer(hr.count); f["firstTs"] = integer(hr.map(\.ts).min()!)
        f["lastTs"] = integer(hr.map(\.ts).max()!); f["creditedMinutes"] = number(durations.reduce(0, +))
        f["stream"] = string(streamSignature(hr))
        f["windowStart"] = integer(hr.map(\.ts).min()!)
        let last = hr.map(\.ts).max()!
        guard last < Int.max else { return nil }
        f["windowEnd"] = integer(last + 1); f["windowKind"] = string("observed-samples")
        guard let recipe = make(f), recipe.score == actual else { return nil }
        return recipe
    }
    private static func streamSignature(_ hr: [HRSample]) -> String {
        hash(hr.map { "\($0.ts):\($0.bpm)" }.joined(separator: ";"))
    }
    private static func base(_ key: String, _ source: String, _ method: String) -> [String: String] {
        ["schema": "i1", "key": string(key), "source": string(source), "method": string(method)]
    }
    private static func number(_ v: Double?) -> String {
        v.map { "d" + String(format: "%016llx", $0.bitPattern) } ?? "n"
    }
    private static func integer(_ v: Int) -> String { "i" + String(v) }
    private static func string(_ s: String) -> String { "s" + s.utf8.map { String(format: "%02x", $0) }.joined() }
    private static func text(_ value: String) -> String? {
        guard value.first == "s" else { return nil }
        let chars = Array(value.dropFirst().utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let n = UInt8(String(bytes: chars[i...i+1], encoding: .utf8)!, radix: 16) else { return nil }
            bytes.append(n)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
    private static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 95 || $0 == 45 }
    }
    private static func hash(_ s: String) -> String {
        var h: UInt64 = 14695981039346656037
        for c in s.utf8 { h = (h ^ UInt64(c)) &* 1099511628211 }
        return String(format: "%016llx", h)
    }
    public static func decode(_ payload: String) -> ScoreRecipe? {
        guard !payload.isEmpty, payload.utf8.count <= 16384, payload.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        var f: [String: String] = [:]
        for row in payload.split(separator: "\n", omittingEmptySubsequences: false) {
            let pair = row.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, validName(String(pair[0])), f[String(pair[0])] == nil else { return nil }
            let v = String(pair[1])
            if v == "n" { } else if v.first == "s" {
                guard let t = text(v), string(t) == v else { return nil }
            } else if v.first == "d" {
                guard v.count == 17, let bits = UInt64(v.dropFirst(), radix: 16), Double(bitPattern: bits).isFinite,
                      number(Double(bitPattern: bits)) == v else { return nil }
            } else if v.first == "i" {
                guard let n = Int(v.dropFirst()), integer(n) == v else { return nil }
            } else { return nil }
            f[String(pair[0])] = v
        }
        guard let recipe = make(f), recipe.payload == payload else { return nil }
        return recipe
    }
    private static func make(_ f: [String: String]) -> ScoreRecipe? {
        let payload = f.keys.sorted().map { $0 + "=" + f[$0]! }.joined(separator: "\n")
        guard payload.utf8.count <= 16384, f["schema"] == "i1",
              let key = f["key"].flatMap(text), let source = f["source"].flatMap(text), !source.isEmpty,
              let method = f["method"].flatMap(text),
              f.filter({ $0.key.hasPrefix("ctx.") }).allSatisfy({ validName(String($0.key.dropFirst(4))) && text($0.value) != nil }),
              let score = evaluate(f, method: method, key: key), score.isFinite, (0...100).contains(score) else { return nil }
        // Reject nonfinite factory inputs too; decode is not the sole entry point.
        for v in f.values where v.first == "d" {
            guard let bits = UInt64(v.dropFirst(), radix: 16), Double(bitPattern: bits).isFinite else { return nil }
        }
        return ScoreRecipe(key: key, sourceId: source, methodId: method, payload: payload,
                           fingerprint: hash(payload), score: score, fields: f)
    }
    public func replay() -> Double? { Self.evaluate(fields, method: methodId, key: key) }
    private static func evaluate(_ f: [String: String], method: String, key: String) -> Double? {
        func d(_ k: String) -> Double? {
            guard let s = f[k], s.first == "d", let bits = UInt64(s.dropFirst(), radix: 16) else { return nil }
            let x = Double(bitPattern: bits); return x.isFinite ? x : nil
        }
        let common: Set<String> = ["schema", "key", "source", "method"]
        let allowed: Set<String>
        switch method {
        case recoveryMethod: allowed = Set(["hrv", "rhr", "resp", "skin", "sleep"] + ["hrv", "rhr", "resp", "skin"].flatMap { name in ["Mean", "Spread", "NValid", "NightsSinceUpdate", "Status"].map { name + $0 } })
        case restMethod: allowed = ["minutes", "efficiency", "deepMinutes", "remMinutes"]
        case edwardsMethod, banisterMethod: allowed = ["trimp", "denominator", "maxHR", "restingHR", "sex", "count", "firstTs", "lastTs", "creditedMinutes", "stream", "windowStart", "windowEnd", "windowKind"]
        default: return nil
        }
        guard Set(f.keys.filter { !$0.hasPrefix("ctx.") }) == common.union(allowed) else { return nil }
        let numeric = allowed.subtracting(["sex", "count", "firstTs", "lastTs", "stream", "windowStart", "windowEnd", "windowKind"]).filter { !$0.hasSuffix("NValid") && !$0.hasSuffix("NightsSinceUpdate") && !$0.hasSuffix("Status") }
        guard numeric.allSatisfy({ f[$0] == "n" || d($0) != nil }) else { return nil }
        switch method {
        case recoveryMethod:
            for name in ["hrv", "rhr", "resp", "skin"] {
                let keys = ["Mean", "Spread", "NValid", "NightsSinceUpdate", "Status"].map { name + $0 }
                if keys.allSatisfy({ f[$0] == "n" }) { continue }
                guard d(name + "Mean") != nil, d(name + "Spread") != nil,
                      let n = f[name + "NValid"], n.first == "i", let nv = Int(n.dropFirst()), nv >= 0,
                      let u = f[name + "NightsSinceUpdate"], u.first == "i", let nu = Int(u.dropFirst()), nu >= 0,
                      let status = f[name + "Status"].flatMap(text), ["calibrating", "provisional", "trusted", "stale"].contains(status) else { return nil }
            }
            func usable(_ name: String) -> Bool { f[name + "Status"].flatMap(text).map { ["trusted", "provisional"].contains($0) } ?? false }
            guard usable("hrv"), key == "recovery", let h = d("hrv"), let r = d("rhr"), let hm = d("hrvMean"), let hs = d("hrvSpread") else { return nil }
            func z(_ v: Double, _ m: Double, _ s: Double) -> Double { (v - m) / max(1.253 * s, 1e-9) }
            var terms = [(z(h, hm, hs), 0.55)]
            if usable("rhr"), let m = d("rhrMean"), let s = d("rhrSpread") { terms.append((z(m, r, s), 0.20)) }
            if usable("resp"), let v = d("resp"), let m = d("respMean"), let s = d("respSpread") { terms.append((z(m, v, s), 0.05)) }
            if let s = d("sleep") { terms.append(((s - 0.85) / 0.12, 0.15)) }
            if let s = d("skin") { terms.append((-abs(s) / 1.0, 0.05)) }
            let z = terms.reduce(0) { $0 + $1.0 * $1.1 } / terms.reduce(0) { $0 + $1.1 }
            return max(0, min(100, 100.0 / (1.0 + exp(-1.6 * (z - -0.20)))))
        case restMethod:
            guard key == "sleep_performance", let t = d("minutes"), t > 0, let e = d("efficiency") else { return nil }
            func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
            let seconds = t * 60.0, deep = (d("deepMinutes") ?? 0) * 60.0
            let restorative = deep + (d("remMinutes") ?? 0) * 60.0
            let factor = 0.5 + (1.0 - 0.5) * clamp((deep / seconds) / 0.13)
            let weighted = 0.50 * clamp(seconds / (8.0 * 3600.0)) + 0.20 * clamp(e)
                + 0.20 * clamp((restorative / seconds) / 0.50) * factor + 0.10 * 0.5
            return (weighted * 10000).rounded() / 100
        default:
            guard key == "strain", let t = d("trimp"), t >= 0, let denominator = d("denominator"), denominator > 1,
                  let maximum = d("maxHR"), let resting = d("restingHR"), maximum > resting,
                  let credited = d("creditedMinutes"), credited > 0,
                  let c = f["count"], c.first == "i", let count = Int(c.dropFirst()), count > 0,
                  let first = f["firstTs"], first.first == "i", let lo = Int(first.dropFirst()),
                  let last = f["lastTs"], last.first == "i", let hi = Int(last.dropFirst()), hi >= lo,
                  f["sex"].flatMap(text).map({ ["female", "male"].contains($0) }) == true,
                  f["stream"].flatMap(text)?.count == 16,
                  let ws = f["windowStart"], ws.first == "i", let start = Int(ws.dropFirst()),
                  let we = f["windowEnd"], we.first == "i", let end = Int(we.dropFirst()), start <= lo, end > hi,
                  f["windowKind"].flatMap(text).map({ ["observed-samples", "sleep-onset", "calendar"].contains($0) }) == true else { return nil }
            return t <= 0 ? 0 : (100 * log(t + 1.0) / log(denominator) * 100).rounded() / 100
        }
    }
}
