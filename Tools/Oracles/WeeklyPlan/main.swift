import Foundation
// Compile this file WITH the production WeeklyPlan.swift (no package dependencies).
let sleep: [WeeklyPlanSleep] = [
    .init(day: "2026-11-09", minutes: 420), .init(day: "2026-11-09", minutes: 480),
    .init(day: "2026-11-10", minutes: .nan), .init(day: "2026-11-10", minutes: -1),
    .init(day: "2026-11-11", minutes: 0), .init(day: "2026-11-12", minutes: 9999),
    .init(day: "2026-11-13", minutes: 600)]
let dates = ["2026-11-12", "2026-11-15", "2026-11-16", "2026-01-01", "2024-03-03", "2026-03-29", "2026-10-25", "2026-02-29", "2026-2-03", "0000-01-01", "２０２６-01-01", "0001-01-01", "1500-02-28", "2100-01-01", "9999-12-31"]
for date in dates {
    let rows = WeeklyPlanEngine.build(today: date, sleep: sleep, workoutDays: ["2026-11-09", "2026-11-09", "2026-11-12", "2026-11-13"])
    let goals = WeeklyPlanGoals(sleepMinutes: 480, sleepNights: 2, workoutDays: 3)
    let p = WeeklyPlanEngine.progress(rows: rows, goals: goals)
    let trace = rows.map { "\($0.day):\($0.sleepMinutes.map { String(Int($0)) } ?? "?"):\($0.hasRecordedWorkout ? 1 : 0):\($0.isToday ? 1 : 0):\($0.isFuture ? 1 : 0)" }.joined(separator: ";")
    print("\(date)|\(trace)|\(p.sleepNights),\(p.sleepObservedNights),\(p.workoutDays)")
}
for triple in [(Int.min, -8, -2), (Int.max, 90, 80), (480, 0, 0), (421, 2, 3)] {
    let g = WeeklyPlanGoals(sleepMinutes: triple.0, sleepNights: triple.1, workoutDays: triple.2)
    print("goals|\(g.sleepMinutes),\(g.sleepNights),\(g.workoutDays)")
}
