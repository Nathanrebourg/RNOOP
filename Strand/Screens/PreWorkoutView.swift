import SwiftUI
import StrandDesign
import StrandAnalytics

/// WHOOP-style "before you start" screen: the live strap heart rate, its zone, and today's effort
/// guide from the real recovery score. Nothing is recorded until Start is tapped.
struct PreWorkoutView: View {
    let sport: String
    let onStart: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject var model: AppModel

    private var today: String { Repository.logicalDayKey(Date()) }
    private var zoneSet: HRZoneSet { model.profile.hrZoneSet }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NoopMetrics.space5) {
                    Text(WorkoutSource.displaySport(sport).uppercased())
                        .font(StrandFont.headline).tracking(1)
                        .foregroundStyle(StrandPalette.textSecondary)
                    liveHeartRate
                    effortGuide
                    Button(action: onStart) {
                        Label("Start activity", systemImage: "play.fill")
                            .font(StrandFont.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(PerformanceDesign.effort))
                    }
                    .buttonStyle(.plain)
                    Text("Nothing is recorded until you start.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(NoopMetrics.space4)
            }
            .navigationTitle(Text("Before you start"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }

    private var liveHeartRate: some View {
        VStack(spacing: NoopMetrics.space2) {
            ZStack {
                Circle().stroke(StrandPalette.textPrimary.opacity(0.12), lineWidth: 10)
                VStack(spacing: 0) {
                    Image(systemName: "heart.fill").foregroundStyle(PerformanceDesign.recoveryLow)
                    if let bpm = model.bpm {
                        Text(verbatim: "\(bpm)").font(StrandFont.display(64)).monospacedDigit()
                        Text("BPM").font(StrandFont.overline).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text(verbatim: "—").font(StrandFont.display(64))
                        Text("Waiting for your strap's heart rate…").font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary).multilineTextAlignment(.center)
                    }
                }
            }
            .frame(width: 220, height: 220)
            if let bpm = model.bpm {
                let zone = zoneSet.zoneNumber(forBPM: Double(bpm))
                Text(zone >= 1 ? String(localized: "Heart rate zone \(zone)") : String(localized: "Below Zone 1"))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if !model.live.connected {
                Label("Strap not connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(StrandFont.footnote).foregroundStyle(PerformanceDesign.recoveryMedium)
            }
        }
    }

    @ViewBuilder private var effortGuide: some View {
        let recovery = model.repo.days.first(where: { $0.day == today })?.recovery
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        if scale == .whoop, let recovery, let band = CoupledView.optimalStrainRange(recovery: recovery) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label("Effort target", systemImage: "scope").font(StrandFont.headline)
                Text(verbatim: "\(band.lowerBound)–\(band.upperBound)").font(StrandFont.title2).monospacedDigit()
                    .foregroundStyle(PerformanceDesign.effort)
                let recoveryText = "\(Int(recovery.rounded())) %"
                Text("Suggested for a recovery of \(recoveryText). A NROOP guide, not WHOOP's Strain Coach.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NoopMetrics.space4)
            .background(PerformanceDesign.panelTop, in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
        } else {
            Text("Effort target appears once today's recovery is scored.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
