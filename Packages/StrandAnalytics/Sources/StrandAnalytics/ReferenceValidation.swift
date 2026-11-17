import Foundation

/// Unit/method-separated agreement with personal reports, not a clinical accuracy certificate.
public enum ReferenceValidation {
    public struct Observation:Equatable,Sendable {
        public let id:String,order:Int,method:String,kind:String,estimate:Double,reference:Double,usedForCalibration:Bool
        public init(id:String,order:Int,method:String,kind:String,estimate:Double,reference:Double,usedForCalibration:Bool) {self.id=id;self.order=order;self.method=method;self.kind=kind;self.estimate=estimate;self.reference=reference;self.usedForCalibration=usedForCalibration}
    }
    public struct Result:Sendable {public let count:Int,excluded:Int,mae:Double?,bias:Double?,recentMAE:Double?,priorMAE:Double?}
    public static func analyze(_ rows:[Observation],method:String,kind:String)->Result {
        func empty()->Result {.init(count:0,excluded:rows.count,mae:nil,bias:nil,recentMAE:nil,priorMAE:nil)}
        guard rows.count<=256,PersonalEvidenceMath.ascii(method),["steps","sleep-start-minutes","sleep-end-minutes"].contains(kind) else{return empty()}
        let eligible=Dictionary(grouping:rows,by:\.id).values.compactMap {g -> Observation? in
            guard let a=g.first,g.allSatisfy({$0==a}),PersonalEvidenceMath.ascii(a.id),a.order>=0,a.method==method,a.kind==kind,!a.usedForCalibration,
                  a.estimate.isFinite,a.reference.isFinite,abs(a.estimate)<=100000,abs(a.reference)<=100000,
                  kind != "steps" || (a.estimate>=0 && a.reference>0) else{return nil};return a
        }.sorted {$0.order==$1.order ? $0.id<$1.id:$0.order>$1.order}
        guard !eligible.isEmpty else{return empty()}
        let error=eligible.map{$0.estimate-$0.reference}
        func mae(_ a:[Double])->Double? {a.isEmpty ? nil:a.reduce(0){$0+abs($1)}/Double(a.count)}
        return .init(count:eligible.count,excluded:rows.count-eligible.count,mae:mae(error),bias:error.reduce(0,+)/Double(error.count),
                     recentMAE:eligible.count>=10 ? mae(Array(error.prefix(10))):nil,priorMAE:eligible.count>=20 ? mae(Array(error.dropFirst(10).prefix(10))):nil)
    }
}
