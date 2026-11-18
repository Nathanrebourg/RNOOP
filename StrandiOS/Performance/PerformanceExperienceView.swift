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
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
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
    @State private var showSleepPlanner = false
    @State private var sleepGoalPercent = 100
    @State private var planWorkouts: [WorkoutRow] = []
    @State private var planReady = false
    @State private var stressTimeline: [DaytimeStress.HourPoint] = []
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
        .refreshable { await repo.refresh() }
        .task(id: loadID) {
            router.performanceContext = context
            await model.load(repo: repo, context: context)
        }
        .onAppear { router.performanceContext = context }
        .onReceive(repo.performanceSnapshotCache.$revision) { dataRevision = $0 }
        .sheet(isPresented: $showCalendar) { calendar }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showSleepPlanner) {
            if let snapshot = model.snapshot { sleepPlanner(snapshot) }
        }
        .sheet(isPresented: $showDashboardEditor) {
            TodayCustomizationSheet(initialDestination: .yourCards, sectionOrderRaw: $sectionOrderRaw,
                hiddenSectionsRaw: $hiddenSectionsRaw, keyMetricsRaw: $keyMetricsRaw,
                keyMetricsDetailed: $keyMetricsDetailed, keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw, hostedCardsRaw: $hostedCardsRaw)
        }
        .task(id: "stress|\(repo.deviceId)|\(repo.refreshSeq)|\(day)") {
            stressTimeline = []
            guard day == today else { return }
            let result = await StressDayCurve.today(repo: repo, personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)
            guard !Task.isCancelled else { return }
            stressTimeline = result?.result.timeline ?? []
        }
        .task(id: "\(repo.deviceId)|\(repo.refreshSeq)|\(today)") {
            planReady = false
            let rows = await repo.workoutRows(days: 8)
            guard !Task.isCancelled else { return }
            planWorkouts = rows
            planReady = true
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
                else { Text(day == today ? "Today" : "Selected day").font(StrandFont.subhead) }
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
            DatedPerformanceScoreRing(domain: context.domain, value: snapshot.value(context.domain.metricKey), large: true)
                .frame(maxWidth: .infinity).padding(.vertical, NoopMetrics.space3)
            if snapshot.value(context.domain.metricKey) == nil { emptyState }
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
                        VStack(spacing: NoopMetrics.space2) {
                            DatedPerformanceScoreRing(domain: domain, value: snapshot.value(domain.metricKey))
                            Text(domain.title.uppercased()).font(StrandFont.overline).tracking(PerformanceDesign.labelTracking)
                        }.frame(maxWidth: .infinity).foregroundStyle(StrandPalette.textPrimary)
                    }.buttonStyle(.plain)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: NoopMetrics.space3) { healthMonitor(snapshot); stressMonitor(snapshot) }
                VStack(spacing: NoopMetrics.space3) { healthMonitor(snapshot); stressMonitor(snapshot) }
            }
            ageSummary(snapshot)
            homeMeasurements(snapshot)
            HStack { Text("My Day").font(StrandFont.title2); Spacer(); Button { router.requestQuickActions() } label: { Image(systemName: "plus").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }.accessibilityLabel("Quick actions") }
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Your Daily Outlook", systemImage: "sun.max").font(StrandFont.headline)
                    Text(snapshot.hasAnyData ? "Your recorded results and activities for this day." : "Your measurements will appear here after synchronization.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            PerformanceCoachLink(context: context)
            NavigationLink(value: TabRoute.workouts) { Label("All activities", systemImage: "figure.run").font(StrandFont.subhead) }
            activityList(snapshot, includeSleep: true)
            if day == today {
                HStack(spacing: NoopMetrics.space3) {
                    WorkoutStartControl(compact: true)
                    Button { router.openJournal(day: 0) } label: { Label("Journal", systemImage: "book.closed").font(StrandFont.subhead).frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight) }
                }
                tonightSleep(snapshot)
                JournalReminderCard()
                weeklyPlan
                dashboard(snapshot)
            }
        }
    }

    private func tonightSleep(_ snapshot: PerformanceSnapshot) -> some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let weekday = Calendar.current.component(.weekday, from: tomorrow)
        let wake = WindDownNudge.wakeMinutes(forWeekday: weekday)
        let need = snapshot.value("sleep_need_min").flatMap { $0.isFinite && $0 > 0 && $0 <= 1440 ? Int($0.rounded()) : nil }
        let bedtime = need.map { (wake - $0 + 1440) % 1440 }
        return Button { showSleepPlanner = true } label: {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Tonight’s sleep", systemImage: "moon").font(StrandFont.headline)
                    if let bedtime {
                        Text("Suggested bedtime \(clockMinute(bedtime)) · usual wake \(clockMinute(wake))")
                            .font(StrandFont.subhead).monospacedDigit()
                        Text("Based on your sleep need and usual wake time; not an alarm.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text("Sleep need is not available yet. Set your usual wake time in Alarms.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }.buttonStyle(.plain).foregroundStyle(StrandPalette.textPrimary)
    }

    private func sleepPlanner(_ snapshot: PerformanceSnapshot) -> some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let wake = WindDownNudge.wakeMinutes(forWeekday: Calendar.current.component(.weekday, from: tomorrow))
        let need = snapshot.value("sleep_need_min").flatMap { $0.isFinite && $0 > 0 && $0 <= 1440 ? $0 : nil }
        return NavigationStack {
            Form {
                Section("Sleep goal") {
                    Picker("Sleep goal", selection: $sleepGoalPercent) {
                        Text("70%").tag(70)
                        Text("85%").tag(85)
                        Text("100%").tag(100)
                    }.pickerStyle(.segmented)
                    if let need {
                        let target = Int((need * Double(sleepGoalPercent) / 100).rounded())
                        let bedtime = (wake - target + 1440) % 1440
                        LabeledContent("Suggested bedtime", value: clockMinute(bedtime))
                        LabeledContent("Usual wake", value: clockMinute(wake))
                        LabeledContent("Sleep goal", value: PerformanceFormat.duration(Double(target)))
                        Text("Based on your estimated sleep need and usual wake time. This does not set an alarm.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text("A sleep need is required to suggest a bedtime.")
                    }
                }
                Section {
                    Button("Open alarm settings") {
                        showSleepPlanner = false
                        router.openAlarms()
                    }
                }
            }.navigationTitle("Tonight’s sleep")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSleepPlanner = false } } }
        }
    }

    private func clockMinute(_ minute: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .minute, value: minute, to: start) ?? start
        return date.formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }

    private var weeklyPlan: some View {
        let goals = WeeklyPlanGoals(sleepMinutes: planSleepMinutes, sleepNights: planSleepNights, workoutDays: planWorkoutDays)
        let rows = WeeklyPlanSource.rows(days: repo.days, workouts: planReady ? planWorkouts : [], now: Date())
        let progress = WeeklyPlanEngine.progress(rows: rows, goals: goals)
        return NavigationLink { WeeklyPlanView().modifier(PerformanceLegacyContextReset()) } label: {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack { Text("My plan").font(StrandFont.headline); Spacer(); Image(systemName: "pencil") }
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
        let cards = DashboardCardPrefs.decodeEnabled(dashboardCardsRaw).filter { dashboardMetric($0) != nil }
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack {
                Text("My dashboard").font(StrandFont.headline)
                Spacer()
                Button("Customize") { showDashboardEditor = true }.font(StrandFont.caption)
            }
            PerformancePanel {
                VStack(spacing: 0) {
                    ForEach(cards) { card in
                        if let key = dashboardMetric(card) {
                            let age = key == "fitness_age" || key == "vitality" ? agePoint(snapshot, key: key) : nil
                            let vo2 = key == "vo2max" ? vo2Point(snapshot) : nil
                            let formatKey = vo2?.sourceKey == "vo2max_est" ? "vo2max_est" : key
                            let value = key == "stress" ? snapshot.stress :
                                (key == "fitness_age" || key == "vitality" ? age?.value :
                                    (key == "vo2max" ? vo2?.value : snapshot.value(key)))
                            let caption = key == "fitness_age" || key == "vitality"
                                ? (age.map { PerformanceFormat.date($0.day) } ?? String(localized: "Measurement unavailable"))
                                : (key == "vo2max" ? measurementCaption(vo2?.value,
                                    note: formatKey == "vo2max_est" ? String(localized: "Estimate") : nil,
                                    measuredDay: vo2?.day) : card.subtitle)
                            let route: TabRoute = key == "vo2max" ? .health : .performance(PerformanceContext(day: day, domain: .trend, metric: key)!)
                            NavigationLink(value: route) {
                                PerformanceMeasureRow(title: card.title, value: key == "vo2max" ? vo2Value(value) : PerformanceFormat.value(formatKey, value), caption: caption, symbol: card.icon)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                    if cards.isEmpty { Text("Choose metrics to show here.").font(StrandFont.subhead) }
                }
            }
        }
    }

    private func dashboardMetric(_ card: DashboardCard) -> String? {
        switch card {
        case .hrv: "hrv"
        case .restingHr: "rhr"
        case .respiratory: "resp_rate"
        case .steps: "steps"
        case .stress: "stress"
        case .fitnessAge: "fitness_age"
        case .vo2max: "vo2max"
        case .vitality: "vitality"
        case .skinTemp: "skin_temp"
        case .sleep: "sleep_performance"
        default: nil
        }
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
        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: "stress")!)) {
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Label("Stress estimate", systemImage: "waveform.path.ecg").font(StrandFont.overline)
                    Text(PerformanceFormat.number(snapshot.stress, decimals: 1)).font(StrandFont.title2)
                    Text("Daily proxy, 0–3").font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary)
                    if day == today && !stressTimeline.isEmpty {
                        DaytimeLoadLine(hours: stressTimeline).frame(height: PerformanceDesign.stageChartHeight)
                        Text("Today · on-device estimate").font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text("Intraday curve unavailable").font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }.buttonStyle(.plain).foregroundStyle(StrandPalette.textPrimary)
    }

    @ViewBuilder private func pillarContents(_ snapshot: PerformanceSnapshot) -> some View {
        if context.domain == .sleep {
            PerformancePanel {
                VStack(spacing: 0) {
                    measure("sleep_total_min", snapshot, fallback: snapshot.daily?.totalSleepMin)
                    Divider()
                    measure("hours_vs_needed_pct", snapshot)
                    Divider()
                    measure("sleep_consistency", snapshot)
                    Divider()
                    measure("sleep_efficiency", snapshot, fallback: snapshot.daily?.efficiency.map { $0 <= 1 ? $0 * 100 : $0 })
                    Divider()
                    measure("sleep_need_min", snapshot)
                }
            }
            PerformanceFullHistoryLink(key: context.domain.metricKey)
            PerformanceCoachLink(context: context)
            sleepDetail(snapshot)
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
            recoveryBars(snapshot)
            PerformanceFullHistoryLink(key: context.domain.metricKey)
            PerformanceCoachLink(context: context)
            Text("These measurements provide context; they are not a percentage breakdown of the recovery score.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            trendLink("hrv")
            trendLink("rhr")
        } else {
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
        return NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: key)!)) {
            PerformanceMeasureRow(title: PerformanceFormat.title(key), value: PerformanceFormat.value(key, value),
                                  caption: value == nil ? String(localized: "Measurement unavailable") : sourceCaption(snapshot.source(key)),
                                  symbol: metric?.icon ?? "waveform.path.ecg")
        }.buttonStyle(.plain)
    }

    private func trendLink(_ key: String) -> some View {
        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: key)!)) {
            PerformancePanel { PerformanceMeasureRow(title: PerformanceFormat.title(key),
                                                     value: "", caption: String(localized: "Explore this trend"), symbol: "chart.xyaxis.line") }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func sleepDetail(_ snapshot: PerformanceSnapshot) -> some View {
        if let night = snapshot.night {
            Text("My night").font(StrandFont.title2).padding(.top, NoopMetrics.space2)
            PerformancePanel {
                StageDetailView(night: night, intervals: night.intervals)
            }
        }
    }

    private func activityList(_ snapshot: PerformanceSnapshot, includeSleep: Bool) -> some View {
        PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Today’s Activities").font(StrandFont.overline)
                if includeSleep, let night = snapshot.night {
                    NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .sleep)!)) {
                        PerformanceMeasureRow(title: String(localized: "Sleep"), value: PerformanceFormat.duration(night.stages.asleep),
                                              caption: "\(PerformanceFormat.clock(night.session.effectiveStartTs)) – \(PerformanceFormat.clock(night.session.endTs))", symbol: "moon")
                    }.buttonStyle(.plain)
                }
                ForEach(Array(snapshot.workouts.enumerated()), id: \.offset) { _, row in
                    NavigationLink(value: TabRoute.performanceWorkout(start: row.startTs, source: row.source)) {
                        PerformanceMeasureRow(title: row.sport, value: PerformanceFormat.effort(row.strain),
                                              caption: "\(PerformanceFormat.clock(row.startTs)) – \(PerformanceFormat.clock(row.endTs))", symbol: "figure.run")
                    }.buttonStyle(.plain)
                }
                if snapshot.workouts.isEmpty, !(includeSleep && snapshot.night != nil) {
                    Text("No recorded activity for this day.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func healthContents(_ snapshot: PerformanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            Text("Health").font(StrandFont.title1)
            ageSummary(snapshot)
            stressMonitor(snapshot)
            Text("Health Monitor").font(StrandFont.headline)
            PerformancePanel {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("\(snapshot.availableVitals.count) available measurements").font(StrandFont.headline)
                    Text(snapshot.personalVitals.isEmpty ? String(localized: "Learning your personal reference") : String(localized: "\(snapshot.inPersonalRange) in your personal range"))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            PerformancePanel {
                VStack(spacing: 0) {
                    ForEach(snapshot.vitals) { vital in
                        NavigationLink(value: TabRoute.performance(PerformanceContext(day: day, domain: .trend, metric: vital.key)!)) {
                            PerformanceMeasureRow(title: vital.label,
                                                  value: vital.day == day ? PerformanceFormat.value(PerformanceContext.canonicalMetric(vital.key), vital.value) : "—",
                                                  caption: vital.day != day || vital.value == nil ? String(localized: "Measurement unavailable") : (vital.banding.basis == .personal ? String(localized: "Compared with your personal reference") : String(localized: "Personal reference not established")),
                                                  symbol: vital.banding.basis == .personal && vital.day == day ? (vital.banding.band == .inRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill") : "circle.dashed")
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            PerformanceCoachLink(context: context)
            NavigationLink { LongitudinalTrendsView(repo: repo).modifier(PerformanceLegacyContextReset()) } label: { Label("Long-term trends", systemImage: "chart.line.uptrend.xyaxis").font(StrandFont.subhead) }
            NavigationLink(value: TabRoute.health) { Label("All health tools", systemImage: "heart.text.square").font(StrandFont.subhead) }
        }
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
        let respiratory = snapshot.source("resp_rate") == Repository.appleHealthSource ? nil : snapshot.value("resp_rate")
        let steps = snapshot.value("steps").flatMap { $0 >= 0 ? $0 : nil }
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
                        caption: measurementCaption(respiratory, note: String(localized: "Sleep")), symbol: "lungs",
                        route: .performance(PerformanceContext(day: day, domain: .trend, metric: "resp_rate")!))
                    Divider()
                    homeMeasurementRow(title: String(localized: "VO₂ Max"), value: vo2Value(vo2?.value),
                        caption: measurementCaption(vo2?.value, note: vo2Key == "vo2max_est" ? String(localized: "Estimate") : nil,
                                                    measuredDay: vo2?.day), symbol: "figure.run", route: .health)
                    Divider()
                    homeMeasurementRow(title: String(localized: "Steps"), value: PerformanceFormat.value("steps", steps),
                        caption: measurementCaption(steps), symbol: "figure.walk",
                        route: .performance(PerformanceContext(day: day, domain: .trend, metric: "steps")!))
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
