#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

extension PerformanceContext.Domain {
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .sleep: String(localized: "Sleep")
        case .recovery: String(localized: "Recovery")
        case .effort: String(localized: "Strain")
        case .health: String(localized: "Health")
        case .activities: String(localized: "Activities")
        case .trend: String(localized: "Trends")
        }
    }
    var metricKey: String {
        switch self { case .sleep: "sleep_performance"; case .recovery: "recovery"; case .effort: "strain"; default: "" }
    }
    func tint(score: Double? = nil) -> Color {
        switch self {
        case .sleep: return PerformanceDesign.sleep
        case .effort, .activities: return PerformanceDesign.effort
        case .recovery:
            guard let score else { return PerformanceDesign.recoveryHigh }
            return score >= 67 ? PerformanceDesign.recoveryHigh : score >= 34 ? PerformanceDesign.recoveryMedium : PerformanceDesign.recoveryLow
        default: return PerformanceDesign.coach
        }
    }
}

enum PerformanceFormat {
    static func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value = PerformanceContext.finite(value) else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals)).locale(AppLanguage.activeLocale))
    }
    static func duration(_ value: Double?) -> String {
        guard let value = PerformanceContext.finite(value), value >= 0 else { return "—" }
        let minutes = Int(value.rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
    static func date(_ day: String) -> String {
        guard let date = PerformanceSnapshotModel.localNoon(day) else { return day }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.activeLocale))
    }
    static func clock(_ timestamp: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }
    static var effortScale: EffortScale { UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "") }
    static func effort(_ value: Double?) -> String {
        number(value.map { UnitFormatter.effortValue($0, scale: effortScale) }, decimals: effortScale == .whoop ? 1 : 0)
    }
    static func metric(_ key: String) -> MetricDescriptor? { MetricCatalog.metric(key: key, source: Repository.whoopSource) ?? MetricCatalog.all.first { $0.key == key } }
    static func title(_ key: String) -> String {
        switch PerformanceContext.canonicalMetric(key) {
        case "sleep_performance": String(localized: "Sleep")
        case "recovery": String(localized: "Recovery")
        case "strain": String(localized: "Strain")
        case "hrv": String(localized: "Heart rate variability")
        case "rhr": String(localized: "Resting heart rate")
        case "resp_rate": String(localized: "Respiratory rate")
        case "stress": String(localized: "Stress estimate")
        default: metric(key)?.title ?? key
        }
    }
    static func value(_ key: String, _ value: Double?) -> String {
        guard let value = PerformanceContext.finite(value) else { return "—" }
        if key == "strain" { return effort(value) }
        if key.hasSuffix("_min") { return duration(value) }
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let temperature = UnitPrefs.resolveTemperature(system: system, override: UserDefaults.standard.string(forKey: UnitPrefs.temperatureKey) ?? "")
        guard let descriptor = metric(PerformanceContext.canonicalMetric(key)) else { return number(value) }
        if descriptor.unit == "kg" || descriptor.unit == "°C" {
            return descriptor.format(value, system: system, temperature: temperature, effortScale: effortScale)
        }
        let unit = descriptor.key == "resp_rate" ? String(localized: "breaths/min") : descriptor.unit == "steps" ? String(localized: "steps") : descriptor.unit
        return number(value, decimals: descriptor.decimals) + (unit.isEmpty ? "" : " " + unit)
    }
}

struct DatedPerformanceScoreRing: View {
    let domain: PerformanceContext.Domain
    let value: Double?
    var large = false
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = PerformanceDesign.scoreSize
    // Scores, including effort, arrive on the stored 0–100 axis. The display formatter
    // converts effort to 0–21; both axes therefore have the same ring fraction.
    private var fraction: Double { min(1, max(0, (PerformanceContext.finite(value) ?? 0) / 100)) }
    var body: some View {
        ZStack {
            Circle().stroke(StrandPalette.textPrimary.opacity(0.09), lineWidth: large ? PerformanceDesign.largeStroke : PerformanceDesign.smallStroke)
            if value != nil {
                Circle().trim(from: 0, to: fraction)
                    .stroke(domain.tint(score: value), style: StrokeStyle(lineWidth: large ? PerformanceDesign.largeStroke : PerformanceDesign.smallStroke, lineCap: .round))
                    .rotationEffect(.degrees(NoopMetrics.performanceRingRotation))
                    .shadow(color: domain.tint(score: value).opacity(0.3), radius: NoopMetrics.space2)
            }
            VStack(spacing: NoopMetrics.space2) {
                if large { Text(verbatim: "NROOP").font(StrandFont.overline).tracking(PerformanceDesign.labelTracking).foregroundStyle(StrandPalette.textSecondary) }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(domain == .effort ? PerformanceFormat.effort(value) : PerformanceFormat.number(value))
                        .font(StrandFont.rounded(large ? min(scoreSize, PerformanceDesign.scoreSize * 1.5) : PerformanceDesign.compactScoreSize))
                    if domain != .effort, value != nil {
                        Text(verbatim: "%").font(StrandFont.rounded(large ? PerformanceDesign.suffixSize : PerformanceDesign.compactSuffixSize))
                    }
                }.foregroundStyle(StrandPalette.textPrimary).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                if large { Text(domain.title.uppercased()).font(StrandFont.overline).tracking(PerformanceDesign.labelTracking) }
            }
        }
        .padding(large ? NoopMetrics.space2 : NoopMetrics.space1)
        .frame(maxWidth: large ? PerformanceDesign.largeRing : PerformanceDesign.smallRing)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(domain.title), \(domain == .effort ? PerformanceFormat.effort(value) : PerformanceFormat.number(value))")
    }
}

