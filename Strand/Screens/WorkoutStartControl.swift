import SwiftUI
import StrandDesign

/// #459: "Start Workout" used to live ONLY on the Live screen, so a user reaching Workouts (via the
/// Quick-action FAB or the tab) had no way to begin one from the obvious place. This button starts a live
/// session and presents the in-exercise view directly.
///
/// PERF (chart-invalidation): this is the ONE place `WorkoutsView` needs live `AppModel` state
/// (`activeWorkout`) — everything else it needs (`hrMax`, `analyzeRecent()`) lives on sub-objects that
/// don't publish at live-tick frequency. `AppModel` publishes `bpm` at ~1 Hz (AppModel.swift:202), and
/// `@EnvironmentObject` subscribes to the WHOLE object's `objectWillChange`, so if `WorkoutsView` itself
/// held `model: AppModel`, every tick would re-evaluate its entire ~1900-line body (chart + grids +
/// sorting) even though only this button's label and its two sheets read `model`. Isolating it here
/// (mirroring `HealthView`'s live-observing-leaf pattern, HealthView.swift:17-22, 44-46) means a tick
/// re-renders only this small leaf. Owns its own sheet-presentation state so nothing about it needs to
/// live on the parent either.
struct WorkoutStartControl: View {
    /// Compact treatment for the Today's activities row; both variants share the same session flow.
    var compact = false
    @EnvironmentObject var model: AppModel
    @State private var showLiveWorkout = false
    @State private var showStartSport = false
    /// Sport picked, waiting on the "before you start" screen (nil when no pre-start is showing).
    @State private var pendingSport: String?

    init(compact: Bool = false) {
        self.compact = compact
    }

    var body: some View {
        button
        .accessibilityLabel(model.activeWorkout == nil ? "Start a workout" : "View the active workout")
        // #459: the in-exercise view, presented when Start Workout is tapped here (same screen LiveView
        // shows). activeWorkout is global on AppModel, so ending it from either surface stays in sync.
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false })
                // Inject the shared live snapshot so the in-exercise sensor readout (speed/cadence/power)
                // resolves here too, matching how LiveView presents the same screen.
                .environmentObject(model.live)
        }
        // #519: name the sport before a live session starts, then open the in-exercise view directly
        // (same direct present as the button's already-active path — no cross-view auto-present race).
        .workoutSelectionCover(isPresented: $showStartSport) {
            StartWorkoutSheet { name in
                pendingSport = name
            }
        }
        .sheet(isPresented: Binding(get: { pendingSport != nil }, set: { if !$0 { pendingSport = nil } })) {
            PreWorkoutView(sport: pendingSport ?? "", onStart: {
                let name = pendingSport ?? ""
                pendingSport = nil
                model.startWorkout(sport: name)
                showLiveWorkout = true
            }, onCancel: { pendingSport = nil })
            .environmentObject(model)
        }
    }

    @ViewBuilder private var button: some View {
        if compact {
            Button(action: openWorkout) {
                HStack(spacing: NoopMetrics.space1) {
                    Image(systemName: "stopwatch")
                    Text(model.activeWorkout == nil ? LocalizedStringKey("Start an activity")
                                                    : LocalizedStringKey("View active workout"))
                        .font(StrandFont.overline).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: NoopButtonMetrics.minHitTarget)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(NoopVisualStyle.borderHighlight.opacity(0.6)))
            }
            .buttonStyle(.plain)
        } else {
            NoopButton(model.activeWorkout == nil ? "Start workout" : "View active workout",
                       systemImage: model.activeWorkout == nil ? "figure.run" : "timer",
                       kind: .primary, fullWidth: true, action: openWorkout)
        }
    }

    private func openWorkout() {
        if model.activeWorkout == nil { showStartSport = true }
        else { showLiveWorkout = true }
    }
}
