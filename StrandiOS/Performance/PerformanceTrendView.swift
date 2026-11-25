#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

/// A date-anchored trend: missing calendar days split the line instead of being interpolated.
struct PerformanceTrendView: View {
    let initialContext: PerformanceContext
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PerformanceSnapshotModel()
    @AppStorage(UnitPrefs.systemKey) private var unitPreference = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperaturePreference = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinPreference = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortPreference = EffortScale.whoop.rawValue
    @State private var metric: String
    @State private var window: Int
    @State private var selectedDate: Date?
    @State private var dataRevision = 0
    init(context: PerformanceContext) {
        initialContext = context
        _window = State(initialValue: context.windowDays)
        _metric = State(initialValue: context.metric ?? "hrv")
    }
    private var context: PerformanceContext {
        PerformanceContext(day: initialContext.day, domain: .trend, metric: metric, windowDays: window)!
    }
    private var key: String { context.metric ?? "hrv" }
    private var descriptor: MetricDescriptor? { PerformanceFormat.metric(key) }
    private var loadID: String { context.id + "|" + repo.deviceId + "|" + String(dataRevision) + "|" + unitPreference + temperaturePreference + skinPreference + effortPreference }

    static let metricOptions = ["sleep_performance", "recovery", "strain", "hrv", "rhr", "resp_rate", "stress",
                                "sleep_total_min", "hours_vs_needed_pct", "sleep_consistency", "sleep_efficiency",
                                "steps_est", "hr_zones13_min", "hr_zones45_min", "strength_min",
                                "fitness_age", "body_age", "vitality"]
    /// WHOOP draws daily totals and scores as bars, physiology as a line.
    static let barMetrics: Set<String> = ["sleep_performance", "recovery", "strain", "sleep_total_min",
                                          "hours_vs_needed_pct", "steps_est", "hr_zones13_min", "hr_zones45_min", "strength_min"]
    private var usesBars: Bool { Self.barMetrics.contains(key) }

    private func barColor(_ value: Double) -> Color {
        switch key {
        case "recovery": return PerformanceContext.Domain.recovery.tint(score: value)
        case "strain", "steps_est", "hr_zones13_min", "hr_zones45_min", "strength_min": return PerformanceDesign.effort
        default: return PerformanceDesign.sleep
        }
    }

    /// Real readings of the equally long period just before the visible one.
    private func previousValues(_ snapshot: PerformanceSnapshot) -> [Double] {
        let end = context.shiftedDay(by: -context.windowDays)
        let start = context.shiftedDay(by: 1 - 2 * context.windowDays)
        return (snapshot.series[key] ?? []).filter { $0.day >= start && $0.day <= end && $0.value.isFinite }.map(\.value)
    }

    /// Personal typical range: mean ± one standard deviation over both periods (at least 5 real days).
    private func typicalRange(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 5 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        let sd = variance.squareRoot()
        guard mean.isFinite, sd.isFinite, sd > 0 else { return nil }
        return (mean - sd)...(mean + sd)
    }

