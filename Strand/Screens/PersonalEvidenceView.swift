import SwiftUI
import StrandDesign
import StrandAnalytics

/// Session-local opt-in; no result enters the headline scores or recommendation engine.
struct PersonalEvidenceView:View {
    @EnvironmentObject var repo:Repository
    @State private var enabled=false
    @State private var snapshot:PersonalEvidenceData.Snapshot?
    @State private var failure:String?
    @State private var loading=false
    @State private var generation=0
    @State private var captureBusy=false
    @State private var archiveAlert=false
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) {tick in
            content.task(id:"\(enabled)|\(repo.deviceId)|\(repo.refreshSeq)|\(WeeklyPlanSource.dayKey(tick.date))|\(TimeZone.current.identifier)") {await load()}
        }
    }
    private var content:some View {
        ScreenScaffold(title:"Personal evidence",subtitle:"Matched habits, reference shifts and tested forecasts.",onRefresh:{await load()}) {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                Toggle("Enable personal research",isOn:$enabled)
                Button("Clear forecast snapshot archive") {archiveAlert=true}.buttonStyle(NoopButtonStyle(.secondary)).disabled(captureBusy)
                Text("Experimental comparisons only. Existing scores and recommendations are unchanged. Missing evidence can withhold every result.").font(StrandFont.footnote)
                NavigationLink {PersonalReferenceView()} label:{Label("My verification measurements",systemImage:"checkmark.ruler")}
                if enabled {
                    if loading {ProgressView()}
                    if let s=snapshot {
                        NoopCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                                Text("Matched journal comparisons").font(StrandFont.headline)
                                Text("Native journal only. Yes and No days are matched within a week on prior-day Effort, same-morning sleep and weekday/weekend. Unlogged days are unknown. The outcome is next-day Recovery.").font(StrandFont.footnote)
                                if s.journal.isEmpty {Text("No eligible journal questions yet.")}
                                ForEach(s.journal,id:\.id) {row in
                                    VStack(alignment:.leading,spacing:NoopMetrics.space2) {
                                        Text(s.labels[row.id] ?? row.id).font(StrandFont.body)
                                        Text("Weekly pairs: \(row.pairs) · Nonzero pairs: \(row.nonzero)")
                                        value("Median paired difference (points)",row.medianDelta)
                                        value("Holm-adjusted nominal p",row.adjustedP,digits:4)
                                        Text(row.association ? "Exploratory association after correction":"No association established by this comparison")
                                    }.font(StrandFont.footnote)
                                }
                                Text("One pair per week reduces repetition. Eight nonzero pairs are required for a nominal test. Correction covers all displayed questions, including unavailable tests. Other habits and dependence remain uncontrolled; this is not a causal effect or a probability that a conclusion is true.").font(StrandFont.footnote)
                            }
                        }
                        NoopCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                                Text("Personal reference shifts").font(StrandFont.headline)
                                shift("Resting heart rate",s.hr)
                                shift("Heart rate variability",s.hrv)
                                Text("Recent 7 versus previous 28 completed days. At least 5 recent and 20 prior observations are required. A provisional shift needs a two-scale median change and four consistent recent observations. No baseline is reset. Illness, adaptation and recording changes are not distinguished automatically.").font(StrandFont.footnote)
                                Text("Computed cache source tags are checked. Historical scoring settings and calibration changes are unknown, so an observed shift does not prove a physiological change.").font(StrandFont.footnote)
                            }
                        }
                        NoopCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                                Text("Training response forecasts").font(StrandFont.headline)
                                Text("Uses first-captured evening snapshots only. Current Effort is partial at capture; Recovery is the value observed then. Remaining and future activity are unknown. Recalculated historical caches never train these forecasts.").font(StrandFont.footnote)
                                Text("Saved snapshots for this strap and zone: \(s.archived)")
                                Text("Compatible with today's capture: \(s.compatibleArchived) · Legacy context: \(s.legacyArchived)").font(StrandFont.footnote)
                                Text("Interface updates preserve compatible learning. Changes to numerical recipes or captured scoring settings separate contexts. Older captures remain saved in their original context; missing historical settings are not guessed.").font(StrandFont.footnote)
                                NavigationLink {ScoreCalculationHistoryView()} label:{Text("View calculation history")}
                                Button("Capture today's evening snapshot") {capture()}.buttonStyle(NoopButtonStyle(.secondary)).disabled(captureBusy)
                                Text("Capture once per day after 20:00. The first capture is immutable; missed days are not backfilled. Source, numerical-recipe, setting or timezone changes separate learning contexts. Enough future observations must accumulate before any forecast appears.").font(StrandFont.footnote)
                                ForEach(Array(s.forecasts.enumerated()),id:\.offset) {i,row in
                                    VStack(alignment:.leading,spacing:NoopMetrics.space2) {
                                        Text("Horizon: \(i+1) days")
                                        value("Experimental Recovery forecast",row.prediction)
                                        Text("Training examples: \(row.training) · Evaluated forecasts: \(row.evaluated)")
                                        value("Forecast mean absolute error",row.modelMAE)
                                        value("Persistence mean absolute error",row.baselineMAE)
                                        Text(row.prediction == nil ? "Forecast withheld: insufficient evidence or no measured improvement":"Experimental forecast passed its historical comparison")
                                    }.font(StrandFont.footnote)
                                }
                                Text("Each historical prediction trains only on outcomes already available then, with nonoverlapping intervals. At least eight training examples and eight evaluated forecasts are required. A forecast must reduce mean absolute error by at least 10% versus keeping captured Recovery unchanged. This engineering gate is not validation for future days or an injury-risk estimate.").font(StrandFont.footnote)
                            }
                        }
                    }
                    if let failure {Text(failure).foregroundStyle(StrandPalette.statusWarning)}
                }
            }.foregroundStyle(StrandPalette.textPrimary)
        }.alert("Clear forecast snapshots?",isPresented:$archiveAlert) {
            Button("Clear",role:.destructive) {PersonalForecastArchive.clear();Task{await load()}}
            Button("Cancel",role:.cancel) {}
        }message:{Text("This removes the local forecast research archive for every strap. It does not change daily scores.")}
    }
    private func capture() {
        guard !captureBusy else{return};captureBusy=true
        let owner=repo.deviceId,zone=TimeZone.current,request=generation
        Task {defer{captureBusy=false}
            do {
                guard let store=await repo.storeHandle() else{return}
                let record=try await PersonalForecastArchive.capture(store:store,owner:owner,now:Date(),zone:zone)
                guard !Task.isCancelled,request==generation,owner==repo.deviceId,zone.identifier==TimeZone.current.identifier,enabled,record.observedAt<=Int(Date().timeIntervalSince1970),record.day==PersonalEvidenceData.ordinal(WeeklyPlanSource.dayKey(Date(),timeZone:zone)) else{return}
                try PersonalForecastArchive.append(record);await load()
            }catch{if owner==repo.deviceId{failure=error.localizedDescription}}
        }
    }
    private func value(_ title:LocalizedStringKey,_ v:Double?,digits:Int=2)->some View {HStack{Text(title);Spacer();Text(v.map{String(format:"%.*f",digits,$0)} ?? "—").monospacedDigit()}}
    private func shift(_ title:LocalizedStringKey,_ row:BaselineShiftEvidence.Result)->some View {
        VStack(alignment:.leading,spacing:NoopMetrics.space2) {
            Text(title).font(StrandFont.body)
            Text("Recent observations: \(row.recentCount) · Prior observations: \(row.priorCount)")
            value("Recent median",row.recentMedian);value("Prior median",row.priorMedian)
            Text(row.scaledDelta == nil ? "Shift comparison unavailable":row.shift ? "Sustained descriptive shift observed":"No sustained shift at this provisional threshold")
        }.font(StrandFont.footnote)
    }
    @MainActor private func load()async {
        generation+=1;let request=generation,owner=repo.deviceId
        snapshot=nil;failure=nil;loading=false
        guard enabled,let store=await repo.storeHandle(),!Task.isCancelled,request==generation else{return}
        loading=true
        do {
            let next=try await PersonalEvidenceData.load(store:store,owner:owner,now:Date(),zone:.current,archive:PersonalForecastArchive.load())
            guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return}
            snapshot=next;loading=false
        }catch {guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return};failure=error.localizedDescription;loading=false}
    }
}
