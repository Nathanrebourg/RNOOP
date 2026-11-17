import Foundation

/// Optional, user-chosen goals, not physiological recommendations. Zero nights/days disables a goal.
/// All persisted fields are Int; canonical keys and limits mirror Kotlin exactly. Local preferences
/// are deliberately NOT part of the .noopbak whitelist.
public struct WeeklyPlanGoals: Equatable {
    public static let sleepMinutesKey = "weeklyPlanSleepMinutes"
    public static let sleepNightsKey = "weeklyPlanSleepNights"
    public static let workoutDaysKey = "weeklyPlanWorkoutDays"
    public let sleepMinutes: Int
    public let sleepNights: Int
    public let workoutDays: Int
    public init(sleepMinutes: Int, sleepNights: Int, workoutDays: Int) {
        self.sleepMinutes = min(960, max(60, sleepMinutes))
        self.sleepNights = min(7, max(0, sleepNights))
        self.workoutDays = min(7, max(0, workoutDays))
    }
}

public struct WeeklyPlanSleep: Equatable {
    public let day: String
    public let minutes: Double?
    public init(day: String, minutes: Double?) { self.day = day; self.minutes = minutes }
}

public struct WeeklyPlanDay: Equatable {
    public let day: String
    public let sleepMinutes: Double?
    /// Positive evidence only. False means no recorded completed workout; never proof of inactivity.
    public let hasRecordedWorkout: Bool
    public let isToday: Bool
    public let isFuture: Bool
}

public struct WeeklyPlanProgress: Equatable {
    public let sleepNights: Int
    public let sleepObservedNights: Int
    public let workoutDays: Int
}

/// Calendar aggregation only: no health score, sleep algorithm, or training prescription.
/// Supported input years are 1970...2099, matching the repository's Unix history horizon.
/// Input day keys must already be local civil dates. Gregorian/UTC arithmetic here prevents DST from
/// adding/removing a day; it does not reinterpret those keys as UTC observations. Sleep is attributed
/// to the existing daily row's day (normally its wake date). Workouts belong to their start date.
public enum WeeklyPlanEngine {
    public static func build(today: String, sleep: [WeeklyPlanSleep], workoutDays: [String]) -> [WeeklyPlanDay] {
        let calendar = calendar
        guard let anchor = date(today, calendar: calendar) else { return [] }
        let offset = (calendar.component(.weekday, from: anchor) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: anchor) else { return [] }
        var byDay: [String: Double] = [:]
        for row in sleep {
            guard let value = row.minutes, value.isFinite, (0...1440).contains(value),
                  row.day <= today, date(row.day, calendar: calendar) != nil else { continue }
            // Repository publishes merged daily rows. Defensive duplicate handling is order independent;
            // never add competing estimates of the same night's duration together.
            byDay[row.day] = max(byDay[row.day] ?? value, value)
        }
        let workouts = Set(workoutDays)
        return (0..<7).compactMap { index in
            guard let value = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            let key = key(value, calendar: calendar)
            let future = key > today
            return WeeklyPlanDay(day: key, sleepMinutes: future ? nil : byDay[key],
                                 hasRecordedWorkout: !future && workouts.contains(key),
                                 isToday: key == today, isFuture: future)
        }
    }

    public static func progress(rows: [WeeklyPlanDay], goals: WeeklyPlanGoals) -> WeeklyPlanProgress {
        let observed = rows.filter { !$0.isFuture }
        return WeeklyPlanProgress(
            sleepNights: observed.filter { ($0.sleepMinutes ?? -1) >= Double(goals.sleepMinutes) }.count,
            sleepObservedNights: observed.filter { $0.sleepMinutes != nil }.count,
            workoutDays: observed.filter(\.hasRecordedWorkout).count)
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(key.prefix(4)), (1970...2099).contains(year),
              let month = Int(key.dropFirst(5).prefix(2)), let day = Int(key.suffix(2)),
              let value = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              self.key(value, calendar: calendar) == key else { return nil }
        return value
    }

    private static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), c.year!, c.month!, c.day!)
    }
}
