#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Hosts the same opt-in Sleep, Stress and Trends cards as the classic dashboard.
struct PerformanceHostedCards: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortPreference = EffortScale.whoop.rawValue
    let rawSelection: String
    let day: String
    let revision: Int
    let stressTimeline: [DaytimeStress.HourPoint]
    let stressActivityMaskedHours: Int
    let onCustomize: () -> Void
    @State private var sleepModel: SleepModel?
    @State private var sleepLoading = false

    private var cards: [HostedCard] { HostedCardPrefs.decodeEnabled(rawSelection) }
    private var needsSleepModel: Bool {
        cards.contains { card in
            switch card {
            case .stagesVsTypical, .nightDetail, .sleepDebt, .stages, .hoursVsNeeded, .consistency: true
            default: false
            }
        }
    }
    private var loadID: String { "\(repo.deviceId)|\(revision)|\(day)|\(rawSelection)" }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack {
                Text("Added Cards").font(StrandFont.headline)
                Spacer()
                Button("Customize", action: onCustomize).font(StrandFont.caption)
            }
            ForEach(cards) { card in
                if let route = card.route {
                    NavigationLink(value: route) { hostedCard(card) }.buttonStyle(.plain)
                } else {
                    hostedCard(card)
                }
            }
        }
        .task(id: loadID) { await loadSleep() }
    }

    @ViewBuilder private func hostedCard(_ card: HostedCard) -> some View {
        switch card {
        case .sleepMarks:
            SleepMarkCard()
        case .asleepDuration:
            AsleepDurationCard(data: AsleepDurationData.build(days: repo.days.filter { $0.day <= day }))
        case .trendHRV, .trendRestingHR, .trendEffort:
            HostedTrendCard(card: card, days: repo.days.filter { $0.day <= day },
                            effortScale: UnitPrefs.resolveEffortScale(effortPreference))
        case .stressToday:
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("Stress through the day").font(StrandFont.headline)
                    if stressTimeline.contains(where: { $0.level != nil }) {
                        DaytimeLoadLine(hours: stressTimeline)
                    } else {
                        Text("No hourly stress measurements available.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let caption = stressActivityMaskedHoursCaption(stressActivityMaskedHours) {
                        Text(caption).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        case .stagesVsTypical, .nightDetail, .sleepDebt, .stages, .hoursVsNeeded, .consistency:
            if let model = sleepModel {
                switch card {
                case .stagesVsTypical: StagesVsTypicalCard(model: model)
                case .nightDetail: NightDetailCard(model: model)
                case .sleepDebt: SleepDebtLedgerCard(model: model)
                case .stages: StagesCard(model: model)
                case .hoursVsNeeded: HoursVsNeededCard(model: model)
                case .consistency: ConsistencyCard(model: model)
                default: EmptyView()
                }
            } else {
                PerformancePanel {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text(card.title).font(StrandFont.headline)
                        if sleepLoading { ProgressView() }
                        else { Text("Not enough nights yet.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary) }
                    }
                }
            }
        }
    }

    private func loadSleep() async {
        sleepModel = nil
        guard needsSleepModel else { sleepLoading = false; return }
        sleepLoading = true
        let sessions = await repo.allSleepSessions().filter {
            Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) <= day
        }
        let habitual = await repo.habitualMidsleepSec()
        let motion = await repo.sessionMotions(sessions: sessions)
        guard !Task.isCancelled else { return }
        sleepModel = SleepModel.build(SleepModelInputs(
            days: repo.days.filter { $0.day <= day },
            sleeps: repo.sleeps.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) <= day },
            allSessions: sessions,
            importedSleep: repo.importedSleep.filter { $0.key <= day },
            habitualMidsleepSec: habitual,
            motionByStart: motion))
        sleepLoading = false
    }
}
#endif
