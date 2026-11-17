import SwiftUI
import StrandAnalytics
import StrandDesign

/// Offline manual calculator for the existing WHOOP 5/MG tick divisor. Opening, editing and previewing
/// never change settings. It intentionally has no BLE or repository-capture dependency.
struct StepCalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var trials: [StepCalibration.Trial] = []
    @State private var countedSteps = ""
    @State private var rawTicks = ""
    @State private var sourceConfirmed = false
    @State private var entryIssue: StepCalibration.Issue?
    @State private var isApplying = false
    @State private var applied = false

    private var result: StepCalibration.Result { StepCalibration.evaluate(trials) }
    private var draft: StepCalibration.Trial {
        .init(id: UUID().uuidString,
              countedSteps: Double(Int(countedSteps.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0),
              rawTicks: Double(Int(rawTicks.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0),
              sourceConfirmed: sourceConfirmed)
    }

    var body: some View {
        ScreenScaffold(title: "Walking step calibration",
                       subtitle: "Guided walks or manual observations for the WHOOP 5/MG motion counter.",
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                               .disabled(isApplying)
                       }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                NavigationLink { GuidedWalkingCalibrationView() } label: {
                    Label("Calibrate with Start and Finish",systemImage:"figure.walk")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.accent)
                }
                instructionsCard
                entryCard
                if !trials.isEmpty { trialsCard }
                previewCard
            }
            .disabled(isApplying)
        }
        .interactiveDismissDisabled(isApplying)
    }

    private var instructionsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Count a walk, then repeat").font(StrandFont.headline)
                Text("Complete 3–8 separate walks with the same strap and placement. Count 100–10,000 actual steps per walk. Use different walk lengths so each observation is distinct.")
                Text("For each walk, enter the complete unscaled tick increase from your own local raw-counter observation. The @57 motion counter is not a validated step count. NOOP's displayed daily steps may already be scaled and must not be used here.")
                Text("The manual form below does not capture a walk or verify its source. If you cannot obtain an unscaled tick increase, keep your current scale. Do not use observations with missing records, counter resets or ambiguous wraps.")
                Text("A repeatable scale does not validate the counter or filter non-walking wrist motion. Nothing changes until you tap Apply scale.")
                Text("The scale divides ticks retained by NOOP's existing step pipeline. It cannot restore discarded ticks or fill missing walks.")
            }
            .font(StrandFont.body)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var entryCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Add a walking trial").font(StrandFont.headline)
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Steps you counted").font(StrandFont.subhead)
                    TextField("Counted steps", text: $countedSteps)
                        .stepCalibrationNumberInput()
                        .accessibilityLabel("Steps you counted")
                    Text("Unscaled tick increase").font(StrandFont.subhead)
                    TextField("Raw tick increase", text: $rawTicks)
                        .stepCalibrationNumberInput()
                        .accessibilityLabel("Unscaled tick increase")
                }
                Toggle("I counted a separate walk with this strap and used complete, unscaled ticks without gaps, resets or uncertain wraps.", isOn: $sourceConfirmed)
                    .font(StrandFont.footnote)
                    .tint(StrandPalette.accent)
                Text("Whole numbers only. Tick increase must be positive and at most 300,000. Each trial must imply 0.5–30 ticks per counted step.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let entryIssue {
                    Text(Self.message(for: entryIssue))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("Add trial") { addTrial() }
                    .buttonStyle(NoopButtonStyle(.secondary))
                    .disabled(!sourceConfirmed || trials.count >= StepCalibration.maximumTrials)
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private var trialsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Walking trials").font(StrandFont.headline)
                ForEach(Array(trials.enumerated()), id: \.element.id) { index, trial in
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        HStack {
                            Text("Trial \(index + 1)").font(StrandFont.subhead)
                            Spacer()
                            Button("Remove") {
                                trials.removeAll { $0.id == trial.id }
                                applied = false
                                entryIssue = nil
                            }
                            .buttonStyle(.plain)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.accent)
                            .accessibilityLabel("Remove trial \(index + 1)")
                        }
                        Text("\(Int(trial.countedSteps)) counted steps · \(Int(trial.rawTicks)) raw ticks")
                            .font(StrandFont.captionNumber)
                        Text("\(scaleString(trial.rawTicks / trial.countedSteps)) ticks per step")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Text("Trials stay only in this screen. Closing it discards them; an applied scale remains saved on this device.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private var previewCard: some View {
        let preview = result
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Review before applying").font(StrandFont.headline)
                Text("Current scale: \(scaleString(profile.stepTicksPerStep)) ticks per step")
                    .font(StrandFont.bodyNumber)
                if let spread = preview.relativeSpread {
                    Text("Trial spread: \(spread.formatted(.percent.precision(.fractionLength(1))))")
                        .font(StrandFont.bodyNumber)
                }
                if let factor = preview.factor {
                    Text("Proposed scale: \(scaleString(factor)) ticks per step")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.accent)
                    Text("The proposal is the median of all trial scales. Display is rounded; the full calculated value is saved.")
                        .font(StrandFont.footnote)
                } else if let issue = preview.issue {
                    Text(Self.message(for: issue)).font(StrandFont.footnote)
                }
                Text("Spread is the range of trial scales divided by their median. The 20% limit is a workflow rule for repeatability, not a confidence score or an accuracy guarantee.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                Button("Apply scale") { applyScale() }
                    .buttonStyle(NoopButtonStyle(.primary))
                    .disabled(preview.factor == nil || isApplying || applied)
                if isApplying {
                    ProgressView("Updating local estimates…")
                        .font(StrandFont.footnote)
                } else if applied {
                    Text("Scale saved. Local estimates will use it when recalculated.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusPositive)
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scaleString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func addTrial() {
        let trial = draft
        if let issue = StepCalibration.validate(trial) {
            entryIssue = issue
            return
        }
        let candidate = StepCalibration.evaluate(trials + [trial])
        if candidate.issue == .duplicateTrial || candidate.issue == .tooManyTrials {
            entryIssue = candidate.issue
            return
        }
        trials.append(trial)
        countedSteps = ""
        rawTicks = ""
        sourceConfirmed = false
        entryIssue = nil
        applied = false
    }

    @MainActor private func applyScale() {
        guard !isApplying, let factor = result.factor else { return }
        isApplying = true
        // This is the existing preference and standard Settings recompute/refresh path.
        profile.stepTicksPerStep = factor
        Task {
            await model.intelligence.analyzeRecent()
            await model.repo.refresh()
            applied = true
            isApplying = false
        }
    }

    private static func message(for issue: StepCalibration.Issue) -> String {
        switch issue {
        case .unconfirmedSource:
            return String(localized: "Confirm the source and completeness of this separate walking trial.")
        case .invalidIdentity:
            return String(localized: "This trial needs a valid identifier. Remove it and add the walk again.")
        case .invalidSteps:
            return String(localized: "Enter a whole number of counted steps from 100 to 10,000.")
        case .invalidTicks:
            return String(localized: "Enter a whole unscaled tick increase from 1 to 300,000.")
        case .unsupportedFactor:
            return String(localized: "This trial falls outside 0.5–30 ticks per counted step. Check the unscaled source and the step count.")
        case .duplicateTrial:
            return String(localized: "This repeats an existing observation. Use a separate walk with a different length.")
        case .insufficientTrials:
            return String(localized: "Add at least three independent walking trials to preview a scale.")
        case .tooManyTrials:
            return String(localized: "Use no more than eight walking trials in one calibration.")
        case .inconsistentTrials:
            return String(localized: "Trial spread exceeds 20%. Check the observations and repeat the walks before applying a scale.")
        }
    }
}

private extension View {
    func stepCalibrationNumberInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad).textFieldStyle(.roundedBorder).font(StrandFont.bodyNumber)
        #else
        self.textFieldStyle(.roundedBorder).font(StrandFont.bodyNumber)
        #endif
    }
}
