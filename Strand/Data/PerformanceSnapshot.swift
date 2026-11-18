import Foundation
import Combine
import WhoopStore
import StrandAnalytics

/// Read-only presentation snapshot. Every resolved point keeps its actual provider and day.
struct PerformanceSnapshot {
    let context: PerformanceContext
    var daily: DailyMetric?
    var series: [String: [ResolvedMetricPoint]] = [:]
    var workouts: [WorkoutRow] = []
    var night: Night?
    var vitals: [BodyVitalReading] = []
    var stress: Double?
    var hadReadErrors = false

    func value(_ key: String) -> Double? {
        PerformanceContext.finite(series[key]?.first(where: { $0.day == context.day })?.value)
    }

    func source(_ key: String) -> String? {
        series[key]?.first(where: { $0.day == context.day })?.source
    }

    var availableVitals: [BodyVitalReading] {
        vitals.filter { $0.day == context.day && PerformanceContext.finite($0.value) != nil }
    }
    var personalVitals: [BodyVitalReading] {
        availableVitals.filter { $0.banding.basis == .personal }
    }
    var inPersonalRange: Int { personalVitals.filter { $0.banding.band == .inRange }.count }

    var hasAnyData: Bool {
        daily != nil || series.values.contains { $0.contains { $0.day == context.day } } || !workouts.isEmpty
    }

    /// A capture depends on the date, window and metric, but not on the screen that displays it.
    func forContext(_ newContext: PerformanceContext) -> PerformanceSnapshot {
        PerformanceSnapshot(context: newContext, daily: daily, series: series, workouts: workouts,
                            night: night, vitals: vitals, stress: stress, hadReadErrors: hadReadErrors)
    }
}

/// An in-memory, repository-scoped cache: views can share one day without sharing another device's data.
@MainActor
final class PerformanceSnapshotCache: ObservableObject {
    typealias Loader = @MainActor (Repository, PerformanceContext, PerformanceSnapshotModel.Scope) async -> PerformanceSnapshot
    /// Separate from Repository.objectWillChange, so a no-op refresh does not redraw unrelated screens.
    @Published private(set) var revision = 0

    private struct Key: Hashable {
        let day: String
        let windowDays: Int
        let metric: String?
        let isTrend: Bool
        let device: String
        let revision: Int
        let units: String
        let temperature: String
        let skin: String

        @MainActor init(repo: Repository, context: PerformanceContext, cacheRevision: Int) {
            day = context.day
            windowDays = context.windowDays
            metric = context.metric
            isTrend = context.domain == .trend
            device = repo.deviceId
            revision = cacheRevision
            let defaults = UserDefaults.standard
            units = defaults.string(forKey: UnitPrefs.systemKey) ?? ""
            temperature = defaults.string(forKey: UnitPrefs.temperatureKey) ?? ""
            skin = defaults.string(forKey: UnitPrefs.skinTempDisplayKey) ?? ""
        }
    }

    private final class Flight {
        let id = UUID()
        let task: Task<PerformanceSnapshot, Never>
        var readers = Set<UUID>()
        init(task: Task<PerformanceSnapshot, Never>) { self.task = task }
    }

    private var snapshots: [Key: PerformanceSnapshot] = [:]
    private var inFlight: [Key: Flight] = [:]
    private var order: [Key] = []
    private let capacity = 8
    private let loader: Loader

    init(loader: @escaping Loader = { repo, context, scope in
        await PerformanceSnapshotModel.capture(repo: repo, context: context, scope: scope)
    }) {
        self.loader = loader
    }

    func invalidate() {
        snapshots.removeAll()
        order.removeAll()
        for flight in inFlight.values { flight.task.cancel() }
        inFlight.removeAll()
        revision &+= 1
    }

