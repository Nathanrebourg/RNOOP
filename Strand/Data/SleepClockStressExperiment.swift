import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Explicit screen-only reads. Never participates in IntelligenceEngine or persists a candidate.
enum SleepClockStressExperiment {
    struct Entry: Sendable { let day: String; let night: SleepClockStressComparison.Night; let computedSource: String }
    struct Snapshot: Sendable {
        let entries: [Entry]
        let selected: Entry
        let result: SleepClockStressComparison.Result
        let physiology: SleepClockStressComparison.Physiology
        let incumbent: Double?
        let zone: String
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription=message }
    }
    private struct StoredStage: Decodable { let start: Int; let end: Int; let stage: String }
    static func entry(_ row: CachedSleepSession, zone: TimeZone, computedSource: String = "") -> Entry? {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=zone
        let start=row.effectiveStartTs,end=row.endTs
        guard start>=0,end>start,Double(end)-Double(start)>=10_800,Double(end)-Double(start)<=57_600 else{return nil}
        let bed=Date(timeIntervalSince1970:Double(start)),wake=Date(timeIntervalSince1970:Double(end))
        guard let ordinal=cal.ordinality(of:.day,in:.era,for:wake) else{return nil}
        let stages=row.stagesJSON.flatMap {$0.data(using:.utf8)}.flatMap {try? JSONDecoder().decode([StoredStage].self,from:$0)}?.map {
            SleepClockStressComparison.Stage(start:$0.start,end:$0.end,kind:$0.stage == "wake" ? "awake":$0.stage)
        }
        return Entry(day:WeeklyPlanSource.dayKey(wake,timeZone:zone),night:.init(day:ordinal,start:start,end:end,
            bedtimeMinute:cal.component(.hour,from:bed)*60+cal.component(.minute,from:bed),
            wakeMinute:cal.component(.hour,from:wake)*60+cal.component(.minute,from:wake),stages:stages,sparse:row.stagingSparse != false),computedSource:computedSource)
    }
    static func run(store: WhoopStore, owner: String, selectedDay: String?, now: Date, zone: TimeZone) async throws -> Snapshot {
        let nowTs=Int(now.timeIntervalSince1970)
        var cal=Calendar(identifier:.gregorian);cal.timeZone=zone
        guard let fromDate=cal.date(byAdding:.day,value:-60,to:cal.startOfDay(for:now)) else {
            throw Failure(String(localized:"The local calendar window is unavailable."))
        }
        let fingerprint=try await store.analysisFingerprint()
        let sources=[owner+"-noop",Repository.whoopSource+"-noop"].reduce(into:[String]()) { if !$0.contains($1) {$0.append($1)} }
        var attributable:[Entry]=[]
        for source in sources {
            let stored=try await store.sleepSessions(deviceId:source,from:Int(fromDate.timeIntervalSince1970),to:nowTs,limit:501)
            guard stored.count<501 else{throw Failure(String(localized:"Too many computed sessions. No partial comparison is shown."))}
            var tags:[String:Bool]=[:]
            for row in stored where row.endTs<=nowTs {
                guard let item=entry(row,zone:zone,computedSource:source) else{continue}
                if tags[item.day]==nil {
                    tags[item.day]=(try await store.scoreInputSource(deviceId:source,day:item.day,key:"sleep_performance")) == owner
                }
                if tags[item.day] == true { attributable.append(item) }
            }
        }
        let historyEntries=Dictionary(grouping:attributable,by:\.day).values.compactMap { items -> Entry? in
            var unique:[Entry]=[]
            for item in items where !unique.contains(where:{$0.night==item.night}) {unique.append(item)}
            let sorted=unique.sorted {($0.night.end-$0.night.start)>($1.night.end-$1.night.start)}
            guard let first=sorted.first else{return nil}
            if sorted.count>1,sorted[1].night.end-sorted[1].night.start == first.night.end-first.night.start {return nil}
            return first
        }.sorted {$0.day>$1.day}
        let today=cal.ordinality(of:.day,in:.era,for:now) ?? 0
        let entries=historyEntries.filter{$0.night.day>=today-29}
        guard let selected=selectedDay.flatMap({day in entries.first {$0.day == day}}) ?? (selectedDay == nil ? entries.first:nil) else {
            throw Failure(String(localized:"No stored NOOP night with matching input-source provenance is available for this strap."))
        }
        let confirmed=try await store.isWhoop5RRSource(deviceId:owner)
        let prior=historyEntries.filter {$0.night.day<selected.night.day && selected.night.day-$0.night.day<=28 && $0.night.end<=selected.night.start}
        var summaries:[SleepClockStressComparison.Physiology]=[]
        // At most eight individual session windows, loaded sequentially. No pooled month-wide raw read.
        for entry in [selected]+Array(prior.prefix(7)) {
            try Task.checkCancellation()
            if !confirmed {
                summaries.append(SleepClockStressComparison.physiology(night:entry.night,hr:[],rr:[],gravity:[],confirmedWhoop5:false))
                continue
            }
            let n=entry.night
            let hr=try await store.hrSamples(deviceId:owner,from:n.start,to:n.end-1,limit:60_001)
            let rr=try await store.rrIntervals(deviceId:owner,from:n.start,to:n.end-1,limit:120_001)
            let gravity=try await store.gravitySamples(deviceId:owner,from:n.start,to:n.end-1,limit:60_001)
            let summary=await Task.detached(priority:.utility) {
                SleepClockStressComparison.physiology(night:n,hr:hr,rr:rr,gravity:gravity,confirmedWhoop5:true,
                    readCapped:hr.count>60_000 || rr.count>120_000 || gravity.count>60_000)
            }.value
            summaries.append(summary)
        }
        try Task.checkCancellation()
        let points=try await store.metricSeries(deviceId:selected.computedSource,key:"sleep_performance",from:selected.day,to:selected.day)
        let source=try await store.scoreInputSource(deviceId:selected.computedSource,day:selected.day,key:"sleep_performance")
        let incumbent=source == owner ? points.first(where:{$0.day == selected.day && $0.value.isFinite && (0...100).contains($0.value)})?.value:nil
        guard try await store.analysisFingerprint() == fingerprint else {
            throw Failure(String(localized:"Local data changed during the comparison. Refresh to read a consistent set."))
        }
        guard let physiology=summaries.first else {throw Failure(String(localized:"The selected night could not be analyzed."))}
        let result=SleepClockStressComparison.analyze(target:selected.night,history:prior.map(\.night),now:nowTs,
            physiology:physiology,priorPhysiology:Array(summaries.dropFirst()))
        return Snapshot(entries:entries,selected:selected,result:result,physiology:physiology,incumbent:incumbent,zone:zone.identifier)
    }
}
