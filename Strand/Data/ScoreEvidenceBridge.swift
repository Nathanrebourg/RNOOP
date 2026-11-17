import Foundation
import StrandAnalytics
import WhoopStore

/// Captures only recipes actually observed at the final write; never reconstructs preserved scores.
enum ScoreEvidenceBridge {
    static func settings(age:Double,sex:String,maxHR:Double?,deep:Bool,v2:Bool,motion:Bool,cycle:String,
                         hrvEpoch:Double,recoveryEpoch:Double,respEpoch:Double)->[String:String]? {
        guard age.isFinite,(0...120).contains(age),maxHR.map({$0.isFinite && (30...250).contains($0)}) ?? true,
              [hrvEpoch,recoveryEpoch,respEpoch].allSatisfy({$0.isFinite && (0...4_102_444_800).contains($0)}) else{return nil}
        func bits(_ x:Double)->String {String((x==0 ? 0.0:x).bitPattern,radix:16)}
        return ["pipeline":"noop-scoring-v1","age":bits(age),"sex":sex.lowercased(),"manualHRmax":maxHR.map(bits) ?? "none",
                "hrvWindow":deep ? "deep":"whole","sleepStager":v2 ? "v2":"v1","motionWake":motion ? "1":"0","dayCycle":cycle,
                "hrvEpoch":bits(hrvEpoch),"recoveryEpoch":bits(recoveryEpoch),"respEpoch":bits(respEpoch)]
    }
    static func row(_ recipe:ScoreRecipe?,day:String,source:String,value:Double?,context:[String:String]?,now:Int)->ScoreCalculationEvidence? {
        guard let context,let r=recipe?.withContext(context),r.sourceId==source,let value,value.isFinite,r.score==value,r.replay()==value else{return nil}
        return .init(day:day,key:r.key,sourceId:r.sourceId,methodId:r.methodId,fingerprint:r.fingerprint,payload:r.payload,value:value,capturedAt:now)
    }
}
