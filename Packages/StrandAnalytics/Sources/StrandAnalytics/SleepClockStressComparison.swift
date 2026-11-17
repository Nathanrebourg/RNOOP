import Foundation
import WhoopProtocol

/// Default-off, read-only Rest instrumentation. Kotlin twin: SleepClockStressComparison.kt.
/// Frozen v1: 40% duration + 25% efficiency + 20% bed/wake clock + 15% nocturnal calmness.
/// Engineering hypothesis only. Missing inputs never receive neutral values or redistributed weights.
public enum SleepClockStressComparison {
    public struct Stage: Equatable, Sendable {
        public let start: Int, end: Int
        public let kind: String
        public init(start: Int, end: Int, kind: String) { self.start=start;self.end=end;self.kind=kind }
    }
    public struct Night: Equatable, Sendable {
        public let day: Int, start: Int, end: Int, bedtimeMinute: Int, wakeMinute: Int
        public let stages: [Stage]?
        public let sparse: Bool
        public init(day:Int,start:Int,end:Int,bedtimeMinute:Int,wakeMinute:Int,stages:[Stage]?,sparse:Bool) {
            self.day=day;self.start=start;self.end=end;self.bedtimeMinute=bedtimeMinute;self.wakeMinute=wakeMinute
            self.stages=stages;self.sparse=sparse
        }
    }
    public struct Physiology: Sendable {
        public let day: Int, start: Int, end: Int, channel: Int?
        public let hr: Double?, rmssd: Double?, coverage: Double
        public let windows: Int
        public let status: String
    }
    public struct Result: Sendable {
        public let status: String
        public let duration: Double?, efficiency: Double?, clock: Double?, calmness: Double?, candidate: Double?
        public let coverage: Double
        public let priorNights: Int, baselineNights: Int
        public let stressStatus: String
    }
    public static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let d=abs(a-b);return min(d,1440-d)
    }
    private static func valid(_ n: Night) -> Bool {
        n.start >= 0 && n.end <= 4_102_444_800 && n.end > n.start && Double(n.end)-Double(n.start) >= 10_800
            && Double(n.end)-Double(n.start) <= 57_600 && (0..<1440).contains(n.bedtimeMinute)
            && (0..<1440).contains(n.wakeMinute) && n.day >= 0
    }
    private static func median(_ xs:[Double])->Double {
        let s=xs.sorted(),m=s.count/2;return s.count%2 == 0 ? (s[m-1]+s[m])/2:s[m]
    }
    /// Complete known-stage coverage only. Identical repeated segments collapse; overlaps or malformed
    /// segments fail closed. A missing interval is never silently counted as awake or asleep.
    private static func segments(_ n: Night) -> [Stage]? {
        guard valid(n), !n.sparse, let stages=n.stages, !stages.isEmpty,
              stages.allSatisfy({ $0.start >= 0 && $0.end > $0.start && ["awake","light","deep","rem"].contains($0.kind) }) else { return nil }
        let sorted=stages.filter { $0.end > n.start && $0.start < n.end }
            .map { Stage(start:max(n.start,$0.start),end:min(n.end,$0.end),kind:$0.kind) }
            .sorted { ($0.start,$0.end,$0.kind) < ($1.start,$1.end,$1.kind) }
        var unique:[Stage]=[]
        for s in sorted where unique.last != s { unique.append(s) }
        var cursor=n.start
        for s in unique { guard s.start == cursor else { return nil };cursor=s.end }
        return cursor == n.end ? unique:nil
    }
    private static func qualified(_ p:Physiology,for n:Night)->Bool {
        guard p.day==n.day,p.start==n.start,p.end==n.end,p.status=="qualified",
              let channel=p.channel,[5,7].contains(channel),let h=p.hr,(30...250).contains(h),h.isFinite,
              let r=p.rmssd,r.isFinite,r>0,r<=2000,p.coverage.isFinite,(0.7...1).contains(p.coverage),
              p.windows>=12,p.windows<=(n.end-n.start)/300,let stage=segments(n) else{return false}
        let asleep=stage.filter{$0.kind != "awake"}.reduce(0){$0+$1.end-$1.start}
        return asleep>0 && abs(p.coverage-Double(p.windows*300)/Double(asleep))<1e-9
    }
    public static func analyze(target:Night,history:[Night],now:Int,
                               physiology:Physiology?=nil,priorPhysiology:[Physiology]=[]) -> Result {
        func result(_ status:String,_ d:Double?=nil,_ e:Double?=nil,_ c:Double?=nil,_ n:Double?=nil,
                    _ cov:Double=0,_ count:Int=0,_ baselines:Int=0,_ stress:String="night-stress-provenance-unavailable")->Result {
            let candidate:Double?
            if let d,let e,let c,let n { candidate=100*(0.40*d+0.25*e+0.20*c+0.15*n) } else { candidate=nil }
            return Result(status:status,duration:d,efficiency:e,clock:c,calmness:n,candidate:candidate,coverage:cov,
                          priorNights:count,baselineNights:baselines,stressStatus:stress)
        }
        guard valid(target) else { return result("invalid-night") }
        guard target.end <= now else { return result("unfinished-night") }
        let groups=Dictionary(grouping:history.filter { valid($0) && $0.day < target.day && target.day-$0.day <= 28 && $0.end <= target.start },by: \.day)
        let prior=groups.values.compactMap { rows -> Night? in
            guard let n=rows.first,rows.allSatisfy({$0 == n}) else{return nil};return n
        }
        let clock=prior.count >= 3 ? max(0,1-(median(prior.map {Double(circularDistance(target.bedtimeMinute,$0.bedtimeMinute))})
            + median(prior.map {Double(circularDistance(target.wakeMinute,$0.wakeMinute))}))/240):nil
        let stage=segments(target)
        let asleep=stage.map { Double($0.filter {$0.kind != "awake"}.reduce(0) {$0+$1.end-$1.start}) }
        let d=asleep.map { min(1,$0/28_800) },e=asleep.map {$0/Double(target.end-target.start)}
        guard let p=physiology,qualified(p,for:target),let hr=p.hr,let rmssd=p.rmssd else {
            return result("candidate-withheld",d,e,clock,nil,stage == nil ? 0:1,prior.count,0,physiology?.status ?? "night-stress-provenance-unavailable")
        }
        let priorKeys=Dictionary(uniqueKeysWithValues:prior.map {($0.day,$0)})
        let pGroups=Dictionary(grouping:priorPhysiology.filter {
            guard let n=priorKeys[$0.day] else {return false}
            return $0.channel == p.channel && qualified($0,for:n)
        },by: \.day)
        let ps=pGroups.values.compactMap { rows -> Physiology? in rows.count == 1 ? rows[0]:nil }.sorted {$0.day<$1.day}
        guard ps.count >= 3 else {return result("candidate-withheld",d,e,clock,nil,stage == nil ? 0:1,prior.count,ps.count,"insufficient-prior-night-baseline")}
        let hrs=ps.compactMap(\.hr),rrs=ps.compactMap(\.rmssd)
        func mean(_ xs:[Double])->Double {xs.reduce(0,+)/Double(xs.count)}
        func spread(_ xs:[Double])->Double {let m=mean(xs);return sqrt(xs.reduce(0){$0+($1-m)*($1-m)}/Double(xs.count))}
        let raw=(hr-mean(hrs))/max(5,spread(hrs))-(rmssd-mean(rrs))/max(10,spread(rrs))
        // The same checked logistic physics as DaytimeStress, with an explicit NIGHT-only reference.
        let calm=1-DaytimeStress.squash(raw)/3
        return result(d != nil && clock != nil ? "compared":"candidate-withheld",d,e,clock,calm,stage == nil ? 0:1,prior.count,ps.count,"qualified-nocturnal-activation-proxy")
    }
    /// Five-minute raw instrumentation; no waking-hour mask or awake baseline may enter this path.
    public static func physiology(night:Night,hr:[HRSample],rr:[RRInterval],gravity:[GravitySample],
                                  confirmedWhoop5:Bool,readCapped:Bool=false)->Physiology {
        func out(_ status:String,_ channel:Int?=nil,_ h:Double?=nil,_ r:Double?=nil,_ coverage:Double=0,_ windows:Int=0)->Physiology {
            Physiology(day:night.day,start:night.start,end:night.end,channel:channel,hr:h,rmssd:r,coverage:coverage,windows:windows,status:status)
        }
        guard !readCapped,hr.count<=60_000,rr.count<=120_000,gravity.count<=60_000 else{return out("read-capped")}
        guard confirmedWhoop5 else{return out("unconfirmed-whoop5-source")}
        guard let stage=segments(night) else{return out("incomplete-or-sparse-stages")}
        let beats=rr.filter {$0.ts>=night.start && $0.ts<night.end}
        let channels=Set(beats.compactMap {$0.srcChannel?.rawValue})
        guard channels.count == 1,let channel=channels.first,[5,7].contains(channel),
              beats.allSatisfy({$0.srcChannel?.rawValue == channel}) else{return out("rr-source-unavailable-or-mixed")}
        let normalized=RRReplayIdentity.normalize(beats,declared:true)
        guard let rs=normalized.rows else { return out("conflicting-rr-identity") }
        let hs=SampleQuality.uniqueHR(hr.filter {$0.ts>=night.start && $0.ts<night.end && (30...250).contains($0.bpm)})
        let gs=Dictionary(grouping:gravity.filter {
            $0.ts>=night.start && $0.ts<night.end && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                && abs($0.x)<=100 && abs($0.y)<=100 && abs($0.z)<=100 && ($0.x != 0 || $0.y != 0 || $0.z != 0)
        },by:\.ts).values.compactMap { rows -> GravitySample? in
            guard let a=rows.first,rows.allSatisfy({$0.x == a.x && $0.y == a.y && $0.z == a.z}) else{return nil};return a
        }.sorted {$0.ts<$1.ts}
        let activity=WorkoutDetector.activitySeries(gs)
        let hg=Dictionary(grouping:hs,by:{($0.ts-night.start)/300})
        let gg=Dictionary(grouping:gs,by:{($0.ts-night.start)/300})
        let rg=Dictionary(grouping:rs,by:{($0.ts-night.start)/300})
        let ag=Dictionary(grouping:activity,by:{($0.ts-night.start)/300})
        func covered(_ ts:[Int],_ start:Int)->Bool {
            guard ts.count>=240,let first=ts.first,let last=ts.last,first-start<=15,start+299-last<=15 else{return false}
            return zip(ts,ts.dropFirst()).allSatisfy {$1-$0<=15}
        }
        var means:[Double]=[],rmssds:[Double]=[]
        for i in 0..<((night.end-night.start)/300) {
            let lo=night.start+i*300,hi=lo+300
            let sleeping=stage.filter {$0.kind != "awake"}.reduce(0) {$0+max(0,min(hi,$1.end)-max(lo,$1.start))}
            guard sleeping == 300 else{continue}
            let h=hg[i] ?? [],g=gg[i] ?? [],a=ag[i] ?? [],r=rg[i] ?? []
            guard covered(h.map(\.ts),lo),covered(g.map(\.ts),lo),!a.isEmpty,
                  Double(a.filter {$0.intensity>WorkoutDetector.motionThreshold}.count)/Double(a.count)<DaytimeStress.activityMaskFraction else{continue}
            let q=NightlyHRVQuality.analyze(start:lo,end:hi,rr:r)
            guard let rmssd=q.weightedRMSSD,rmssd>0,q.coverage>=0.8,!q.overCounted,q.inputBeats>0,
                  Double(q.rejectedBeats)/Double(q.inputBeats)<=0.1 else{continue}
            means.append(h.reduce(0){$0+Double($1.bpm)}/Double(h.count));rmssds.append(rmssd)
        }
        let asleep=stage.filter {$0.kind != "awake"}.reduce(0){$0+$1.end-$1.start}
        let cov=asleep>0 ? Double(means.count*300)/Double(asleep):0
        guard means.count>=12,cov>=0.7 else{return out("insufficient-night-signal",channel,nil,nil,cov,means.count)}
        return out("qualified",channel,means.reduce(0,+)/Double(means.count),rmssds.reduce(0,+)/Double(rmssds.count),cov,means.count)
    }
}
