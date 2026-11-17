import SwiftUI
import StrandDesign
import StrandAnalytics

/// Explicit opt-in research surface. The switch is session-local and always starts off.
struct SleepClockStressLabView: View {
    @ObservedObject var repo: Repository
    @State private var enabled=false
    @State private var selectedDay=""
    @State private var snapshot:SleepClockStressExperiment.Snapshot?
    @State private var failure:String?
    @State private var loading=false
    @State private var generation=0
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) { context in
            content.task(id:"\(enabled)|\(repo.deviceId)|\(repo.refreshSeq)|\(selectedDay)|\(WeeklyPlanSource.dayKey(context.date))|\(TimeZone.current.identifier)") {await load()}
        }
    }
    private var content:some View {
        ScreenScaffold(title:"Sleep clock and night activation",subtitle:"Experimental local comparison. No saved score is replaced.",onRefresh:{await load()}) {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                Toggle("Enable this research comparison",isOn:$enabled)
                Text("This comparison is an unvalidated design hypothesis. It measures a nocturnal cardiac activation proxy, not mental stress, sleep-stage accuracy or improved precision.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                if enabled {
                    if loading {ProgressView()}
                    if let s=snapshot {
                        Picker("Stored night",selection:Binding(get:{selectedDay.isEmpty ? s.selected.day:selectedDay},set:{selectedDay=$0})) {
                            ForEach(s.entries,id:\.day) {Text($0.day).tag($0.day)}
                        }
                        Text("Longest attributable stored session per wake date. Times and values may change after synchronization.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        StrandCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.gap) {
                                Text("Stored Rest and experimental candidate").font(StrandFont.headline)
                                component("Stored Rest",s.incumbent,scale:1)
                                component("Experimental candidate",s.result.candidate,scale:1)
                                Text("Stored Rest is shown only with matching source provenance. Missing components withhold the candidate; weights are never redistributed.")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        StrandCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.gap) {
                                Text("Component availability").font(StrandFont.headline)
                                component("Duration relative to 8 hours · 40%",s.result.duration)
                                component("Sleep efficiency · 25%",s.result.efficiency)
                                component("Bedtime and wake-time regularity · 20%",s.result.clock)
                                component("Nocturnal calmness proxy · 15%",s.result.calmness)
                                Text("Prior clock nights: \(s.result.priorNights) · Qualified baseline nights: \(s.result.baselineNights)")
                                    .font(StrandFont.footnote)
                                Text("Qualified signal windows: \(s.physiology.windows) · Sleep signal coverage: \(Int((s.physiology.coverage*100).rounded()))%")
                                    .font(StrandFont.footnote)
                                Text(stressReason(s.result.stressStatus)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        Text("Clock view: \(s.zone). Historical travel timezones are unknown; all bed and wake times use this current zone's historical clock rules.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        Text("Frozen v1: 40% duration, 25% efficiency, 20% bed/wake regularity and 15% nocturnal calmness. The eight-hour reference and these weights are provisional choices. They are not WHOOP's undisclosed formula.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let failure {Text(failure).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)}
                }
            }
        }
    }
    private func component(_ title:LocalizedStringKey,_ value:Double?,scale:Double=100)->some View {
        HStack {Text(title);Spacer();Text(value.map {String(format:"%.1f",$0*scale)} ?? "—").monospacedDigit()}
            .font(StrandFont.body)
    }
    private func stressReason(_ status:String)->String {
        switch status {
        case "qualified-nocturnal-activation-proxy":return String(localized:"Night-only HR and cleaned RR passed source, motion and coverage gates. The activation formula remains unvalidated.")
        case "insufficient-prior-night-baseline":return String(localized:"At least three qualified prior nights from the same source and RR channel are required.")
        case "unconfirmed-whoop5-source":return String(localized:"Night activation currently requires a confirmed WHOOP 5.0 or MG source.")
        case "rr-source-unavailable-or-mixed":return String(localized:"A single attributable WHOOP 5 RR channel is unavailable for this night.")
        case "incomplete-or-sparse-stages":return String(localized:"Complete known stages and non-sparse staging are required to attribute signals to sleep.")
        case "read-capped":return String(localized:"This night reached the read limit. No partial activation value is shown.")
        case "conflicting-rr-identity":return String(localized:"Conflicting RR records prevent an attributable night activation value.")
        default:return String(localized:"Night activation is unavailable: too little qualified sleeping HR, RR or motion. Awake stress is never substituted.")
        }
    }
    @MainActor private func load() async {
        generation+=1;let request=generation
        snapshot=nil;failure=nil;loading=false
        guard enabled else{return}
        let owner=repo.deviceId
        guard let store=await repo.storeHandle() else {failure=String(localized:"No on-device store is available yet.");return}
        guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return}
        loading=true
        do {
            let value=try await SleepClockStressExperiment.run(store:store,owner:owner,selectedDay:selectedDay.isEmpty ? nil:selectedDay,now:Date(),zone:.current)
            guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return}
            snapshot=value;loading=false
        } catch {
            guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return}
            failure=error.localizedDescription;loading=false
        }
    }
}
