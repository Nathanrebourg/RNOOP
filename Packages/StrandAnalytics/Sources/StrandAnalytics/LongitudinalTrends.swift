import Foundation

/// Descriptive daily arithmetic only. No health prediction, age estimate or confidence score.
/// Callers supply calendar-day ages: 0 is the incomplete current day, 1 is yesterday.
public enum LongitudinalTrends {
    public struct Sample: Equatable, Sendable {
        public let dayAge: Int
        public let value: Double?
        public init(dayAge: Int, value: Double?) { self.dayAge = dayAge; self.value = value }
    }

    public struct Window: Equatable, Sendable {
        public let count: Int
        public let calendarDays: Int
        public let mean: Double?
        public var coverage: Double { Double(count) / Double(calendarDays) }
    }

    public enum InsufficientReason: String, Sendable {
        case recentWindowTooSparse, priorWindowTooSparse, bothWindowsTooSparse
    }

    public struct Summary: Equatable, Sendable {
        public let recent30: Window
        public let prior150: Window
        public let context180: Window
        /// Recent mean minus prior mean, in the original unit. No direction is labelled healthy.
        public let delta: Double?
        public let insufficientReason: InsufficientReason?
        public let conflictingDays: Int
    }

    /// One equal-weight value per day. Identical duplicates collapse; conflicting valid values
    /// exclude that day entirely. Missing / nonfinite / out-of-bounds values never become zero.
    /// A comparison needs two distinct measured days in EACH window; coverage remains visible.
    public static func summarize(_ samples: [Sample], bounds: ClosedRange<Double>? = nil) -> Summary {
        var values: [Int: Double] = [:]
        var conflicts = Set<Int>()
        for sample in samples {
            guard (1...180).contains(sample.dayAge), let v = sample.value, v.isFinite,
                  bounds?.contains(v) ?? true else { continue }
            if let previous = values[sample.dayAge], previous != v { conflicts.insert(sample.dayAge) }
            else { values[sample.dayAge] = v }
        }
        let days = values.keys.sorted().filter { !conflicts.contains($0) }
        func window(_ range: ClosedRange<Int>) -> Window {
            let selected = days.filter { range.contains($0) }.compactMap { values[$0] }
            let mean = selected.isEmpty ? nil : selected.reduce(0.0) { $0 + $1 / Double(selected.count) }
            return Window(count: selected.count, calendarDays: range.count, mean: mean)
        }
        let recent = window(1...30), prior = window(31...180), context = window(1...180)
        let reason: InsufficientReason?
        if recent.count < 2 && prior.count < 2 { reason = .bothWindowsTooSparse }
        else if recent.count < 2 { reason = .recentWindowTooSparse }
        else if prior.count < 2 { reason = .priorWindowTooSparse }
        else { reason = nil }
        let delta: Double?
        if reason == nil, let a = recent.mean, let b = prior.mean { delta = a - b }
        else { delta = nil }
        return Summary(recent30: recent, prior150: prior, context180: context,
                       delta: delta, insufficientReason: reason, conflictingDays: conflicts.count)
    }

    /// Strict ISO day key interpreted in the caller's calendar/time zone. Calendar components,
    /// rather than elapsed seconds, preserve yesterday across 23-hour and 25-hour DST days.
    public static func dayAge(day: String, asOf: Date, calendar: Calendar) -> Int? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              day.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let number = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: number)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == number else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: asOf)).day
    }
}
