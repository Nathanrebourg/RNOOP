import Foundation
import StrandAnalytics
import WhoopProtocol

// Research-only two-step candidate. No app entry point or stored stages call this model.
enum HierarchicalRecipe {
    private static let sleepStates = ["deep", "rem", "light"]

    // Log-sum-exp marginalizes mutually exclusive sleep stages without overflow.
    private static func sleepEmission(_ em: [String:Double]) -> Double {
        let values = sleepStates.map { em[$0]! }
        let maximum = values.max()!
        return maximum + log(values.reduce(0) { $0 + exp($1-maximum) })
    }

    private static func path(_ emissions: [[String:Double]], states: [String],
                             transition: [String:[String:Double]]) -> [String] {
        guard let first = emissions.first else { return [] }
        var values=first, back=[[String:String]]()
        for emission in emissions.dropFirst() {
            var next=[String:Double](), previous=[String:String]()
            for state in states {
                var best=states[0], score=values[best]!+log(transition[best]![state]!)
                for candidate in states.dropFirst() {
                    let trial=values[candidate]!+log(transition[candidate]![state]!)
                    if trial>score { best=candidate;score=trial }
                }
                next[state]=score+emission[state]!;previous[state]=best
            }
            values=next;back.append(previous)
        }
        var last=states[0]
        for state in states.dropFirst() where values[state]!>values[last]! { last=state }
        var result=[last]
        for previous in back.reversed() { last=previous[last]!;result.append(last) }
        return result.reversed()
    }

    static func decode(_ emissions: [[String:Double]], minutes: [Double]) -> [String] {
        guard !emissions.isEmpty,emissions.count==minutes.count,
              emissions.allSatisfy({em in V2Recipe.stageNames.allSatisfy{em[$0]?.isFinite == true}}),
              minutes.allSatisfy(\.isFinite) else { return [] }
        let cfg=RecipeConfig.shipped
        let sleepWake=(0.15*0.007+0.22*0.015+0.50*0.03)/0.87
        let binary=path(emissions.map{["sleep":sleepEmission($0),"awake":$0["awake"]!]},
            states:["sleep","awake"],transition:["sleep":["sleep":1-sleepWake,"awake":sleepWake],
                "awake":["sleep":0.10,"awake":0.90]])
        let onset=V2Recipe.sustainedSleepOnset(binary,cfg).map{minutes[$0]} ?? 0
        var transition=[String:[String:Double]]()
        for from in sleepStates {
            let row=cfg.transition[from]!, total=sleepStates.reduce(0){$0+row[$1]!}
            transition[from]=Dictionary(uniqueKeysWithValues:sleepStates.map{($0,row[$0]!/total)})
        }
        var result=[String](repeating:"wake",count:emissions.count),i=0
        while i<binary.count {
            if binary[i]=="awake" { i+=1;continue }
            let lo=i
            while i<binary.count && binary[i]=="sleep" { i+=1 }
            let sequence=(lo..<i).map { index -> [String:Double] in
                var emission=emissions[index]
                emission["rem"]!-=V2Recipe.remLatencyGuard(minutes[index]-onset,cfg)
                return emission
            }
            let sleep=path(sequence,states:sleepStates,transition:transition)
            for (index,label) in sleep.enumerated() { result[lo+index]=label }
        }
        return result
    }

    // Every skipped feature epoch breaks both models' state; gaps cannot transmit a stage or onset.
    static func labels(_ features: [V2Recipe.Epoch]) -> [String] {
        var result=[String](),lo=0
        while lo<features.count {
            var hi=lo+1
            while hi<features.count && features[hi].start==features[hi-1].start+30 { hi+=1 }
            let block=Array(features[lo..<hi])
            result+=decode(V2Recipe.emissions(block),minutes:block.map(\.minutesSinceOnset))
            lo=hi
        }
        return result
    }

    static func predict(start:Int,end:Int,grav:[GravitySample],hr:[HRSample],rr:[RRInterval]) -> [String] {
        guard end>start,end-start<=86400,start>=0,end<=4_102_444_800 else { return [] }
        let count=(end-start+29)/30
        var prediction=[String](repeating:"unknown",count:count)
        // Prepared research cases are aligned. An unaligned request is not silently re-timed.
        guard start%30==0,end%30==0 else { return prediction }
        let heart=hr.filter{$0.ts>=start-330 && $0.ts<end+390 && (1...300).contains($0.bpm)}.sorted{$0.ts<$1.ts}
        let motion=grav.filter{$0.ts>=start-330 && $0.ts<end+390 && [$0.x,$0.y,$0.z].allSatisfy(\.isFinite) && ($0.x != 0 || $0.y != 0 || $0.z != 0)}.sorted{$0.ts<$1.ts}
        let coverage=SleepSignalCoverage.analyze(start:start,end:end,hr:heart,gravity:motion)
        let supported=Set(coverage.intervals.filter{$0.kind != "unknown"}.flatMap{
            Array(stride(from:$0.start,to:$0.end,by:30))
        })
        let features=V2Recipe.features(start:start,end:end,grav:motion,hr:heart,rr:rr.sortedByTsStable())
            .filter{supported.contains($0.start)}
        let stages=labels(features)
        for (index,feature) in features.enumerated() { prediction[(feature.start-start)/30]=stages[index] }
        return prediction
    }
}
