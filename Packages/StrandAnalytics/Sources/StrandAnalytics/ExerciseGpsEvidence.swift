import Foundation

/// Generic GPS/HR evidence is descriptive. The separate Kline estimator requires an explicitly
/// confirmed, repeated one-mile walking protocol and never changes the incumbent VO2max.
public enum ExerciseGpsEvidence {
    public struct Fix: Sendable {
        public var lat: Double; public var lon: Double; public var time: Double?; public var accuracyM: Double?
        public init(lat: Double, lon: Double, time: Double?, accuracyM: Double?) { self.lat = lat; self.lon = lon; self.time = time; self.accuracyM = accuracyM }
    }
    public struct HeartRate: Sendable {
        public var time: Double; public var bpm: Double; public var owner: String
        public init(time: Double, bpm: Double, owner: String) { self.time = time; self.bpm = bpm; self.owner = owner }
    }
    public struct Input: Sendable {
        public var start: Double; public var end: Double; public var sport: String; public var owner: String?; public var storedDistanceM: Double?; public var fixes: [Fix]; public var heartRates: [HeartRate]
        public init(start: Double, end: Double, sport: String, owner: String?, storedDistanceM: Double?, fixes: [Fix], heartRates: [HeartRate]) { self.start = start; self.end = end; self.sport = sport; self.owner = owner; self.storedDistanceM = storedDistanceM; self.fixes = fixes; self.heartRates = heartRates }
    }
    public struct Result: Sendable {
        public var distanceM: Double?; public var speedMps: Double?; public var meanHr: Double?; public var hrCoveredS: Double; public var metersPerBeat: Double?; public var reasons: [String]
        public var vo2max: Double? { nil }
    }
    public static func evaluate(_ input: Input) -> Result {
        var r = Result(distanceM: nil, speedMps: nil, meanHr: nil, hrCoveredS: 0, metersPerBeat: nil, reasons: [])
        func finish() -> Result { r.reasons += ["slope-unknown", "protocol-unverified"]; return r }
        let span = input.end - input.start
        guard input.start.isFinite, input.end.isFinite, input.start >= 0, span >= 600, span <= 21600 else { r.reasons.append("window-invalid"); return finish() }
        if !["running", "walking"].contains(input.sport) { r.reasons.append("sport-unsupported") }
        guard input.fixes.count >= 2, input.fixes.count <= 100000 else { r.reasons.append("gps-missing"); return finish() }
        guard input.fixes.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }) else { r.reasons.append("gps-invalid"); return finish() }
        var distance = 0.0, gpsTime = 0.0, stopped = 0.0
        var timing = true, accuracy = true, gpsGap = false, gpsSpeed = false
        for fix in input.fixes {
            if let t = fix.time { if !t.isFinite || t < input.start || t > input.end { timing = false } } else { timing = false }
            if let a = fix.accuracyM { if !a.isFinite || a < 0 || a > 20 { accuracy = false } } else { accuracy = false }
        }
        for i in 1..<input.fixes.count {
            let a = input.fixes[i-1], b = input.fixes[i]
            let dl = (b.lat-a.lat) * .pi / 180, dn = (b.lon-a.lon) * .pi / 180
            let h = sin(dl/2)*sin(dl/2) + cos(a.lat * .pi/180)*cos(b.lat * .pi/180)*sin(dn/2)*sin(dn/2)
            let d = 6371000 * 2 * atan2(sqrt(max(0,min(1,h))),sqrt(max(0,1-h)))
            distance += d
            if let t0 = a.time, let t1 = b.time, t0.isFinite, t1.isFinite {
                let dt = t1-t0
                if dt <= 0 { timing = false }
                else { gpsTime += dt; if dt > 15 { gpsGap = true }; if d/dt > 8 { gpsSpeed = true }; if d/dt < 0.5 { stopped += dt } }
            }
        }
        r.distanceM = distance
        r.speedMps = distance / span
        if distance < 1000 { r.reasons.append("distance-short") }
        if !timing { r.reasons.append("gps-timing-missing") }
        if !accuracy { r.reasons.append(input.fixes.contains(where: { $0.accuracyM == nil }) ? "gps-accuracy-missing" : "gps-accuracy") }
        if gpsGap { r.reasons.append("gps-gap") }
        if gpsSpeed { r.reasons.append("gps-speed") }
        if !timing || gpsTime / span < 0.9 { r.reasons.append("gps-coverage") }
        if gpsTime > 0 && stopped / gpsTime > 0.1 { r.reasons.append("stops") }
        if let stored = input.storedDistanceM, !stored.isFinite || stored < 0 || abs(stored-distance) > max(50,distance*0.1) { r.reasons.append("distance-mismatch") }
        let owner = input.owner ?? ""
        if owner.isEmpty { r.reasons.append("hr-owner-unknown") }
        let hr = input.heartRates
        if hr.contains(where: { $0.owner != owner }) && !owner.isEmpty { r.reasons.append("hr-owner-mismatch") }
        var valid = hr.count >= 2 && hr.count <= 100000
        var weighted = 0.0, covered = 0.0, hrGap = false
        for i in hr.indices {
            let p = hr[i]
            if !p.time.isFinite || !p.bpm.isFinite || p.time < input.start || p.time > input.end || p.bpm < 40 || p.bpm > 220 { valid = false }
            if i > 0 {
                let previous = hr[i-1], dt = p.time-previous.time
                if dt <= 0 || !dt.isFinite { valid = false }
                else if dt > 10 { hrGap = true }
                else { covered += dt; weighted += previous.bpm * dt }
            }
        }
        if !valid { r.reasons.append("hr-invalid") }
        if hrGap { r.reasons.append("hr-gap") }
        if covered < 600 || covered/span < 0.9 { r.reasons.append("hr-coverage") }
        if valid && !owner.isEmpty && !r.reasons.contains("hr-owner-mismatch") && covered > 0 {
            r.hrCoveredS = covered; r.meanHr = weighted/covered
        }
        if r.reasons.isEmpty, let mean = r.meanHr { r.metersPerBeat = distance/span * 60/mean }
        return finish()
    }
    public struct KlineEstimate: Sendable { public let litersPerMinute: Double; public let mlKgMin: Double }
    public static func kline(age: Double, weightKg: Double, sex: Int, seconds: Double, repeatSeconds: Double, fourthQuarterHr: Double, confirmed: Bool) -> KlineEstimate? {
        guard confirmed, age.isFinite, (30...69).contains(age), weightKg.isFinite, weightKg >= 30, weightKg <= 250,
              sex == 0 || sex == 1, seconds.isFinite, repeatSeconds.isFinite, seconds >= 600, seconds <= 1800,
              repeatSeconds >= seconds, repeatSeconds-seconds <= 30, fourthQuarterHr.isFinite, (40...220).contains(fourthQuarterHr) else { return nil }
        let liters = 6.9652 + 0.0091 * (weightKg / 0.45359237) - 0.0257 * age + 0.5955 * Double(sex) - 0.2240 * (seconds/60) - 0.0115 * fourthQuarterHr
        guard liters > 0 else { return nil }
        return KlineEstimate(litersPerMinute: liters, mlKgMin: liters*1000/weightKg)
    }
}
