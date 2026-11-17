import Foundation
import CryptoKit
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// A user-triggered, read-only replay capture. This format is not a backup or an upload.
enum NightDiagnosticExport {
    struct Settings: Codable, Sendable {
        let age: Double
        let sex: String
        let manualHRmax: Double?
        let useV2: Bool
        let deepWindow: Bool
        let appVersion: String
        let build: String
    }
    struct Window: Sendable { let day: String; let start: Int; let end: Int; let offset: Int }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    struct HR: Codable { let ts: Int; let bpm: Int }
    struct Motion: Codable { let ts: Int; let x: Double; let y: Double; let z: Double }
    struct Event: Codable { let ts: Int; let kind: String }
    struct Band: Codable { let ts: Int; let state: Int }
    struct Night: Encodable {
        let dayStart: Int
        let source = "computed"
        let hours: Double?
        let hrv: Double?
        let rhr: Double?
        let resp: Double?
    }
    struct Recording: Encodable {
        let schema = 1
        let origin = "recorded"
        let caseID: String
        let owner: String
        let dayStart: Int
        let now: Int
        let offset: Int
        let age: Double
        let sex: String
        let manualHRmax: Double?
        let useV2: Bool
        let deepWindow: Bool
        let rrIdentity = "store-key-v1"
        let hr: [HR]
        let gravity: [Motion]
        let rr: [RRInterval]
        let events: [Event]
        let band: [Band]
        let history: [Night]
        let historyStreams: [String] = []
        let warnings: [String]
    }
    struct Session: Codable {
        let start: Int
        let end: Int
        let userEdited: Bool
        let stagingSparse: Bool?
        let stagesJSON: String?
    }
    struct AppSnapshot: Encodable {
        let schema = 1
        let scope = "persisted-canonical-computed-cache; not replay output"
        let actualScoringBaselines = "unavailable: per-night final engine baseline is not persisted"
        let settingsScope = "settings at export time; original scoring settings are not persisted"
        let daily: [DailyMetric]
        let sessions: [Session]
    }
    struct Baseline: Encodable {
        let baseline: Double
        let spread: Double
        let nValid: Int
        let nightsSinceUpdate: Int
        let status: String
        init(_ state: BaselineState) {
            baseline = state.baseline; spread = state.spread; nValid = state.nValid
            nightsSinceUpdate = state.nightsSinceUpdate; status = state.status.rawValue
        }
    }
    struct ReplayBaselines: Encodable {
        let scope = "strictly-prior-computed-30-calendar-days; replay-only; not actual final app baselines"
        let hrv: Baseline
        let restingHR: Baseline
        let respiration: Baseline
    }
    struct CoverageInterval: Codable { let start: Int; let end: Int; let kind: String }
    struct Coverage: Codable {
        let start: Int
        let end: Int
        let status: String
        let unknownSeconds: Int
        let hrOnlySeconds: Int
        let motionOnlySeconds: Int
        let bothSeconds: Int
        let intervals: [CoverageInterval]
    }
    struct CoverageFile: Encodable {
        let schema = 1
        let scope = "raw HR/motion availability in persisted computed sessions; not stage accuracy or confidence"
        let sessions: [Coverage]
    }
    struct Manifest: Encodable {
        let schema = 1
        let format = "nroop-night-diagnostic-v1"
        let replayModel = "nroop-lab-v1"
        let researchModel = "nroop-research-v1"
        let day: String
        let timeZone: String
        let offset: Int
        let capturedAt: Int
        let owner: String
        let identityScope = "installation-and-source; stable until preferences reset or reinstall; not proof of a distinct person"
        let settings: Settings
        let snapshotConsistency = "separate bounded reads; matching change witnesses; not an atomic database snapshot"
        let witnessSHA256: String
        let sha256: [String: String]
        let warnings: [String]
    }
    struct Result {
        let entries: [FileExport.BundleEntry]
        let suggestedName: String
        let coverage: [Coverage]
        let hrRows: Int
        let motionRows: Int
        let rrRows: Int
    }

