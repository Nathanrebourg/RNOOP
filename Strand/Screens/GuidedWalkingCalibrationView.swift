import SwiftUI
import StrandAnalytics
import StrandDesign

/// User-triggered capture of a time window, followed by bounded reads after ordinary synchronization.
struct GuidedWalkingCalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var draft: GuidedCalibrationDraft?
    @State private var countedSteps = ""
    @State private var countedConfirmed = false
    @State private var inspected: GuidedWalkingTrial.Result?
    @State private var inspectedID: String?
    @State private var failure: String?
    @State private var corruptSaved = false
    @State private var busy = false
    @State private var applying = false
    @State private var applied = false
    @State private var resetAlert = false
    @State private var generation = 0
    @State private var work: Task<Void,Never>?
    private var sameOwner: Bool { draft == nil || draft?.owner == model.repo.deviceId }
    private var proposal: StepCalibration.Result { StepCalibration.evaluate(draft?.trials ?? []) }
    var body: some View {
        ScreenScaffold(title:"Guided walking calibration",subtitle:"Start and finish in the app. Raw records are inspected after synchronization.") {
            VStack(alignment:.leading,spacing:NoopMetrics.sectionGap) {
                instructions
                if !sameOwner {
                    Text("Saved trials belong to another selected strap. Select that strap again or clear this local calibration.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                }
                if sameOwner && !corruptSaved {
                    captureCard
                    if let pending=draft?.pending,pending.end != nil { inspectionCard(pending) }
                    trialsCard
                    previewCard
                }
                if let failure { Text(failure).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning) }
                if draft != nil || corruptSaved {
                    Button("Clear saved walking calibration") { resetAlert=true }
                        .buttonStyle(NoopButtonStyle(.secondary)).disabled(busy || applying)
                }
            }.disabled(applying)
        }
        .task(id:model.repo.deviceId) { restore() }
        .onDisappear { generation+=1;work?.cancel();busy=false }
        .navigationBarBackButtonHidden(applying)
        .interactiveDismissDisabled(applying)
        .alert("Clear this local calibration?",isPresented:$resetAlert) {
            Button("Clear trials",role:.destructive) {
                GuidedCalibrationDraft.clear();draft=nil;corruptSaved=false;failure=nil;inspected=nil;inspectedID=nil
                countedSteps="";countedConfirmed=false;applied=false
            }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Saved walking trials and the pending window will be removed. Your applied step scale remains saved.") }
    }
    private var instructions: some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Two buttons, one counted walk").font(StrandFont.headline)
                Text("Stand still for a few seconds, tap Start walk, then walk while counting your steps. Stand still again for a few seconds before tapping Finish walk.")
                Text("Use at least 100 counted steps and a window of one to 60 minutes. The time limits and stationary checks are workflow rules, not accuracy guarantees.")
                Text("The app records the time window, not a new sensor stream. Let the selected bracelet synchronize normally, then inspect its stored records. Missing or ambiguous records refuse the trial.")
                Text("Complete 3–8 separate walks with different lengths. Only Apply scale changes the existing step setting. Local progress is saved so you can leave this screen to synchronize.")
            }.font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
    }
    private var captureCard: some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                if let pending=draft?.pending {
                    HStack { Text("Walk started");Spacer();Text(Date(timeIntervalSince1970:Double(pending.start)),style:.time) }
                    if let end=pending.end {
                        HStack { Text("Walk finished");Spacer();Text(Date(timeIntervalSince1970:Double(end)),style:.time) }
                    } else {
                        TimelineView(.periodic(from:.now,by:1)) { context in
                            let elapsed=max(0,Int(context.date.timeIntervalSince1970)-pending.start)
                            VStack(alignment:.leading,spacing:NoopMetrics.space2) {
                                Text("Elapsed: \(elapsed) seconds").font(StrandFont.captionNumber)
                                Button("Finish walk") { finish() }.buttonStyle(NoopButtonStyle(.primary))
                                    .disabled(elapsed<GuidedWalkingTrial.minimumDuration || busy)
                            }
                        }
                    }
                    Button("Discard this walk") {
                        var next=draft!;next.pending=nil
                        if commit(next) { inspected=nil;inspectedID=nil;countedSteps="";countedConfirmed=false }
                    }.buttonStyle(NoopButtonStyle(.secondary)).disabled(busy)
                } else {
                    Button("Start walk") { begin() }.buttonStyle(NoopButtonStyle(.primary))
                        .disabled(busy)
                }
                if busy { ProgressView("Reading local records…") }
            }.font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
        }
    }
    private func inspectionCard(_ pending:GuidedCalibrationDraft.Pending)->some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Inspect after synchronization").font(StrandFont.headline)
                Text("If the capture is incomplete, finish normal bracelet synchronization and inspect again. The app cannot certify that every strap record has arrived.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                Button("Inspect walking records") { inspect(pending) }.buttonStyle(NoopButtonStyle(.secondary)).disabled(busy)
                if let inspected,inspectedID==pending.id {
                    if let ticks=inspected.retainedTicks {
                        Text("Retained unscaled ticks: \(ticks)").font(StrandFont.bodyNumber)
                        Text("Observed samples: \(inspected.sampleCount)").font(StrandFont.footnote)
                        TextField("Steps you counted",text:$countedSteps).guidedCountInput()
                        Toggle("I counted only this walk with the same strap and kept still at both boundaries.",isOn:$countedConfirmed)
                            .font(StrandFont.footnote).tint(StrandPalette.accent)
                        Button("Save as verification only") { saveVerification(pending,ticks:ticks) }.buttonStyle(NoopButtonStyle(.secondary)).disabled(busy || !countedConfirmed)
                        Text("Verification walks are stored separately and never added to the calibration fit.").font(StrandFont.footnote)
                        Button("Save this trial") { saveTrial(pending,ticks:ticks) }.buttonStyle(NoopButtonStyle(.secondary))
                            .disabled(busy || !countedConfirmed || (draft?.completed.count ?? 0)>=StepCalibration.maximumTrials)
                        if (draft?.completed.count ?? 0)>=StepCalibration.maximumTrials {Text("Calibration already has eight trials. Further walks can be saved as verification only.").font(StrandFont.footnote)}
                    } else if let issue=inspected.issue {
                        Text(message(issue)).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                    }
                }
            }.foregroundStyle(StrandPalette.textPrimary)
        }
    }
    private var trialsCard: some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Saved guided trials").font(StrandFont.headline)
                ForEach(draft?.completed ?? [],id:\.id) { row in
                    HStack {
                        Text("\(row.countedSteps) steps · \(row.ticks) retained ticks").font(StrandFont.captionNumber)
                        Spacer()
                        Button("Remove") { var next=draft!;next.completed.removeAll{$0.id==row.id};_ = commit(next) }
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.accent).disabled(busy)
                    }
                }
                if draft?.completed.isEmpty ?? true { Text("No guided trial saved yet.").font(StrandFont.footnote) }
            }.foregroundStyle(StrandPalette.textPrimary)
        }
    }
    private var previewCard: some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Review before applying").font(StrandFont.headline)
                Text("Current scale: \(profile.stepTicksPerStep.formatted(.number.precision(.fractionLength(3)))) ticks per step")
                if let factor=proposal.factor {
                    Text("Proposed scale: \(factor.formatted(.number.precision(.fractionLength(3)))) ticks per step").foregroundStyle(StrandPalette.accent)
                } else { Text("At least three valid, distinct trials with a scale spread within 20% are required.") }
                Text("Repeatability is not sensor accuracy. The scale applies only to increments retained by NOOP's existing pipeline; discarded ticks cannot be restored.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                Button("Apply scale") { apply() }.buttonStyle(NoopButtonStyle(.primary))
                    .disabled(proposal.factor == nil || busy || applying || applied || draft?.pending != nil)
                if applying { ProgressView("Updating local estimates…") }
                if applied { Text("Scale saved. Local estimates will use it when recalculated.").font(StrandFont.footnote) }
            }.font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
        }
    }
    private func restore() {
        generation+=1;work?.cancel();busy=false;inspected=nil;inspectedID=nil;failure=nil;countedSteps="";countedConfirmed=false
        do { draft=try GuidedCalibrationDraft.load();corruptSaved=false }
        catch { draft=nil;corruptSaved=true;failure=String(localized:"Saved walking progress could not be read. Clear it before starting again.") }
    }
    @discardableResult private func commit(_ next:GuidedCalibrationDraft)->Bool {
        do { try GuidedCalibrationDraft.save(next);draft=next;failure=nil;applied=false;return true }
        catch { failure=error.localizedDescription;return false }
    }
    private func begin() {
        guard !busy,!applying,sameOwner,!corruptSaved,draft?.pending==nil else { return }
        let owner=model.repo.deviceId
        generation+=1;let request=generation;busy=true;failure=nil
        work=Task {
            defer { if request==generation { busy=false } }
            do {
                guard let store=await model.repo.storeHandle() else { throw GuidedWalkingCapture.Failure("No on-device store is available yet.") }
                try await GuidedWalkingCapture.authorize(store:store,owner:owner)
                try Task.checkCancellation()
                guard request==generation,owner==model.repo.deviceId else { return }
                let now=Int(Date().timeIntervalSince1970)
                guard now>0,now<GuidedWalkingTrial.maximumUnixTimestamp else { throw GuidedWalkingCapture.Failure("The device clock cannot define a valid walking interval.") }
                var next=draft ?? GuidedCalibrationDraft(owner:owner,completed:[],pending:nil)
                next.pending = .init(id:UUID().uuidString,start:now,end:nil)
                if commit(next) { inspected=nil;inspectedID=nil;countedSteps="";countedConfirmed=false }
            } catch is CancellationError {} catch { if request==generation { failure=error.localizedDescription } }
        }
    }
    private func finish() {
        guard sameOwner,var next=draft,var pending=next.pending,pending.end==nil,!busy else { return }
        let end=Int(Date().timeIntervalSince1970)
        guard end>pending.start,end-pending.start>=GuidedWalkingTrial.minimumDuration,end-pending.start<=GuidedWalkingTrial.maximumDuration else {
            failure=String(localized:"The clock changed or the walk is outside the one-to-60-minute window. Discard it and start again.");return
        }
        pending.end=end;next.pending=pending;_ = commit(next)
    }
    private func inspect(_ pending:GuidedCalibrationDraft.Pending) {
        guard let end=pending.end,let owner=draft?.owner,owner==model.repo.deviceId,!busy else { return }
        generation+=1;let request=generation;busy=true;failure=nil;inspected=nil;inspectedID=nil
        work=Task {
            defer { if request==generation { busy=false } }
            do {
                guard let store=await model.repo.storeHandle() else { throw GuidedWalkingCapture.Failure("No on-device store is available yet.") }
                let value=try await GuidedWalkingCapture.read(store:store,owner:owner,start:pending.start,end:end)
                try Task.checkCancellation()
                guard request==generation,owner==model.repo.deviceId,draft?.pending?.id==pending.id else { return }
                inspected=value;inspectedID=pending.id
            } catch is CancellationError {} catch { if request==generation { failure=error.localizedDescription } }
        }
    }
    private func saveTrial(_ pending:GuidedCalibrationDraft.Pending,ticks:Int) {
        guard countedConfirmed,sameOwner,var next=draft,next.pending?.id==pending.id,let end=pending.end,
              let steps=Int(countedSteps.trimmingCharacters(in:.whitespacesAndNewlines)) else {
            failure=String(localized:"Enter the whole number of steps you counted for this walk.");return
        }
        do {
            if try PersonalReferenceStore.load().contains(where:{$0.owner==next.owner && $0.start==pending.start && $0.end==end && $0.kind=="steps"}) {failure=String(localized:"This walk is already a verification observation and cannot also fit the calibration.");return}
        }catch{failure=error.localizedDescription;return}
        let trial=StepCalibration.Trial(id:pending.id,countedSteps:Double(steps),rawTicks:Double(ticks),sourceConfirmed:true)
        guard StepCalibration.validate(trial)==nil else {
            failure=String(localized:"This trial is outside the supported step-count or scale bounds. Check the count before saving.");return
        }
        let evaluation=StepCalibration.evaluate(next.trials+[trial])
        guard evaluation.issue != .duplicateTrial,evaluation.issue != .tooManyTrials else {
            failure=String(localized:"This repeats a saved measurement or exceeds eight trials. Use a separate walk with a different length.");return
        }
        next.completed.append(.init(id:pending.id,start:pending.start,end:end,countedSteps:steps,ticks:ticks));next.pending=nil
        if commit(next) { inspected=nil;inspectedID=nil;countedSteps="";countedConfirmed=false }
    }
    private func saveVerification(_ pending:GuidedCalibrationDraft.Pending,ticks:Int) {
        guard countedConfirmed,sameOwner,var next=draft,next.pending?.id==pending.id,let end=pending.end,
              let steps=Int(countedSteps.trimmingCharacters(in:.whitespacesAndNewlines)),(100...10000).contains(steps) else{failure=String(localized:"Enter the whole number of steps you counted for this walk.");return}
        let scale=profile.stepTicksPerStep
        guard scale.isFinite,(0.5...30).contains(scale) else{return}
        do {
            let all=try PersonalReferenceStore.load()
            let record=PersonalReferenceStore.Record(id:pending.id,owner:next.owner,start:pending.start,end:end,kind:"steps",estimate:(Double(ticks)/scale).rounded(),reference:Double(steps),method:PersonalReferenceStore.stepMethod(scale),created:Int(Date().timeIntervalSince1970),rawTicks:ticks,scale:scale)
            if let existing=all.first(where:{$0.id==record.id}) {
                guard existing.owner==record.owner,existing.start==record.start,existing.end==record.end,existing.method==record.method,existing.reference==record.reference,existing.rawTicks==record.rawTicks else{throw PersonalReferenceStore.failure()}
            }else{try PersonalReferenceStore.save(all+[record])}
            next.pending=nil
            if commit(next) {inspected=nil;inspectedID=nil;countedSteps="";countedConfirmed=false;failure=String(localized:"Verification saved separately. Review it under My verification measurements.")}
        }catch{failure=error.localizedDescription}
    }
    private func apply() {
        guard let factor=proposal.factor,sameOwner,!busy,!applying,draft?.pending==nil else { return }
        applying=true;profile.stepTicksPerStep=factor
        Task { await model.intelligence.analyzeRecent();await model.repo.refresh();applying=false;applied=true }
    }
    private func message(_ issue:GuidedWalkingTrial.Issue)->String {
        switch issue {
        case .insufficientSamples,.incompleteCoverage,.sampleGap:
            return String(localized:"Walking records are incomplete. Finish synchronization and inspect again; repeat the walk if gaps remain.")
        case .counterDecreased:return String(localized:"The counter decreased. A reset and a wrap cannot be distinguished; repeat the trial.")
        case .movingBoundary:return String(localized:"Stationary boundaries were not observed. Repeat the walk and keep still before Start and before Finish.")
        case .implausibleIncrement,.nonWalkingIncrement:return String(localized:"The existing step pipeline would discard movement in this interval. No scale can repair that trial.")
        case .noMovement:return String(localized:"No retained movement was observed in this interval.")
        case .conflictingSample:return String(localized:"Conflicting counter records prevent a reliable trial.")
        default:return String(localized:"The walking interval or its stored counter values are invalid. Discard it and start again.")
        }
    }
}
private extension View {
    func guidedCountInput()->some View {
        #if os(iOS)
        self.keyboardType(.numberPad).textFieldStyle(.roundedBorder).font(StrandFont.bodyNumber)
        #else
        self.textFieldStyle(.roundedBorder).font(StrandFont.bodyNumber)
        #endif
    }
}
