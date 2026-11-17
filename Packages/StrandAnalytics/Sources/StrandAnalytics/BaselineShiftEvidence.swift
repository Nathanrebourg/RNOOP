import Foundation

/// Robust descriptive shift alarm, not automatic recalibration or a health classification.
public enum BaselineShiftEvidence {
    public struct Sample:Equatable,Sendable {
        public let age:Int,value:Double?,era:String
        public init(age:Int,value:Double?,era:String) {self.age=age;self.value=value;self.era=era}
    }
    public struct Result:Sendable {
        public let status:String,recentCount:Int,priorCount:Int,recentMedian:Double?,priorMedian:Double?,scaledDelta:Double?,shift:Bool
    }
    public static func analyze(_ samples:[Sample],floor:Double,bounds:ClosedRange<Double>)->Result {
        func out(_ status:String,_ a:[Double]=[],_ b:[Double]=[],_ z:Double?=nil,_ flag:Bool=false)->Result {
            .init(status:status,recentCount:a.count,priorCount:b.count,recentMedian:PersonalEvidenceMath.median(a),priorMedian:PersonalEvidenceMath.median(b),scaledDelta:z,shift:flag)
        }
        guard samples.count<=400,floor.isFinite,floor>=0.000001,floor<=100000,bounds.lowerBound.isFinite,bounds.upperBound.isFinite,abs(bounds.lowerBound)<=100000,abs(bounds.upperBound)<=100000 else{return out("invalid-input")}
        let groups=Dictionary(grouping:samples.filter{(1...35).contains($0.age)},by:\.age)
        let valid=groups.values.compactMap {g -> Sample? in guard let a=g.first,g.allSatisfy({$0==a}),let v=a.value,v.isFinite,bounds.contains(v),PersonalEvidenceMath.ascii(a.era) else{return nil};return a}
        let recent=valid.filter{$0.age<=7}.sorted{$0.age<$1.age}.compactMap(\.value),prior=valid.filter{$0.age>7}.sorted{$0.age<$1.age}.compactMap(\.value)
        guard Set(valid.map(\.era)).count<=1 else{return out("context-changed",recent,prior)}
        guard recent.count>=5,prior.count>=20,let a=PersonalEvidenceMath.median(recent),let b=PersonalEvidenceMath.median(prior) else{return out("insufficient-days",recent,prior)}
        let scale=max(floor,1.4826*(PersonalEvidenceMath.median(prior.map{abs($0-b)}) ?? 0)),z=(a-b)/scale
        let directional=recent.filter {z>=0 ? $0-b>=2*scale:b-$0>=2*scale}.count
        return out("compared",recent,prior,z,abs(z)>=2 && directional>=4)
    }
}