    static func window(date: Date, timeZone: TimeZone, now: Int) throws -> Window {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = calendar.startOfDay(for: date)
        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            throw Failure(String(localized: "This date cannot be exported."))
        }
        let start = Int(startDate.timeIntervalSince1970), next = Int(nextDate.timeIntervalSince1970)
        let offset = timeZone.secondsFromGMT(for: startDate)
        guard next - start == 86_400, timeZone.secondsFromGMT(for: nextDate) == offset else {
            throw Failure(String(localized: "This civil day changes UTC offset. Fixed-offset replay cannot represent it without losing or repeating an hour."))
        }
        guard (946_684_800...4_102_444_800).contains(start), now > start else {
            throw Failure(String(localized: "Choose a day that has already started."))
        }
        return Window(day: AnalyticsEngine.dayString(start, offsetSec: offset), start: start, end: min(now, next), offset: offset)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let identityLock = NSLock()
    /// The random installation token is deliberately absent from the backup settings whitelist and ZIP.
    /// Stability prevents separate exports from masquerading as independent people in research tools.
    static func installationSalt(defaults: UserDefaults = .standard) -> String {
        identityLock.lock(); defer { identityLock.unlock() }
        let key = "nightDiagnostic.installationSalt.v1"
        if let salt = defaults.string(forKey: key), UUID(uuidString: salt) != nil { return salt }
        let salt = UUID().uuidString
        defaults.set(salt, forKey: key)
        return salt
    }
    static func pseudonym(owner: String, salt: String) -> String {
        sha256(Data(("nroop-night-owner-v1:" + salt + ":" + owner).utf8))
    }

