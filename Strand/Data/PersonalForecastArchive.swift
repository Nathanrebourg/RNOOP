import Foundation
import CryptoKit
import StrandAnalytics
import WhoopStore

/// First-capture-only evening observations. Apple-local research state, not shared backup/wire data.
enum PersonalForecastArchive {
    struct Record:Codable,Equatable {
        var owner:String,day:Int,observedAt:Int,zone:String,recovery:Double,effort:Double,era:String
        var compatibilityVersion:String? = nil
        var captureVersion:String? = nil
        var input:TrainingResponseForecast.Day {.init(day:day,recovery:recovery,effort:effort,era:era)}
    }
    static let key="personalEvidence.forecastArchive.local.v1"
    static func failure()->NSError {NSError(domain:"PersonalForecastArchive",code:1,userInfo:[NSLocalizedDescriptionKey:String(localized:"Evening snapshots must be valid, unique and captured after 20:00. Existing daily snapshots cannot be overwritten.")])}
    static func validate(_ rows:[Record])throws {
        guard rows.count<=400 else{throw failure()}
        var identities=Set<String>()
        for row in rows {
            guard !row.owner.isEmpty,row.owner.count<=200,(0...1_000_000).contains(row.day),row.observedAt>0,row.observedAt<=4_102_444_800,
                  let zone=TimeZone(identifier:row.zone),!row.era.isEmpty,row.era.utf8.count<=200,row.era.utf8.allSatisfy({(32...126).contains($0)}),
                  row.recovery.isFinite,(0...100).contains(row.recovery),row.effort.isFinite,(0...100).contains(row.effort),
                  identities.insert("\(row.owner)|\(row.day)").inserted else{throw failure()}
            if let version=row.compatibilityVersion {
                guard version==LearningCompatibility.version,row.era.utf8.count==64,row.era.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw failure()}
            }
            let date=Date(timeIntervalSince1970:Double(row.observedAt));var cal=Calendar(identifier:.gregorian);cal.timeZone=zone
            guard cal.component(.hour,from:date)>=20,PersonalEvidenceData.ordinal(WeeklyPlanSource.dayKey(date,timeZone:zone))==row.day else{throw failure()}
        }
    }
    static func load(defaults:UserDefaults = .standard)throws->[Record] {
        guard let data=defaults.data(forKey:key) else{return []};guard data.count<=262144 else{throw failure()}
        let rows=try JSONDecoder().decode([Record].self,from:data);try validate(rows);return rows
    }
    static func append(_ row:Record,defaults:UserDefaults = .standard)throws {
        let rows=try load(defaults:defaults)+[row];try validate(rows)
        let data=try JSONEncoder().encode(rows);guard data.count<=262144 else{throw failure()};defaults.set(data,forKey:key)
    }
    static func clear(defaults:UserDefaults = .standard) {defaults.removeObject(forKey:key)}
    static func capture(store:WhoopStore,owner:String,now:Date,zone:TimeZone,clock:()->Date = {Date()})async throws->Record {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=zone
        guard cal.component(.hour,from:now)>=20 else{throw failure()}
        let day=WeeklyPlanSource.dayKey(now,timeZone:zone),source=Repository.whoopSource+"-noop"
        let rows=try await store.dailyMetrics(deviceId:source,from:day,to:day)
        guard rows.count==1,let row=rows.first,let recovery=row.recovery,let effort=row.strain,
              try await store.scoreInputSource(deviceId:source,day:day,key:"recovery")==owner,
              try await store.scoreInputSource(deviceId:source,day:day,key:"strain")==owner,
              let ordinal=PersonalEvidenceData.ordinal(day) else{throw failure()}
        let recoveryEvidence=try await store.scoreCalculationCurrent(deviceId:source,day:day,key:"recovery")
        let effortEvidence=try await store.scoreCalculationCurrent(deviceId:source,day:day,key:"strain")
        guard let r=recoveryEvidence,let e=effortEvidence,r.sourceId==owner,e.sourceId==owner,r.value==recovery,e.value==effort,r.capturedAt<=Int(now.timeIntervalSince1970),e.capturedAt<=Int(now.timeIntervalSince1970),
              let rr=ScoreRecipe.decode(r.payload),let er=ScoreRecipe.decode(e.payload),rr.sourceId==owner,er.sourceId==owner,
              rr.key=="recovery",er.key=="strain",rr.methodId==r.methodId,er.methodId==e.methodId,
              rr.fingerprint==r.fingerprint,er.fingerprint==e.fingerprint,rr.replay()==recovery,er.replay()==effort,
              rr.context==er.context,
              let manifest=LearningCompatibility.manifest(source:owner,zone:zone.identifier,recoveryMethod:rr.methodId,effortMethod:er.methodId,settings:rr.context) else{
            throw NSError(domain:"PersonalForecastArchive",code:2,userInfo:[NSLocalizedDescriptionKey:String(localized:"Scoring recipes are unavailable or incompatible. Refresh calculations before capturing a recipe-compatible snapshot.")])
        }
        guard try await store.scoreCalculationCurrent(deviceId:source,day:day,key:"recovery")==recoveryEvidence,
              try await store.scoreCalculationCurrent(deviceId:source,day:day,key:"strain")==effortEvidence,
              try await store.dailyMetrics(deviceId:source,from:day,to:day)==rows,
              try await store.scoreInputSource(deviceId:source,day:day,key:"recovery")==owner,
              try await store.scoreInputSource(deviceId:source,day:day,key:"strain")==owner else{throw failure()}
        try Task.checkCancellation()
        let finished=clock()
        guard finished>=now,finished.timeIntervalSince(now)<=300,WeeklyPlanSource.dayKey(finished,timeZone:zone)==day else{throw failure()}
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
        let era=SHA256.hash(data:Data(manifest.utf8)).map{String(format:"%02x",$0)}.joined()
        let result=Record(owner:owner,day:ordinal,observedAt:Int(finished.timeIntervalSince1970),zone:zone.identifier,recovery:recovery,effort:effort,era:era,compatibilityVersion:LearningCompatibility.version,captureVersion:version)
        try validate([result]);return result
    }
}
