import XCTest
import WhoopStore
import WhoopProtocol
@testable import Strand

final class GuidedWalkingCaptureTests: XCTestCase {
    func fixture(_ owner:String="walk") async throws -> WhoopStore {
        let store=try await WhoopStore.inMemory()
        let registry=DeviceRegistryStore(dbQueue:store.registryWriter)
        try registry.add(.init(id:owner,brand:"WHOOP",model:"WHOOP 5.0",peripheralId:"fixture",sourceKind:.liveBLE,capabilities:[.hr,.hrv],status:.active,addedAt:1,lastSeenAt:1))
        try registry.setActive(owner)
        return store
    }
    func testReadsOneSourceOnlyAndPreservesRawRows() async throws {
        let store=try await fixture(),start=1_800_000_000
        var streams=Streams()
        streams.steps=(0...60).map { i in StepSample(ts:start+i,counter:i==0 ? 0 : (i==60 ? 116 : (i-1)*2),activityClass:1) }
        _=try await store.insert(streams,deviceId:"walk")
        var foreign=Streams();foreign.steps=[.init(ts:start,counter:500),.init(ts:start+60,counter:900)]
        _=try await store.insert(foreign,deviceId:"other")
        let before=try await store.stepSamples(deviceId:"walk",from:start,to:start+60,limit:100)
        let result=try await GuidedWalkingCapture.read(store:store,owner:"walk",start:start,end:start+60)
        XCTAssertEqual(result.retainedTicks,116)
        let after=try await store.stepSamples(deviceId:"walk",from:start,to:start+60,limit:100)
        XCTAssertEqual(before,after)
    }
    func testDraftPersistsOnlyBoundedSessionMetadataAndRestoresTrials() throws {
        let suite="guided-walk-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let draft=GuidedCalibrationDraft(owner:"walk",completed:[.init(id:"one",start:1_800_000_000,end:1_800_000_060,countedSteps:100,ticks:116)],pending:nil)
        try GuidedCalibrationDraft.save(draft,defaults:defaults)
        XCTAssertEqual(try GuidedCalibrationDraft.load(defaults:defaults),draft)
        XCTAssertEqual(draft.trials.first?.rawTicks,116)
        var invalid=draft;invalid.completed.append(draft.completed[0])
        XCTAssertThrowsError(try GuidedCalibrationDraft.save(invalid,defaults:defaults))
    }
    func testUnregisteredSourceCannotBePromotedToVerifiedWalk() async throws {
        let store=try await fixture()
        do {
            _=try await GuidedWalkingCapture.read(store:store,owner:"unknown",start:1_800_000_000,end:1_800_000_060)
            XCTFail("Unknown source accepted")
        } catch { XCTAssertTrue(error is GuidedWalkingCapture.Failure) }
    }
}
