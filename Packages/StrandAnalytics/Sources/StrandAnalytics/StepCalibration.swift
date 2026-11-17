import Foundation

/// Manual walking-trial calculator for the existing counter-ticks-per-step preference.
/// Input is an independently observed, unscaled tick DELTA, never a displayed daily step estimate.
/// It does not decode counters, infer wrap/reset behavior, or validate the strap's motion algorithm.
/// Kotlin twin: `com.noop.analytics.StepCalibration`.
public enum StepCalibration {
    public static let minimumTrials = 3
    public static let maximumTrials = 8
    public static let minimumSteps = 100.0
    public static let maximumSteps = 10_000.0
    public static let maximumTicks = 300_000.0
    public static let minimumFactor = 0.5
    public static let maximumFactor = 30.0
    /// A conservative workflow threshold, not an empirically validated accuracy/confidence bound.
    public static let maximumRelativeSpread = 0.20

    public struct Trial: Equatable, Sendable {
        public let id: String
        public let countedSteps: Double
        public let rawTicks: Double
        /// The user confirms a separate same-device walk and a complete, unscaled observation.
        /// This declaration is not machine verification of freshness, gaps, ownership, or resets.
        public let sourceConfirmed: Bool

        public init(id: String, countedSteps: Double, rawTicks: Double, sourceConfirmed: Bool) {
            self.id = id
            self.countedSteps = countedSteps
            self.rawTicks = rawTicks
            self.sourceConfirmed = sourceConfirmed
        }
    }

    public enum Issue: String, Sendable {
        case unconfirmedSource, invalidIdentity, invalidSteps, invalidTicks, unsupportedFactor
        case duplicateTrial, insufficientTrials, tooManyTrials, inconsistentTrials
    }

    public struct Result: Equatable, Sendable {
        /// Present only when every trial passes and repeatability is within the workflow threshold.
        public let factor: Double?
        /// (Largest trial factor − smallest trial factor) / median; repeatability, not confidence.
        public let relativeSpread: Double?
        public let issue: Issue?
    }

    public static func validate(_ trial: Trial) -> Issue? {
        guard trial.sourceConfirmed else { return .unconfirmedSource }
        // IDs are opaque; reject empty/ASCII-blank input without platform-specific Unicode trimming.
        guard !trial.id.unicodeScalars.allSatisfy({ [9, 10, 13, 32].contains($0.value) }) else { return .invalidIdentity }
        guard trial.countedSteps.isFinite,
              trial.countedSteps >= minimumSteps, trial.countedSteps <= maximumSteps,
              trial.countedSteps.rounded(.towardZero) == trial.countedSteps else { return .invalidSteps }
        guard trial.rawTicks.isFinite, trial.rawTicks > 0, trial.rawTicks <= maximumTicks,
              trial.rawTicks.rounded(.towardZero) == trial.rawTicks else { return .invalidTicks }
        let factor = trial.rawTicks / trial.countedSteps
        guard factor >= minimumFactor, factor <= maximumFactor else { return .unsupportedFactor }
        return nil
    }

    /// No outlier is silently dropped. Duplicate identities or identical observations cannot count
    /// as independent walks. Independent walks that happen to match need a different walk length.
    public static func evaluate(_ trials: [Trial]) -> Result {
        func rejected(_ issue: Issue) -> Result {
            Result(factor: nil, relativeSpread: nil, issue: issue)
        }
        guard trials.count <= maximumTrials else { return rejected(.tooManyTrials) }
        for (index, trial) in trials.enumerated() {
            if let issue = validate(trial) { return rejected(issue) }
            if trials.prefix(index).contains(where: {
                $0.id == trial.id || ($0.countedSteps == trial.countedSteps && $0.rawTicks == trial.rawTicks)
            }) { return rejected(.duplicateTrial) }
        }
        guard trials.count >= minimumTrials else { return rejected(.insufficientTrials) }
        let factors = trials.map { $0.rawTicks / $0.countedSteps }.sorted()
        let middle = factors.count / 2
        let median = factors.count.isMultiple(of: 2)
            ? (factors[middle - 1] + factors[middle]) / 2 : factors[middle]
        let spread = (factors[factors.count - 1] - factors[0]) / median
        guard spread <= maximumRelativeSpread else {
            return Result(factor: nil, relativeSpread: spread, issue: .inconsistentTrials)
        }
        return Result(factor: median, relativeSpread: spread, issue: nil)
    }
}
