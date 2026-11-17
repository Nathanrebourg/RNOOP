import Foundation
import CryptoKit
import StrandAnalytics
import WhoopStore

/// Strict source-tagged computed-history adapter; never merges dashboard/import source unions.
enum PersonalEvidenceData {
    struct Day:Equatable,Sendable {let day:Int,key:String,recovery:Double?,effort:Double?,sleep:Double?,hr:Double?,hrv:Double?,era:String}
    struct Snapshot {
        let days:[Day],journal:[MatchedJournalComparison.Result],labels:[String:String]
        let hr:BaselineShiftEvidence.Result,hrv:BaselineShiftEvidence.Result,forecasts:[TrainingResponseForecast.Result]
        let origin:Int
        let archived:Int
        let compatibleArchived:Int
        let legacyArchived:Int
    }
    struct Failure:LocalizedError {let errorDescription:String?;init(_ s:String){errorDescription=s}}
    static func ordinal(_ day:String)->Int? {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:0)!
        guard let age=LongitudinalTrends.dayAge(day:day,asOf:Date(timeIntervalSince1970:0),calendar:cal),(-1000000...0).contains(age) else{return nil};return -age
    }
    static func load(store:WhoopStore,owner:String,now:Date,zone:TimeZone,archive:[PersonalForecastArchive.Record]=[])async throws->Snapshot {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=zone
        let today=cal.startOfDay(for:now)
        guard let start=cal.date(byAdding:.day,value:-182,to:today),let end=cal.date(byAdding:.day,value:-1,to:today),
              let origin=ordinal(WeeklyPlanSource.dayKey(end,timeZone:zone)) else{throw Failure(String(localized:"The local calendar window is unavailable."))}
        let from=WeeklyPlanSource.dayKey(start,timeZone:zone),to=WeeklyPlanSource.dayKey(end,timeZone:zone)
        let fingerprint=try await store.analysisFingerprint()
        let sources=Array(Set([owner+"-noop",Repository.whoopSource+"-noop"])).sorted()
        var byDay:[Int:[Day]]=[:],snapshots:[String:[DailyMetric]]=[:]
        var tagWitnesses:[(String,String,String,String?)]=[]
        for source in sources {
            try Task.checkCancellation()
            let rows=try await store.dailyMetrics(deviceId:source,from:from,to:to)
            snapshots[source]=rows
            guard rows.count<=183 else{throw Failure(String(localized:"Too many local days. No partial analysis is shown."))}
            for row in rows {
                guard let d=ordinal(row.day),d<=origin,d>=origin-181 else{continue}
                try Task.checkCancellation()
                let recoveryTag=try await store.scoreInputSource(deviceId:source,day:row.day,key:"recovery")
                let strainTag=try await store.scoreInputSource(deviceId:source,day:row.day,key:"strain")
                let sleepTag=try await store.scoreInputSource(deviceId:source,day:row.day,key:"sleep_performance")
                tagWitnesses += [(source,row.day,"recovery",recoveryTag),(source,row.day,"strain",strainTag),(source,row.day,"sleep_performance",sleepTag)]
                let recovery=recoveryTag==owner,strain=strainTag==owner,sleep=sleepTag==owner
                guard recovery || strain || sleep else{continue}
                let era=SHA256.hash(data:Data((owner+"|"+source).utf8)).map{String(format:"%02x",$0)}.joined()
                byDay[d,default:[]].append(.init(day:d,key:row.day,recovery:recovery ? row.recovery:nil,effort:strain ? row.strain:nil,
                    sleep:sleep ? row.totalSleepMin:nil,hr:recovery && sleep ? row.restingHr.map(Double.init):nil,
                    hrv:recovery && sleep ? row.avgHrv:nil,era:era))
            }
        }
        // Different computed namespaces may overlap; never silently choose a conflicting cache.
        let days=byDay.values.compactMap {g->Day? in guard let first=g.first,g.allSatisfy({$0==first}) else{return nil};return first}.sorted{$0.day<$1.day}
        let map=Dictionary(uniqueKeysWithValues:days.map{($0.day,$0)})
        let journal=try await store.journalEntries(deviceId:Repository.journalDeviceId,from:from,to:to)
        let questions=Set(journal.map(\.question)).sorted()
        guard journal.count<=10000,questions.count<=50 else{throw Failure(String(localized:"Too many journal questions. The complete comparison family must fit before analysis."))}
        var labels:[String:String]=[:],experiments:[MatchedJournalComparison.Experiment]=[]
        for (index,question) in questions.enumerated() {
            let id=String(format:"q%03d",index);labels[id]=question
            let rows=journal.filter{$0.question==question}.compactMap {entry->MatchedJournalComparison.Row? in
                guard let d=ordinal(entry.day),d>=origin-179,d<origin,let current=map[d],let previous=map[d-1],let outcome=map[d+1],
                      current.era==previous.era,current.era==outcome.era,
                      let effort=previous.effort,effort.isFinite,(0...100).contains(effort),
                      let sleep=current.sleep,sleep.isFinite,(0...1440).contains(sleep),let y=outcome.recovery else{return nil}
                let context="\(current.era)|\((d+3)%7>=5 ? 1:0)|\(effort<33 ? 0:effort<66 ? 1:2)|\(sleep<360 ? 0:sleep<480 ? 1:2)"
                return .init(day:d,context:context,answer:entry.answeredYes,outcome:y)
            }
            experiments.append(.init(id:id,rows:rows))
        }
        for source in sources {
            guard try await store.dailyMetrics(deviceId:source,from:from,to:to)==snapshots[source] else{throw Failure(String(localized:"Local data changed during the comparison. Refresh to read a consistent set."))}
        }
        for (source,day,key,tag) in tagWitnesses {
            try Task.checkCancellation()
            guard try await store.scoreInputSource(deviceId:source,day:day,key:key)==tag else{throw Failure(String(localized:"Local data changed during the comparison. Refresh to read a consistent set."))}
        }
        guard try await store.analysisFingerprint()==fingerprint,
              try await store.journalEntries(deviceId:Repository.journalDeviceId,from:from,to:to)==journal else{
            throw Failure(String(localized:"Local data changed during the comparison. Refresh to read a consistent set."))
        }
        try Task.checkCancellation()
        let hr=BaselineShiftEvidence.analyze(days.map{.init(age:origin-$0.day+1,value:$0.hr,era:$0.era)},floor:3,bounds:20...250)
        let hrv=BaselineShiftEvidence.analyze(days.map{.init(age:origin-$0.day+1,value:$0.hrv,era:$0.era)},floor:5,bounds:0...1000)
        // Mutable historical scores may be rescored with later baselines: NEVER train forecasts on them.
        try PersonalForecastArchive.validate(archive)
        let captured=archive.filter{$0.owner==owner && $0.zone==zone.identifier && $0.day<=origin+1 && $0.observedAt<=Int(now.timeIntervalSince1970)}
        let training=captured.map(\.input)
        let currentEra=captured.first{$0.day==origin+1}?.era
        return Snapshot(days:days,journal:MatchedJournalComparison.analyze(experiments),labels:labels,hr:hr,hrv:hrv,
            forecasts:(1...3).map{TrainingResponseForecast.analyze(training,origin:origin+1,horizon:$0)},origin:origin+1,archived:captured.count,compatibleArchived:captured.filter{$0.era==currentEra}.count,legacyArchived:captured.filter{$0.compatibilityVersion==nil}.count)
    }
}
