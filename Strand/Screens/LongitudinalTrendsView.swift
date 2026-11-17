import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Full-history adapter, deliberately separate from repo.days (the recent home-screen cache).
enum LongitudinalTrendsData {
    enum Metric: String, CaseIterable, Identifiable {
        case restingHR, hrv, sleepHours, steps
        var id: String { rawValue }
        var title: String {
            switch self {
            case .restingHR: return String(localized: "Resting heart rate")
            case .hrv: return String(localized: "Heart rate variability")
            case .sleepHours: return String(localized: "Sleep duration")
            case .steps: return String(localized: "Steps / motion estimate")
            }
        }
        var unit: String {
            switch self {
            case .restingHR: return String(localized: "bpm")
            case .hrv: return String(localized: "ms")
            case .sleepHours: return String(localized: "h")
            case .steps: return String(localized: "steps / ticks")
            }
        }
        var bounds: ClosedRange<Double> {
            switch self {
            case .restingHR: return 20...250
            case .hrv: return 0...1000
            case .sleepHours: return 0...24
            case .steps: return 0...1_000_000
            }
        }
        func value(_ row: DailyMetric) -> Double? {
            switch self {
            case .restingHR: return row.restingHr.map(Double.init)
            case .hrv: return row.avgHrv
            case .sleepHours: return row.totalSleepMin.map { $0 / 60 }
            case .steps: return row.steps.map(Double.init)
            }
        }
    }

    struct Row: Identifiable {
        let metric: Metric
        let summary: LongitudinalTrends.Summary
        var id: Metric { metric }
    }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func window(asOf: Date, calendar: Calendar) -> (from: String, to: String)? {
        let today = calendar.startOfDay(for: asOf)
        guard let start = calendar.date(byAdding: .day, value: -180, to: today),
              let end = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        return (dayKey(start, calendar: calendar), dayKey(end, calendar: calendar))
    }

    static func rows(days: [DailyMetric], asOf: Date, calendar: Calendar) -> [Row] {
        let aged = days.compactMap { day -> (DailyMetric, Int)? in
            guard let age = LongitudinalTrends.dayAge(day: day.day, asOf: asOf, calendar: calendar) else { return nil }
            return (day, age)
        }
        return Metric.allCases.map { metric in
            Row(metric: metric, summary: LongitudinalTrends.summarize(
                aged.map { .init(dayAge: $0.1, value: metric.value($0.0)) }, bounds: metric.bounds))
        }
    }
}

/// Local descriptive contributor trends; no biological-age or pace-of-aging estimate.
struct LongitudinalTrendsView: View {
    @ObservedObject var repo: Repository
    @State private var rows: [LongitudinalTrendsData.Row] = []
    @State private var loading = true

    private struct LoadKey: Equatable {
        let revision: Int
        let owner: String
        let today: String
        let zone: String
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let calendar = LongitudinalTrendsData.calendar()
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                            Text("Your last 180 completed days").font(StrandFont.title2)
                            Text("The last 30 completed calendar days are compared with the previous 150 days. Today and future days are excluded.")
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                            Text("Descriptive averages of your recorded data. These are not an age estimate, diagnosis or prediction.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(rows) { row in metricCard(row) }
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                            Text("Data sources and limits").font(StrandFont.headline)
                            Text("Uses NOOP’s merged daily history: imported strap values, on-device calculations and activity-file steps, with the same precedence as the dashboard. Each daily value has no individual source label. Changes in source or calibration can affect these averages.")
                            Text("Steps may include strap motion ticks or imported step counts. WHOOP 5.0 motion ticks are not a validated step count; a scale of 1 does not establish calibration. Changes in source or scale can affect this comparison.")
                            Text("Missing and invalid readings are excluded, never replaced with zero. Identical same-day readings count once; conflicting valid readings exclude that day. Coverage is measured days divided by calendar days, not statistical confidence.")
                        }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }.padding(NoopMetrics.screenPadding)
            }
            .task(id: LoadKey(revision: repo.refreshSeq, owner: repo.deviceId,
                              today: LongitudinalTrendsData.dayKey(timeline.date, calendar: calendar),
                              zone: calendar.timeZone.identifier)) {
                await load(asOf: timeline.date, calendar: calendar)
            }
        }
        .background(StrandPalette.surfaceBase)
        .foregroundStyle(StrandPalette.textPrimary)
        .navigationTitle(String(localized: "Long-term trends"))
    }

    private func number(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "—" }
        let formatted = abs(value).formatted(.number.precision(.fractionLength(1)))
        return (value < 0 ? "−" : signed && value > 0 ? "+" : "") + formatted
    }

    private func metricCard(_ row: LongitudinalTrendsData.Row) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text(row.metric.title).font(StrandFont.headline)
                windowLine(String(localized: "Last 30 days"), row.summary.recent30, unit: row.metric.unit)
                windowLine(String(localized: "Previous 150 days"), row.summary.prior150, unit: row.metric.unit)
                windowLine(String(localized: "Full 180-day context"), row.summary.context180, unit: row.metric.unit)
                Divider().overlay(StrandPalette.hairline)
                if let delta = row.summary.delta {
                    HStack {
                        Text("Change in daily mean")
                        Spacer()
                        Text(verbatim: "\(number(delta, signed: true)) \(row.metric.unit)")
                    }.font(StrandFont.bodyNumber)
                } else {
                    Text(reason(row.summary.insufficientReason)).font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if row.summary.conflictingDays > 0 {
                    Text("\(row.summary.conflictingDays) conflicting days excluded")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func windowLine(_ title: String, _ window: LongitudinalTrends.Window, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.gap) {
            VStack(alignment: .leading) {
                Text(title).font(StrandFont.subhead)
                Text("\(window.count) of \(window.calendarDays) days measured")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Text(verbatim: "\(number(window.mean)) \(unit)").font(StrandFont.bodyNumber)
                .multilineTextAlignment(.trailing)
        }
    }

    private func reason(_ reason: LongitudinalTrends.InsufficientReason?) -> String {
        switch reason {
        case .recentWindowTooSparse: return String(localized: "Comparison needs at least 2 measured days in the last 30 days.")
        case .priorWindowTooSparse: return String(localized: "Comparison needs at least 2 measured days in the previous 150 days.")
        case .bothWindowsTooSparse, .none: return String(localized: "Comparison needs at least 2 measured days in each period. Available averages are shown above.")
        }
    }

    @MainActor private func load(asOf: Date, calendar: Calendar) async {
        guard let window = LongitudinalTrendsData.window(asOf: asOf, calendar: calendar) else { return }
        loading = true
        rows = []
        let owner = repo.deviceId
        let days = await repo.mergedHistoryDays(fromDay: window.from, toDay: window.to, calendar: calendar)
        guard !Task.isCancelled, repo.deviceId == owner else { return }
        rows = LongitudinalTrendsData.rows(days: days, asOf: asOf, calendar: calendar)
        loading = false
    }
}
