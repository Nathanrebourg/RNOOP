import Foundation

/// Explicit journal context only; a missing answer is never interpreted as false or as a free night.
public enum ContextualSleepNeed {
    public static let naturalWakeQuestion = "Did you wake naturally without an alarm or obligation?"
    public static let restedQuestion = "Did you wake feeling rested?"
    public static let disruptedQuestion = "Was your sleep disrupted by an external event?"
    public struct Night: Sendable {
        public let dayStart: Int, hours: Double
        public let naturalWake: Bool?, rested: Bool?, disrupted: Bool?
        public init(dayStart: Int, hours: Double, naturalWake: Bool? = nil, rested: Bool? = nil, disrupted: Bool? = nil) {
            self.dayStart = dayStart; self.hours = hours; self.naturalWake = naturalWake; self.rested = rested; self.disrupted = disrupted
        }
    }
    public struct Estimate: Sendable {
        public let originalHours: Double, candidateHours: Double?
        public let eligibleNights: Int
    }
    public static func estimate(nights: [Night], before: Int, age: Int?) -> Estimate {
        let groups = Dictionary(grouping: nights.filter { n in
            n.dayStart < before && Double(before) - Double(n.dayStart) <= 30 * 86_400
                && (before - n.dayStart) % 86_400 == 0 && n.hours.isFinite && (3...12).contains(n.hours)
        }, by: \.dayStart)
        let unique = groups.values.compactMap { r -> Night? in
            let f = r[0]
            return r.allSatisfy { $0.hours == f.hours && $0.naturalWake == f.naturalWake && $0.rested == f.rested && $0.disrupted == f.disrupted } ? f : nil
        }
        let eligible = unique.filter { $0.naturalWake == true && $0.rested == true && $0.disrupted == false }
        let original = AnalyticsEngine.Rest.personalizedNeedHours(nightlyHours: unique.map(\.hours), age: age)
        let candidate = eligible.count >= 7 ? AnalyticsEngine.Rest.personalizedNeedHours(nightlyHours: eligible.map(\.hours), age: age) : nil
        return Estimate(originalHours: original, candidateHours: candidate, eligibleNights: eligible.count)
    }
}