    func value(repo: Repository, context: PerformanceContext) async -> PerformanceSnapshot {
        while true {
            let key = Key(repo: repo, context: context, cacheRevision: revision)
            if let cached = snapshots[key] {
                touch(key)
                return cached.forContext(context)
            }
            // Concurrent screens share the work, but an abandoned read must stop when its last reader leaves.
            let flight: Flight
            if let running = inFlight[key] {
                flight = running
            } else {
                let scope: PerformanceSnapshotModel.Scope = context.domain == .trend ? .trend : .full
                flight = Flight(task: Task { await loader(repo, context, scope) })
                inFlight[key] = flight
            }
            let reader = UUID()
            flight.readers.insert(reader)
            let flightID = flight.id
            let result = await withTaskCancellationHandler {
                await flight.task.value
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.release(key: key, flightID: flightID, reader: reader, cancelIfEmpty: true)
                }
            }
            release(key: key, flightID: flightID, reader: reader, cancelIfEmpty: false)
            if Task.isCancelled { return result.forContext(context) }
            // Do not publish a capture invalidated during its read; retry for the new revision.
            if key != Key(repo: repo, context: context, cacheRevision: revision) {
                continue
            }
            if flight.task.isCancelled { continue }
            if !result.hadReadErrors {
                snapshots[key] = result
                touch(key)
                while order.count > capacity { snapshots.removeValue(forKey: order.removeFirst()) }
            }
            return result.forContext(context)
        }
    }

    private func release(key: Key, flightID: UUID, reader: UUID, cancelIfEmpty: Bool) {
        guard let flight = inFlight[key], flight.id == flightID, flight.readers.remove(reader) != nil else { return }
        if flight.readers.isEmpty {
            inFlight[key] = nil
            if cancelIfEmpty { flight.task.cancel() }
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

@MainActor
final class PerformanceSnapshotModel: ObservableObject {
    enum Scope { case full, trend }
    @Published private(set) var snapshot: PerformanceSnapshot?
    @Published private(set) var loading = false
    private var generation = 0
    private var loadedDevice: String?
    private var loadedPreferences: [String]?

    func load(repo: Repository, context: PerformanceContext) async {
        generation += 1
        let token = generation
        loading = true
        // Keep the same screen visible during a refresh, but never show another date or device.
        if snapshot?.context != context || loadedDevice != repo.deviceId || loadedPreferences != Self.displayPreferences {
            snapshot = nil
        }
        let device = repo.deviceId
        let value = await repo.performanceSnapshotCache.value(repo: repo, context: context)
        guard generation == token, !Task.isCancelled else { return }
        guard device == repo.deviceId else { loading = false; return }
        snapshot = value
        loadedDevice = device
        loadedPreferences = Self.displayPreferences
        loading = false
    }

    private static var displayPreferences: [String] {
        let defaults = UserDefaults.standard
        return [UnitPrefs.systemKey, UnitPrefs.temperatureKey, UnitPrefs.skinTempDisplayKey]
            .map { defaults.string(forKey: $0) ?? "" }
    }

    static let keys = ["sleep_performance", "sleep_consistency", "sleep_need_min", "sleep_debt_min",
                       "sleep_total_min", "sleep_efficiency", "hours_vs_needed_pct", "recovery", "strain",
                       "hrv", "rhr", "resp_rate", "steps", "steps_est", "hr_zones13_min",
                       "hr_zones45_min", "strength_min", "stress", "skin_temp", "spo2", "active_kcal",
                       "fitness_age", "body_age", "vitality", "vo2max", "vo2max_est"]

    static func capture(repo: Repository, context: PerformanceContext, scope: Scope = .full) async -> PerformanceSnapshot {
        var result = PerformanceSnapshot(context: context)
        result.daily = repo.days.first { $0.day == context.day }
        let requestedKeys = scope == .trend ? [context.metric ?? "hrv"]
            : keys + (context.metric.map { keys.contains($0) ? [] : [$0] } ?? [])
        for key in requestedKeys {
            if Task.isCancelled { return result }
            // VO₂ readings can be much older than the seven-day dashboard window.
            let from = scope == .full && (key == "vo2max" || key == "vo2max_est") ? "0000-01-01" : context.lowerBound
            let resolved = await repo.resolvedSeries(key: key, source: Repository.whoopSource,
                                                     from: from, to: context.day)
            result.hadReadErrors = result.hadReadErrors || resolved.hadReadErrors
            result.series[key] = resolved.points.compactMap { point in
                guard point.day >= from, point.day <= context.day, let value = displayValue(point.value, key: key,
                                                                           origin: point.origin, source: point.source) else { return nil }
                return ResolvedMetricPoint(day: point.day, value: value, source: point.source,
                                           sourceKey: point.sourceKey, origin: point.origin)
            }
        }
        if scope == .full {
            // Apple steps and VO₂ are not WHOOP-compatible candidates in the generic resolver.
            for key in ["steps", "vo2max"] {
                let from = key == "vo2max" ? "0000-01-01" : context.lowerBound
                let apple = await repo.resolvedSeries(key: key, source: Repository.appleHealthSource,
                                                      from: from, to: context.day)
                result.hadReadErrors = result.hadReadErrors || apple.hadReadErrors
                result.series[key] = PerformanceHomeData.merged(result.series[key] ?? [], fallback: apple.points,
                                                                  from: from, through: context.day)
            }
            if let store = await repo.storeHandle() {
                do {
                    // Older imports can have daily aggregates without a corresponding metric series.
                    let rows = try await store.appleDaily(deviceId: Repository.appleHealthSource,
                                                          from: "0000-01-01", to: context.day)
                    for key in ["steps", "active_kcal", "vo2max"] {
                        let points = rows.compactMap { row -> ResolvedMetricPoint? in
                            let value: Double?
                            switch key {
                            case "steps": value = row.steps.map(Double.init)
                            case "active_kcal": value = row.activeKcal
                            default: value = row.vo2max
                            }
                            guard let value else { return nil }
                            return ResolvedMetricPoint(day: row.day, value: value, source: Repository.appleHealthSource,
                                                       sourceKey: key, origin: .daily)
                        }
                        let from = key == "vo2max" ? "0000-01-01" : context.lowerBound
                        result.series[key] = PerformanceHomeData.merged(result.series[key] ?? [], fallback: points,
                                                                          from: from, through: context.day)
                    }
                } catch { result.hadReadErrors = true }
            } else { result.hadReadErrors = true }
        }
        if Task.isCancelled { return result }
        let historicalDays = repo.days.filter { $0.day <= context.day }
        if scope == .full || context.metric == "stress" {
            let storedStress = (result.series["stress"] ?? []).map { (day: $0.day, value: $0.value) }
            // StressModel may carry a previous signal; only call it when this exact day is scorable.
            let stressModel = StressModel(days: historicalDays, stored: storedStress)
            if let stored = result.value("stress") {
                result.stress = min(3, max(0, stored))
            } else if result.daily?.avgHrv != nil || result.daily?.restingHr != nil {
                result.stress = stressModel?.score
            }
            var stressPoints = Dictionary(uniqueKeysWithValues: (result.series["stress"] ?? []).map { ($0.day, $0) })
            if let lower = PerformanceContext.date(context.lowerBound), let upper = PerformanceContext.date(context.day) {
                for point in stressModel?.fullTrend ?? [] where point.date >= lower && point.date < upper.addingTimeInterval(86_400) {
                    let day = PerformanceContext.dayKey(point.date)
                    if context.contains(day), stressPoints[day] == nil {
                        stressPoints[day] = ResolvedMetricPoint(day: day, value: point.value,
                            source: Repository.whoopSource + "-noop", sourceKey: "stress")
                    }
                }
            }
            result.series["stress"] = stressPoints.values.sorted { $0.day < $1.day }
        }
        if Task.isCancelled { return result }
        if scope == .full {
            let rows = await repo.workoutRows(days: workoutLookbackDays(day: context.day, now: Date()))
            if Task.isCancelled { return result }
            result.workouts = rows.filter {
                Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == context.day
            }.sorted { $0.startTs < $1.startTs }
            let sessions = await repo.allSleepSessions(days: 4000)
            if Task.isCancelled { return result }
            let groups = SleepModel.navDays(navSessions: sessions.filter {
                Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == context.day
            })
            let historicalSessions = sessions.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) < context.day }
            let offset = TimeZone.current.secondsFromGMT(for: localNoon(context.day) ?? Date())
            let blocks = historicalSessions.compactMap { session -> SleepStageTotals.HistoryBlock? in
                guard session.endTs > session.effectiveStartTs else { return nil }
                let mid = session.effectiveStartTs + (session.endTs - session.effectiveStartTs) / 2
                return .init(start: session.effectiveStartTs, end: session.endTs,
                             dayKey: AnalyticsEngine.dayString(mid, offsetSec: offset))
            }
            let habitual = SleepStageTotals.habitualMidsleepSec(blocks, offsetSec: offset)
            result.night = SleepModel.decodedNight(at: 0, navDays: groups, habitualMidsleepSec: habitual,
                                                  motionByStart: [:])
        }
        if scope == .trend, context.metric != "skin_temp" { return result }
        let sourceRows = repo.vitalMetricRows.filter { $0.metric.day <= context.day }
        let preferredSkin = SkinTempDisplay.Kind(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.skinTempDisplayKey) ?? "") ?? .absolute
        let temperature = UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric,
                                                       override: UserDefaults.standard.string(forKey: UnitPrefs.temperatureKey) ?? "")
        if scope == .full || context.metric == "skin_temp" {
            // Match the explorer's single-scale policy after restricting every input to this window.
            let temperatureDays = historicalDays.filter { context.contains($0.day) }
            let anyAbsolute = temperatureDays.contains { $0.skinTempC != nil || $0.skinTempDevC.map(VitalBands.isAbsoluteSkinTemp) == true }
            let anyDeviation = temperatureDays.contains { $0.skinTempDevC.map { !VitalBands.isAbsoluteSkinTemp($0) } == true }
            let leadsAbsolute = preferredSkin == .absolute ? anyAbsolute : (!anyDeviation && anyAbsolute)
            let sources = skinTempSourceByDay(sourceRows, leadsAbsolute: leadsAbsolute)
            result.series["skin_temp"] = temperatureDays.compactMap { row in
                let value = leadsAbsolute
                    ? row.skinTempC ?? row.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
                    : row.skinTempDevC.flatMap { !VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
                guard let value = PerformanceContext.finite(value) else { return nil }
                return ResolvedMetricPoint(day: row.day, value: value, source: sources[row.day] ?? "local-cache", sourceKey: "skin_temp")
            }.sorted { $0.day < $1.day }
        }
        if scope == .full {
            // The BLE pipeline already banks the nightly deviation; never reinterpret absolute °C as Δ°C.
            var deviations: [String: ResolvedMetricPoint] = [:]
            for row in sourceRows.sorted(by: { $0.source.vitalPriority < $1.source.vitalPriority }) {
                guard context.contains(row.metric.day), deviations[row.metric.day] == nil,
                      let value = PerformanceContext.finite(row.metric.skinTempDevC),
                      !VitalBands.isAbsoluteSkinTemp(value) else { continue }
                let source: String
                switch row.source {
                case .whoopImport: source = Repository.whoopSource
                case .noopComputed: source = Repository.whoopSource + "-noop"
                case .appleHealth: continue
                case .localCache: source = "local-cache"
                }
                deviations[row.metric.day] = ResolvedMetricPoint(day: row.metric.day, value: value,
                                                               source: source, sourceKey: "skin_temp")
            }
            result.series["skin_temp_delta"] = deviations.values.sorted { $0.day < $1.day }
        }
        // Noon in the local calendar avoids a UTC date drifting to the preceding logical day.
        if scope == .full, let localNoon = localNoon(context.day) {
            result.vitals = BodyVitalSigns.readings(sourceRows: sourceRows, temperatureUnit: temperature, now: localNoon, skinTempPreferred: preferredSkin)
                .filter { $0.key != "spo2raw" && $0.key != "spo2" }
        }
        return result
    }

    /// Daily efficiency can be stored either as a fraction or an imported percentage.
    static func displayValue(_ raw: Double, key: String, origin: MetricReadOrigin = .daily,
                             source: String? = nil) -> Double? {
        guard raw.isFinite else { return nil }
        guard key == "sleep_efficiency" else { return raw }
        return PerformanceContext.sleepEfficiencyPercent(raw, origin: origin, source: source)
    }

    nonisolated static func localNoon(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.date(from: day + " 12:00")
    }

    static func workoutLookbackDays(day: String, now: Date) -> Int {
        guard let selected = localNoon(day) else { return 4000 }
        let elapsedDays = max(0, now.timeIntervalSince(selected) / 86_400)
        guard elapsedDays.isFinite, elapsedDays < 4000 else { return 4000 }
        // Two days of extra history keep near-midnight cross-source deduplication intact.
        return min(4000, max(3, Int(elapsedDays.rounded(.up)) + 3))
    }
}
