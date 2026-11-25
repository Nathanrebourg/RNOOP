#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Native daily and pillar pages. No fixture values or score calculations live in this view.
struct PerformanceExperienceView: View {
    let initialContext: PerformanceContext
    var isRoot = false
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = PerformanceSnapshotModel()
    @AppStorage(UnitPrefs.systemKey) private var unitPreference = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperaturePreference = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinPreference = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortPreference = EffortScale.whoop.rawValue
    @State private var day: String
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var dataRevision = 0
    @State private var showDashboardEditor = false
    @State private var dashboardEditorDestination: TodayCustomizationDestination = .yourCards
    @State private var showCoachLauncher = false
    @State private var hydrationDisplay: String?
    @State private var showManualSleep = false
    @State private var editingSleep: SleepEditSelection?
    @State private var nightHeartRate: [HRBucket] = []
    @State private var showManualWorkout = false
    @State private var planWorkouts: [WorkoutRow] = []
    @State private var planReady = false
    @State private var stressTimeline: [DaytimeStress.HourPoint] = []
    @State private var stressActivityMaskedHours = 0
    @State private var stressLoaded = false
    /// Today's in-progress Effort, scored from the strap HR since the day began (nil below the scorer's minimum).
    @State private var liveEffort: Double?
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @AppStorage(WeeklyPlanGoals.sleepMinutesKey) private var planSleepMinutes = 480
    @AppStorage(WeeklyPlanGoals.sleepNightsKey) private var planSleepNights = 0
    @AppStorage(WeeklyPlanGoals.workoutDaysKey) private var planWorkoutDays = 0
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) private var hostedCardsRaw = ""
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14

    init(context: PerformanceContext, isRoot: Bool = false) {
        self.initialContext = context
        self.isRoot = isRoot
        _day = State(initialValue: context.day)
    }
    init(domain: PerformanceContext.Domain, isRoot: Bool = true) {
        self.init(context: PerformanceContext(day: Repository.logicalDayKey(Date()), domain: domain)!, isRoot: isRoot)
    }
    private var context: PerformanceContext {
        PerformanceContext(day: day, domain: initialContext.domain, metric: initialContext.metric,
                           windowDays: initialContext.windowDays)!
    }
    private var today: String { Repository.logicalDayKey(Date()) }
    private var loadID: String { context.id + "|" + repo.deviceId + "|" + String(dataRevision) + "|" + unitPreference + temperaturePreference + skinPreference + effortPreference }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                header
                if context.domain == .today {
                    Text(verbatim: "NROOP").font(StrandFont.rounded(PerformanceDesign.wordmarkSize, weight: .light))
                        .tracking(PerformanceDesign.brandTracking).frame(maxWidth: .infinity).padding(.vertical, NoopMetrics.space1)
                }
                if let snapshot = model.snapshot, snapshot.context == context {
                    if snapshot.hadReadErrors {
                        PerformanceReadError { Task { await model.load(repo: repo, context: context) } }
                    }
                    contents(snapshot)
                } else {
                    ProgressView("Reading your measurements…").frame(maxWidth: .infinity).padding(.vertical, NoopMetrics.space8)
                }
                if context.domain != .today {
                    NavigationLink(value: TabRoute.metricExplorer) {
                        Label("Explore all metrics", systemImage: "chart.xyaxis.line").font(StrandFont.subhead)
                    }.padding(.vertical, NoopMetrics.space3)
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space6)
        }
        .background(PerformanceBackground())
        .toolbar(.hidden, for: .navigationBar)
        // Like the classic Today pull-to-sync: a pull asks the strap for its stored history, not just a UI reload.
        .refreshable {
            if live.historyReady { ble.syncNow() }
            await repo.refresh()
        }
        .task(id: loadID) {
            router.performanceContext = context
            await model.load(repo: repo, context: context)
        }
        .onAppear { router.performanceContext = context }
        .onReceive(repo.performanceSnapshotCache.$revision) { dataRevision = $0 }
        .sheet(isPresented: $showCalendar) { calendar }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showManualWorkout) {
            ManualWorkoutSheet(editing: nil) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }
            }
        }
        .sheet(isPresented: $showDashboardEditor) {
            TodayCustomizationSheet(initialDestination: dashboardEditorDestination, sectionOrderRaw: $sectionOrderRaw,
                hiddenSectionsRaw: $hiddenSectionsRaw, keyMetricsRaw: $keyMetricsRaw,
                keyMetricsDetailed: $keyMetricsDetailed, keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw, hostedCardsRaw: $hostedCardsRaw)
        }
        .sheet(isPresented: $showCoachLauncher) { CoachLauncherSheet() }
        .task(id: "stress|\(repo.deviceId)|\(dataRevision)|\(day)|\(PuffinExperiment.stressPersonalBaselineEnabled)") {
            stressTimeline = []
            stressActivityMaskedHours = 0
            stressLoaded = false
            guard day == today else { return }
            let result = await StressDayCurve.today(repo: repo, personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)
            guard !Task.isCancelled else { return }
            stressTimeline = result?.result.timeline ?? []
            stressActivityMaskedHours = result?.result.activityMaskedHours ?? 0
            stressLoaded = true
        }
        .task(id: "liveEffort|\(repo.deviceId)|\(repo.refreshSeq)|\(day)|\(dayCycleModeRaw)") {
            liveEffort = nil
            guard day == today, context.domain == .today || context.domain == .effort else { return }
            // Like WHOOP, the Effort ring builds up during the day; re-read every few minutes while visible.
            while !Task.isCancelled {
                let value = await computeLiveEffort()
                guard !Task.isCancelled else { return }
                liveEffort = value
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            }
        }
        .task(id: "\(repo.deviceId)|\(repo.refreshSeq)|\(today)") {
            planReady = false
            let rows = await repo.workoutRows(days: 8)
            guard !Task.isCancelled else { return }
            planWorkouts = rows
            planReady = true
        }
        .task(id: "hydration|\(repo.deviceId)|\(repo.hydrationSeq)|\(hydrationEnabled)|\(profile.sex)|\(day)|\(dataRevision)|\(dashboardCardsRaw)") {
            hydrationDisplay = nil
            guard context.domain == .today, day == today, hydrationEnabled,
                  DashboardCardPrefs.decodeEnabled(dashboardCardsRaw).contains(.hydration),
                  let store = await repo.storeHandle() else { return }
            do {
                let manual = try await store.metricSeries(deviceId: HydrationStore.sourceId, key: HydrationStore.key, from: day, to: day)
                let imported = try await store.metricSeries(deviceId: HydrationStore.sourceId, key: HydrationStore.importedKey, from: day, to: day)
                let total = (manual.first?.value ?? 0) + (imported.first?.value ?? 0)
                guard !Task.isCancelled, total.isFinite, total >= 0 else { return }
                hydrationDisplay = HydrationGoal.cardValueString(totalML: total, goalML: repo.hydrationGoalML(profileSex: profile.sex))
            } catch { hydrationDisplay = nil }
        }
    }

    @ViewBuilder private var header: some View {
        if context.domain == .today { dailyHeader }
        else { secondaryHeader }
    }

    private var dailyHeader: some View {
        HStack(spacing: NoopMetrics.space1) {
            Button { showSettings = true } label: {
                ProfileAvatarView(imageData: profile.avatarImageData, size: 36)
                    .frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter)
            }.accessibilityLabel("Profile and settings")
            let days = repo.days
            let streak = StreakCalculator.streaks(dayKeys: days.map { $0.day },
                                                   qualified: days.map { $0.recovery != nil },
                                                   today: today)
            Label("\(streak.current)", systemImage: "flame.fill")
                .font(StrandFont.caption).monospacedDigit()
                .accessibilityLabel("\(streak.current) days in a row")
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }.accessibilityLabel("Previous day")
                Button { showCalendar = true } label: {
                    Text(day == today ? String(localized: "Today") : day).font(StrandFont.caption).lineLimit(1).minimumScaleFactor(0.75)
                }.frame(minHeight: PerformanceDesign.controlDiameter).accessibilityLabel(PerformanceFormat.date(day))
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }.disabled(day >= today).accessibilityLabel("Next day")
            }.background(StrandPalette.textPrimary.opacity(0.035), in: Capsule())
            Spacer(minLength: 0)
            Button { router.openDevices() } label: {
                VStack(spacing: 0) {
                    Image(systemName: "battery.75").font(StrandFont.headline)
                    if live.connected, live.activeIsWhoop, let pct = live.batteryPct {
                        Text("\(Int(pct.rounded()))%") .font(StrandFont.overline).monospacedDigit()
                    }
                }.frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter)
            }.accessibilityLabel("Manage devices")
        }.foregroundStyle(StrandPalette.textPrimary).font(StrandFont.caption)
    }

    private var secondaryHeader: some View {
        VStack(spacing: NoopMetrics.space2) {
            HStack {
                Button {
                    if isRoot { showSettings = true } else { dismiss() }
                } label: {
                    Image(systemName: isRoot ? "person.crop.circle" : "chevron.left")
                        .font(StrandFont.headline)
                        .frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter)
                }.accessibilityLabel(isRoot ? "Profile and settings" : "Back")
                Spacer(minLength: NoopMetrics.space1)
                if context.domain != .today { Text(context.domain.title.uppercased()).font(StrandFont.overline).tracking(PerformanceDesign.labelTracking) }
                else { Text(day == today ? String(localized: "Today") : String(localized: "Selected day")).font(StrandFont.subhead) }
                Spacer(minLength: NoopMetrics.space1)
                Button { router.openDevices() } label: {
                    Image(systemName: "applewatch").font(StrandFont.headline)
                        .frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter)
                }.accessibilityLabel("Manage devices")
            }
            HStack(spacing: NoopMetrics.space1) {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }
                    .accessibilityLabel("Previous day")
                Button { showCalendar = true } label: {
                    Text(PerformanceFormat.date(day)).font(StrandFont.caption).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: PerformanceDesign.controlDiameter)
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }
                    .disabled(day >= today).accessibilityLabel("Next day")
            }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }.foregroundStyle(StrandPalette.textPrimary)
    }

    private var calendar: some View {
        NavigationStack {
            DatePicker("Choose a day", selection: Binding(get: {
                PerformanceSnapshotModel.localNoon(day) ?? Date()
            }, set: { value in
                let key = Repository.localDayKey(value)
                day = min(today, key)
                showCalendar = false
            }), in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.graphical).padding(NoopMetrics.space4)
            .navigationTitle("Choose a day")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCalendar = false } } }
        }.presentationDetents([.medium])
    }

    private func shiftDay(_ offset: Int) { day = min(today, context.shiftedDay(by: offset)) }

    @ViewBuilder private func contents(_ snapshot: PerformanceSnapshot) -> some View {
        switch context.domain {
        case .today: todayContents(snapshot)
        case .sleep, .recovery, .effort:
            DatedPerformanceScoreRing(domain: context.domain, value: displayedScore(context.domain, snapshot), large: true)
                .frame(maxWidth: .infinity).padding(.vertical, NoopMetrics.space3)
            if context.domain == .effort, isLiveEffort(snapshot) { liveEffortCaption }
            if displayedScore(context.domain, snapshot) == nil { emptyState }
            pillarContents(snapshot)
        case .health: healthContents(snapshot)
        case .activities: activitiesContents(snapshot)
        case .trend: EmptyView()
        }
    }

    private func todayContents(_ snapshot: PerformanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space5) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: NoopMetrics.space5)) : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
            layout {
                ForEach([PerformanceContext.Domain.sleep, .recovery, .effort], id: \.self) { domain in
                    NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: domain)!)) {
                        let current = displayedScore(domain, snapshot)
                        // WHOOP keeps the last computed cycle visible until the new one is scored.
                        let carried = current == nil && day == today ? snapshot.latestPrior(domain.metricKey) : nil
                        VStack(spacing: NoopMetrics.space2) {
                            DatedPerformanceScoreRing(domain: domain, value: current ?? carried?.value)
                                .opacity(carried == nil ? 1 : 0.6)
                            Text(domain.title.uppercased()).font(StrandFont.overline).tracking(PerformanceDesign.labelTracking)
                            if domain == .effort, carried == nil, isLiveEffort(snapshot) {
                                Text("In progress").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }
                            if let carried {
                                Text(carriedDayLabel(carried.day))
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }
                        }.frame(maxWidth: .infinity).foregroundStyle(StrandPalette.textPrimary)
                    }.buttonStyle(.plain)
                }
            }
            if day == today, [PerformanceContext.Domain.sleep, .recovery, .effort].contains(where: { displayedScore($0, snapshot) == nil }) {
                unscoredTodayStatus(snapshot)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: NoopMetrics.space3) { healthMonitor(snapshot); stressMonitor(snapshot) }
                VStack(spacing: NoopMetrics.space3) { healthMonitor(snapshot); stressMonitor(snapshot) }
            }
            ageSummary(snapshot)
            homeMeasurements(snapshot)
            HStack { Text(String(localized: "My Day")).font(StrandFont.title2); Spacer(); Button { router.requestQuickActions() } label: { Image(systemName: "plus").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }.accessibilityLabel("Quick actions") }
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Your Daily Outlook", systemImage: "sun.max").font(StrandFont.headline)
                    Text(dailyOutlook(snapshot))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            PerformanceCoachLink(context: context)
            NavigationLink(value: TabRoute.workouts) { Label("All activities", systemImage: "figure.run").font(StrandFont.subhead) }
            activityList(snapshot, includeSleep: true)
            if day == today {
                AutoWorkoutCard()
                tonightSleep(snapshot)
                JournalReminderCard(showsBehaviorInsights: true)
                weeklyPlan
                dashboard(snapshot)
                PerformanceHostedCards(rawSelection: hostedCardsRaw, day: day, revision: dataRevision,
                    stressTimeline: stressTimeline, stressActivityMaskedHours: stressActivityMaskedHours) {
                    dashboardEditorDestination = .addedCards
                    showDashboardEditor = true
                }
            }
        }
    }

    /// Why today's cycle has no score yet, read from real state only, plus a manual sync + re-score.
    private func unscoredTodayStatus(_ snapshot: PerformanceSnapshot) -> some View {
        let reason: String
        if intelligence.computing {
            reason = String(localized: "Calculating today's scores…")
        } else if live.backfilling {
            reason = String(localized: "Syncing last night from the strap…")
        } else if snapshot.night != nil || !snapshot.sleepSessions.isEmpty {
            reason = String(localized: "Night detected, today's scores are not calculated yet.")
        } else if !live.connected {
            reason = String(localized: "Strap not connected: last night is not synced yet.")
        } else if let last = live.lastSyncedAt {
            let time = Date(timeIntervalSince1970: last).formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
            reason = String(localized: "No sleep detected for last night (last strap sync \(time)).")
        } else {
            reason = String(localized: "Last night is not synced yet.")
        }
        return PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label(reason, systemImage: "info.circle")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = intelligence.note, !note.isEmpty {
                    Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task {
                        if live.historyReady { ble.syncNow() }
                        await intelligence.analyzeRecent(triggerLabel: "today-recalculate")
                        await repo.refresh()
                    }
                } label: {
                    Label(intelligence.computing ? String(localized: "Calculating today's scores…") : String(localized: "Recalculate today"),
                          systemImage: "arrow.clockwise").font(StrandFont.subhead)
                }
                .disabled(intelligence.computing)
            }
        }
    }

    /// "Yesterday" for the previous day, otherwise a short weekday/date of the carried score.
    private func carriedDayLabel(_ key: String) -> String {
        if key == context.shiftedDay(by: -1) { return String(localized: "Yesterday") }
        guard let date = PerformanceContext.date(key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.activeLocale))
    }

    /// The stored score, except today's Effort: max(stored, live) exactly like the classic Today screen.
    private func displayedScore(_ domain: PerformanceContext.Domain, _ snapshot: PerformanceSnapshot) -> Double? {
        let stored = snapshot.value(domain.metricKey)
        guard domain == .effort, day == today else { return stored }
        return StrainScorer.effectiveEffort(live: liveEffort, stored: stored)
    }

    private func isLiveEffort(_ snapshot: PerformanceSnapshot) -> Bool {
        guard day == today, let liveEffort else { return false }
        guard let stored = snapshot.value("strain") else { return true }
        return liveEffort > stored
    }

    private var liveEffortCaption: some View {
        Label("Effort in progress, measured since the start of your day", systemImage: "dot.radiowaves.left.and.right")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            .frame(maxWidth: .infinity)
    }

    /// Same window and parameters as the classic Today live Effort (LiquidTodayView, #1001/#2460).
    private func computeLiveEffort() async -> Double? {
        guard let noon = PerformanceSnapshotModel.localNoon(today) else { return nil }
        let calendar = Calendar.current
        var from = Int(calendar.startOfDay(for: noon).timeIntervalSince1970)
        if DayCycleMode.persisted(dayCycleModeRaw) == .sleepOnset {
            let markers = await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: Repository.whoopSource)
            if let onset = markers.last(where: { $0.day == today }), onset.value.isFinite, onset.value > 0 {
                from = Int(onset.value)
            }
        }
        let to = max(from, Int(Date().timeIntervalSince1970))
        let samples = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard !samples.isEmpty else { return nil }
        let maxHR = profile.effortHRmax
        let restHR = repo.days.first(where: { $0.day == today })?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let method = PuffinExperiment.effortMethod
        let sex = profile.sex
        return await Task.detached(priority: .utility) {
            StrainScorer.strain(samples, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
        }.value
    }

    private func dailyOutlook(_ snapshot: PerformanceSnapshot) -> String {
        var facts: [String] = []
        if let sleep = snapshot.value("sleep_performance") {
            facts.append(String(localized: "sleep performance \(PerformanceFormat.value("sleep_performance", sleep))"))
        }
        if let recovery = snapshot.value("recovery") {
            facts.append(String(localized: "recovery \(PerformanceFormat.value("recovery", recovery))"))
        }
        if let effort = displayedScore(.effort, snapshot) {
            facts.append(String(localized: "effort \(PerformanceFormat.effort(effort))"))
        }
        if let debt = snapshot.value("sleep_debt_min") {
            facts.append(String(localized: "sleep debt \(PerformanceFormat.duration(debt))"))
        }
        if !snapshot.workouts.isEmpty {
            let count = snapshot.workouts.count
            facts.append(count == 1 ? String(localized: "one recorded workout") :
                            String(localized: "\(count) recorded workouts"))
        }
        guard !facts.isEmpty else { return String(localized: "No daily scores or workouts available yet.") }
        let formatter = ListFormatter()
        formatter.locale = AppLanguage.activeLocale
        let summary = formatter.string(from: facts) ?? facts.joined(separator: ", ")
        return String(localized: "Recorded for this day: \(summary).")
    }

    private func tonightSleep(_ snapshot: PerformanceSnapshot) -> some View {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let weekday = calendar.component(.weekday, from: tomorrow)
        let wake = WindDownNudge.wakeMinutes(forWeekday: weekday)
        let need = snapshot.recommendedSleepNeed.flatMap { $0 > 0 && $0 <= 1440 ? Int($0.rounded()) : nil }
        let bedtime = need.map { (wake - $0 + 1440) % 1440 }
        return PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Tonight’s sleep", systemImage: "moon").font(StrandFont.headline)
                HStack(alignment: .top, spacing: NoopMetrics.space4) {
                    sleepTime(String(localized: "Suggested bedtime"), time: bedtime.map(clockMinute))
                    sleepTime(String(localized: "Usual wake"), time: clockMinute(wake))
                }
                if bedtime == nil {
                    Text("Sleep need is unavailable.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
                Button { router.openAlarms() } label: {
                    Label("Set or edit alarm", systemImage: "alarm")
                }.font(StrandFont.subhead)
            }
        }
    }

    private func sleepTime(_ title: String, time: String?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Text(time ?? "—").font(StrandFont.title2).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clockMinute(_ minute: Int) -> String {
        let clock = AppClock.hourMinuteFormatter()
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                              hour: minute / 60, minute: minute % 60))
        return date.map { clock.string(from: $0) } ?? "—"
    }

    private var weeklyPlan: some View {
        let goals = WeeklyPlanGoals(sleepMinutes: planSleepMinutes, sleepNights: planSleepNights, workoutDays: planWorkoutDays)
        let rows = WeeklyPlanSource.rows(days: repo.days, workouts: planReady ? planWorkouts : [], now: Date())
        let progress = WeeklyPlanEngine.progress(rows: rows, goals: goals)
        return NavigationLink { WeeklyPlanView().modifier(PerformanceLegacyContextReset()) } label: {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack { Text(String(localized: "My plan")).font(StrandFont.headline); Spacer(); Image(systemName: "pencil") }
                    if goals.sleepNights > 0 {
                        Text("Sleep nights: \(progress.sleepNights) / \(goals.sleepNights)").font(StrandFont.subhead).monospacedDigit()
                        ProgressView(value: Double(min(progress.sleepNights, goals.sleepNights)), total: Double(goals.sleepNights))
                    }
                    if goals.workoutDays > 0 && planReady {
                        Text("Workout days: \(progress.workoutDays) / \(goals.workoutDays)").font(StrandFont.subhead).monospacedDigit()
                        ProgressView(value: Double(min(progress.workoutDays, goals.workoutDays)), total: Double(goals.workoutDays))
                    }
                    if goals.sleepNights == 0 && goals.workoutDays == 0 {
                        Text("Choose your weekly sleep and activity goals.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }.buttonStyle(.plain).foregroundStyle(StrandPalette.textPrimary)
    }

    private func dashboard(_ snapshot: PerformanceSnapshot) -> some View {
        let cards = DashboardCardPrefs.decodeEnabled(dashboardCardsRaw).filter { hydrationEnabled || $0 != .hydration }
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack {
                Text(String(localized: "My dashboard")).font(StrandFont.headline)
                Spacer()
                Button("Customize") {
                    dashboardEditorDestination = .yourCards
                    showDashboardEditor = true
                }.font(StrandFont.caption)
            }
            PerformancePanel {
                VStack(spacing: 0) {
                    ForEach(cards) { card in
                        dashboardCardRow(card, snapshot: snapshot)
                        if card != cards.last { Divider() }
                    }
                    if cards.isEmpty { Text("Choose metrics to show here.").font(StrandFont.subhead) }
                }
            }
        }
    }

    @ViewBuilder private func dashboardCardRow(_ card: DashboardCard, snapshot: PerformanceSnapshot) -> some View {
        switch PerformanceDashboardPolicy.destination(for: card) {
        case .metric(let key):
            dashboardMetricRow(card, key: key, snapshot: snapshot)
        case .stepsAverage:
            RollingStepsAverageCard(day: day)
        case .hydration:
            NavigationLink(value: TabRoute.hydration) {
                PerformanceMeasureRow(title: card.title, value: hydrationDisplay ?? "—", caption: card.subtitle, symbol: card.icon)
            }.buttonStyle(.plain)
        case .coupled:
            NavigationLink(value: TabRoute.coupled) {
                PerformanceMeasureRow(title: card.title, value: "", caption: card.subtitle, symbol: card.icon)
            }.buttonStyle(.plain)
        case .coach:
            Button { showCoachLauncher = true } label: {
                PerformanceMeasureRow(title: card.title, value: "", caption: card.subtitle, symbol: card.icon)
            }.buttonStyle(.plain)
        }
    }

    private func dashboardMetricRow(_ card: DashboardCard, key: String, snapshot: PerformanceSnapshot) -> some View {
        let age = key == "fitness_age" || key == "vitality" ? agePoint(snapshot, key: key) : nil
        let vo2 = key == "vo2max" ? vo2Point(snapshot) : nil
        let steps = key == "steps" ? stepsPoint(snapshot) : nil
        let oxygen = key == "spo2" ? PerformanceHomeData.importedOxygen(snapshot.series["spo2_imported"] ?? [], on: day) : nil
        let formatKey = vo2?.sourceKey == "vo2max_est" ? "vo2max_est" : key
        let value = key == "stress" ? snapshot.stress :
            (key == "fitness_age" || key == "vitality" ? age?.value :
                (key == "vo2max" ? vo2?.value : (key == "steps" ? steps?.value :
                    (key == "spo2" ? oxygen?.value : snapshot.value(key)))))
        let caption: String
        if key == "fitness_age" || key == "vitality" {
            caption = age.map { PerformanceFormat.date($0.day) } ?? String(localized: "Measurement unavailable")
        } else if key == "vo2max" {
            caption = measurementCaption(vo2?.value, note: formatKey == "vo2max_est" ? String(localized: "Estimate") : nil,
                                         measuredDay: vo2?.day)
        } else if key == "active_kcal" {
            caption = measurementCaption(value, note: String(localized: "Estimate"))
        } else if key == "steps" {
            caption = measurementCaption(value, note: steps?.sourceKey == "steps_est" ? String(localized: "Estimate") : nil)
        } else if key == "resp_rate", snapshot.source(key)?.hasSuffix("-noop") == true {
            caption = measurementCaption(value, note: String(localized: "Estimate"))
        } else if key == "spo2" {
            caption = oxygen == nil ? String(localized: "Not available via Bluetooth") :
                [String(localized: "Imported"), String(localized: "Not available via Bluetooth")].joined(separator: " · ")
        } else {
            caption = card.subtitle
        }
        let route: TabRoute
        switch key {
        case "vo2max", "active_kcal", "spo2": route = .health
        case "steps": route = .metricSourced(key: "steps", source: MetricCatalog.combinedStepsSource)
        default: route = .performance(PerformanceContext(day: day, domain: .trend, metric: key)!)
        }
        return NavigationLink(value: route) {
            PerformanceMeasureRow(title: card.title, value: key == "vo2max" ? vo2Value(value) : PerformanceFormat.value(formatKey, value),
                                  caption: caption, symbol: card.icon)
        }.buttonStyle(.plain)
    }

    private func healthMonitor(_ snapshot: PerformanceSnapshot) -> some View {
        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .health)!)) {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Label("Health Monitor", systemImage: "heart.text.square").font(StrandFont.overline)
                    Text(snapshot.personalVitals.isEmpty ? "—/4" : "\(snapshot.inPersonalRange)/4").font(StrandFont.title2).monospacedDigit()
                    Text(snapshot.personalVitals.isEmpty ? String(localized: "Learning your personal reference") : String(localized: "\(snapshot.inPersonalRange) in your personal range"))
                        .font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.buttonStyle(.plain).foregroundStyle(StrandPalette.textPrimary)
    }

    private func stressMonitor(_ snapshot: PerformanceSnapshot) -> some View {
        let hours = day == today ? stressTimeline : []
        let latest = hours.last(where: \.hasData)?.level
        let value = latest ?? snapshot.stress
        return NavigationLink(value: TabRoute.stress) {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Stress estimate", systemImage: "waveform.path.ecg").font(StrandFont.overline)
                    if let value {
                        HStack {
                            Text(PerformanceFormat.number(value, decimals: 1)).font(StrandFont.title2)
                            Text(StressBand(score: value).title).font(StrandFont.footnote)
                        }
                        .foregroundStyle(StressRamp.color(value))
                        Text(latest != nil ? String(localized: "Latest hourly estimate") : String(localized: "Daily proxy, 0–3"))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if latest != nil {
                        DaytimeLoadLine(hours: hours)
                    } else if day != today {
                        Text("Hourly stress is shown for today.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    } else if stressLoaded {
                        Text("No hourly stress measurements available.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }.buttonStyle(.plain).foregroundStyle(StrandPalette.textPrimary)
    }

    @ViewBuilder private func pillarContents(_ snapshot: PerformanceSnapshot) -> some View {
        if context.domain == .sleep {
            sleepDetail(snapshot)
            sleepWeek(snapshot)
            PerformancePanel {
                VStack(spacing: 0) {
                    measure("sleep_performance", snapshot)
                    Divider()
                    measure("sleep_total_min", snapshot, fallback: snapshot.daily?.totalSleepMin)
                    Divider()
                    measure("hours_vs_needed_pct", snapshot)
                    Divider()
                    measure("sleep_consistency", snapshot)
                    Divider()
                    measure("sleep_efficiency", snapshot, fallback: snapshot.daily?.efficiency.map { $0 <= 1 ? $0 * 100 : $0 })
                    Divider()
                    measure("sleep_need_min", snapshot)
                    Divider()
                    measure("sleep_debt_min", snapshot)
                }
            }
            PerformanceFullHistoryLink(key: context.domain.metricKey)
            PerformanceCoachLink(context: context)
            Button { showManualSleep = true } label: {
                Label("Add sleep", systemImage: "plus.circle")
                    .foregroundStyle(PerformanceDesign.sleep)
            }
            .sheet(isPresented: $showManualSleep) {
                ManualSleepEntry(end: min(Int(Date().timeIntervalSince1970),
                    Int((PerformanceSnapshotModel.localNoon(day) ?? Date()).timeIntervalSince1970)))
            }
            trendLink("sleep_total_min")
            trendLink("sleep_consistency")
            NavigationLink { SleepClockStressLabView(repo: repo).modifier(PerformanceLegacyContextReset()) } label: {
                Label("Experimental sleep stress research", systemImage: "waveform.path.ecg").font(StrandFont.subhead)
            }
            Text("Night activation is an unvalidated local research proxy, not an official WHOOP sleep stress score.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            NavigationLink(value: TabRoute.sleep) { Label("Detailed sleep tools", systemImage: "moon.zzz").font(StrandFont.subhead) }
        } else if context.domain == .recovery {
            PerformancePanel {
                VStack(spacing: 0) {
                    measure("hrv", snapshot, fallback: snapshot.daily?.avgHrv)
                    Divider()
                    measure("rhr", snapshot, fallback: snapshot.daily?.restingHr.map(Double.init))
                    Divider()
                    measure("resp_rate", snapshot, fallback: snapshot.daily?.respRateBpm)
                    Divider()
                    measure("sleep_performance", snapshot)
                }
            }
            if let insight = recoveryInsight(snapshot) {
                PerformancePanel {
                    Label(insight, systemImage: "text.bubble").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            recoveryBars(snapshot)
            PerformanceFullHistoryLink(key: context.domain.metricKey)
            PerformanceCoachLink(context: context)
            Text("These measurements provide context; they are not a percentage breakdown of the recovery score.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            trendLink("hrv")
            trendLink("rhr")
        } else {
            if day == today { effortTarget(snapshot) }
            PerformancePanel {
                VStack(spacing: 0) {
                    measure(snapshot.value("steps") != nil ? "steps" : "steps_est", snapshot)
                    Divider()
                    measure("hr_zones13_min", snapshot)
                    Divider()
                    measure("hr_zones45_min", snapshot)
                    Divider()
                    measure("strength_min", snapshot)
                }
            }
            PerformanceFullHistoryLink(key: context.domain.metricKey)
            PerformanceCoachLink(context: context)
            activityList(snapshot, includeSleep: false)
            trendLink("strain")
            if day == today { WorkoutStartControl() }
        }
    }

    private func recoveryBars(_ snapshot: PerformanceSnapshot) -> some View {
        let points = snapshot.series["recovery"] ?? []
        return PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Recovery · 7 days").font(StrandFont.headline)
                if points.isEmpty {
                    Text("No recovery measurements in this period.").font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Chart(points, id: \.day) { point in
                        if let date = PerformanceSnapshotModel.localNoon(point.day) {
                            BarMark(x: .value("Day", date, unit: .day), y: .value("Recovery", point.value))
                                .foregroundStyle(PerformanceContext.Domain.recovery.tint(score: point.value))
                        }
                    }.chartYScale(domain: 0...100).frame(height: PerformanceDesign.compactChartHeight)
                }
            }
        }
    }

    private func measure(_ key: String, _ snapshot: PerformanceSnapshot, fallback: Double? = nil) -> some View {
        let metric = PerformanceFormat.metric(key)
        let value = snapshot.value(key) ?? PerformanceContext.finite(fallback)
        let baseline = snapshot.baselines[key]
        let bandKeys: Set<String> = ["sleep_performance", "hours_vs_needed_pct", "sleep_consistency", "sleep_efficiency"]
        return NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: key)!)) {
            PerformanceMeasureRow(title: PerformanceFormat.title(key), value: PerformanceFormat.value(key, value),
                                  caption: value == nil ? String(localized: "Measurement unavailable") : sourceCaption(snapshot.source(key)),
                                  symbol: metric?.icon ?? "waveform.path.ecg",
                                  baseline: baseline.map { String(localized: "30-day avg \(PerformanceFormat.value(key, $0))") },
                                  direction: Self.direction(value, baseline),
                                  badge: bandKeys.contains(key) ? PerformanceBand(percent: value) : nil)
        }.buttonStyle(.plain)
    }

    /// +1 / -1 when today differs from the 30-day average by more than 3 %, else 0.
    static func direction(_ value: Double?, _ baseline: Double?) -> Int {
        guard let value, let baseline, value.isFinite, baseline.isFinite, baseline != 0 else { return 0 }
        let change = (value - baseline) / abs(baseline)
        return change > 0.03 ? 1 : change < -0.03 ? -1 : 0
    }

    /// Short, factual recovery comment from today's HRV / RHR against their own 30-day average.
    private func recoveryInsight(_ snapshot: PerformanceSnapshot) -> String? {
        var parts: [String] = []
        if let hrv = snapshot.value("hrv") ?? PerformanceContext.finite(snapshot.daily?.avgHrv),
           let base = snapshot.baselines["hrv"], base > 0 {
            let pct = Int(((hrv - base) / base * 100).rounded())
            let pctText = "\(abs(pct)) %"
            if pct > 0 { parts.append(String(localized: "Your HRV is \(pctText) above your 30-day average.")) }
            else if pct < 0 { parts.append(String(localized: "Your HRV is \(pctText) below your 30-day average.")) }
            else { parts.append(String(localized: "Your HRV matches your 30-day average.")) }
        }
        if let rhr = snapshot.value("rhr") ?? snapshot.daily?.restingHr.map(Double.init),
           let base = snapshot.baselines["rhr"], base > 0 {
            let diff = Int((rhr - base).rounded())
            if diff > 0 { parts.append(String(localized: "Resting heart rate is \(diff) bpm above your 30-day average.")) }
            else if diff < 0 { parts.append(String(localized: "Resting heart rate is \(-diff) bpm below your 30-day average.")) }
            else { parts.append(String(localized: "Resting heart rate matches your 30-day average.")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// NROOP's effort guide for today's recovery (CoupledView bands), on WHOOP's 0–21 scale only.
    @ViewBuilder private func effortTarget(_ snapshot: PerformanceSnapshot) -> some View {
        let recovery = snapshot.value("recovery")
        if PerformanceFormat.effortScale == .whoop, let band = CoupledView.optimalStrainRange(recovery: recovery), let recovery {
            let current = displayedScore(.effort, snapshot).map { UnitFormatter.effortValue($0, scale: .whoop) }
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Effort target", systemImage: "scope").font(StrandFont.headline)
                    Text("\(band.lowerBound)–\(band.upperBound)").font(StrandFont.title2).monospacedDigit()
                        .foregroundStyle(PerformanceDesign.effort)
                    if let current {
                        ProgressView(value: min(current, 21), total: 21)
                            .tint(Double(band.lowerBound)...Double(band.upperBound) ~= current ? PerformanceDesign.recoveryHigh : PerformanceDesign.effort)
                    }
                    let recoveryText = "\(Int(recovery.rounded())) %"
                    Text("Suggested for a recovery of \(recoveryText). A NROOP guide, not WHOOP's Strain Coach.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func trendLink(_ key: String) -> some View {
        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: key)!)) {
            PerformancePanel { PerformanceMeasureRow(title: PerformanceFormat.title(key),
                                                     value: "", caption: String(localized: "Explore this trend"), symbol: "chart.xyaxis.line") }
        }.buttonStyle(.plain)
    }

    private struct SleepEditSelection: Identifiable {
        let session: CachedSleepSession
        var id: Int { session.startTs }
    }

    @ViewBuilder private func sleepDetail(_ snapshot: PerformanceSnapshot) -> some View {
        if let night = snapshot.night {
            HStack {
                Text(day == today ? String(localized: "Last night’s sleep") : String(localized: "My night"))
                    .font(StrandFont.title2)
                Spacer()
                if let target = night.editTarget {
                    Button { editingSleep = SleepEditSelection(session: target) } label: {
                        Label("Edit sleep times", systemImage: "pencil")
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(PerformanceDesign.sleep)
                }
            }
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("\(night.onsetText) – \(night.wakeText)").font(StrandFont.subhead)
                    if night.session.userEdited && night.session.stagesJSON == nil {
                        Text("Manual entry").font(StrandFont.footnote)
                    }
                    SleepStageTimeline(night: night, intervals: night.realSegments ?? [],
                                       heartRate: nightHeartRate, days: repo.days)
                }
            }
            .task(id: "\(repo.deviceId)|\(night.session.effectiveStartTs)-\(night.session.endTs)-\(repo.refreshSeq)") {
                nightHeartRate = []
                let readings = await repo.hrBuckets(from: night.session.effectiveStartTs,
                                                     to: night.session.endTs, bucketSeconds: 60)
                if !Task.isCancelled { nightHeartRate = readings }
            }
            .sheet(item: $editingSleep) { selection in
                let target = selection.session
                SleepTimeEditor(bedTs: target.effectiveStartTs, wakeTs: target.endTs,
                                coverage: min(target.startTs, target.effectiveStartTs)...target.endTs,
                                onSave: { start, end in
                                    await repo.editSleepTimes(detectedStartTs: target.startTs, oldEndTs: target.endTs,
                                                              storedStagesJSON: target.stagesJSON, newStartTs: start, newEndTs: end)
                                    let age = max(0, Int(Date().timeIntervalSince1970) - min(end, target.endTs)) / 86_400
                                    await intelligence.analyzeRecent(maxDays: max(21, age + 2))
                                    await repo.refresh()
                                })
            }
            ForEach(snapshot.sleepSessions.filter { !night.mainGroupStarts.contains($0.startTs) },
                    id: \.startTs) { nap in
                PerformancePanel { napMeasure(nap) }
            }
        }
    }

    @ViewBuilder private func sleepWeek(_ snapshot: PerformanceSnapshot) -> some View {
        let previous = snapshot.sleepWeek.dropLast().last.map { Repository.localDayKey($0.date) }
        let recentEffort = snapshot.series["strain"]?.first { $0.day == previous }?.value
        PerformancePanel {
            HoursVsNeededCard(slept: snapshot.value("sleep_total_min"), needed: snapshot.value("sleep_need_min"),
                              debt: snapshot.value("sleep_debt_min"),
                              recentEffort: recentEffort.map { PerformanceFormat.effort($0) })
        }
        PerformancePanel {
            ConsistencyCard(week: snapshot.sleepWeek, score: snapshot.value("sleep_consistency"))
        }
        if !snapshot.sleepWeek.isEmpty {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("Weekly sleep performance").font(StrandFont.headline)
                    HStack(alignment: .bottom, spacing: NoopMetrics.space1) {
                        ForEach(snapshot.sleepWeek) { night in
                            let key = Repository.localDayKey(night.date)
                            let score = snapshot.series["sleep_performance"]?.first { $0.day == key }?.value
                            sleepPerformanceBar(night.date, score: score)
                        }
                    }
                }
            }
        }
    }

    private func sleepPerformanceBar(_ date: Date, score: Double?) -> some View {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.activeLocale))
        let value = score.map { ($0 / 100).formatted(.percent.precision(.fractionLength(0))) }
        return VStack(spacing: NoopMetrics.space1) {
            Text(value ?? "—").font(StrandFont.footnote).lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { geometry in
                if let score {
                    Capsule().fill(StrandPalette.surfaceInset)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(PerformanceDesign.sleep)
                                .frame(height: geometry.size.height * CGFloat(min(100, max(0, score))) / 100)
                        }
                }
            }
            .frame(width: NoopMetrics.space3, height: PerformanceDesign.stageChartHeight)
            Text(weekday).font(StrandFont.footnote).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.activeLocale)))
        .accessibilityValue(value ?? String(localized: "No measurement"))
    }

    private func napMeasure(_ nap: CachedSleepSession) -> some View {
        let window = "\(PerformanceFormat.clock(nap.effectiveStartTs)) – \(PerformanceFormat.clock(nap.endTs))"
        let caption = nap.userEdited && nap.stagesJSON == nil
            ? [window, String(localized: "Manual entry")].joined(separator: " · ") : window
        return PerformanceMeasureRow(title: String(localized: "Nap"),
                                     value: PerformanceFormat.duration(SleepView.creditedMinutes(nap)),
                                     caption: caption, symbol: "powersleep")
    }

    private func creditedSleep(_ night: Night) -> Double? {
        let minutes = SleepView.creditedMinutes(night.session)
        return minutes > 0 ? minutes : nil
    }

    private func activityList(_ snapshot: PerformanceSnapshot, includeSleep: Bool) -> some View {
        let mainStarts = snapshot.night?.mainGroupStarts ?? []
        let naps = includeSleep ? snapshot.sleepSessions.filter { !mainStarts.contains($0.startTs) } : []
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(day == today ? String(localized: "Today’s Activities") : String(localized: "Activities"))
                .font(StrandFont.title2)
            if includeSleep, let night = snapshot.night {
                NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .sleep)!)) {
                    PerformancePanel {
                        PerformanceMeasureRow(title: String(localized: "Sleep"),
                                              value: PerformanceFormat.duration(night.stages.asleep > 0
                                                  ? night.stages.asleep : creditedSleep(night)),
                                              caption: "\(night.onsetText) – \(night.wakeText)", symbol: "moon")
                    }
                }.buttonStyle(.plain)
            }
            ForEach(naps, id: \.startTs) { nap in
                NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .sleep)!)) {
                    PerformancePanel { napMeasure(nap) }
                }.buttonStyle(.plain)
            }
            ForEach(Array(snapshot.workouts.enumerated()), id: \.offset) { _, row in
                NavigationLink(value: TabRoute.performanceWorkout(start: row.startTs, source: row.source)) {
                    PerformancePanel {
                        PerformanceMeasureRow(title: WorkoutSource.displaySport(row.sport), value: PerformanceFormat.effort(row.strain),
                                              caption: "\(PerformanceFormat.clock(row.startTs)) – \(PerformanceFormat.clock(row.endTs))", symbol: "figure.run")
                    }
                }.buttonStyle(.plain)
            }
            if snapshot.workouts.isEmpty, naps.isEmpty, !(includeSleep && snapshot.night != nil) {
                Text("No recorded activity for this day.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if includeSleep && day == today {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoopMetrics.space3) { addActivityButton; WorkoutStartControl(compact: true) }
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) { addActivityButton; WorkoutStartControl(compact: true) }
                }
            }
        }
    }

    private var addActivityButton: some View {
        Button { showManualWorkout = true } label: {
            Label("Add an activity", systemImage: "plus.circle")
                .font(StrandFont.subhead)
                .frame(minHeight: NoopMetrics.controlHeight)
        }
    }

    private func healthContents(_ snapshot: PerformanceSnapshot) -> some View {
        let oxygen = PerformanceHomeData.importedOxygen(snapshot.series["spo2_imported"] ?? [], on: day)
        let availableCount = snapshot.availableVitals.count + (oxygen == nil ? 0 : 1)
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            Text("Health").font(StrandFont.title1)
            ageSummary(snapshot)
            stressMonitor(snapshot)
            Text("Health Monitor").font(StrandFont.headline)
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("\(availableCount) available measurements").font(StrandFont.headline)
                    Text(snapshot.personalVitals.isEmpty ? String(localized: "Learning your personal reference") : String(localized: "\(snapshot.inPersonalRange) in your personal range"))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            PerformancePanel {
                VStack(spacing: 0) {
                    ForEach(snapshot.vitals) { vital in
                        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: vital.key)!)) {
                            PerformanceMeasureRow(title: vital.label,
                                                  value: vital.day == day ? (vital.formattedValue ?? "—") : "—",
                                                  caption: healthVitalCaption(vital, snapshot: snapshot),
                                                  symbol: vital.banding.basis == .personal && vital.day == day ? (vital.banding.band == .inRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill") : "circle.dashed")
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    NavigationLink(value: TabRoute.health) {
                        PerformanceMeasureRow(title: String(localized: "Blood O₂"),
                            value: PerformanceFormat.value("spo2", oxygen?.value),
                            caption: oxygen == nil ? String(localized: "Not available via Bluetooth") :
                                [String(localized: "Imported"), String(localized: "Not available via Bluetooth")].joined(separator: " · "),
                            symbol: "drop")
                    }.buttonStyle(.plain)
                }
            }
            PerformanceCoachLink(context: context)
            NavigationLink { LongitudinalTrendsView(repo: repo).modifier(PerformanceLegacyContextReset()) } label: { Label("Long-term trends", systemImage: "chart.line.uptrend.xyaxis").font(StrandFont.subhead) }
            NavigationLink(value: TabRoute.health) { Label("All health tools", systemImage: "heart.text.square").font(StrandFont.subhead) }
        }
    }

    private func healthVitalCaption(_ vital: BodyVitalReading, snapshot: PerformanceSnapshot) -> String {
        guard vital.day == day, vital.value != nil else { return String(localized: "Measurement unavailable") }
        if vital.key == "resp", vital.source == .noopComputed || snapshot.source("resp_rate")?.hasSuffix("-noop") == true {
            return [String(localized: "Estimate"), vital.stateCaption].joined(separator: " · ")
        }
        return vital.stateCaption
    }

    private func ageSummary(_ snapshot: PerformanceSnapshot) -> some View {
        PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("NROOP Age").font(StrandFont.headline)
                Text("On-device approximations, not WHOOP scores. Pace of Aging is not available.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                ForEach(["fitness_age", "body_age", "vitality"], id: \.self) { key in
                    let point = agePoint(snapshot, key: key)
                    NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: key)!)) {
                        PerformanceMeasureRow(title: PerformanceFormat.title(key), value: PerformanceFormat.value(key, point?.value),
                                              caption: point.map { PerformanceFormat.date($0.day) } ?? String(localized: "Measurement unavailable"),
                                              symbol: PerformanceFormat.metric(key)?.icon ?? "heart")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func agePoint(_ snapshot: PerformanceSnapshot, key: String) -> ResolvedMetricPoint? {
        snapshot.series[key]?.last(where: { $0.day <= day })
    }

    private func homeMeasurements(_ snapshot: PerformanceSnapshot) -> some View {
        let temperature = UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitPreference) ?? .metric,
                                                       override: temperaturePreference)
        let skin = snapshot.value("skin_temp_delta")
        let skinValue = skin.map { SkinTempDisplay.formatReading(.init(value: $0, kind: .deviation),
                                                                   fahrenheit: temperature == .fahrenheit) } ?? "—"
        // Apple Health respiratory samples are not necessarily nocturnal.
        let respiratorySource = snapshot.source("resp_rate")
        let respiratory = respiratorySource == Repository.appleHealthSource ? nil : snapshot.value("resp_rate")
        let respiratoryNote = respiratorySource?.hasSuffix("-noop") == true
            ? [String(localized: "Sleep"), String(localized: "Estimate")].joined(separator: " · ")
            : String(localized: "Sleep")
        let steps = stepsPoint(snapshot)
        let energy = snapshot.value("active_kcal").flatMap { $0 >= 0 ? $0 : nil }
        let vo2 = vo2Point(snapshot)
        let vo2Key = vo2?.sourceKey == "vo2max_est" ? "vo2max_est" : "vo2max"
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Key Metrics").font(StrandFont.headline)
            PerformancePanel {
                VStack(spacing: 0) {
                    homeMeasurementRow(title: String(localized: "Skin Temperature"), value: skinValue,
                        caption: measurementCaption(skin, note: String(localized: "vs baseline")), symbol: "thermometer",
                        route: .performance(PerformanceContext(day: day, domain: .health)!))
                    Divider()
                    homeMeasurementRow(title: String(localized: "Respiratory Rate"),
                        value: PerformanceFormat.value("resp_rate", respiratory),
                        caption: measurementCaption(respiratory, note: respiratoryNote), symbol: "lungs",
                        route: .performance(PerformanceContext(day: day, domain: .trend, metric: "resp_rate")!))
                    Divider()
                    homeMeasurementRow(title: String(localized: "VO₂ Max"), value: vo2Value(vo2?.value),
                        caption: measurementCaption(vo2?.value, note: vo2Key == "vo2max_est" ? String(localized: "Estimate") : nil,
                                                    measuredDay: vo2?.day), symbol: "figure.run", route: .health)
                    Divider()
                    homeMeasurementRow(title: String(localized: "Steps"), value: PerformanceFormat.value("steps", steps?.value),
                        caption: measurementCaption(steps?.value, note: steps?.sourceKey == "steps_est" ? String(localized: "Estimate") : nil),
                        symbol: "figure.walk", route: .metricSourced(key: "steps", source: MetricCatalog.combinedStepsSource))
                    Divider()
                    homeMeasurementRow(title: String(localized: "Active Energy"), value: PerformanceFormat.value("active_kcal", energy),
                        caption: measurementCaption(energy, note: String(localized: "Estimate")), symbol: "flame",
                        route: .performance(PerformanceContext(day: day, domain: .trend, metric: "active_kcal")!))
                }
            }
        }
    }

    private func measurementCaption(_ value: Double?, note: String? = nil, measuredDay: String? = nil) -> String {
        guard value != nil else { return String(localized: "Measurement unavailable") }
        return [note, PerformanceFormat.date(measuredDay ?? day)].compactMap { $0 }.joined(separator: " · ")
    }

    private func vo2Point(_ snapshot: PerformanceSnapshot) -> ResolvedMetricPoint? {
        let points = PerformanceHomeData.merged(snapshot.series["vo2max"] ?? [],
                                                fallback: snapshot.series["vo2max_est"] ?? [],
                                                from: "0000-01-01", through: day)
        return PerformanceHomeData.latest(points.filter { $0.value > 0 }, through: day)
    }

    private func stepsPoint(_ snapshot: PerformanceSnapshot) -> ResolvedMetricPoint? {
        PerformanceHomeData.dailySteps(measured: snapshot.series["steps"] ?? [],
                                       estimated: snapshot.series["steps_est"] ?? [], on: day)
    }

    private func vo2Value(_ value: Double?) -> String {
        guard value != nil else { return "—" }
        return PerformanceFormat.number(value, decimals: 1) + " mL/kg/min"
    }

    private func homeMeasurementRow(title: String, value: String, caption: String, symbol: String, route: TabRoute) -> some View {
        NavigationLink(value: route) {
            PerformanceMeasureRow(title: title, value: value, caption: caption, symbol: symbol)
        }.buttonStyle(.plain)
    }

    private func activitiesContents(_ snapshot: PerformanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            Text("Prepare your activity").font(StrandFont.title1)
            Image("NathanWhoopSensor").resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: PerformanceDesign.productHeight)
                .accessibilityLabel("Your WHOOP 5.0 sensor")
            if day == today { WorkoutStartControl() }
            PerformanceCoachLink(context: context)
            activityList(snapshot, includeSleep: false)
            NavigationLink { WeeklyPlanView().modifier(PerformanceLegacyContextReset()) } label: { Label("Weekly plan", systemImage: "calendar").font(StrandFont.subhead) }
            NavigationLink(value: TabRoute.workouts) { Label("Workout history", systemImage: "figure.run").font(StrandFont.subhead) }
        }
    }

    private var emptyState: some View {
        PerformancePanel { VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Label("No score for this day", systemImage: "chart.line.downtrend.xyaxis").font(StrandFont.headline)
            Text("Some measurements may still be available even when this score has not been calculated.")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        } }
    }

    private func sourceCaption(_ source: String?) -> String? {
        guard let source else { return nil }
        return source.hasSuffix("-noop") ? String(localized: "Calculated on this device") : String(localized: "Recorded measurement")
    }
}

struct PerformanceWorkoutRouteView: View {
    let start: Int
    let source: String
    @EnvironmentObject private var repo: Repository
    @State private var row: WorkoutRow?
    @State private var loaded = false
    @EnvironmentObject private var router: NavRouter
    var body: some View {
        Group {
            if let row { WorkoutDetailView(row: row) }
            else if loaded { Text("This recorded activity is unavailable.").font(StrandFont.body).padding(NoopMetrics.space4) }
            else { ProgressView() }
        }.task {
            row = await repo.workoutRows(days: 4000).first { $0.startTs == start && $0.source == source }
            if let row { router.performanceContext = PerformanceContext(day: Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(row.startTs))), domain: .activities) }
            loaded = true
        }
    }
}
#endif
