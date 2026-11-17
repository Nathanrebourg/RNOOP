import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Independent personal reports are captured separately from algorithm fitting and detected sessions.
struct PersonalReferenceView:View {
    @EnvironmentObject var repo:Repository
    @State private var records:[PersonalReferenceStore.Record]=[]
    @State private var night:CachedSleepSession?
    @State private var referenceStart=Date()
    @State private var referenceEnd=Date()
    @State private var confirmed=false
    @State private var failure:String?
    @State private var generation=0
    @State private var nightOwner:String?
    @State private var nightDay:String?
    @State private var nightZone:String?
    @State private var saving=false
    @State private var clearAlert=false
    private var own:[PersonalReferenceStore.Record] {records.filter{$0.owner==repo.deviceId}}
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) {tick in
            content.onChange(of:repo.deviceId) {_ in night=nil;nightOwner=nil;confirmed=false}.task(id:"\(repo.deviceId)|\(repo.refreshSeq)|\(WeeklyPlanSource.dayKey(tick.date))|\(TimeZone.current.identifier)") {await load()}
        }
    }
    private var content:some View {
        ScreenScaffold(title:"My verification measurements",subtitle:"Personal reports, kept separate from calibration and sleep edits.",onRefresh:{await load()}) {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                Text("For walking, use Start and Finish in guided calibration, then Save as verification only. The counted walk will not enter the calibration fit. Its estimate and applied scale are frozen at capture.").font(StrandFont.footnote)
                NavigationLink {GuidedWalkingCalibrationView()} label:{Label("Open guided walking",systemImage:"figure.walk")}
                Text("Personal reports are not laboratory truth. Sleep records compare session boundaries, not sleep stages. Original scoring settings are unknown; capture versions and walking scales stay in separate groups.").font(StrandFont.footnote)
                ForEach(Array(Set(own.map{ $0.method+"|"+$0.kind })).sorted(),id:\.self) {group in
                    let entries=own.filter{$0.method+"|"+$0.kind==group}
                    if let first=entries.first {
                        let result=ReferenceValidation.analyze(entries.map(\.observation),method:first.method,kind:first.kind)
                        NoopCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                                Text(kind(first.kind)).font(StrandFont.headline)
                                if let scale=first.scale {Text("Frozen scale: \(scale.formatted()) ticks per step")}else{Text("Captured app version: \(first.method.replacingOccurrences(of:"sleep-boundaries-capture-",with:""))")}
                                Text("Independent observations: \(result.count)")
                                metric("Mean absolute error",result.mae);metric("Signed bias",result.bias)
                                metric("Latest 10 mean absolute error",result.recentMAE);metric("Previous 10 mean absolute error",result.priorMAE)
                                Text("Positive bias means the estimate exceeds the report. Error is in steps for walks and minutes for sleep boundaries. Comparing groups or periods does not establish improvement caused by an algorithm change.").font(StrandFont.footnote)
                            }
                        }
                    }
                }
                if let night {
                    NoopCard {
                        VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                            Text("Report the latest unedited night").font(StrandFont.headline)
                            Text(Date(timeIntervalSince1970:Double(night.endTs)),style:.date)
                            DatePicker("Reported sleep start",selection:$referenceStart,displayedComponents:[.date,.hourAndMinute])
                            DatePicker("Reported sleep end",selection:$referenceEnd,displayedComponents:[.date,.hourAndMinute])
                            Toggle("I independently noted these times; these are not copied from the app estimate",isOn:$confirmed)
                            Button("Save sleep boundary reports") {saveSleep(night)}.buttonStyle(NoopButtonStyle(.secondary)).disabled(!confirmed || saving)
                            Text("This saves a separate observation. Detected sleep times and scores are not edited.").font(StrandFont.footnote)
                        }
                    }
                }else {Text("No attributable, completed, unedited night is available for a new sleep report.").font(StrandFont.footnote)}
                if !own.isEmpty {
                    Text("Saved observations").font(StrandFont.headline)
                    ForEach(own.sorted{$0.created>$1.created}.prefix(20)) {row in
                        HStack {
                            Text(kind(row.kind));Spacer()
                            Text(Date(timeIntervalSince1970:Double(row.end)),style:.date)
                            Button("Remove") {remove(row.id)}
                        }.font(StrandFont.footnote)
                    }
                }
                if let failure {Text(failure).foregroundStyle(StrandPalette.statusWarning).font(StrandFont.footnote)}
                Button("Clear all local reference records") {clearAlert=true}.buttonStyle(NoopButtonStyle(.secondary))
            }.foregroundStyle(StrandPalette.textPrimary).disabled(saving)
        }.onDisappear{generation+=1}.alert("Clear all reference records?",isPresented:$clearAlert) {
            Button("Clear",role:.destructive) {PersonalReferenceStore.clear();records=[];failure=nil}
            Button("Cancel",role:.cancel) {}
        }message:{Text("This removes reference observations for every strap on this installation. Calibration settings and detected sleep remain saved.")}
    }
    private func metric(_ label:LocalizedStringKey,_ x:Double?)->some View {HStack{Text(label);Spacer();Text(x.map{String(format:"%.2f",$0)} ?? "—").monospacedDigit()}}
    private func kind(_ key:String)->String {switch key {case "steps":return String(localized:"Counted walking steps");case "sleep-start-minutes":return String(localized:"Sleep start agreement (minutes)");default:return String(localized:"Sleep end agreement (minutes)")}}
    private func remove(_ id:String) {do {let next=try PersonalReferenceStore.load().filter{$0.id != id};try PersonalReferenceStore.save(next);records=next;failure=nil}catch{failure=error.localizedDescription}}
    private func saveSleep(_ n:CachedSleepSession) {
        let start=Int(referenceStart.timeIntervalSince1970),end=Int(referenceEnd.timeIntervalSince1970),now=Int(Date().timeIntervalSince1970)
        guard !saving,nightOwner==repo.deviceId,nightZone==TimeZone.current.identifier,confirmed,end>start,end<=now,end-start<=57600,abs(start-n.startTs)<=21600,abs(end-n.endTs)<=21600 else{failure=String(localized:"Check the reported dates and times. Each boundary must be within six hours of the stored session.");return}
        let method="sleep-boundaries-capture-"+(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown")
        let base=UUID().uuidString,owner=repo.deviceId,request=generation,source=Repository.whoopSource+"-noop",selectedDay=nightDay,zone=nightZone
        guard let selectedDay else{return}
        saving=true
        Task {defer{saving=false}
            do {
                guard let store=await repo.storeHandle() else{return}
                let rows=try await store.sleepSessions(deviceId:source,from:n.startTs,to:n.endTs,limit:501)
                guard rows.count<=500,rows.contains(n),!n.userEdited,
                      try await store.scoreInputSource(deviceId:source,day:selectedDay,key:"sleep_performance")==owner,
                      !Task.isCancelled,request==generation,owner==repo.deviceId,zone==TimeZone.current.identifier else{throw PersonalReferenceStore.failure()}
                let rowsToSave=[PersonalReferenceStore.Record(id:base+"-start",owner:owner,start:n.startTs,end:n.endTs,kind:"sleep-start-minutes",estimate:0,reference:Double(start-n.startTs)/60,method:method,created:now),
                    .init(id:base+"-end",owner:owner,start:n.startTs,end:n.endTs,kind:"sleep-end-minutes",estimate:Double(n.endTs-n.startTs)/60,reference:Double(end-n.startTs)/60,method:method,created:now)]
                try PersonalReferenceStore.add(rowsToSave);records=try PersonalReferenceStore.load();confirmed=false;night=nil;failure=nil
            }catch{if request==generation,owner==repo.deviceId{failure=error.localizedDescription}}
        }
    }

    @MainActor private func load()async {
        generation+=1;let request=generation,owner=repo.deviceId
        records=[];night=nil;nightOwner=nil;nightDay=nil;nightZone=nil;confirmed=false;failure=nil
        do {
            records=try PersonalReferenceStore.load()
            guard let store=await repo.storeHandle(),!Task.isCancelled,request==generation,owner==repo.deviceId else{return}
            let now=Date(),from=Int(now.timeIntervalSince1970)-30*86400,to=Int(now.timeIntervalSince1970),source=Repository.whoopSource+"-noop"
            let rows=try await store.sleepSessions(deviceId:source,from:from,to:to,limit:501)
            guard rows.count<=500 else{throw PersonalReferenceStore.failure()}
            let sorted=rows.filter{!$0.userEdited && $0.startTs>0 && $0.endTs>$0.startTs && $0.endTs<=to && $0.endTs-$0.startTs>=10800 && $0.endTs-$0.startTs<=57600}.sorted{$0.endTs>$1.endTs}
            var candidate:CachedSleepSession?
            for row in sorted {
                let day=WeeklyPlanSource.dayKey(Date(timeIntervalSince1970:Double(row.endTs)))
                if try await store.scoreInputSource(deviceId:source,day:day,key:"sleep_performance")==owner,
                   !records.contains(where:{$0.owner==owner && $0.start==row.startTs && $0.end==row.endTs && $0.kind.hasPrefix("sleep-")}) {candidate=row;break}
            }
            guard !Task.isCancelled,request==generation,owner==repo.deviceId else{return}
            night=candidate;nightOwner=owner;nightZone=TimeZone.current.identifier
            nightDay=candidate.map{WeeklyPlanSource.dayKey(Date(timeIntervalSince1970:Double($0.endTs)))}
            // Reference pickers deliberately do not copy the detector's boundaries.
            if let candidate {
                let wake=Date(timeIntervalSince1970:Double(candidate.endTs)),cal=Calendar.current
                referenceEnd=cal.date(bySettingHour:7,minute:0,second:0,of:wake) ?? wake
                referenceStart=cal.date(byAdding:.hour,value:-9,to:referenceEnd) ?? referenceEnd
            }
        }catch {guard !Task.isCancelled,request==generation,owner==repo.deviceId else{return};failure=error.localizedDescription}
    }
}
