import Foundation
import StrandAnalytics
import WhoopStore

/// Thin bridge over Repository's already-merged daily cache and its canonical workout read.
/// Uses calendar dates at midnight, intentionally independent of Today's 04:00 presentation rollover.
enum WeeklyPlanSource {
    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func rows(days: [DailyMetric], workouts: [WorkoutRow], now: Date,
                     timeZone: TimeZone = .current) -> [WeeklyPlanDay] {
        let formatter = formatter(timeZone: timeZone)
        let today = formatter.string(from: now)
        let completed = workouts.filter {
            $0.startTs >= 0 && $0.endTs > $0.startTs && Double($0.endTs) <= now.timeIntervalSince1970
        }
        return WeeklyPlanEngine.build(today: today,
            sleep: days.map { WeeklyPlanSleep(day: $0.day, minutes: $0.totalSleepMin) },
            workoutDays: completed.map { formatter.string(from: Date(timeIntervalSince1970: Double($0.startTs))) })
    }
}
