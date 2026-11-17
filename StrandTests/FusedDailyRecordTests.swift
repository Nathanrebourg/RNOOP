import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

final class FusedDailyRecordTests: XCTestCase {
    private func row(_ day: String, sleep: Double? = nil, efficiency: Double? = nil,
                     deep: Double? = nil, rem: Double? = nil, light: Double? = nil,
                     rhr: Int? = nil, hrv: Double? = nil, respiratory: Double? = nil,
                     steps: Int? = nil, kcal: Double? = nil,
                     skinDeviation: Double? = nil, skinAbsolute: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: efficiency, deepMin: deep,
                    remMin: rem, lightMin: light, disturbances: nil, restingHr: rhr, avgHrv: hrv,
                    recovery: nil, strain: nil, exerciseCount: nil, skinTempDevC: skinDeviation,
                    respRateBpm: respiratory, steps: steps, activeKcalEst: kcal, skinTempC: skinAbsolute)
    }

    func testAvailableDailyMeasurementsIncludeSleepStagesAndRespiration() {
        let day = "2026-11-15"
        let sample = row(day, sleep: 450, efficiency: 0.94, deep: 80, rem: 100, light: 270,
                         rhr: 52, hrv: 64, respiratory: 14.2, steps: 1200, kcal: 210,
                         skinDeviation: 0.3, skinAbsolute: 34.2)
        let record = FusedRecordBuilder.build(day: day,
            sources: [.init(source: .noopComputed, rows: [sample])], preferAbsoluteSkin: true)
        let values = Dictionary(uniqueKeysWithValues: record.rows.map { ($0.point.metric, $0.point.value) })
        XCTAssertEqual(values["sleep_total_min"], 450)
        XCTAssertEqual(values["sleep_deep_min"], 80)
        XCTAssertEqual(values["sleep_rem_min"], 100)
        XCTAssertEqual(values["sleep_light_min"], 270)
        XCTAssertEqual(values["sleep_efficiency"], 94)
        XCTAssertEqual(values["resp_rate"], 14.2)
        XCTAssertEqual(values["active_kcal"], 210)
        XCTAssertEqual(values["skin_temp"], 34.2)
        XCTAssertNil(values["spo2"])
    }

    func testNeverFusesDifferentCalendarDaysAsIfTheyWereTheSameDay() {
        let day = "2026-11-15"
        let current = row(day, hrv: 55)
        let earlier = row("2026-11-14", hrv: 100, respiratory: 19)
        let future = row("2026-11-16", hrv: 110)
        let record = FusedRecordBuilder.build(day: day, sources: [
            .init(source: .noopComputed, rows: [current]),
            .init(source: .whoopImport, rows: [earlier, future])
        ], preferAbsoluteSkin: true)
        let hrv = record.rows.first { $0.point.metric == "hrv" }?.point
        XCTAssertEqual(hrv?.value, 55)
        XCTAssertEqual(hrv?.contributors.count, 1)
        XCTAssertNil(record.rows.first { $0.point.metric == "resp_rate" })
    }

    func testSameSourceNamespacesFillMissingFieldsWithoutDuplicateContributors() {
        let day = "2026-11-15"
        let active = row(day, hrv: 61)
        let canonical = row(day, sleep: 420, hrv: 90)
        let record = FusedRecordBuilder.build(day: day,
            sources: [.init(source: .noopComputed, rows: [active]),
                      .init(source: .noopComputed, rows: [canonical])], preferAbsoluteSkin: true)
        XCTAssertEqual(record.rows.first { $0.point.metric == "hrv" }?.point.value, 61)
        XCTAssertEqual(record.rows.first { $0.point.metric == "sleep_total_min" }?.point.value, 420)
        XCTAssertEqual(record.rows.first { $0.point.metric == "hrv" }?.point.contributors.count, 1)
    }

    func testSleepStagesAreNotBorrowedFromADifferentNightInAnotherNamespace() {
        let day = "2026-11-15"
        let active = row(day, sleep: 480)
        let olderNamespace = row(day, sleep: 360, deep: 120)
        let record = FusedRecordBuilder.build(day: day, sources: [
            .init(source: .noopComputed, rows: [active]),
            .init(source: .noopComputed, rows: [olderNamespace])
        ], preferAbsoluteSkin: true)
        XCTAssertEqual(record.rows.first { $0.point.metric == "sleep_total_min" }?.point.value, 480)
        XCTAssertNil(record.rows.first { $0.point.metric == "sleep_deep_min" })
    }

    func testAbsoluteTemperatureIsNeverComparedToADeviation() {
        let day = "2026-11-15"
        let absolute = row(day, skinAbsolute: 34.4)
        let deviation = row(day, skinDeviation: 0.2)
        let sources: [FusedRecordBuilder.SourceRows] = [
            .init(source: .whoopImport, rows: [absolute]),
            .init(source: .noopComputed, rows: [deviation])
        ]
        let inAbsolute = FusedRecordBuilder.build(day: day, sources: sources, preferAbsoluteSkin: true)
        let inDeviation = FusedRecordBuilder.build(day: day, sources: sources, preferAbsoluteSkin: false)
        let absPoint = inAbsolute.rows.first { $0.point.metric == "skin_temp" }?.point
        let devPoint = inDeviation.rows.first { $0.point.metric == "skin_temp" }?.point
        XCTAssertEqual(absPoint?.value, 34.4)
        XCTAssertEqual(absPoint?.contributors.count, 1)
        XCTAssertEqual(devPoint?.value, 0.2)
        XCTAssertEqual(devPoint?.contributors.count, 1)
    }

    @MainActor
    func testStoreLoaderUnionsActiveAndCanonicalSourcesOnTheRequestedDay() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "whoop-test-strap")
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        _ = try await store.upsertDailyMetrics([row(day, hrv: 61, respiratory: 14.2)],
                                               deviceId: "whoop-test-strap-noop")
        _ = try await store.upsertDailyMetrics([row(day, sleep: 420, hrv: 90)],
                                               deviceId: Repository.whoopSource + "-noop")
        _ = try await store.upsertDailyMetrics([row("2026-11-14", hrv: 110)],
                                               deviceId: Repository.appleHealthSource)
        _ = try await store.upsertMetricSeries([.init(day: day, key: "sleep_performance", value: 77),
                                                .init(day: day, key: "strain", value: 50)],
                                               deviceId: Repository.whoopSource + "-noop")

        let record = await repo.fusedDailyRecord(day: day, preferAbsoluteSkin: true)
        XCTAssertEqual(record.rows.first { $0.point.metric == "hrv" }?.point.value, 61)
        XCTAssertEqual(record.rows.first { $0.point.metric == "sleep_total_min" }?.point.value, 420)
        XCTAssertEqual(record.rows.first { $0.point.metric == "hrv" }?.point.contributors.count, 1)
        XCTAssertEqual(record.scores.first { $0.key == "sleep_performance" }?.value, 77)
        XCTAssertEqual(record.scores.first { $0.key == "strain" }?.value, 50)
        XCTAssertNil(record.scores.first { $0.key == "recovery" })
    }

    @MainActor
    func testStoreLoaderIncludesMetricsStoredOnlyInImportedSeries() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        _ = try await store.upsertDailyMetrics([row(day, steps: 3000)], deviceId: Repository.whoopSource + "-noop")
        _ = try await store.upsertMetricSeries([.init(day: day, key: "steps", value: 5400),
                                                .init(day: day, key: "energy_kcal", value: 250)],
                                               deviceId: FusionSource.xiaomiBand.rawValue)
        _ = try await store.upsertMetricSeries([.init(day: day, key: "active_kcal", value: 230)],
                                               deviceId: Repository.appleHealthSource)
        let record = await repo.fusedDailyRecord(day: day, preferAbsoluteSkin: true)
        let steps = record.rows.first { $0.point.metric == "steps" }?.point
        let energy = record.rows.first { $0.point.metric == "active_kcal" }?.point
        XCTAssertEqual(steps?.value, 5400)
        XCTAssertEqual(steps?.winningSource, .xiaomiBand)
        XCTAssertEqual(energy?.value, 230)
        XCTAssertEqual(energy?.winningSource, .appleHealth)
    }

    @MainActor
    func testStoreLoaderIncludesAppleDailyWhenSeriesAreMissingWithoutMixingDays() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        _ = try await store.upsertAppleDaily([
            AppleDaily(day: day, steps: 4100, activeKcal: 215, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-11-14", steps: 9900, activeKcal: 600, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
        ], deviceId: Repository.appleHealthSource)
        _ = try await store.upsertMetricSeries([.init(day: day, key: "steps", value: 4300)],
                                               deviceId: Repository.appleHealthSource)
        let record = await repo.fusedDailyRecord(day: day, preferAbsoluteSkin: true)
        XCTAssertEqual(record.rows.first { $0.point.metric == "steps" }?.point.value, 4300)
        XCTAssertEqual(record.rows.first { $0.point.metric == "active_kcal" }?.point.value, 215)
        XCTAssertEqual(record.rows.first { $0.point.metric == "active_kcal" }?.point.winningSource, .appleHealth)
    }

    @MainActor
    func testLocallyDerivedSleepScoreIsNotDescribedAsAnImportedScore() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        let night = row(day, sleep: 450, efficiency: 0.95, deep: 80, rem: 100, light: 270)
        _ = try await store.upsertDailyMetrics([night], deviceId: Repository.whoopSource)
        let derived = await repo.fusedDailyRecord(day: day, preferAbsoluteSkin: true)
        XCTAssertEqual(derived.scores.first { $0.key == "sleep_performance" }?.calculated, true)

        _ = try await store.upsertMetricSeries([.init(day: day, key: "sleep_performance", value: 77)],
                                               deviceId: Repository.whoopSource)
        let imported = await repo.fusedDailyRecord(day: day, preferAbsoluteSkin: true)
        XCTAssertEqual(imported.scores.first { $0.key == "sleep_performance" }?.calculated, false)
    }
}
