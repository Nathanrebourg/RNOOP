import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
import StrandAnalytics
import WhoopProtocol

struct ResearchNight: Decodable {
    let schema: Int
    let dataset: String, reference: String, origin: String, subject: String, night: String, split: String
    let start: Int, end: Int
    let hr: [HRSample], gravity: [GravitySample]
    let truth: [String?]
}
private struct ResearchVector: Decodable { let ts:Int; let x:Double,y:Double,z:Double }
extension ResearchNight {
    private enum Keys:String,CodingKey { case schema,dataset,reference,origin,subject,night,split,start,end,hr,gravity,truth }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:Keys.self)
        schema=try c.decode(Int.self,forKey:.schema);dataset=try c.decode(String.self,forKey:.dataset)
        reference=try c.decode(String.self,forKey:.reference);origin=try c.decode(String.self,forKey:.origin)
        subject=try c.decode(String.self,forKey:.subject);night=try c.decode(String.self,forKey:.night);split=try c.decode(String.self,forKey:.split)
        start=try c.decode(Int.self,forKey:.start);end=try c.decode(Int.self,forKey:.end)
        hr=try c.decode([HRSample].self,forKey:.hr);truth=try c.decode([String?].self,forKey:.truth)
        // The prepared case carries native dataset vectors, with no unsupported physical-unit conversion.
        gravity=try c.decode([ResearchVector].self,forKey:.gravity).map { .init(ts:$0.ts,x:$0.x,y:$0.y,z:$0.z,unit:"dataset-native") }
    }
}
struct ResearchStageMetric: Codable {
    let precision: Double?, recall: Double?, f1: Double
    let support: Int
    let fractionBiasPP: Double?
}
struct ResearchStageResult: Codable {
    let epochs: Int
    let confusion: [[Int]]
    let accuracy: Double?, macroF1: Double?
    let kappa: Double?
    let perStage: [String:ResearchStageMetric]
    let predictions: [String]
    var coverage: ResearchPredictionCoverage? = nil
    var metricScope: String? = nil
    var fullReference: ResearchFullReferenceMetrics? = nil
}
struct ResearchFullReferenceMetrics: Codable {
    let epochs: Int
    let confusionColumns: [String]
    let confusion: [[Int]]
    let accuracy: Double, macroF1: Double
    let perStage: [String:ResearchStageMetric]
}
struct ResearchPredictionCoverage: Codable {
    let referenceEpochs: Int, predictedReferenceEpochs: Int, unknownReferenceEpochs: Int
    // Full reference denominator: unknown predictions count as incorrect, never as wake.
    let referenceAccuracy: Double
}
struct ResearchNightReport: Codable {
    let version: String, dataset: String, reference: String, origin: String, subject: String, night: String, split: String
    let qualityMethod: String, inputSHA256: String
    let quality: Double
    let variants: [String:ResearchStageResult]
}
enum ResearchBench {
    static let variantIDs=["shipped","awake-014","awake-020","awake-026","rem-018","rem-016","awake020-rem018"]
    static func config(_ id:String) throws -> RecipeConfig {
        var c=RecipeConfig.shipped
        switch id {
        case "shipped":break
        case "awake-014":c.priorAwake=log(0.14)
        case "awake-020":c.priorAwake=log(0.20)
        case "awake-026":c.priorAwake=log(0.26)
        case "rem-018":c.priorRem=log(0.18)
        case "rem-016":c.priorRem=log(0.16)
        case "awake020-rem018":c.priorAwake=log(0.20);c.priorRem=log(0.18)
        default:throw Failure.invalid("Unknown frozen recipe")
        }
        return c
    }
    enum Failure: Error { case invalid(String) }
    private static func fullReferenceMetrics(truth:[String?],prediction:[String]) -> ResearchFullReferenceMetrics {
        var matrix=Array(repeating:Array(repeating:0,count:5),count:4)
        for (index,label) in truth.enumerated() {
            guard let label,let row=stageOrder.firstIndex(of:label) else { continue }
            let column=stageOrder.firstIndex(of:prediction[index]) ?? 4
            matrix[row][column]+=1
        }
        let references=matrix.flatMap{$0}.reduce(0,+)
        let correct=(0..<4).reduce(0){$0+matrix[$1][$1]}
        var perStage=[String:ResearchStageMetric]()
        for (i,name) in stageOrder.enumerated() {
            let support=matrix[i].reduce(0,+),predicted=matrix.reduce(0){$0+$1[i]},tp=matrix[i][i]
            let denominator=support+predicted
            perStage[name] = .init(precision:predicted>0 ? Double(tp)/Double(predicted) : nil,
                recall:support>0 ? Double(tp)/Double(support) : nil,
                f1:denominator>0 ? 2*Double(tp)/Double(denominator) : 0,support:support,
                fractionBiasPP:100*Double(predicted-support)/Double(references))
        }
        return .init(epochs:references,confusionColumns:stageOrder+["unknown"],confusion:matrix,
            accuracy:Double(correct)/Double(references),macroF1:stageOrder.reduce(0){$0+perStage[$1]!.f1}/4,perStage:perStage)
    }
    static func evaluate(_ n:ResearchNight,variants:[String],inputSHA256:String=String(repeating:"0",count:64)) throws -> ResearchNightReport {
        guard n.schema==1,n.dataset=="bidsleep-1.0.1",n.reference=="dreem2-expert",["recorded","synthetic"].contains(n.origin),
              ["training","holdout"].contains(n.split),!n.subject.isEmpty,!n.night.isEmpty,n.start>=946_684_800,n.start<=4_102_444_800,n.end<=4_102_444_800,n.start%30==0,
              n.end>n.start,n.end-n.start<=86400,n.truth.count*30==n.end-n.start,n.hr.count<=500_000,n.gravity.count<=100_000,
              n.truth.compactMap({$0}).allSatisfy({stageOrder.contains($0)}),n.truth.contains(where:{$0 != nil}),
              !variants.isEmpty,Set(variants).count==variants.count else { throw Failure.invalid("Invalid research case/window/labels") }
        guard n.hr.allSatisfy({(0...300).contains($0.bpm) && $0.ts>=n.start-330 && $0.ts<n.end+390}),
              n.gravity.allSatisfy({$0.ts>=n.start-330 && $0.ts<n.end+390 && [$0.x,$0.y,$0.z].allSatisfy({$0.isFinite && abs($0)<=1e6})})
        else { throw Failure.invalid("Invalid research sensor numeric domain") }
        let seconds=Double(n.end-n.start)
        let hrCoverage=min(1,Double(Set(n.hr.filter{$0.bpm>0 && $0.ts>=n.start && $0.ts<n.end}.map(\.ts)).count)*5/seconds)
        let motionCoverage=min(1,Double(Set(n.gravity.filter{$0.ts>=n.start && $0.ts<n.end}.map(\.ts)).count)/seconds)
        var result:[String:ResearchStageResult]=[:]
        for id in variants {
            let prediction: [String]
            if id == "hierarchical-v1" {
                prediction = HierarchicalRecipe.predict(start:n.start,end:n.end,grav:n.gravity,hr:n.hr,rr:[])
            } else {
                let cfg=try config(id)
                let segments = id=="shipped"
                    ? SleepStagerV2.stageSession(start:n.start,end:n.end,grav:n.gravity,hr:n.hr,rr:[],resp:[])
                    : V2Recipe.stageSession(start:n.start,end:n.end,grav:n.gravity,hr:n.hr,rr:[],resp:[],cfg:cfg)
                prediction=epochLabels(segments,start:n.start,end:n.end)
            }
            var c=Confusion()
            for (i,t) in n.truth.enumerated() { if let t { c.add(ref:t,pred:prediction[i]) } }
            var stage:[String:ResearchStageMetric]=[:]
            for (i,name) in stageOrder.enumerated() {
                let p=c.prf(name),truth=c.m[i].reduce(0,+),pred=c.m.reduce(0){$0+$1[i]}
                stage[name] = .init(precision:p.precision.isFinite ? p.precision : nil,recall:p.recall.isFinite ? p.recall : nil,
                    f1:p.f1,support:p.support,fractionBiasPP:c.total>0 ? 100*Double(pred-truth)/Double(c.total) : nil)
            }
            var scored = ResearchStageResult(epochs:c.total,confusion:c.m,accuracy:c.total>0 ? c.accuracy : nil,
                macroF1:c.total>0 ? stageOrder.reduce(0){$0+stage[$1]!.f1}/4 : nil,
                kappa:c.kappa.isFinite ? c.kappa : nil,perStage:stage,predictions:prediction)
            if id == "hierarchical-v1" {
                scored.metricScope="conditional-on-nonunknown-predictions"
                scored.fullReference=fullReferenceMetrics(truth:n.truth,prediction:prediction)
                let references=n.truth.compactMap{$0}.count
                let correct=(0..<4).reduce(0){$0+c.m[$1][$1]}
                scored.coverage = .init(referenceEpochs:references,predictedReferenceEpochs:c.total,
                    unknownReferenceEpochs:references-c.total,referenceAccuracy:Double(correct)/Double(references))
            }
            result[id] = scored
        }
        return .init(version:"nroop-sleep-selection-v1",dataset:n.dataset,reference:n.reference,origin:n.origin,subject:n.subject,night:n.night,split:n.split,
            qualityMethod:"apple-watch-availability-v1",inputSHA256:inputSHA256,quality:min(hrCoverage,motionCoverage),variants:result)
    }
    static func runCLI() -> Never {
        do {
            let args=Array(CommandLine.arguments.dropFirst());var options:[String:String]=[:];var index=0
            while index<args.count {
                guard index+1<args.count,["--research-case","--research-output","--variants"].contains(args[index]),options[args[index]]==nil else { throw Failure.invalid("Expected research-case, research-output and optional variants") }
                options[args[index]]=args[index+1];index+=2
            }
            guard let input=options["--research-case"],let output=options["--research-output"] else { throw Failure.invalid("Missing research input/output") }
            let src=URL(fileURLWithPath:input),dst=URL(fileURLWithPath:output)
            guard src.resolvingSymlinksInPath() != dst.resolvingSymlinksInPath(),!FileManager.default.fileExists(atPath:dst.path),
                  (try src.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=64*1024*1024 else { throw Failure.invalid("Output exists, source collision or oversized case") }
            let data=try Data(contentsOf:src),night=try JSONDecoder().decode(ResearchNight.self,from:data)
            let ids=options["--variants"].map{$0.split(separator:",").map(String.init)} ?? variantIDs
            let inputHash:String
            #if canImport(CryptoKit)
            inputHash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            #else
            throw Failure.invalid("Research JSON hashing requires CryptoKit on macOS; baseline/port modes remain available")
            #endif
            let report=try evaluate(night,variants:ids,inputSHA256:inputHash)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(report).write(to:dst,options:.atomic)
            print("Research sleep case evaluated locally; no app recipe changed.");exit(0)
        } catch {
            FileHandle.standardError.write(Data(("sleeppsg research: \(error)\n").utf8));exit(2)
        }
    }
}
