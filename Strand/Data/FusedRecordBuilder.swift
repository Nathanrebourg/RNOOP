import Foundation
import StrandAnalytics
import WhoopStore

/// Builds the presentation from per-source rows; does not change the store or the analytics.
enum FusedRecordBuilder {
    struct SourceRows {
        let source: FusionSource
        let rows: [DailyMetric]
        let points: [MetricPoint]
        init(source: FusionSource, rows: [DailyMetric], points: [MetricPoint] = []) {
            self.source = source; self.rows = rows; self.points = points
        }
    }

    static func build(day: String, sources: [SourceRows], preferAbsoluteSkin: Bool) -> FusedRecord {
        let specs = [("rhr", "Resting HR"), ("hrv", "HRV"), ("resp_rate", "Respiratory Rate"),
                     ("sleep_total_min", "Sleep"), ("sleep_deep_min", "Deep (SWS) Sleep"),
                     ("sleep_rem_min", "REM Sleep"), ("sleep_light_min", "Light Sleep"),
                     ("sleep_efficiency", "Sleep Efficiency"), ("steps", "Steps"),
                     ("active_kcal", "Active Energy"), ("skin_temp", "Skin temp"), ("spo2", "Blood oxygen")]
        let dayRows = sources.flatMap(\.rows).filter { $0.day == day }
        let skinPoints = sources.flatMap(\.points).filter { $0.day == day && $0.key == "skin_temp" && $0.value.isFinite }
        let hasAbsolute = dayRows.contains { skin($0, absolute: true) != nil } || skinPoints.contains { VitalBands.isAbsoluteSkinTemp($0.value) }
        let hasDeviation = dayRows.contains { skin($0, absolute: false) != nil } || skinPoints.contains { !VitalBands.isAbsoluteSkinTemp($0.value) }
        let absoluteSkin = preferAbsoluteSkin ? hasAbsolute : (!hasDeviation && hasAbsolute)
        let sleepKeys: Set<String> = ["sleep_total_min", "sleep_deep_min", "sleep_rem_min", "sleep_light_min", "sleep_efficiency"]
        var sleepGroupBySource: [FusionSource: Int] = [:]
        for (index, group) in sources.enumerated() where sleepGroupBySource[group.source] == nil {
            let dailyHasSleep = group.rows.contains { row in
                row.day == day && (row.totalSleepMin != nil || row.efficiency != nil || row.deepMin != nil ||
                                   row.remMin != nil || row.lightMin != nil || row.disturbances != nil)
            }
            let seriesHasSleep = group.points.contains { point in
                point.day == day && ["sleep_total_min", "asleep_min", "sleep_deep_min", "deep_min", "sleep_rem_min",
                                     "rem_min", "sleep_light_min", "core_min", "sleep_efficiency"].contains(point.key)
            }
            if dailyHasSleep || seriesHasSleep { sleepGroupBySource[group.source] = index }
        }
        var rows: [FusedRow] = []
        var contributors = Set<FusionSource>()
        for (key, label) in specs {
            var seen = Set<FusionSource>()
            let inputs = sources.enumerated().compactMap { index, group -> FusionInput? in
                guard !seen.contains(group.source) else { return nil }
                if sleepKeys.contains(key), sleepGroupBySource[group.source] != index { return nil }
                let aliases = seriesKeys(key, source: group.source)
                let stored = aliases.lazy.compactMap { alias in
                    group.points.first { $0.day == day && $0.key == alias && $0.value.isFinite }
                }.compactMap { point -> Double? in
                    if key == "sleep_efficiency" {
                        return PerformanceContext.sleepEfficiencyPercent(point.value, origin: .series, source: group.source.rawValue)
                    }
                    if key == "skin_temp", VitalBands.isAbsoluteSkinTemp(point.value) != absoluteSkin { return nil }
                    return point.value
                }.first
                let value = stored ?? group.rows.lazy.filter { $0.day == day }
                    .compactMap { column(key, $0, absoluteSkin: absoluteSkin, source: group.source) }.first
                guard let v = PerformanceContext.finite(value) else { return nil }
                seen.insert(group.source)
                contributors.insert(group.source)
                return FusionInput(source: group.source, value: v)
            }
            if let point = FusionResolver.resolve(metricKey: key, inputs: inputs) {
                rows.append(FusedRow(point: point, label: label))
            }
        }
        let owner = contributors.min { MetricArbitrationPolicy.sourcePriority($0) < MetricArbitrationPolicy.sourcePriority($1) }
        return FusedRecord(rows: rows, dayOwner: owner, contributingSourceCount: contributors.count)
    }