    static func capture(store: WhoopStore, date: Date, timeZone: TimeZone, now: Int, settings: Settings) async throws -> Result {
        let window = try window(date: date, timeZone: timeZone, now: now)
        guard settings.age.isFinite, (0...120).contains(settings.age),
              settings.manualHRmax == nil || (settings.manualHRmax!.isFinite && (30...250).contains(settings.manualHRmax!)) else {
            throw Failure(String(localized: "Check your age and maximum heart rate before exporting."))
        }
        try Task.checkCancellation()
        let fingerprint = try await store.analysisFingerprint()
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        let devices = try registry.all()
        let active = try registry.activeDeviceId() ?? Repository.whoopSource
        let from = window.start - 108_000
        let owner = await IntelligenceEngine.resolveDayOwner(day: window.day, from: from, to: window.end,
            store: store, devices: devices, activeId: active, registry: registry, fallbackDeviceId: Repository.whoopSource)
        guard try await store.isWhoop5RRSource(deviceId: owner) else {
            throw Failure(String(localized: "This replay export currently requires a confirmed WHOOP 5.0 or MG source."))
        }
        let computed = Repository.whoopSource + "-noop"
        let since = AnalyticsEngine.dayString(window.start - 30 * 86_400, offsetSec: window.offset)
        let until = AnalyticsEngine.dayString(window.start - 1, offsetSec: window.offset)
        let current = try await store.dailyMetrics(deviceId: computed, from: window.day, to: window.day)
        let historyRows = try await store.dailyMetrics(deviceId: computed, from: since, to: until)
        let sessions = try await store.sleepSessions(deviceId: computed, from: from, to: window.end, limit: 501)
        guard sessions.count < 501 else { throw Failure(String(localized: "Too many sleep sessions for one diagnostic. No truncated export was created.")) }
        let hr = try await store.hrSamples(deviceId: owner, from: from, to: window.end, limit: 300_001)
        let gravity = try await store.gravitySamples(deviceId: owner, from: from, to: window.end, limit: 300_001)
        let rr = try await store.rrIntervals(deviceId: owner, from: from, to: window.end, limit: 400_001)
        let events = try await store.events(deviceId: owner, from: from, to: window.end, limit: 50_001)
        let band = try await store.sleepStateSamples(deviceId: owner, from: from, to: window.end, limit: 300_001)
        guard hr.count <= 300_000, gravity.count <= 300_000, rr.count <= 400_000,
              hr.count + gravity.count + rr.count <= 1_000_000, events.count <= 50_000, band.count <= 300_000 else {
            throw Failure(String(localized: "This night exceeds the diagnostic size limit. No truncated export was created."))
        }
        guard !hr.isEmpty || !gravity.isEmpty else {
            throw Failure(String(localized: "No heart rate or motion samples are available for this night."))
        }
        guard hr.allSatisfy({ (0...300).contains($0.bpm) }), gravity.allSatisfy({
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 && abs($0.z) <= 1_000_000
        }), rr.allSatisfy({ [5, 7].contains($0.srcChannel?.rawValue ?? -1) && (0...65_535).contains($0.rrMs) && $0.seq >= 0 && ($0.ord == nil || $0.ord! >= 0) }),
        Set(rr.compactMap { $0.srcChannel?.rawValue }).count <= 1, band.allSatisfy({ (0...3).contains($0.state) }) else {
            throw Failure(String(localized: "Some sensor values or R-R sources are not compatible with replay. The export was refused without altering them."))
        }
        let parser = ISO8601DateFormatter()
        let history = try historyRows.map { row -> Night in
            guard let date = parser.date(from: row.day + "T00:00:00Z") else { throw Failure("Invalid stored history date") }
            return Night(dayStart: Int(date.timeIntervalSince1970) - window.offset,
                hours: row.totalSleepMin.map { $0 / 60 }, hrv: row.avgHrv, rhr: row.restingHr.map(Double.init), resp: row.respRateBpm)
        }
        guard history.count <= 30, Set(history.map(\.dayStart)).count == history.count,
              history.allSatisfy({ $0.dayStart >= window.start - 30 * 86_400 && $0.dayStart < window.start
                  && (window.start - $0.dayStart) % 86_400 == 0
                  && [$0.hours, $0.hrv, $0.rhr, $0.resp].compactMap { $0 }.allSatisfy(\.isFinite) }) else {
            throw Failure(String(localized: "Stored baseline history is invalid. No diagnostic was created."))
        }
        let ownSessions = sessions.filter { $0.endTs > window.start && $0.endTs <= window.end }
        let coverage: [Coverage] = ownSessions.compactMap { session in
            let start = max(from, session.effectiveStartTs), end = min(window.end, session.endTs)
            guard end > start else { return nil }
            let result = SleepSignalCoverage.analyze(start: start, end: end, hr: hr, gravity: gravity)
            return Coverage(start: start, end: end, status: result.status,
                unknownSeconds: result.unknownSeconds, hrOnlySeconds: result.hrOnlySeconds,
                motionOnlySeconds: result.motionOnlySeconds, bothSeconds: result.bothSeconds,
                intervals: result.intervals.map { CoverageInterval(start: $0.start, end: $0.end, kind: $0.kind) })
        }
        let fingerprintAfter = try await store.analysisFingerprint()
        let currentAfter = try await store.dailyMetrics(deviceId: computed, from: window.day, to: window.day)
        let historyAfter = try await store.dailyMetrics(deviceId: computed, from: since, to: until)
        let sessionsAfter = try await store.sleepSessions(deviceId: computed, from: from, to: window.end, limit: 501)
        guard fingerprint == fingerprintAfter, current == currentAfter, historyRows == historyAfter, sessions == sessionsAfter,
              devices == (try registry.all()), active == (try registry.activeDeviceId() ?? Repository.whoopSource) else {
            throw Failure(String(localized: "The stored data changed while preparing the night. Wait for synchronization to finish and try again."))
        }
        try Task.checkCancellation()
        let nonce = UUID().uuidString
        let pseudonym = pseudonym(owner: owner, salt: installationSalt())
        var warnings = [
            "Capture settings are current, not the unpersisted original scoring recipe.",
            "Replay uses detected sleep and strictly prior computed baselines. App cache may include imported or manually edited sleep and different final baselines.",
            "Historical quality witnesses, free-text journal, alarm answers and seven raw HRmax days are omitted. Quality-history and contextual-need candidates may be unavailable.",
            "This is a bounded local snapshot of currently stored samples, not proof that strap synchronization is complete.",
            "Times, age, sex and physiological measurements remain sensitive even though source identifiers are pseudonymized.",
            "Owner identity links only this installation and source. A reset, reinstall or another phone breaks linkage; it is not proof of an independent person."
        ]
        if window.end < window.start + 86_400 { warnings.append("Current day is still in progress; replay is provisional.") }
        if ownSessions.isEmpty { warnings.append("No persisted computed sleep session ends on this date; session coverage is unavailable.") }
        let recording = Recording(caseID: "night-" + window.day + "-" + String(nonce.prefix(8)), owner: pseudonym,
            dayStart: window.start, now: window.end, offset: window.offset, age: settings.age, sex: settings.sex,
            manualHRmax: settings.manualHRmax, useV2: settings.useV2, deepWindow: settings.deepWindow,
            hr: hr.map { HR(ts: $0.ts, bpm: $0.bpm) }, gravity: gravity.map { Motion(ts: $0.ts, x: $0.x, y: $0.y, z: $0.z) },
            rr: rr, events: events.map { Event(ts: $0.ts, kind: $0.kind) }, band: band.map { Band(ts: $0.ts, state: $0.state) },
            history: history, warnings: warnings)
        let app = AppSnapshot(daily: current, sessions: ownSessions.map { Session(start: $0.effectiveStartTs, end: $0.endTs,
            userEdited: $0.userEdited, stagingSparse: $0.stagingSparse, stagesJSON: $0.stagesJSON) })
        func fold(_ key: String, value: (Night) -> Double?) -> Baseline {
            let byDay = Dictionary(uniqueKeysWithValues: history.map { ($0.dayStart, $0) })
            let padded = (1...30).reversed().map { back in byDay[window.start - back * 86_400].flatMap(value) }
            return Baseline(Baselines.foldHistory(padded, cfg: Baselines.metricCfg[key]!))
        }
        let baselines = ReplayBaselines(hrv: fold("hrv", value: { $0.hrv }), restingHR: fold("resting_hr", value: { $0.rhr }), respiration: fold("resp", value: { $0.resp }))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var entries = [
            FileExport.BundleEntry(name: "recording.json", data: try encoder.encode(recording)),
            FileExport.BundleEntry(name: "app-snapshot.json", data: try encoder.encode(app)),
            FileExport.BundleEntry(name: "replay-baselines.json", data: try encoder.encode(baselines)),
            FileExport.BundleEntry(name: "coverage.json", data: try encoder.encode(CoverageFile(sessions: coverage))),
            FileExport.BundleEntry(name: "README.txt", data: Data("""
            NOOP night diagnostic v1
            This ZIP is unencrypted. It contains sensitive physiological data and timestamps.
            No NOOP server or upload is involved. Sharing only happens through your chosen destination.
            recording.json is an AlgorithmReplay schema 1 input. Verify its SHA256 against manifest.json before replay.
            app-snapshot.json contains persisted on-device computed rows, not a recalculated score.
            replay-baselines.json describes the strictly prior 30-day replay baselines, not the app's unpersisted final baseline.
            coverage.json names HR/motion availability per 30-second epoch in persisted computed sleep sessions. Unknown means neither signal was available; it is not a predicted sleep stage.
            Current settings are recorded because original per-night settings are not persisted. The replay cannot reproduce imported/manual sessions or omitted sensor models exactly.
            A matching change witness detects common concurrent writes but these are separate reads, not an atomic database transaction.
            """.utf8))
        ]
        let manifest = Manifest(day: window.day, timeZone: timeZone.identifier, offset: window.offset, capturedAt: now,
            owner: pseudonym, settings: settings, witnessSHA256: sha256(Data(fingerprint.utf8)),
            sha256: Dictionary(uniqueKeysWithValues: entries.map { ($0.name, sha256($0.data)) }), warnings: warnings)
        entries.append(.init(name: "manifest.json", data: try encoder.encode(manifest)))
        guard entries.reduce(0, { $0 + $1.data.count }) <= 128 * 1024 * 1024 else {
            throw Failure(String(localized: "This night exceeds the diagnostic size limit. No truncated export was created."))
        }
        return Result(entries: entries, suggestedName: "NOOP-night-" + window.day + "-" + String(nonce.prefix(8)) + ".zip",
            coverage: coverage, hrRows: hr.count, motionRows: gravity.count, rrRows: rr.count)
    }
}
