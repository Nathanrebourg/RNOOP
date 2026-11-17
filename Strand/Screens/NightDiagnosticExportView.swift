import SwiftUI
import StrandDesign

/// Apple-only diagnostic sharing; no stored score, setting or Bluetooth command is changed.
struct NightDiagnosticExportView: View {
    @EnvironmentObject var model: AppModel
    @State private var date = Date()
    @State private var busy = false
    @State private var prepared: NightDiagnosticExport.Result?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScreenScaffold(title: "Night diagnostic", subtitle: "Inspect signal gaps and export a replayable night from this device.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        DatePicker("Wake date", selection: $date, in: ...Date(), displayedComponents: .date)
                            .font(StrandFont.body)
                            .disabled(busy)
                        Text("Uses the time zone currently selected on this device. Days that change UTC offset cannot be represented by fixed-offset replay.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        NoopButton(busy ? "Preparing…" : "Inspect this night", systemImage: "waveform.path.ecg", kind: .secondary) { prepare() }
                            .disabled(busy)
                    }
                }
                if let prepared {
                    StrandCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                            Text("Signal availability").font(StrandFont.headline)
                            Text("HR: \(prepared.hrRows) rows · Motion: \(prepared.motionRows) rows · R-R: \(prepared.rrRows) rows")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            Text("Counts cover the replay read window, including the preceding night. Availability is not sleep-stage accuracy.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            Text("Durations count 30-second cells containing at least one usable sample, rather than continuous measurement.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            if prepared.coverage.isEmpty {
                                Text("No computed sleep session ends on this date. Session coverage is unavailable; stored raw signals can still be exported.")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            }
                            ForEach(Array(prepared.coverage.enumerated()), id: \.offset) { _, coverage in
                                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                                    Text("\(time(coverage.start))–\(time(coverage.end))")
                                        .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                                    if coverage.status == "observed" {
                                        Text("No HR or motion: \(minutes(coverage.unknownSeconds)) min · HR only: \(minutes(coverage.hrOnlySeconds)) min · Motion only: \(minutes(coverage.motionOnlySeconds)) min · Both: \(minutes(coverage.bothSeconds)) min")
                                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                                        ForEach(Array(coverage.intervals.filter { $0.kind == "unknown" }.prefix(20).enumerated()), id: \.offset) { _, interval in
                                            Text("Indeterminate: \(time(interval.start))–\(time(interval.end))")
                                                .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                                        }
                                        if coverage.intervals.filter({ $0.kind == "unknown" }).count > 20 {
                                            Text("Additional gaps are listed in the diagnostic ZIP.")
                                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                                        }
                                    } else {
                                        Text("This session is too long for the coverage diagnostic. Availability is unknown.")
                                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                                    }
                                }
                            }
                        }
                    }
                    StrandCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                            Text("Local diagnostic ZIP").font(StrandFont.headline)
                            Text("Includes stored signals, current settings, replay baselines and computed results. Original scoring settings and final app baselines are not stored, so replay can differ from the displayed score.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            Text("The ZIP is unencrypted and contains sensitive health data and timestamps. Source identifiers are pseudonymized. Choose where to save or share it.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            NoopButton("Export diagnostic ZIP", systemImage: "square.and.arrow.up", kind: .secondary) { export(prepared) }
                                .disabled(busy)
                        }
                    }
                }
                if let failure {
                    Text(failure).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                }
            }
        }
        .onChangeCompat(of: date) { _ in prepared = nil; failure = nil }
        .onDisappear { task?.cancel() }
    }

    private func prepare() {
        task?.cancel()
        busy = true; failure = nil; prepared = nil
        let selected = date, zone = TimeZone.current
        let settings = NightDiagnosticExport.Settings(age: Double(model.profile.age), sex: model.profile.sex,
            manualHRmax: model.profile.hrMaxOverride > 0 ? Double(model.profile.hrMaxOverride) : nil,
            useV2: PuffinExperiment.experimentalSleepV2Enabled,
            deepWindow: UserDefaults.standard.string(forKey: UnitPrefs.hrvWindowKey) == HrvWindow.deep.rawValue,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
        task = Task {
            defer { busy = false }
            guard let store = await model.repo.storeHandle() else {
                failure = String(localized: "No on-device store is available yet."); return
            }
            do {
                let result = try await NightDiagnosticExport.capture(store: store, date: selected, timeZone: zone,
                    now: Int(Date().timeIntervalSince1970), settings: settings)
                try Task.checkCancellation()
                prepared = result
            } catch is CancellationError {
                // Leaving the screen cancels preparation without presenting an error.
            } catch { failure = error.localizedDescription }
        }
    }

    private func export(_ prepared: NightDiagnosticExport.Result) {
        busy = true; failure = nil
        task = Task {
            let url = await FileExport.exportBundle(entries: prepared.entries, suggestedName: prepared.suggestedName, strict: true) { busy = false }
            #if os(macOS)
            busy = false
            #endif
            if url == nil { busy = false }
        }
    }

    private func time(_ seconds: Int) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(seconds)))
    }
    private func minutes(_ seconds: Int) -> String { String(format: "%.1f", Double(seconds) / 60) }
}
