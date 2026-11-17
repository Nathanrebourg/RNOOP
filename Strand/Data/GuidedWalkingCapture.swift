import Foundation
import StrandAnalytics
import WhoopStore
import WhoopProtocol

/// Local UI progress only. Not a backup/wire format; no raw stream or scale is written here.
/// Numeric capture/calibration decisions live in the independently tested Swift/Kotlin kernels.
struct GuidedCalibrationDraft: Codable, Equatable {
    struct Completed: Codable, Equatable {
        var id: String
        var start: Int
        var end: Int
        var countedSteps: Int
        var ticks: Int
    }
    struct Pending: Codable, Equatable {
        var id: String
        var start: Int
        var end: Int?
    }
    var schema = 1
    var owner: String
    var completed: [Completed]
    var pending: Pending?
    static let key = "guidedWalkingCalibration.localDraft.v1"
    static let maximumBytes = 32 * 1024
    var trials: [StepCalibration.Trial] {
        completed.map { .init(id:$0.id,countedSteps:Double($0.countedSteps),rawTicks:Double($0.ticks),sourceConfirmed:true) }
    }
    private func validate() throws {
        guard schema == 1, !owner.isEmpty, owner.count <= 200, completed.count <= StepCalibration.maximumTrials,
              Set(completed.map(\.id)).count == completed.count else { throw GuidedWalkingCapture.Failure("Saved walking progress is invalid. Clear it before starting again.") }
        func validWindow(_ start:Int,_ end:Int)->Bool {
            start>0 && end>start && end<=GuidedWalkingTrial.maximumUnixTimestamp && end-start<=GuidedWalkingTrial.maximumDuration
        }
        for row in completed {
            guard !row.id.isEmpty, row.id.count<=128, validWindow(row.start,row.end),
                  row.end-row.start>=GuidedWalkingTrial.minimumDuration,
                  StepCalibration.validate(.init(id:row.id,countedSteps:Double(row.countedSteps),rawTicks:Double(row.ticks),sourceConfirmed:true)) == nil else {
                throw GuidedWalkingCapture.Failure("Saved walking progress is invalid. Clear it before starting again.")
            }
        }
        if let pending {
            guard !pending.id.isEmpty,pending.id.count<=128,!completed.contains(where:{$0.id==pending.id}),
                  pending.start>0,pending.start<=GuidedWalkingTrial.maximumUnixTimestamp,
                  pending.end.map({validWindow(pending.start,$0)}) ?? true else {
                throw GuidedWalkingCapture.Failure("Saved walking progress is invalid. Clear it before starting again.")
            }
        }
    }
    static func load(defaults:UserDefaults = .standard) throws -> Self? {
        guard let data=defaults.data(forKey:key) else { return nil }
        guard data.count<=maximumBytes else { throw GuidedWalkingCapture.Failure("Saved walking progress is invalid. Clear it before starting again.") }
        let value=try JSONDecoder().decode(Self.self,from:data)
        try value.validate();return value
    }
    static func save(_ value:Self,defaults:UserDefaults = .standard) throws {
        try value.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(value)
        guard data.count<=maximumBytes else { throw GuidedWalkingCapture.Failure("Saved walking progress is too large.") }
        defaults.set(data,forKey:key)
    }
    static func clear(defaults:UserDefaults = .standard) { defaults.removeObject(forKey:key) }
}

/// Read only one confirmed live source; never ask the bracelet to send a command or change mode.
enum GuidedWalkingCapture {
    struct Failure: LocalizedError {
        let errorDescription:String?
        init(_ message:String) { errorDescription=NSLocalizedString(message,comment:"") }
    }
    static func authorize(store:WhoopStore,owner:String) async throws {
        let registry=DeviceRegistryStore(dbQueue:store.registryWriter)
        guard let device=try registry.all().first(where:{$0.id==owner}),device.sourceKind == .liveBLE,
              (try registry.activeDeviceId()).map({$0==owner}) ?? true,
              try await store.isWhoop5RRSource(deviceId:owner) else {
            throw Failure("Guided calibration needs the selected, registered WHOOP 5.0 live source.")
        }
    }
    static func read(store:WhoopStore,owner:String,start:Int,end:Int) async throws -> GuidedWalkingTrial.Result {
        guard start>0,end>start,end<=GuidedWalkingTrial.maximumUnixTimestamp,
              end-start<=GuidedWalkingTrial.maximumDuration else { throw Failure("This walking interval is invalid or longer than one hour. Start a new trial.") }
        try await authorize(store:store,owner:owner)
        let rows=try await store.stepSamples(deviceId:owner,from:start,to:end,limit:7201)
        guard rows.count<=7200 else { throw Failure("This capture exceeds the read limit. No partial trial was added.") }
        let result=GuidedWalkingTrial.evaluate(startTs:start,endTs:end,
            samples:rows.map{.init(ts:$0.ts,counter:$0.counter,activityClass:$0.activityClass)})
        let after=try await store.stepSamples(deviceId:owner,from:start,to:end,limit:7201)
        try await authorize(store:store,owner:owner)
        guard rows==after else { throw Failure("Walking records changed during inspection. Finish synchronization and try again.") }
        try Task.checkCancellation()
        // A nil-class window can use a different legacy filter than its classed day. Do not calibrate it.
        if result.retainedTicks != nil && !result.usesActivityClasses {
            throw Failure("Walking labels are unavailable for this capture. No guided trial can be verified.")
        }
        return result
    }
}
