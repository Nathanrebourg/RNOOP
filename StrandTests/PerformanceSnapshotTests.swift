import XCTest
import Combine
import WhoopStore
@testable import Strand

@MainActor
final class PerformanceSnapshotTests: XCTestCase {
    private func row(_ day: String, efficiency: Double = 0.95, recovery: Double = 67) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: efficiency, deepMin: 60, remMin: 90,
                    lightMin: 300, disturbances: nil, restingHr: 52, avgHrv: 58, recovery: recovery,
                    strain: 30, exerciseCount: 0, spo2Pct: 97, skinTempDevC: 0.2,
                    respRateBpm: 15.2, skinTempC: 34.1)
    }

    func testStoredStressOnDayWithoutDailyRowIsNotCarriedFromAnotherDay() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        repo.days = (1...14).map { row(String(format: "2026-11-%02d", $0)) }
        _ = try await store.upsertMetricSeries([.init(day: "2026-11-15", key: "stress", value: 2.7)], deviceId: Repository.whoopSource)
        let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .today))
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context)
        XCTAssertNil(snapshot.daily)
        XCTAssertEqual(snapshot.stress, 2.7)
    }

    func testHomeReadsStoredNightlyDeviationAndDailyAppleFallbacksWithoutFutureValues() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        let night = row(day)
        repo.days = [night]
        _ = try await store.upsertDailyMetrics([night], deviceId: Repository.whoopSource + "-noop")
        _ = try await store.upsertAppleDaily([
            AppleDaily(day: day, steps: 4300, activeKcal: 230, basalKcal: nil, vo2max: 42,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-11-16", steps: 9999, activeKcal: 900, basalKcal: nil, vo2max: 70,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
        ], deviceId: Repository.appleHealthSource)
        _ = try await store.upsertMetricSeries([.init(day: "2026-10-01", key: "vo2max_est", value: 38)],
                                               deviceId: Repository.whoopSource + "-noop")

        let context = try XCTUnwrap(PerformanceContext(day: day, domain: .today))
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context)
        XCTAssertEqual(snapshot.value("skin_temp_delta"), 0.2)
        XCTAssertEqual(snapshot.value("resp_rate"), 15.2)
        XCTAssertEqual(snapshot.value("steps"), 4300)
        XCTAssertEqual(snapshot.value("active_kcal"), 230)
        XCTAssertEqual(snapshot.value("vo2max"), 42)
        XCTAssertEqual(snapshot.series["vo2max_est"]?.last?.value, 38)
        XCTAssertFalse(snapshot.series.values.flatMap { $0 }.contains { $0.day > day })
    }

    func testAbsoluteSkinTemperatureIsNeverPresentedAsDeviation() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        let imported = DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                   remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                                   avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil,
                                   skinTempDevC: 34.1)
        repo.days = [imported]
        _ = try await store.upsertDailyMetrics([imported], deviceId: Repository.whoopSource)
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo,
            context: PerformanceContext(day: day, domain: .today)!)
        XCTAssertNil(snapshot.value("skin_temp_delta"))
    }

    func testEmptyHomeMeasurementsStayUnavailable() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo,
            context: PerformanceContext(day: "2026-11-15", domain: .today)!)
        for key in ["skin_temp_delta", "resp_rate", "steps", "active_kcal", "vo2max", "vo2max_est"] {
            XCTAssertTrue((snapshot.series[key] ?? []).isEmpty, "\(key) must remain unavailable")
        }
    }

    func testHealthAliasesAndRequestedMetricReachTheDatedSeries() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        repo.days = [row("2026-11-15"), row("2026-11-16")]
        _ = try await store.upsertDailyMetrics(repo.days, deviceId: Repository.whoopSource)
        for (alias,key,expected) in [("resp","resp_rate",15.2),("skin","skin_temp",34.1),("spo2","spo2",97.0)] {
            let context = try XCTUnwrap(PerformanceContext(day: "2026-11-15", domain: .trend, metric: alias))
            XCTAssertEqual(context.metric, key)
            let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context)
            XCTAssertEqual(snapshot.value(key), expected, key)
            XCTAssertFalse((snapshot.series[key] ?? []).contains { $0.day > context.day })
        }
    }

    func testRawOxygenChannelIsNotCountedAsASixthVitalSign() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        repo.days = [row("2026-11-15")]
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: PerformanceContext(day: "2026-11-15", domain: .health)!)
        XCTAssertFalse(snapshot.vitals.contains { $0.key == "spo2raw" })
        XCTAssertLessThanOrEqual(snapshot.availableVitals.count, 5)
    }

    func testImportedOxygenRemainsAvailableWhenAComputedCandidateExists() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        _ = try await store.upsertMetricSeries([.init(day: day, key: "spo2", value: 98)],
                                               deviceId: Repository.whoopSource + "-noop")
        _ = try await store.upsertMetricSeries([.init(day: day, key: "spo2", value: 97)],
                                               deviceId: Repository.appleHealthSource)
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo,
            context: PerformanceContext(day: day, domain: .health)!)
        let imported = PerformanceHomeData.importedOxygen(snapshot.series["spo2_imported"] ?? [], on: day)
        XCTAssertEqual(imported?.value, 97)
        XCTAssertEqual(imported?.source, Repository.appleHealthSource)
        XCTAssertFalse(snapshot.vitals.contains { $0.key == "spo2" || $0.key == "spo2raw" })
    }

    func testSameDayAcrossScreensReusesSnapshotUntilRepositoryRefreshes() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        let initial = row(day, recovery: 67)
        _ = try await store.upsertDailyMetrics([initial], deviceId: Repository.whoopSource)
        repo.days = [initial]

        let today = try XCTUnwrap(PerformanceContext(day: day, domain: .today))
        let recovery = try XCTUnwrap(PerformanceContext(day: day, domain: .recovery))
        let firstScreen = PerformanceSnapshotModel()
        await firstScreen.load(repo: repo, context: today)
        XCTAssertEqual(firstScreen.snapshot?.value("recovery"), 67)

        // Data changed in the store without a repository refresh. A second screen must reuse the
        // existing revision; reading 72 here demonstrates the expensive capture ran again.
        _ = try await store.upsertDailyMetrics([row(day, recovery: 72)], deviceId: Repository.whoopSource)
        let secondScreen = PerformanceSnapshotModel()
        await secondScreen.load(repo: repo, context: recovery)
        XCTAssertEqual(secondScreen.snapshot?.context, recovery)
        XCTAssertEqual(secondScreen.snapshot?.value("recovery"), 67)

        await repo.refresh()
        await secondScreen.load(repo: repo, context: recovery)
        XCTAssertEqual(secondScreen.snapshot?.value("recovery"), 72)
    }

    func testCachedSnapshotsDoNotCrossCalendarDays() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let rows = [row("2026-11-14", recovery: 42), row("2026-11-15", recovery: 76)]
        _ = try await store.upsertDailyMetrics(rows, deviceId: Repository.whoopSource)
        repo.days = rows
        let screen = PerformanceSnapshotModel()
        await screen.load(repo: repo, context: PerformanceContext(day: "2026-11-14", domain: .today)!)
        XCTAssertEqual(screen.snapshot?.value("recovery"), 42)
        await screen.load(repo: repo, context: PerformanceContext(day: "2026-11-15", domain: .today)!)
        XCTAssertEqual(screen.snapshot?.value("recovery"), 76)
    }

    func testSleepEfficiencyIsPercentForTheDayAndItsTrendWithoutChangingStoredData() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let rows = [row("2026-11-14", efficiency: 0.96), row("2026-11-15", efficiency: 92)]
        _ = try await store.upsertDailyMetrics(rows, deviceId: Repository.whoopSource)
        repo.days = rows
        let context = PerformanceContext(day: "2026-11-15", domain: .trend, metric: "sleep_efficiency")!
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context)

        XCTAssertEqual(snapshot.value("sleep_efficiency"), 92)
        XCTAssertEqual(snapshot.series["sleep_efficiency"]?.first(where: { $0.day == "2026-11-14" })?.value, 96)
        let persisted = try await store.dailyMetrics(deviceId: Repository.whoopSource, from: "2026-11-14", to: "2026-11-15")
        XCTAssertEqual(persisted.first?.efficiency, 0.96)
    }

    func testImportedLowEfficienciesStayPercentWhileDailyFractionsAreConverted() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let rows = [row("2026-11-13", efficiency: 1.0), row("2026-11-14"), row("2026-11-15")]
        _ = try await store.upsertDailyMetrics(rows, deviceId: Repository.whoopSource)
        _ = try await store.upsertMetricSeries([
            .init(day: "2026-11-14", key: "sleep_efficiency", value: 0.5),
            .init(day: "2026-11-15", key: "sleep_efficiency", value: 1.0)
        ], deviceId: Repository.whoopSource)
        repo.days = rows
        let context = PerformanceContext(day: "2026-11-15", domain: .trend, metric: "sleep_efficiency")!
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context, scope: .trend)
        let values = Dictionary(uniqueKeysWithValues: (snapshot.series["sleep_efficiency"] ?? []).map { ($0.day, $0.value) })
        XCTAssertEqual(values["2026-11-13"], 100)
        XCTAssertEqual(values["2026-11-14"], 0.5)
        XCTAssertEqual(values["2026-11-15"], 1.0)
    }

    func testRefreshInvalidatesMetricSeriesEvenWhenDailyRowsDidNotChange() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let day = "2026-11-15"
        _ = try await store.upsertDailyMetrics([row(day)], deviceId: Repository.whoopSource)
        await repo.refresh()
        let context = PerformanceContext(day: day, domain: .effort)!
        let screen = PerformanceSnapshotModel()
        await screen.load(repo: repo, context: context)
        XCTAssertNil(screen.snapshot?.value("hr_zones13_min"))

        // This series is deliberately not a DailyMetric column and does not change refreshSeq.
        _ = try await store.upsertMetricSeries([.init(day: day, key: "hr_zones13_min", value: 25)],
                                              deviceId: Repository.whoopSource)
        let previousRefresh = repo.refreshSeq
        await repo.refresh()
        XCTAssertEqual(repo.refreshSeq, previousRefresh)
        await screen.load(repo: repo, context: context)
        XCTAssertEqual(screen.snapshot?.value("hr_zones13_min"), 25)
    }

    func testSnapshotCacheDoesNotShareDataAcrossRepositories() async throws {
        let a = try await WhoopStore.inMemory()
        let b = try await WhoopStore.inMemory()
        let first = Repository(deviceId: Repository.whoopSource)
        let second = Repository(deviceId: Repository.whoopSource)
        first.setStoreForTesting(a)
        second.setStoreForTesting(b)
        _ = try await a.upsertDailyMetrics([row("2026-11-15", recovery: 35)], deviceId: Repository.whoopSource)
        _ = try await b.upsertDailyMetrics([row("2026-11-15", recovery: 82)], deviceId: Repository.whoopSource)
        let context = PerformanceContext(day: "2026-11-15", domain: .today)!
        let screenA = PerformanceSnapshotModel()
        let screenB = PerformanceSnapshotModel()
        await screenA.load(repo: first, context: context)
        await screenB.load(repo: second, context: context)
        XCTAssertEqual(screenA.snapshot?.value("recovery"), 35)
        XCTAssertEqual(screenB.snapshot?.value("recovery"), 82)
    }

    func testSwitchingDevicesInvalidatesTheVisibleSnapshotImmediately() {
        let repo = Repository(deviceId: Repository.whoopSource)
        let before = repo.performanceSnapshotCache.revision
        XCTAssertTrue(repo.adoptActiveDeviceId("whoop-new-device"))
        XCTAssertGreaterThan(repo.performanceSnapshotCache.revision, before)
        let after = repo.performanceSnapshotCache.revision
        XCTAssertFalse(repo.adoptActiveDeviceId("whoop-new-device"))
        XCTAssertEqual(repo.performanceSnapshotCache.revision, after)
    }

    func testTodayWorkoutReadDoesNotScanTenYears() throws {
        let now = try XCTUnwrap(PerformanceSnapshotModel.localNoon("2026-11-16"))
        let today = PerformanceSnapshotModel.workoutLookbackDays(day: "2026-11-16", now: now)
        let earlier = PerformanceSnapshotModel.workoutLookbackDays(day: "2026-10-16", now: now)
        XCTAssertGreaterThanOrEqual(today, 1)
        XCTAssertLessThanOrEqual(today, 3)
        // The older requested day still fits, including a boundary buffer for deduplication.
        XCTAssertGreaterThanOrEqual(earlier, 31)
        XCTAssertLessThanOrEqual(earlier, 35)
    }

    func testTrendOnlyLoadReadsRequestedMetricWithoutBuildingUnrelatedScreens() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let sample = row("2026-11-15")
        _ = try await store.upsertDailyMetrics([sample], deviceId: Repository.whoopSource)
        repo.days = [sample]
        let context = PerformanceContext(day: sample.day, domain: .trend, metric: "hrv")!
        let snapshot = await PerformanceSnapshotModel.capture(repo: repo, context: context, scope: .trend)
        XCTAssertEqual(snapshot.value("hrv"), 58)
        XCTAssertNil(snapshot.series["recovery"])
        XCTAssertNil(snapshot.night)
        XCTAssertTrue(snapshot.workouts.isEmpty)
    }

    func testTrendOnlyLoadKeepsStoredStressAndSelectedSkinTemperature() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        let sample = row("2026-11-15")
        _ = try await store.upsertDailyMetrics([sample], deviceId: Repository.whoopSource)
        _ = try await store.upsertMetricSeries([.init(day: sample.day, key: "stress", value: 2.4)],
                                               deviceId: Repository.whoopSource)
        repo.days = [sample]
        let stress = PerformanceContext(day: sample.day, domain: .trend, metric: "stress")!
        let skin = PerformanceContext(day: sample.day, domain: .trend, metric: "skin_temp")!
        let stressSnapshot = await PerformanceSnapshotModel.capture(repo: repo, context: stress, scope: .trend)
        let skinSnapshot = await PerformanceSnapshotModel.capture(repo: repo, context: skin, scope: .trend)
        XCTAssertEqual(stressSnapshot.value("stress"), 2.4)
        XCTAssertEqual(stressSnapshot.stress, 2.4)
        XCTAssertNotNil(skinSnapshot.value("skin_temp"))
    }

    func testUnchangedRefreshDoesNotRepublishTheWholeRepository() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: Repository.whoopSource)
        repo.setStoreForTesting(store)
        _ = try await store.upsertDailyMetrics([row("2026-11-15")], deviceId: Repository.whoopSource)
        await repo.refresh()
        let sequence = repo.refreshSeq
        let cacheRevision = repo.performanceSnapshotCache.revision
        var notifications = 0
        let observer = repo.objectWillChange.sink { notifications += 1 }
        await repo.refresh()
        XCTAssertEqual(repo.refreshSeq, sequence)
        XCTAssertEqual(repo.performanceSnapshotCache.revision, cacheRevision)
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(observer) {}
    }

    func testCancelledScreenStopsItsUnsharedCapture() async throws {
        let repo = Repository(deviceId: Repository.whoopSource)
        let context = PerformanceContext(day: "2026-11-15", domain: .today)!
        var started = false
        var stopped = false
        let cache = PerformanceSnapshotCache { _, context, _ in
            started = true
            do { try await Task.sleep(nanoseconds: 250_000_000) }
            catch { stopped = true }
            return PerformanceSnapshot(context: context)
        }
        let reader = Task { await cache.value(repo: repo, context: context) }
        while !started { await Task.yield() }
        reader.cancel()
        _ = await reader.value
        XCTAssertTrue(stopped)
    }

    func testCancellingOneScreenDoesNotCancelAnotherScreenSharingTheCapture() async throws {
        let repo = Repository(deviceId: Repository.whoopSource)
        let context = PerformanceContext(day: "2026-11-15", domain: .today)!
        var starts = 0
        var stopped = false
        let cache = PerformanceSnapshotCache { _, context, _ in
            starts += 1
            do { try await Task.sleep(nanoseconds: 200_000_000) }
            catch { stopped = true }
            return PerformanceSnapshot(context: context)
        }
        let first = Task { await cache.value(repo: repo, context: context) }
        while starts == 0 { await Task.yield() }
        let second = Task { await cache.value(repo: repo, context: context) }
        await Task.yield()
        first.cancel()
        _ = await second.value
        _ = await first.value
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(stopped)
    }

    func testFailedCaptureIsNotKeptAsAnEmptySnapshot() async throws {
        let repo = Repository(deviceId: Repository.whoopSource)
        let context = PerformanceContext(day: "2026-11-15", domain: .today)!
        var calls = 0
        let cache = PerformanceSnapshotCache { _, context, _ in
            calls += 1
            return PerformanceSnapshot(context: context, hadReadErrors: calls == 1)
        }
        _ = await cache.value(repo: repo, context: context)
        _ = await cache.value(repo: repo, context: context)
        XCTAssertEqual(calls, 2)
    }

    func testStoreChangeStampTracksSameAndOtherDatabaseConnections() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("test.sqlite").path
        let first = try await WhoopStore(path: database)
        let second = try await WhoopStore(path: database)
        let initial = try await first.performanceChangeStamp()
        let unchanged = try await first.performanceChangeStamp()
        XCTAssertEqual(initial, unchanged)
        _ = try await first.upsertMetricSeries([.init(day: "2026-11-15", key: "stress", value: 1.5)],
                                               deviceId: Repository.whoopSource)
        let ownWrite = try await first.performanceChangeStamp()
        XCTAssertNotEqual(unchanged, ownWrite)
        _ = try await second.upsertMetricSeries([.init(day: "2026-11-15", key: "stress", value: 2.1)],
                                                deviceId: Repository.whoopSource)
        let otherWrite = try await first.performanceChangeStamp()
        XCTAssertNotEqual(ownWrite, otherWrite)
    }
}
