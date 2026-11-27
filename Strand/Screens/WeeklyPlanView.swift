import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// User-chosen local goals. Repository supplies merged daily sleep and canonical deduplicated workouts.
/// No notifications, accounts, medical recommendations, or inferred zero-activity days.
struct WeeklyPlanView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(WeeklyPlanGoals.sleepMinutesKey) private var sleepMinutes = 480
    @AppStorage(WeeklyPlanGoals.sleepNightsKey) private var sleepNights = 0
    @AppStorage(WeeklyPlanGoals.workoutDaysKey) private var workoutDays = 0
    @AppStorage(NroopPlanGoals.dailyStepsKey) private var dailySteps = 0
    @AppStorage(NroopPlanGoals.stepsDaysKey) private var stepsDays = 0
    @AppStorage(NroopPlanGoals.strengthMinutesKey) private var strengthMinutes = 0
    @State private var workouts: [WorkoutRow] = []
    @State private var loadedKey: String?

    private var goals: WeeklyPlanGoals {
        WeeklyPlanGoals(sleepMinutes: sleepMinutes, sleepNights: sleepNights, workoutDays: workoutDays)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let dayKey = WeeklyPlanSource.dayKey(context.date)
            let loadKey = "\(repo.deviceId)|\(repo.refreshSeq)|\(dayKey)|\(TimeZone.current.identifier)"
            let ready = loadedKey == loadKey
            let rows = WeeklyPlanSource.rows(days: repo.days, workouts: ready ? workouts : [], now: context.date)
            ScreenScaffold(title: "Weekly plan", subtitle: "Your goals, using only recorded data.") {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    weekHeader(rows)
                    goalsCard
                    if repo.loaded {
                        progressCard(rows, workoutsReady: ready)
                        daysCard(rows, workoutsReady: ready)
                    } else {
                        Text("Loading your history…")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text("Sleep uses the daily record's date. Completed workouts count on their local start date. Missing data never means no activity.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: loadKey) {
                loadedKey = nil
                let values = await repo.workoutRows(days: 8)
                guard !Task.isCancelled else { return }
                workouts = values
                loadedKey = loadKey
            }
        }
    }

    private func weekHeader(_ rows: [WeeklyPlanDay]) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Monday–Sunday · local dates")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            if let first = rows.first, let last = rows.last {
                Text(verbatim: "\(first.day) – \(last.day)")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Text("Today is provisional. Imported or newly synced records can update this week.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var goalsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Choose your goals").font(StrandFont.headline)
                Text("Set a nights or workout-days goal above zero to track it. These are your own targets, not recommendations.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                Stepper(value: clamped($sleepMinutes, range: 60...960), in: 60...960, step: 15) {
                    Text("Sleep duration: \(goals.sleepMinutes) min").font(StrandFont.bodyNumber)
                }
                Stepper(value: clamped($sleepNights, range: 0...7), in: 0...7) {
                    Text("Sleep nights goal: \(goals.sleepNights)").font(StrandFont.bodyNumber)
                }
                Stepper(value: clamped($workoutDays, range: 0...7), in: 0...7) {
                    Text("Workout days goal: \(goals.workoutDays)").font(StrandFont.bodyNumber)
                }
                Stepper(value: clamped($dailySteps, range: 0...40_000), in: 0...40_000, step: 500) {
                    Text(dailySteps == 0 ? String(localized: "Daily steps goal: off") : String(localized: "Daily steps goal: \(dailySteps)"))
                        .font(StrandFont.bodyNumber)
                }
                Stepper(value: clamped($stepsDays, range: 0...7), in: 0...7) {
                    Text("Days at the steps goal: \(stepsDays)").font(StrandFont.bodyNumber)
                }
                Stepper(value: clamped($strengthMinutes, range: 0...900), in: 0...900, step: 15) {
                    Text(strengthMinutes == 0 ? String(localized: "Weekly strength goal: off") : String(localized: "Weekly strength goal: \(strengthMinutes) min"))
                        .font(StrandFont.bodyNumber)
                }
                Text("Goals stay on this device and are not included in backups.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func progressCard(_ rows: [WeeklyPlanDay], workoutsReady: Bool) -> some View {
        let progress = WeeklyPlanEngine.progress(rows: rows, goals: goals)
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Recorded progress").font(StrandFont.headline)
                if goals.sleepNights > 0 {
                    Text("Sleep nights at your duration: \(progress.sleepNights) / \(goals.sleepNights)")
                        .font(StrandFont.bodyNumber)
                    ProgressView(value: Double(min(progress.sleepNights, goals.sleepNights)), total: Double(goals.sleepNights))
                        .tint(StrandPalette.accent)
                    Text("Nights with a sleep record: \(progress.sleepObservedNights)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("Sleep goal is off").font(StrandFont.subhead)
                }
                if goals.workoutDays > 0 {
                    if workoutsReady {
                        Text("Days with a recorded workout: \(progress.workoutDays) / \(goals.workoutDays)")
                            .font(StrandFont.bodyNumber)
                        ProgressView(value: Double(min(progress.workoutDays, goals.workoutDays)), total: Double(goals.workoutDays))
                            .tint(StrandPalette.accent)
                    } else {
                        Text("Loading recorded workouts…").font(StrandFont.subhead)
                    }
                } else {
                    Text("Workout goal is off").font(StrandFont.subhead)
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func daysCard(_ rows: [WeeklyPlanDay], workoutsReady: Bool) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("This week's records").font(StrandFont.headline)
                ForEach(rows, id: \.day) { row in
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text(verbatim: row.day).font(StrandFont.bodyNumber)
                            if row.isToday {
                                Text("Today · provisional").font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                        if row.isFuture {
                            Text("Upcoming").font(StrandFont.subhead)
                        } else {
                            if let minutes = row.sleepMinutes {
                                Text("Recorded sleep: \(Int(minutes)) min").font(StrandFont.bodyNumber)
                            } else {
                                Text("No sleep record").font(StrandFont.subhead)
                            }
                            if !workoutsReady {
                                Text("Loading recorded workouts…").font(StrandFont.subhead)
                            } else if row.hasRecordedWorkout {
                                Text("Completed workout recorded").font(StrandFont.subhead)
                            } else {
                                Text("No completed workout recorded").font(StrandFont.subhead)
                            }
                        }
                    }
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityElement(children: .combine)
                    if row.day != rows.last?.day { Divider().overlay(StrandPalette.hairline) }
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func clamped(_ storage: Binding<Int>, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, storage.wrappedValue)) },
                set: { storage.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
    }
}
