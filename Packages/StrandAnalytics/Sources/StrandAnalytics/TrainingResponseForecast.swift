import Foundation

/// Frozen contextual median model with rolling-origin evaluation; never feeds daily recommendations.
public enum TrainingResponseForecast {
    public struct Day:Equatable,Sendable {
        public let day:Int,recovery:Double?,effort:Double?,era:String
        public init(day:Int,recovery:Double?,effort:Double?,era:String) {self.day=day;self.recovery=recovery;self.effort=effort;self.era=era}
    }
    public struct Result:Sendable {
        public let status:String,prediction:Double?,training:Int,evaluated:Int,modelMAE:Double?,baselineMAE:Double?
    }
    static func bucket(_ x:Double)->Int {x<33 ? 0:x<66 ? 1:2}
    public static func analyze(_ input:[Day],origin:Int,horizon:Int)->Result {
        func out(_ s:String,_ p:Double?=nil,_ n:Int=0,_ e:Int=0,_ m:Double?=nil,_ b:Double?=nil)->Result {.init(status:s,prediction:p,training:n,evaluated:e,modelMAE:m,baselineMAE:b)}
        guard input.count<=400,(0...1_000_000).contains(origin),(1...3).contains(horizon) else{return out("invalid-input")}
        let groups=Dictionary(grouping:input.filter{$0.day>=0 && $0.day<=origin},by:\.day)
        var days:[Int:Day]=[:]
        for (key,g) in groups {
            if let a=g.first,g.allSatisfy({$0==a}),PersonalEvidenceMath.ascii(a.era),
               a.recovery.map({$0.isFinite && (0...100).contains($0)}) ?? true,
               a.effort.map({$0.isFinite && (0...100).contains($0)}) ?? true {days[key]=a}
        }
        guard let target=days[origin],let effort=target.effort,let recovery=target.recovery else{return out("origin-unavailable")}
        func matches(_ d:Day,_ t:Day)->Bool {guard let e=d.effort,let r=d.recovery,let te=t.effort,let tr=t.recovery else{return false};return d.era==t.era && bucket(e)==bucket(te) && bucket(r)==bucket(tr)}
        func fit(_ t:Day)->(Double?,Int) {
            var deltas:[Double]=[],last=Int.max
            for key in days.keys.sorted(by:>) where key+horizon<t.day && key>=t.day-180 {
                guard key+horizon<last,let d=days[key],matches(d,t),let y=days[key+horizon],y.era==t.era,let result=y.recovery,let initial=d.recovery else{continue}
                deltas.append(result-initial);last=key
                if deltas.count==30 {break}
            }
            guard deltas.count>=8,let delta=PersonalEvidenceMath.median(deltas),let r=t.recovery else{return (nil,deltas.count)}
            return (max(0,min(100,r+delta)),deltas.count)
        }
        let current=fit(target)
        guard let forecast=current.0 else{return out("insufficient-training",nil,current.1)}
        var errors:[Double]=[],baseline:[Double]=[],last=Int.max
        for key in days.keys.sorted(by:>) where key+horizon<=origin && key>=origin-90 {
            guard key+horizon<last,let d=days[key],matches(d,target),let y=days[key+horizon],y.era==target.era,let actual=y.recovery,let r=d.recovery,
                  let prediction=fit(d).0 else{continue}
            errors.append(abs(prediction-actual));baseline.append(abs(r-actual));last=key
            if errors.count==30 {break}
        }
        guard errors.count>=8 else{return out("insufficient-evaluation",nil,current.1,errors.count)}
        let mae=errors.reduce(0,+)/Double(errors.count),base=baseline.reduce(0,+)/Double(baseline.count)
        guard base>0,mae<=base*0.9 else{return out("no-improvement",nil,current.1,errors.count,mae,base)}
        _=effort;_=recovery
        return out("qualified-experimental",forecast,current.1,errors.count,mae,base)
    }
}