    private static func seriesKeys(_ key: String, source: FusionSource) -> [String] {
        if source == .appleHealth {
            switch key {
            case "rhr": return ["resting_hr", "rhr"]
            case "sleep_total_min": return ["asleep_min", key]
            case "sleep_deep_min": return ["deep_min", key]
            case "sleep_rem_min": return ["rem_min", key]
            case "sleep_light_min": return ["core_min", key]
            default: break
            }
        }
        if source == .xiaomiBand && key == "active_kcal" { return ["energy_kcal", key] }
        return [key]
    }

    private static func skin(_ d: DailyMetric, absolute: Bool) -> Double? {
        let direct = PerformanceContext.finite(d.skinTempC).flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
        let other = PerformanceContext.finite(d.skinTempDevC)
        return absolute ? direct ?? other.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
                        : other.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? nil : $0 }
    }

    private static func column(_ key: String, _ d: DailyMetric, absoluteSkin: Bool, source: FusionSource) -> Double? {
        switch key {
        case "rhr": d.restingHr.map(Double.init)
        case "hrv": d.avgHrv
        case "resp_rate": d.respRateBpm
        case "sleep_total_min": d.totalSleepMin
        case "sleep_deep_min": d.deepMin
        case "sleep_rem_min": d.remMin
        case "sleep_light_min": d.lightMin
        case "sleep_efficiency": PerformanceContext.sleepEfficiencyPercent(d.efficiency, origin: .daily, source: source.rawValue)
        case "steps": d.steps.map(Double.init)
        case "active_kcal": d.activeKcalEst
        case "skin_temp": skin(d, absolute: absoluteSkin)
        case "spo2": d.spo2Pct
        default: nil
        }
    }
}

@MainActor
extension Repository {
    /// Resolves one calendar day from the active and canonical namespaces, then adds existing scores.
    func fusedDailyRecord(day: String, preferAbsoluteSkin: Bool) async -> FusedRecord {
        guard PerformanceContext.date(day) != nil, let store = await storeHandle() else {
            return FusedRecord(rows: [], dayOwner: nil, contributingSourceCount: 0, hadReadErrors: true)
        }
        // Do not attribute a different brand's active imported record to WHOOP.
        let whoopIds = importedReadIds.filter { $0 == Self.whoopSource || $0.hasPrefix("whoop-") }
        let namespaces: [(FusionSource, [String])] = [
            (.whoopImport, whoopIds),
            (.noopComputed, computedReadIds),
            (.appleHealth, [Self.appleHealthSource]),
            (.xiaomiBand, [FusionSource.xiaomiBand.rawValue])
        ]
        var sourceRows: [FusedRecordBuilder.SourceRows] = []
        var hadReadErrors = false
        for (source, ids) in namespaces {
            for id in ids {
                let rows: [DailyMetric]
                let points: [MetricPoint]
                do { rows = try await store.dailyMetrics(deviceId: id, from: day, to: day) }
                catch { rows = []; hadReadErrors = true }
                do { points = try await store.metricSeries(deviceId: id, from: day, to: day) }
                catch { points = []; hadReadErrors = true }
                sourceRows.append(.init(source: source, rows: rows, points: points))
                if source == .appleHealth {
                    // Older Health imports can exist only in the daily aggregate. Keep that
                    // as a fallback so an explicit series or daily metric still wins.
                    do {
                        let aggregates = try await store.appleDaily(deviceId: id, from: day, to: day)
                        let fallback = aggregates.flatMap { aggregate -> [MetricPoint] in
                            var result: [MetricPoint] = []
                            if let steps = aggregate.steps {
                                result.append(.init(day: aggregate.day, key: "steps", value: Double(steps)))
                            }
                            if let energy = aggregate.activeKcal {
                                result.append(.init(day: aggregate.day, key: "active_kcal", value: energy))
                            }
                            return result
                        }
                        sourceRows.append(.init(source: source, rows: [], points: fallback))
                    } catch { hadReadErrors = true }
                }
            }
        }
        let record = FusedRecordBuilder.build(day: day, sources: sourceRows, preferAbsoluteSkin: preferAbsoluteSkin)
        let scoreSpecs = [("sleep_performance", "Sleep score"), ("recovery", "Recovery score"), ("strain", "Strain")]
        var scores: [FusedScore] = []
        for (key, label) in scoreSpecs {
            let resolved = await resolvedSeries(key: key, source: Self.whoopSource, from: day, to: day)
            hadReadErrors = hadReadErrors || resolved.hadReadErrors
            if let point = resolved.points.first(where: { $0.day == day && $0.value.isFinite }) {
                let calculated: Bool? = point.source.hasSuffix("-noop") ? true :
                    (point.origin == .unknown ? nil : (key == "sleep_performance" && point.origin == .daily))
                scores.append(FusedScore(key: key, label: label, value: point.value,
                                         source: point.source, calculated: calculated))
            }
        }
        return FusedRecord(rows: record.rows, dayOwner: record.dayOwner,
                           contributingSourceCount: record.contributingSourceCount, scores: scores, hadReadErrors: hadReadErrors)
    }
}
