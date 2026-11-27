import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Hours vs Needed (#today-hosted-cards)
//
// The Sleep tab surfaces "Hours vs Needed" only as a StatTile inside the Night-detail metric grid — there
// is no standalone renderer for it. This card gives that single metric its own hostable view so it can be
// surfaced in the Today tab on its own. Both the Sleep tab tile and this hosted card read the SAME
// `SleepModel.hoursVsNeeded` metric (latest / typical / series), so the number, the vs-typical caption and
// the sparkline can never diverge between the two surfaces (the parity contract). The tile presentation
// (value / caption / accent / sparkline) is a verbatim lift of the `NightDetailCard` "Hours vs Needed"
// tile, so the hosted card reads byte-identically to the Sleep-tab tile.

/// The "Hours vs Needed" card. Renders the wearer's latest hours-vs-needed percentage against their
/// personal typical from the shared [SleepModel], as a single full-width StatTile with its sparkline and
/// vs-typical caption — the same presentation the Night-detail grid uses for this metric.
struct HoursVsNeededCard: View {
    private let model: SleepModel?
    private var slept: Double?
    private var needed: Double?
    private var debt: Double?
    private var recentEffort: String?

    init(model: SleepModel) { self.model = model }

    init(slept: Double?, needed: Double?, debt: Double?, recentEffort: String?) {
        model = nil
        self.slept = slept
        self.needed = needed
        self.debt = debt
        self.recentEffort = recentEffort
    }

    var body: some View {
        if let model {
            summary(model)
        } else {
            comparison
        }
    }

    private var comparison: some View {
        let scale = max(1, max(slept ?? 0, needed ?? 0))
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Hours vs Needed").font(StrandFont.headline)
            durationRow(String(localized: "Slept"), minutes: slept, scale: scale, tint: PerformanceDesign.sleep)
            durationRow(String(localized: "Sleep need"), minutes: needed, scale: scale, tint: StrandPalette.textSecondary)
            if let debt {
                LabeledContent(String(localized: "Sleep debt"), value: duration(debt))
                    .font(StrandFont.footnote)
            }
            if let recentEffort {
                LabeledContent(String(localized: "Effort on the previous day"), value: recentEffort)
                    .font(StrandFont.footnote)
            }
        }
    }

    private func durationRow(_ title: String, minutes: Double?, scale: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            LabeledContent(title, value: minutes.map(duration) ?? "—").font(StrandFont.subhead)
            if let minutes {
                GeometryReader { geometry in
                    Capsule().fill(StrandPalette.surfaceInset)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: geometry.size.width * CGFloat(max(0, minutes) / scale))
                        }
                }
                .frame(height: NoopMetrics.space2)
                .accessibilityHidden(true)
            }
        }
    }

    private func duration(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        return String(localized: "\(rounded / 60)h \(rounded % 60)m")
    }

    private func summary(_ model: SleepModel) -> some View {
        // The metric (latest %, typical mean, history series) is computed ONCE in the model build and
        // read here — the same memoized result the Night-detail grid reads for its tile.
        let need = model.hoursVsNeeded

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Hours vs Needed", overline: "Sleep")
            // Verbatim of the NightDetailCard "Hours vs Needed" tile so the hosted value matches the
            // Sleep-tab tile exactly; stretched to the card's full width as a single-metric summary.
            StatTile(
                label: "Hours vs Needed",
                value: pctValue(need.latest),
                caption: tileCaption(latestDay: need.latestDay, latest: need.latest,
                                     typical: need.typical, suffix: "%"),
                accent: need.latest.map { StrandPalette.recoveryColor(min(100, $0)) } ?? StrandPalette.textPrimary,
                sparkline: spark(need.series),
                sparkColor: StrandPalette.restColor)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tile formatting (verbatim lift of the NightDetailCard "Hours vs Needed" tile helpers)

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
