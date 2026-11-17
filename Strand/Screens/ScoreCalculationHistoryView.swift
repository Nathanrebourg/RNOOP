import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore
import UniformTypeIdentifiers

/// Saved observations only: no historical recipe is inferred from today's profile.
struct ScoreCalculationHistoryView:View {
    @EnvironmentObject var repo:Repository
    @EnvironmentObject var model:AppModel
    @State private var date=Date()
    @State private var key="recovery"
    @State private var records:[ScoreCalculationEvidence]=[]
    @State private var head:ScoreCalculationEvidence?
    @State private var loading=false
    @State private var loadedOwner:String?
    @State private var recalculating=false
    @State private var failure:String?
    @State private var generation=0
    @State private var document=CalculationRecipeDocument(text:"")
    @State private var exporting=false
    var body:some View {
        ScreenScaffold(title:"Calculation history",subtitle:"Saved recipes, exact replay and changes between revisions.",onRefresh:{await load()}) {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                DatePicker("Score date",selection:$date,in:...Date(),displayedComponents:.date)
                Picker("Score",selection:$key) {
                    Text("Recovery").tag("recovery");Text("Effort").tag("strain");Text("Rest").tag("sleep_performance")
                }
                Text("Only calculations observed since this feature was added can have a saved recipe. Imported or preserved historical values can remain unknown. A replay match verifies arithmetic, not physiological accuracy.").font(StrandFont.footnote)
                Button("Refresh calculations") {
                    guard !recalculating else{return};recalculating=true
                    Task {await model.intelligence.analyzeRecent(force:true,skipIfUnchanged:false);await repo.refresh();recalculating=false;await load()}
                }.buttonStyle(NoopButtonStyle(.secondary)).disabled(recalculating)
                if loading || recalculating {ProgressView()}
                if head==nil {Text("The current score has no matching saved recipe for this strap.").font(StrandFont.footnote)}
                ForEach(Array((loadedOwner==repo.deviceId ? records:[]).enumerated()),id:\.offset) {index,row in
                    let recipe=verified(row)
                    NoopCard {
                        VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                            Text(row.fingerprint==head?.fingerprint ? "Current calculation":"Earlier calculation").font(StrandFont.headline)
                            Text(Date(timeIntervalSince1970:Double(row.capturedAt)),style:.date)
                            Text(Date(timeIntervalSince1970:Double(row.capturedAt)),style:.time)
                            Text(row.value.formatted(.number.precision(.fractionLength(2)))).font(StrandFont.number(28))
                            Text("Calculation version: \(row.methodId)").font(StrandFont.footnote)
                            Text(recipe==nil ? "Recipe cannot be verified":"Saved recipe reproduces the recorded value").font(StrandFont.footnote)
                            if let recipe {
                                if index+1<records.count,let older=verified(records[index+1]) {
                                    let changed=recipe.changedFields(from:older)
                                    Text("Changed recorded fields: \(changed.count)").font(StrandFont.footnote)
                                    ForEach(changed.filter{fieldLabel($0) != nil},id:\.self) {field in
                                        HStack {
                                            Text(fieldLabel(field)!)
                                            Spacer()
                                            Text("\(display(older,field)) → \(display(recipe,field))").monospacedDigit()
                                        }.font(StrandFont.footnote)
                                    }
                                    if changed.contains(where:{$0.hasPrefix("ctx.")}) {Text("Captured scoring settings changed between these revisions.").font(StrandFont.footnote)}
                                }
                                DisclosureGroup("Recorded calculation inputs") {
                                    ForEach(recipe.numericInputs.keys.sorted().filter{fieldLabel($0) != nil},id:\.self) {field in
                                        HStack {Text(fieldLabel(field)!);Spacer();Text(display(recipe,field)).monospacedDigit()}.font(StrandFont.footnote)
                                    }
                                }
                                Button("Export this calculation recipe") {guard loadedOwner==repo.deviceId else{return};document=CalculationRecipeDocument(text:row.payload);exporting=true}.buttonStyle(NoopButtonStyle(.secondary))
                            }
                        }
                    }
                }
                Text("Up to eight saved revisions per score and twelve thousand per computed source are retained. Unchanged recipes keep their first observation time. Missing or evicted evidence is shown as unavailable. Effort replay preserves the integrated load and final mapping; it does not recreate discarded sensor rows.").font(StrandFont.footnote)
                Text("Recipe export is a local text file for inspection. It is not a backup of learning or personal reference records.").font(StrandFont.footnote)
                if let failure {Text(failure).foregroundStyle(StrandPalette.statusWarning).font(StrandFont.footnote)}
            }.foregroundStyle(StrandPalette.textPrimary)
        }
        .task(id:"\(repo.deviceId)|\(repo.refreshSeq)|\(WeeklyPlanSource.dayKey(date))|\(key)|\(TimeZone.current.identifier)") {await load()}
        .fileExporter(isPresented:$exporting,document:document,contentType:.plainText,defaultFilename:"NOOP-calculation-\(key)-\(WeeklyPlanSource.dayKey(date)).txt") {result in if case .failure(let error)=result {failure=error.localizedDescription}}
    }
    private func verified(_ row:ScoreCalculationEvidence)->ScoreRecipe? {
        guard let r=ScoreRecipe.decode(row.payload),r.key==row.key,r.sourceId==row.sourceId,r.methodId==row.methodId,r.fingerprint==row.fingerprint,r.replay()==row.value else{return nil};return r
    }
    private func display(_ r:ScoreRecipe,_ field:String)->String {r.numericInputs[field].map{String(format:"%.3f",$0)} ?? "—"}
    private func fieldLabel(_ key:String)->LocalizedStringKey? {
        switch key {
        case "hrv":return "HRV (ms)";case "rhr","restingHR":return "Resting heart rate (bpm)";case "resp":return "Respiration (breaths/min)"
        case "sleep":return "Sleep input (0–1)";case "skin":return "Skin temperature deviation (°C)"
        case "hrvMean":return "HRV reference (ms)";case "hrvSpread":return "HRV reference spread (ms)"
        case "rhrMean":return "Resting HR reference (bpm)";case "rhrSpread":return "Resting HR spread (bpm)"
        case "respMean":return "Respiration reference";case "respSpread":return "Respiration reference spread"
        case "minutes":return "Sleep duration (minutes)";case "efficiency":return "Sleep efficiency (0–1)"
        case "deepMinutes":return "Deep sleep (minutes)";case "remMinutes":return "REM sleep (minutes)"
        case "trimp":return "Integrated cardiac load";case "denominator":return "Logarithmic mapping denominator"
        case "maxHR":return "Maximum heart rate used (bpm)";case "creditedMinutes":return "Integrated duration (minutes)"
        default:return nil
        }
    }
    @MainActor private func load()async {
        generation+=1;let request=generation,owner=repo.deviceId,day=WeeklyPlanSource.dayKey(date),metric=key
        records=[];head=nil;loadedOwner=nil;failure=nil;loading=true
        do {
            guard let store=await repo.storeHandle() else{loading=false;return}
            let source=Repository.whoopSource+"-noop"
            let current=try await store.scoreCalculationCurrent(deviceId:source,day:day,key:metric)
            let history=try await store.scoreCalculationHistory(deviceId:source,day:day,key:metric,limit:8)
            let tag=try await store.scoreInputSource(deviceId:source,day:day,key:metric)
            let daily=try await store.dailyMetrics(deviceId:source,from:day,to:day)
            let series=try await store.metricSeries(deviceId:source,key:metric,from:day,to:day)
            let value=metric=="recovery" ? daily.first?.recovery:metric=="strain" ? daily.first?.strain:series.first?.value
            guard try await store.scoreCalculationCurrent(deviceId:source,day:day,key:metric)==current,
                  try await store.scoreInputSource(deviceId:source,day:day,key:metric)==tag else{throw PersonalReferenceStore.failure()}
            guard !Task.isCancelled,request==generation,owner==repo.deviceId,day==WeeklyPlanSource.dayKey(date),metric==key else{return}
            head=current.flatMap{$0.sourceId==owner && tag==owner && $0.value==value && verified($0) != nil ? $0:nil}
            records=history.filter{$0.sourceId==owner}
            if let head {records.removeAll{$0.fingerprint==head.fingerprint};records.insert(head,at:0)}
            loadedOwner=owner;loading=false
        }catch {guard !Task.isCancelled,request==generation,owner==repo.deviceId else{return};failure=error.localizedDescription;loading=false}
    }
}
private struct CalculationRecipeDocument:FileDocument {
    static var readableContentTypes:[UTType] {[.plainText]}
    var text:String
    init(text:String) {self.text=text}
    init(configuration:ReadConfiguration)throws {text=String(data:configuration.file.regularFileContents ?? Data(),encoding:.utf8) ?? ""}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper {FileWrapper(regularFileWithContents:Data(text.utf8))}
}