    private struct Point: Identifiable {
        let day: String
        let date: Date
        let value: Double
        let segment: Int
        var id: String { day }
    }
    private func points(_ snapshot: PerformanceSnapshot) -> [Point] {
        var previous: String?
        var segment = 0
        return (snapshot.series[key] ?? []).compactMap { reading in
            guard context.contains(reading.day), let date = PerformanceSnapshotModel.localNoon(reading.day), reading.value.isFinite else { return nil }
            if let previous, PerformanceContext(day: previous, domain: .trend)?.shiftedDay(by: 1) != reading.day { segment += 1 }
            previous = reading.day
            return Point(day: reading.day, date: date, value: reading.value, segment: segment)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space5) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }.accessibilityLabel("Back")
                    Spacer()
                    Text("Trends").font(StrandFont.overline)
                    Spacer()
                    PerformanceCoachSymbol().hidden()
                }
                Text(PerformanceFormat.date(context.day)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).frame(maxWidth: .infinity)
                PerformancePanel {
                    Menu {
                        ForEach(Self.metricOptions, id: \.self) { option in
                            Button(PerformanceFormat.title(option)) { metric = option }
                        }
                    } label: {
                        HStack {
                            Label(PerformanceFormat.title(key), systemImage: descriptor?.icon ?? "chart.xyaxis.line").font(StrandFont.headline)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                    }
                }
                Picker("Period", selection: $window) {
                    Text("1W").tag(7)
                    Text("1M").tag(28)
                    Text("6M").tag(180)
                }.pickerStyle(.segmented)
                if let snapshot = model.snapshot, snapshot.context == context {
                    if snapshot.hadReadErrors {
                        PerformanceReadError { Task { await model.load(repo: repo, context: context) } }
                    }
                    trend(snapshot)
                } else { ProgressView("Reading your measurements…").frame(maxWidth: .infinity) }
                PerformanceFullHistoryLink(key: key)
            }
            .padding(NoopMetrics.space4)
        }
        .background(PerformanceBackground()).toolbar(.hidden, for: .navigationBar)
        .task(id: loadID) {
            router.performanceContext = context
            selectedDate = nil
            await model.load(repo: repo, context: context)
        }
        .onAppear { router.performanceContext = context }
        .onReceive(repo.performanceSnapshotCache.$revision) { dataRevision = $0 }
    }

    @ViewBuilder private func trend(_ snapshot: PerformanceSnapshot) -> some View {
        let readings = points(snapshot)
        let average = PerformanceContext.mean(readings.map { $0.value })
        let previous = previousValues(snapshot)
        let previousAverage = previous.count >= 2 ? PerformanceContext.mean(previous) : nil
        let range = typicalRange(readings.map { $0.value } + previous)
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Average").font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary)
            Text(PerformanceFormat.value(key, average)).font(StrandFont.display(PerformanceDesign.scoreSize)).minimumScaleFactor(0.6).lineLimit(1)
            if readings.count >= 2, let average, let previousAverage, previousAverage != 0 {
                let change = Int(((average - previousAverage) / abs(previousAverage) * 100).rounded())
                let changeText = (change > 0 ? "+" : "−") + "\(abs(change)) %"
                Label(change == 0 ? String(localized: "Same as the previous period")
                        : String(localized: "\(changeText) vs previous period"),
                      systemImage: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "equal")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text("Previous period average: \(PerformanceFormat.value(key, previousAverage))")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
            Text("\(readings.count) measured days").font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Text("\(context.lowerBound) – \(context.day)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        if readings.isEmpty {
            PerformancePanel { Text("No measurements in this period.").font(StrandFont.body) }
        } else {
            Chart {
                if let range, let lower = PerformanceSnapshotModel.localNoon(context.lowerBound),
                   let upper = PerformanceSnapshotModel.localNoon(context.day) {
                    RectangleMark(xStart: .value("Start", lower), xEnd: .value("End", upper),
                                  yStart: .value("Typical low", chartValue(range.lowerBound)),
                                  yEnd: .value("Typical high", chartValue(range.upperBound)))
                        .foregroundStyle(StrandPalette.textPrimary.opacity(0.08))
                }
                if let average {
                    RuleMark(y: .value("Average", chartValue(average)))
                        .foregroundStyle(StrandPalette.textSecondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(readings) { point in
                    if usesBars {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Measurement", chartValue(point.value)))
                            .foregroundStyle(barColor(point.value))
                    } else {
                        LineMark(x: .value("Day", point.date), y: .value("Measurement", chartValue(point.value)),
                                 series: .value("Recorded segment", String(point.segment)))
                        .foregroundStyle(PerformanceDesign.sleep)
                        .lineStyle(StrokeStyle(lineWidth: PerformanceDesign.chartStroke))
                        PointMark(x: .value("Day", point.date), y: .value("Measurement", chartValue(point.value)))
                            .foregroundStyle(PerformanceDesign.sleep)
                    }
                }
                if let selected = selectedPoint(readings) {
                    RuleMark(x: .value("Selected day", selected.date)).foregroundStyle(StrandPalette.textSecondary.opacity(0.5))
                }
            }
            .chartXScale(domain: PerformanceSnapshotModel.localNoon(context.lowerBound)!...PerformanceSnapshotModel.localNoon(context.day)!)
            .chartXSelection(value: $selectedDate)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: PerformanceDesign.chartHeight)
            .accessibilityLabel(PerformanceFormat.title(key))
            .accessibilityValue("\(readings.count) measured days")
            if let selected = selectedPoint(readings) {
                HStack {
                    Text(PerformanceFormat.date(selected.day))
                    Spacer()
                    Text(PerformanceFormat.value(key, selected.value)).font(StrandFont.headline)
                }.font(StrandFont.caption).foregroundStyle(PerformanceDesign.sleep)
            }
            if range != nil {
                Text("Shaded band: your typical range (average ± one standard deviation over this and the previous period).")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
            Text("Gaps represent missing measurements, not zero.").font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            PerformanceCoachLink(context: context)
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("Measurements in this period").font(StrandFont.headline)
                    ForEach(readings.reversed()) { point in
                        HStack {
                            Text(PerformanceFormat.date(point.day)).font(StrandFont.caption)
                            Spacer()
                            Text(PerformanceFormat.value(key, point.value)).font(StrandFont.subhead).monospacedDigit()
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func chartValue(_ value: Double) -> Double {
        key == "strain" ? UnitFormatter.effortValue(value, scale: PerformanceFormat.effortScale) : value
    }
    private func selectedPoint(_ points: [Point]) -> Point? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
}
#endif