/// WHOOP's sleep bands: Optimal at 85 % and above, Sufficient from 70 %, Poor below.
enum PerformanceBand {
    case poor, sufficient, optimal
    init?(percent: Double?) {
        guard let percent, percent.isFinite else { return nil }
        self = percent >= 85 ? .optimal : percent >= 70 ? .sufficient : .poor
    }
    var title: String {
        switch self {
        case .poor: String(localized: "Poor")
        case .sufficient: String(localized: "Sufficient")
        case .optimal: String(localized: "Optimal")
        }
    }
    var color: Color {
        switch self {
        case .poor: PerformanceDesign.recoveryLow
        case .sufficient: PerformanceDesign.recoveryMedium
        case .optimal: PerformanceDesign.recoveryHigh
        }
    }
}

struct PerformanceMeasureRow: View {
    let title: String
    let value: String
    var caption: String? = nil
    var symbol = "waveform.path.ecg"
    /// Optional "30-day average" read-out under the value, with the direction of today vs that average.
    var baseline: String? = nil
    var direction = 0
    /// Optional WHOOP-style band pill (Poor / Sufficient / Optimal).
    var badge: PerformanceBand? = nil
    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: symbol).font(StrandFont.subhead).foregroundStyle(PerformanceDesign.sleep).frame(width: NoopMetrics.space6)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                if let badge {
                    Text(badge.title).font(StrandFont.overline)
                        .padding(.horizontal, NoopMetrics.space2).padding(.vertical, 2)
                        .foregroundStyle(badge.color)
                        .background(badge.color.opacity(0.15), in: Capsule())
                }
                if let caption { Text(caption).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary).monospacedDigit().minimumScaleFactor(0.7)
                if let baseline {
                    HStack(spacing: 2) {
                        if direction != 0 {
                            Image(systemName: direction > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        }
                        Text(baseline).monospacedDigit()
                    }
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Image(systemName: "chevron.right").font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }.padding(.vertical, NoopMetrics.space3).contentShape(Rectangle())
    }
}

/// WHOOP-style activity card: coloured score/duration tile, sport icon, name and times.
struct PerformanceActivityCard: View {
    let badge: String
    let badgeColor: Color
    let symbol: String
    let title: String
    let times: String
    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            Text(badge).font(StrandFont.headline).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(.white)
                .frame(width: 64, height: 44)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Image(systemName: symbol).font(StrandFont.headline).foregroundStyle(badgeColor)
                .frame(width: NoopMetrics.space6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(times).font(StrandFont.footnote).monospacedDigit().foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space2)
            Image(systemName: "chevron.right").font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(NoopMetrics.space3)
        .background(PerformanceDesign.panelTop, in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct PerformanceCoachSymbol: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(verbatim: "N").font(StrandFont.title2).italic()
            Image(systemName: "sparkle").font(StrandFont.overline)
        }
        .foregroundStyle(PerformanceDesign.coach)
        .frame(width: PerformanceDesign.coachSymbolDiameter, height: PerformanceDesign.coachSymbolDiameter)
        .overlay(Circle().strokeBorder(PerformanceDesign.coach.opacity(0.7), lineWidth: NoopMetrics.hairlineWidth))
        .accessibilityHidden(true)
    }
}

struct PerformanceCoachLink: View {
    let context: PerformanceContext
    @EnvironmentObject private var router: NavRouter
    @AppStorage("noop.coachEnabled") private var enabled = true
    var body: some View {
        if enabled {
            Button { router.openPerformanceCoach(context) } label: {
                HStack(spacing: NoopMetrics.space3) {
                    PerformanceCoachSymbol()
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text(String(localized: "Discuss with Coach")).font(StrandFont.subhead)
                        Text(PerformanceFormat.date(context.day)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(StrandFont.footnote)
                }
                .foregroundStyle(StrandPalette.textPrimary).padding(NoopMetrics.space4)
                .background(PerformanceDesign.coach.opacity(0.06), in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
                .overlay(RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius).strokeBorder(PerformanceDesign.coach.opacity(0.3), lineWidth: NoopMetrics.hairlineWidth))
            }.buttonStyle(.plain)
        }
    }
}
/// The existing detailed explorer provides the complete history beyond the selected day.
struct PerformanceFullHistoryLink: View {
    let key: String
    var body: some View {
        NavigationLink(value: TabRoute.metricSourced(key: key, source: Repository.whoopSource)) {
            PerformancePanel {
                PerformanceMeasureRow(title: String(localized: "View full history"), value: "",
                                      caption: String(localized: "Charts, history and comparisons"),
                                      symbol: "chart.xyaxis.line")
            }
        }.buttonStyle(.plain)
    }
}

struct PerformanceReadError: View {
    let retry: () -> Void
    var body: some View {
        PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label("Some measurements could not be read", systemImage: "exclamationmark.circle")
                    .font(StrandFont.headline)
                Button("Try again", action: retry).font(StrandFont.subhead)
            }
        }
    }
}

struct PerformanceLegacyContextReset: ViewModifier {
    @EnvironmentObject private var router: NavRouter
    func body(content: Content) -> some View {
        content.onAppear { router.performanceContext = nil }
    }
}
#endif
