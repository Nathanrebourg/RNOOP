import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Local additions with explicit provenance; experimental evidence never changes a score here.
struct ImprovementsView: View {
    @EnvironmentObject var repo: Repository
    var body: some View {
        ScreenScaffold(title:"Local improvements",subtitle:"Goals, calibration and transparent trends from your own data.") {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                NavigationLink { ScoreCalculationHistoryView() } label: { Label("Calculation history",systemImage:"clock.arrow.circlepath") }
                NavigationLink { PersonalEvidenceView() } label: { Label("Personal evidence",systemImage:"chart.bar.doc.horizontal") }
                NavigationLink { PersonalReferenceView() } label: { Label("My verification measurements",systemImage:"checkmark.ruler") }
                NavigationLink { WeeklyPlanView() } label: { Label("Weekly plan",systemImage:"calendar") }
                NavigationLink { StepCalibrationView() } label: { Label("Step calibration",systemImage:"figure.walk") }
                NavigationLink { LongitudinalTrendsView(repo:repo) } label: { Label("Long-term trends",systemImage:"chart.line.uptrend.xyaxis") }
                NavigationLink { SleepClockStressLabView(repo:repo) } label: { Label("Sleep clock and night activation",systemImage:"moon.zzz") }
                NavigationLink { ExerciseGpsResearchView() } label: { Label("Exercise GPS study",systemImage:"figure.run") }
                NavigationLink { StrengthLoadHistoryView() } label: { Label("Lifting load history",systemImage:"dumbbell.fill") }
                NavigationLink { AlarmDeliveryEvidenceView() } label: { Label("Alarm delivery evidence",systemImage:"alarm") }
            }.font(StrandFont.body).foregroundStyle(StrandPalette.accent)
        }
    }
}

