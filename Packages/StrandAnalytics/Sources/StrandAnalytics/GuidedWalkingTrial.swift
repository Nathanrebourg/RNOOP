/// Pure quality gate for a user-declared walking interval. Kotlin twin: `GuidedWalkingTrial`.
public enum GuidedWalkingTrial {
    // Workflow limits, not validated accuracy/confidence thresholds.
    public static let minimumDuration = 60
    public static let maximumDuration = 3600
    public static let maximumEdgeGap = 3
    public static let maximumSampleGap = 5
    public static let maximumUnixTimestamp = Int(clamping: 4_102_444_800 as Int64)

    public struct Sample: Equatable, Sendable {
        public let ts: Int
        public let counter: Int
        public let activityClass: Int?
        public init(ts: Int, counter: Int, activityClass: Int?) {
            self.ts = ts; self.counter = counter; self.activityClass = activityClass
        }
    }
    public enum Issue: String, Sendable {
        case invalidWindow, invalidDuration, invalidTimestamp, invalidCounter, conflictingSample
        case insufficientSamples, incompleteCoverage, sampleGap, counterDecreased
        case implausibleIncrement, nonWalkingIncrement, movingBoundary, noMovement
    }
    public struct Result: Equatable, Sendable {
        public let retainedTicks: Int?
        public let issue: Issue?
        public let observedStartTs: Int?
        public let observedEndTs: Int?
        public let sampleCount: Int
        public let usesActivityClasses: Bool
    }
    /// The caller selects ONE source before mapping samples; this type cannot verify ownership.
    /// Only samples within [startTs, endTs] contribute. No rejected increment is silently omitted.
    public static func evaluate(startTs: Int, endTs: Int, samples: [Sample]) -> Result {
        var observed: [Sample] = []
        var classed = false
        func finish(_ issue: Issue?, ticks: Int? = nil) -> Result {
            Result(retainedTicks: ticks, issue: issue, observedStartTs: observed.first?.ts,
                   observedEndTs: observed.last?.ts, sampleCount: observed.count,
                   usesActivityClasses: classed)
        }
        guard startTs > 0, endTs > startTs, endTs <= maximumUnixTimestamp else {
            return finish(.invalidWindow)
        }
        let duration = endTs - startTs
        guard duration >= minimumDuration, duration <= maximumDuration else { return finish(.invalidDuration) }
        guard samples.allSatisfy({ $0.ts > 0 && $0.ts <= maximumUnixTimestamp }) else {
            return finish(.invalidTimestamp)
        }
        let ordered = samples.filter { $0.ts >= startTs && $0.ts <= endTs }.sorted { $0.ts < $1.ts }
        for sample in ordered {
            guard (0...65535).contains(sample.counter) else { return finish(.invalidCounter) }
            if let previous = observed.last, previous.ts == sample.ts {
                guard previous == sample else { return finish(.conflictingSample) }
            } else { observed.append(sample) }
        }
        classed = observed.contains { $0.activityClass != nil }
        guard observed.count >= 4 else { return finish(.insufficientSamples) }
        guard observed[0].ts - startTs <= maximumEdgeGap,
              endTs - observed[observed.count - 1].ts <= maximumEdgeGap else {
            return finish(.incompleteCoverage)
        }
        var total = 0
        for index in 1..<observed.count {
            let previous = observed[index - 1], current = observed[index]
            let elapsed = current.ts - previous.ts
            guard elapsed <= maximumSampleGap else { return finish(.sampleGap) }
            // A drop could be either a wrap or a reset. Neither is identifiable from these fields.
            guard current.counter >= previous.counter else { return finish(.counterDecreased) }
            let delta = current.counter - previous.counter
            if delta == 0 { continue }
            // Exactly StepsCounter's positive increment acceptance, before coefficient application.
            guard delta < 512, delta <= elapsed * 4 else { return finish(.implausibleIncrement) }
            guard !classed || current.activityClass == 1 || current.activityClass == 2 else {
                return finish(.nonWalkingIncrement)
            }
            total += delta
        }
        // Observed stationary edges reduce boundary ambiguity; they do not prove a complete walk.
        guard observed[0].counter == observed[1].counter,
              observed[observed.count - 2].counter == observed[observed.count - 1].counter else {
            return finish(.movingBoundary)
        }
        guard total > 0 else { return finish(.noMovement) }
        return finish(nil, ticks: total)
    }
}
