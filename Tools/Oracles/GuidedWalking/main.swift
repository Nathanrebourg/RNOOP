import Foundation
import StrandAnalytics
class OracleFixtures {
 typealias Sample = GuidedWalkingTrial.Sample
    func walk(start: Int = 1000, duration: Int = 60, activity: Int? = 1) -> [Sample] {
        (0...duration).map { second in
            Sample(ts: start + second, counter: 100 + max(0, min(second - 1, duration - 2)) * 2,
                   activityClass: activity)
        }
    }
    func result(_ samples: [Sample], start: Int = 1000, end: Int = 1060) -> GuidedWalkingTrial.Result {
        GuidedWalkingTrial.evaluate(startTs: start, endTs: end, samples: samples)
    }
    func replacing(_ samples: [Sample], at index: Int, ts: Int? = nil, counter: Int? = nil,
                   activity: Int? = nil) -> [Sample] {
        var changed = samples
        changed[index] = Sample(ts: ts ?? samples[index].ts, counter: counter ?? samples[index].counter,
                                activityClass: activity ?? samples[index].activityClass)
        return changed
    }
    func oracleTranscript() -> String {
        let base = walk()
        let cases: [(String, Int, Int, [Sample])] = [
            ("classed", 1000, 1060, base),
            ("legacy", 1000, 1060, walk(activity: nil)),
            ("run", 1000, 1060, walk(activity: 2)),
            ("dedup", 1000, 1060, Array(base.reversed()) + [base[8]]),
            ("conflict", 1000, 1060, base + [Sample(ts: 1008, counter: 999, activityClass: 1)]),
            ("invalid-counter", 1000, 1060, replacing(base, at: 20, counter: 65536)),
            ("invalid-ts", 1000, 1060, base + [Sample(ts: 0, counter: 0, activityClass: nil)]),
            ("invalid-window", 0, 1060, base),
            ("short", 1000, 1059, base),
            ("long", 1000, 4601, base),
            ("empty", 1000, 1060, []),
            ("coverage", 1000, 1060, Array(base.dropFirst(4))),
            ("edge3", 1000, 1066, walk(start: 1003)),
            ("gap5", 1000, 1060, base.filter { !(1020...1023).contains($0.ts) }),
            ("gap6", 1000, 1060, base.filter { !(1020...1024).contains($0.ts) }),
            ("drop", 1000, 1060, replacing(base, at: 20, counter: 1)),
            ("rate5", 1000, 1060, replacing(base, at: 20, counter: base[19].counter + 5)),
            ("delta512", 1000, 1060, replacing(base, at: 20, counter: base[19].counter + 512)),
            ("still", 1000, 1060, replacing(base, at: 20, activity: 0)),
            ("moving-start", 1000, 1060, replacing(base, at: 0, counter: 99)),
            ("moving-end", 1000, 1060, replacing(base, at: 60, counter: 217)),
            ("zero", 1000, 1060, base.map { Sample(ts: $0.ts, counter: 100, activityClass: nil) }),
            ("max-duration", 1000, 4600, walk(duration: 3600)),
            ("unix-ceiling", 4102444740, 4102444800, walk(start: 4102444740))
        ]
        return cases.map { name, start, end, samples in
            let value = result(samples, start: start, end: end)
            func field(_ value: Int?) -> String { value.map(String.init) ?? "-" }
            return "\(name)|\(value.issue?.rawValue ?? "ok")|\(field(value.retainedTicks))|\(field(value.observedStartTs))|\(field(value.observedEndTs))|\(value.sampleCount)|\(value.usesActivityClasses ? 1 : 0)"
        }.joined(separator: "\n")
    }
}

print(OracleFixtures().oracleTranscript())
