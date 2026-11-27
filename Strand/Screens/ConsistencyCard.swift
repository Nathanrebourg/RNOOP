import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Consistency (#today-hosted-cards)
//
// The Sleep tab surfaces "Consistency" only as a StatTile inside the Night-detail metric grid — there is
// no standalone renderer for it. This card gives that single metric its own hostable view so it can be
// surfaced in the Today tab on its own. Both the Sleep tab tile and this hosted card read the SAME
// `SleepModel.consistency` metric (latest / typical / series) — the bedtime-onset-spread score that also
// honours the imported-consistency preference and is byte-identical to Android's `consistencySeries` — so
// the number, the vs-typical caption and the sparkline can never diverge between the two surfaces (the
// parity contract). The tile presentation (value / caption / accent / sparkline) is a verbatim lift of the
// `NightDetailCard` "Consistency" tile, so the hosted card reads byte-identically to the Sleep-tab tile.

struct SleepScheduleDay: Identifiable {
    let date: Date
    let onset: Int?
    let wake: Int?
    var id: Date { date }
}

/// The "Consistency" card. Renders the wearer's latest sleep-consistency percentage against their personal
/// typical from the shared [SleepModel], as a single full-width StatTile with its sparkline and vs-typical
/// caption — the same presentation the Night-detail grid uses for this metric.
struct ConsistencyCard: View {
    private let model: SleepModel?
    private var week: [SleepScheduleDay] = []
    private var score: Double?

    init(model: SleepModel) { self.model = model }

    init(week: [SleepScheduleDay], score: Double?) {
        model = nil
        self.week = week
        self.score = score
    }

    var body: some View {
        if let model {
            summary(model)
        } else {
            schedule
        }
    }

    private var schedule: some View {
        Grid(alignment: .leading, horizontalSpacing: NoopMetrics.space3, verticalSpacing: NoopMetrics.space2) {
            GridRow {
                HStack {
                    Text("Consistency").font(StrandFont.headline)
                    Spacer(minLength: 0)
                    if let score {
                        Text((score / 100).formatted(.percent.precision(.fractionLength(0))))
                            .font(StrandFont.headline)
                    }
                }
                .gridCellColumns(3)
            }
            GridRow {
                Text("Day")
                Text("Bedtime")
                Text("Wake time")
            }
            .foregroundStyle(StrandPalette.textSecondary)
            ForEach(week) { day in
                GridRow {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.activeLocale)))
                    Text(clock(day.onset))
                    Text(clock(day.wake))
                }
                .monospacedDigit()
            }
        }
        .font(StrandFont.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clock(_ timestamp: Int?) -> String {
        guard let timestamp else { return "—" }
        return AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func summary(_ model: SleepModel) -> some View {
        // The metric (latest %, typical mean, history series) is computed ONCE in the model build and
        // read here — the same memoized result the Night-detail grid reads for its tile.
        let cons = model.consistency

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Consistency", overline: "Sleep")
            // Verbatim of the NightDetailCard "Consistency" tile so the hosted value matches the Sleep-tab
            // tile exactly; stretched to the card's full width as a single-metric summary.
            StatTile(
                label: "Consistency",
                value: pctValue(cons.latest),
                caption: tileCaption(latestDay: cons.latestDay, latest: cons.latest,
                                     typical: cons.typical, suffix: "%"),
                accent: cons.latest.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textPrimary,
                sparkline: spark(cons.series),
                sparkColor: StrandPalette.metricCyan)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tile formatting (verbatim lift of the NightDetailCard "Consistency" tile helpers)

    private func pctValue(_ v: Double?) -> String {
        v.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    /// #1946: a carried prior-day value is stamped "Carried · <date>" instead of "vs typical".
    private func tileCaption(latestDay: String?, latest: Double?, typical: Double?,
                             suffix: String, decimals: Int = 0) -> String {
        if let carried = SleepModel.carriedMetricCaption(latestDay: latestDay, latest: latest) {
            return carried
        }
        return vsTypical(latest, typical, suffix: suffix, decimals: decimals)
    }

    /// "+12% vs typical" — the latest-vs-mean caption the metric tile carries.
    private func vsTypical(_ latest: Double?, _ typical: Double?, suffix: String, decimals: Int = 0) -> String {
        guard let latest, let typical, typical != 0 else { return String(localized: "vs typical - ") }
        let diff = latest - typical
        let sign = diff >= 0 ? "+" : "−"
        let mag = abs(diff)
        let num = decimals == 0 ? "\(Int(mag.rounded()))" : String(format: "%.\(decimals)f", mag)
        return String(localized: "\(sign)\(num)\(suffix) vs typical")
    }

    /// A sparkline needs at least two points; otherwise return nil so the tile stays clean.
    private func spark(_ series: [Double]) -> [Double]? {
        let tail = Array(series.suffix(30))
        return tail.count > 1 ? tail : nil
    }
}
