import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Default-off, read-only study; results never enter daily or fitness-age scoring.
struct ExerciseGpsResearchView: View {
    @EnvironmentObject var repo: Repository
    @AppStorage("noop.exerciseGpsResearch.enabled") private var enabled = false
    @State private var rows: [WorkoutRow] = []
    @State private var selected: ExerciseGpsResearchSession?
    @State private var loaded = false
    @State private var generation = 0

    var body: some View {
        ScreenScaffold(title: "Exercise GPS research", subtitle: "Local evidence · experimental", onRefresh: { await load() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Enable exercise GPS study", isOn: $enabled)
                        Text("Generic GPS sessions do not establish VO₂max. Review recorded distance, HR overlap and unadjusted metres per heartbeat. No scores are changed.")
                        Text("VO₂max is oxygen uptake; vVO₂max is running speed at that uptake. Neither is the oxygen cost of a particular pace.")
                    }
                }
                if enabled {
                    if !loaded { ProgressView() }
                    else if rows.isEmpty { Text("No stored GPS workouts found. Legacy polylines may lack timing and accuracy; those sessions cannot support an estimate.") }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Button { selected = .init(row: row) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(WorkoutSource.displaySport(row.sport))
                                    Text(Date(timeIntervalSince1970: Double(row.startTs)), style: .date)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Up to 30 stored GPS sessions from the last year. Source ownership and protocol confirmations apply only to the session currently being reviewed.")
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
        .task(id: "\(enabled)|\(repo.deviceId)|\(repo.refreshSeq)") { await load() }
        .sheet(item: $selected) { session in NavigationStack { ExerciseGpsSessionReview(row: session.row) } }
    }
    private func load() async {
        generation+=1;let request=generation;let owner=repo.deviceId
        rows=[];loaded=false
        guard enabled else{return}
        let all=await repo.workoutRows(days:365)
        guard !Task.isCancelled,request==generation,enabled,owner==repo.deviceId else{return}
        let routes=RouteStore.loadMap()
        rows=Array(all.filter{routes[RouteStore.key(startTs:$0.startTs,sport:$0.sport)] != nil}.sorted{$0.startTs>$1.startTs}.prefix(30))
        loaded=true
    }

}

private struct ExerciseGpsResearchSession: Identifiable {
    let row: WorkoutRow
    var id: String { "\(row.startTs)|\(row.sport)|\(row.source)" }
}

private struct ExerciseGpsSessionReview: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    let row: WorkoutRow
    @State private var ownerConfirmed = false
    @State private var input: ExerciseGpsEvidence.Input?
    @State private var result: ExerciseGpsEvidence.Result?
    @State private var age = ""
    @State private var weight = ""
    @State private var sex = -1
    @State private var repeatSeconds = ""
    @State private var protocolConfirmed = false
    @State private var generation = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("Review this session").font(StrandFont.title2)
                Text("Workout source: \(row.source)")
                Text("Only your selected strap is read after you confirm it recorded this session.")
                Toggle("I confirm this strap recorded this session", isOn: $ownerConfirmed)
                Text("This confirmation selects one stored HR source. Current strap selection alone does not prove historical ownership.")
                if let result {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            metric("GPS distance (m)", result.distanceM)
                            metric("Elapsed speed (m/s)", result.speedMps)
                            metric("Time-weighted HR (bpm)", result.meanHr)
                            metric("HR overlap (s)", result.hrCoveredS)
                            metric("Unadjusted metres per heartbeat", result.metersPerBeat)
                            Text("VO₂max withheld for generic sessions")
                            Text("Eligibility checks: \(result.reasons.map(reason).joined(separator: "; "))")
                        }
                    }
                }
                if ExerciseGpsResearchAdapter.sport(row.sport) == "walking" { walkProtocol }
                Text("Terrain, wind, temperature, fatigue and HR measurement errors affect these observations. No oxygen cost or vVO₂max is inferred.")
                Link("Kline 1987 · one-mile walk study", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/3600239/")!)
                Link("Olher 2019 · vVO₂max study", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/30802508/")!)
            }.padding(NoopMetrics.space4)
        }
        .foregroundStyle(StrandPalette.textPrimary)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task(id: "\(ownerConfirmed)|\(repo.deviceId)|\(repo.refreshSeq)") { await load() }
        .onChange(of: repo.deviceId) { _ in ownerConfirmed = false; protocolConfirmed = false; input = nil; result = nil }
    }
    private var walkProtocol: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Retrospective one-mile walk estimate").font(StrandFont.title2)
                Text("Only for an already completed Kline-style test: a flat, independently measured mile walked throughout, with two fastest trials within 30 seconds. Select the faster trial. GPS distance alone does not verify the protocol. No exercise test is requested here.")
                TextField("Age at test (30–69 years)", text: $age)
                TextField("Body weight at test (kg)", text: $weight)
                Picker("Study sex coefficient", selection: $sex) {
                    Text("Select study coefficient").tag(-1)
                    Text("Female (0)").tag(0)
                    Text("Male (1)").tag(1)
                }
                TextField("Other fastest trial duration (seconds)", text: $repeatSeconds)
                Toggle("I confirm the measured flat mile, walking-only protocol and repeated trials", isOn: $protocolConfirmed)
                if let estimate {
                    metric("Experimental VO₂max (L/min)", estimate.litersPerMinute)
                    metric("Converted VO₂max (mL/kg/min)", estimate.mlKgMin)
                    Text("Population prediction, not measured oxygen uptake. Published cross-validation error: 0.355 L/min (standard error, not an individual confidence interval). Final recorded HR supplies the fourth-quarter observation; no extrapolation to HRmax.")
                } else {
                    Text("Estimate withheld: confirm the protocol, source and study inputs. Recorded GPS must be within 3% of a mile with passing timing, accuracy, stops and HR checks, including HR within five seconds of the finish.")
                }
            }
        }
    }
    private var estimate: ExerciseGpsEvidence.KlineEstimate? {
        guard let input, let result, let a = Double(age), let w = Double(weight), let repeatS = Double(repeatSeconds) else { return nil }
        return ExerciseGpsResearchAdapter.kline(row: row, input: input, evidence: result, age: a, weightKg: w, sex: sex,
                                                repeatSeconds: repeatS, confirmed: protocolConfirmed)
    }
    private func metric(_ label: String, _ value: Double?) -> some View {
        HStack { Text(LocalizedStringKey(label)); Spacer(); Text(value.map { String(format: "%.2f", $0) } ?? "—") }
    }
    private func reason(_ code: String) -> String { NSLocalizedString("exercise.gps." + code, value: code.replacingOccurrences(of: "-", with: " "), comment: "Exercise GPS eligibility reason") }
    private func load() async {
        generation+=1;let request=generation
        input=nil;result=nil;protocolConfirmed=false
        let selectedOwner=repo.deviceId,confirmed=ownerConfirmed
        let owner=confirmed ? selectedOwner:nil
        let raw=owner == nil ? []:await repo.hrSamples(deviceIds:[selectedOwner],from:row.startTs,to:row.endTs,limit:100001)
        guard !Task.isCancelled,request==generation,selectedOwner==repo.deviceId,confirmed==ownerConfirmed else{return}
        let hr=raw.map {ExerciseGpsEvidence.HeartRate(time:Double($0.ts),bpm:Double($0.bpm),owner:selectedOwner)}
        let next=ExerciseGpsResearchAdapter.input(row:row,route:RouteStore.loadWithPoints(startTs:row.startTs,sport:row.sport),owner:owner,heartRates:hr)
        input=next;result=ExerciseGpsEvidence.evaluate(next)
    }
}
