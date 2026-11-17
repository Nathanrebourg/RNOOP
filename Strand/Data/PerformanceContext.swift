import Foundation

enum MetricReadOrigin: Equatable, Sendable { case series, daily, unknown }

/// A presentation-only date anchor. Canonical day keys compare independently of the device time zone.
struct PerformanceContext: Hashable, Identifiable {
    enum Domain: String, CaseIterable, Hashable {
        case today, sleep, recovery, effort, health, activities, trend
    }

    let day: String
    let domain: Domain
    let metric: String?
    let windowDays: Int

    init?(day: String, domain: Domain, metric: String? = nil, windowDays: Int = 7) {
        guard Self.date(day) != nil, (1...400).contains(windowDays) else { return nil }
        self.day = day
        self.domain = domain
        self.metric = metric.map(Self.canonicalMetric)
        self.windowDays = windowDays
    }

    static func canonicalMetric(_ key: String) -> String {
        switch key { case "resp": "resp_rate"; case "skin": "skin_temp"; default: key }
    }

    var id: String { [day, domain.rawValue, metric ?? "", String(windowDays)].joined(separator: "|") }
    var lowerBound: String { shiftedDay(by: 1 - windowDays) }

    func contains(_ candidate: String) -> Bool {
        candidate >= lowerBound && candidate <= day && Self.date(candidate) != nil
    }

    func shiftedDay(by offset: Int) -> String {
        guard let start = Self.date(day), let shifted = Self.calendar.date(byAdding: .day, value: offset, to: start) else { return day }
        return Self.formatter().string(from: shifted)
    }

    /// A screen context does not grant consent. Callers must pass the current consent at send time.
    func coachEnvelope(measurements: String, dataConsent: Bool) -> String {
        let heading = "SELECTED SCREEN: \(domain.rawValue); selected day: \(day); metric: \(metric ?? domain.rawValue); window: \(lowerBound)...\(day)."
        let instructions = "Discuss this selected historical context, not today's measurements. Missing values mean unavailable, not zero. Do not infer unavailable contributions or clinical conclusions."
        return [heading, instructions, dataConsent ? measurements : "Wearable measurements withheld: data consent is off."].joined(separator: "\n\n")
    }

    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Imported metric-series values are percentages; WHOOP daily columns normally hold fractions.
    static func sleepEfficiencyPercent(_ raw: Double?, origin: MetricReadOrigin = .daily,
                                       source: String? = nil) -> Double? {
        guard let raw = finite(raw), (0...100).contains(raw) else { return nil }
        let percentDailySources = ["xiaomi-band", "oura-import", "fitbit-import", "garmin-import"]
        if origin == .series || (source.map { percentDailySources.contains($0) } ?? false) { return raw }
        return raw <= 1 ? raw * 100 : raw
    }

    static func mean(_ values: [Double?]) -> Double? {
        let observed = values.compactMap(finite)
        guard !observed.isEmpty else { return nil }
        return finite(observed.reduce(0, +) / Double(observed.count))
    }

    static func dayKey(_ date: Date) -> String { formatter().string(from: date) }

    static func date(_ key: String) -> Date? {
        guard key.count == 10 else { return nil }
        let parser = formatter()
        guard let date = parser.date(from: key), parser.string(from: date) == key else { return nil }
        return date
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private static func formatter() -> DateFormatter {
        let value = DateFormatter()
        value.calendar = calendar
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = calendar.timeZone
        value.dateFormat = "yyyy-MM-dd"
        value.isLenient = false
        return value
    }
}
