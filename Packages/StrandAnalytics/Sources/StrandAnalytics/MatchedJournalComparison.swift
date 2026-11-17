import Foundation

/// Fixed next-day exploratory comparison; weekly matching does not establish causal independence.
public enum MatchedJournalComparison {
    public struct Row:Equatable,Sendable {
        public let day:Int,context:String,answer:Bool?,outcome:Double?
        public init(day:Int,context:String,answer:Bool?,outcome:Double?) {self.day=day;self.context=context;self.answer=answer;self.outcome=outcome}
    }
    public struct Experiment:Sendable {
        public let id:String,rows:[Row]
        public init(id:String,rows:[Row]) {self.id=id;self.rows=rows}
    }
    public struct Result:Sendable {
        public let id:String,pairs:Int,nonzero:Int,medianDelta:Double?,p:Double?,adjustedP:Double?,association:Bool
    }
    public static func analyze(_ experiments:[Experiment])->[Result] {
        guard experiments.count<=50,Set(experiments.map(\.id)).count==experiments.count,
              experiments.allSatisfy({PersonalEvidenceMath.ascii($0.id) && $0.rows.count<=400}) else{return []}
        let raw=experiments.sorted{$0.id<$1.id}.map { experiment -> Result in
            let groups=Dictionary(grouping:experiment.rows,by:\.day)
            let rows=groups.values.compactMap { group -> Row? in
                guard let a=group.first,group.allSatisfy({$0==a}),(0...1_000_000).contains(a.day),
                      PersonalEvidenceMath.ascii(a.context),a.answer != nil,let y=a.outcome,y.isFinite,(0...100).contains(y) else{return nil};return a
            }
            var deltas:[Double]=[]
            for block in Dictionary(grouping:rows,by:{($0.day+3)/7}).keys.sorted() {
                let items=rows.filter{($0.day+3)/7==block}.sorted{$0.day<$1.day}
                var best:(Int,Int,Double)?
                for yes in items where yes.answer == true {
                    for no in items where no.answer == false && no.context==yes.context {
                        let gap=abs(yes.day-no.day),key=min(yes.day,no.day)
                        if best == nil || gap<best!.0 || (gap==best!.0 && key<best!.1) {best=(gap,key,yes.outcome!-no.outcome!)}
                    }
                }
                if let best {deltas.append(best.2)}
            }
            let nonzero=deltas.filter{$0 != 0},n=nonzero.count,k=min(nonzero.filter{$0>0}.count,nonzero.filter{$0<0}.count)
            var p:Double?
            if n>=8 && n<=60 {
                var term=pow(0.5,Double(n)),sum=term
                if k>0 {for i in 1...k {term*=Double(n-i+1)/Double(i);sum+=term}}
                p=min(1,2*sum)
            }
            return Result(id:experiment.id,pairs:deltas.count,nonzero:n,medianDelta:PersonalEvidenceMath.median(deltas),p:p,adjustedP:nil,association:false)
        }
        let indices=raw.indices.sorted {let a=raw[$0].p ?? 1,b=raw[$1].p ?? 1;return a==b ? raw[$0].id<raw[$1].id:a<b}
        var adjusted=[Int:Double](),previous=0.0
        for (rank,index) in indices.enumerated() {previous=max(previous,min(1,(raw[index].p ?? 1)*Double(raw.count-rank)));if raw[index].p != nil {adjusted[index]=previous}}
        return raw.enumerated().map {i,r in Result(id:r.id,pairs:r.pairs,nonzero:r.nonzero,medianDelta:r.medianDelta,p:r.p,adjustedP:adjusted[i],association:adjusted[i].map{$0<0.05} ?? false)}
    }
}