struct StrengthLoadHistoryView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @State private var result: StrengthLoadHistory.Result?
    @State private var failure: String?
    @State private var generation = 0
    var body: some View {
        TimelineView(.periodic(from:.now,by:60)) { context in
            content.task(id:"\(repo.deviceId)|\(repo.refreshSeq)|\(session.savedSessions)|\(WeeklyPlanSource.dayKey(context.date))|\(TimeZone.current.identifier)") { await load() }
        }
    }
    private var content: some View {
        ScreenScaffold(title:"Lifting load history",subtitle:"Logged perceived load, kept separate from heart-rate Effort.",onRefresh:{ await load() }) {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                Text("Session RPE × minutes describes how hard a logged session felt. It does not measure muscular strain from the bracelet or convert kilograms into Effort points.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                if let result {
                    window("Last 7 calendar days",result.recent7)
                    window("Last 28 calendar days",result.context28)
                    Text("Today is provisional. Missing or invalid ratings are excluded from the load total, not assumed to be zero. These overlapping windows are descriptive totals, not an injury-risk ratio.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    if result.conflictingSessions>0 {
                        Text("Conflicting session records were excluded.").font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                    }
                }
                if let failure { Text(failure).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning) }
            }
        }
    }
    private func window(_ title:LocalizedStringKey,_ value:StrengthLoadHistory.Window)->some View {
        StrandCard {
            VStack(alignment:.leading,spacing:NoopMetrics.gap) {
                Text(title).font(StrandFont.headline)
                Text(value.loadAU.map { String(format:"%.1f AU",$0) } ?? "—").font(StrandFont.number(24))
                Text("Rated sessions: \(value.ratedSessions) · Unrated or invalid: \(value.unratedSessions)")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private func load() async {
        generation += 1
        let request=generation
        failure=nil;result=nil
        guard let store=await repo.storeHandle() else { failure=String(localized:"No on-device store is available yet.");return }
        guard !Task.isCancelled,request==generation else { return }
        let owner=repo.deviceId,now=Date(),cal=Calendar(identifier:.gregorian)
        guard let lo=cal.date(byAdding:.day,value:-27,to:cal.startOfDay(for:now)) else { return }
        do {
            let rows=try await store.liftSessions(deviceId:owner,fromTs:Int(lo.timeIntervalSince1970)-86400,toTs:Int(now.timeIntervalSince1970))
            guard rows.count<=5000 else { failure=String(localized:"Too many sessions to summarize. No partial total is shown.");return }
            let samples=rows.compactMap { row -> StrengthLoadHistory.Session? in
                guard row.startTs>=0,let end=row.endTs,end>row.startTs,end<=Int(now.timeIntervalSince1970),end-row.startTs<=86400,
                      let age=LongitudinalTrends.dayAge(day:WeeklyPlanSource.dayKey(Date(timeIntervalSince1970:Double(end)),timeZone:cal.timeZone),asOf:now,calendar:cal) else { return nil }
                return .init(id:row.id,dayAge:age,durationSec:end-row.startTs,rpe:row.sessionRpe)
            }
            guard !Task.isCancelled,request==generation,repo.deviceId==owner else { return }
            result=StrengthLoadHistory.summarize(samples)
        } catch {
            guard !Task.isCancelled,request==generation,repo.deviceId==owner else { return }
            failure=String(localized:"Stored lifting sessions could not be read. No partial total is shown.") }
    }
}

struct AlarmDeliveryEvidenceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    var body: some View {
        ScreenScaffold(title:"Alarm delivery evidence",subtitle:"Stored evidence only. No Bluetooth command is sent by this screen.") {
            TimelineView(.periodic(from:.now,by:30)) { tick in
                let status=evidence(now:tick.date)
                StrandCard {
                    VStack(alignment:.leading,spacing:NoopMetrics.gap) {
                        Text(message(status)).font(StrandFont.headline)
                        Text("A matching stored readback is not a guarantee that the bracelet will vibrate. WHOOP 5.0 alarms remain experimental. Keep your phone Clock alarm as a backup.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        NavigationLink { SmartAlarmView() } label: { Text("Open alarm settings") }
                            .font(StrandFont.body).foregroundStyle(StrandPalette.accent)
                    }
                }
            }
        }
    }
    private func evidence(now:Date)->String {
        let d=UserDefaults.standard
        let planned=AppModel.nextSmartAlarmDate(minutes:behavior.smartAlarmMinutes,weekdays:behavior.smartAlarmWeekdays,
            overrides:WindDownNudge.perDayWakeOverrides,from:now).map { Int($0.timeIntervalSince1970) }
        return AlarmDeliveryEvidence.status(enabled:behavior.smartAlarmEnabled,protocolAllowed:!model.whoop5Detected || PuffinExperiment.isEnabled,
            plannedEpoch:planned,currentDevice:model.repo.deviceId,sentEpoch:d.object(forKey:"alarm.lastArmSentEpoch") as? Int,
            reportedEpoch:d.object(forKey:"alarm.lastReportedEpoch") as? Int,sentDevice:d.string(forKey:"alarm.lastArmDeviceId"),
            reportedDevice:d.string(forKey:"alarm.lastReportedDeviceId"),sentAt:d.object(forKey:"alarm.lastArmAt") as? Double,
            reportedAt:d.object(forKey:"alarm.lastReportedAt") as? Double,sentConnected:d.object(forKey:"alarm.lastArmConnected") as? Bool,now:now.timeIntervalSince1970)
    }
    private func message(_ status:String)->String {
        switch status {
        case "off":return String(localized:"Strap alarm is switched off")
        case "experimental-blocked":return String(localized:"WHOOP 5.0 experimental arming is disabled")
        case "no-future-plan":return String(localized:"No future alarm is scheduled")
        case "queued-not-sent":return String(localized:"Last request was queued, without a ready command channel")
        case "last-readback-matches":return String(localized:"Last attributable readback matches the requested time")
        case "last-readback-differs":return String(localized:"Last attributable readback reports a different time")
        case "stale-readback":return String(localized:"Stored readback predates the current request")
        case "different-source":return String(localized:"Stored evidence belongs to a different strap")
        case "different-request":return String(localized:"Stored evidence belongs to a different alarm request")
        case "invalid-timestamps":return String(localized:"Stored timestamps cannot establish delivery order")
        default:return String(localized:"No complete attributable readback is available")
        }
    }
}
