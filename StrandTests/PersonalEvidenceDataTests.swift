import XCTest
import WhoopStore
@testable import Strand

final class PersonalEvidenceDataTests:XCTestCase {
    func testOnlyMatchingComputedOwnersBecomeResearchDays() async throws {
        let store=try await WhoopStore.inMemory()
        let days=["2026-11-12","2026-11-13","2026-11-14"]
        let rows=days.map {DailyMetric(day:$0,totalSleepMin:480,efficiency:1,deepMin:0,remMin:0,lightMin:480,disturbances:0,restingHr:60,avgHrv:40,recovery:80,strain:30,exerciseCount:0)}
        let tags=days.flatMap {d in ["recovery","strain","sleep_performance"].map {ScoreInputProvenanceRow(day:d,key:$0,sourceId:d=="2026-11-13" ? "other":"strap")}}
        try await store.persistComputedScores(dailyMetrics:rows,metricPoints:[],provenance:tags,deviceId:"my-whoop-noop",from:days.first!,to:days.last!)
        let result=try await PersonalEvidenceData.load(store:store,owner:"strap",now:ISO8601DateFormatter().date(from:"2026-11-15T12:00:00Z")!,zone:TimeZone(secondsFromGMT:0)!)
        XCTAssertEqual(result.days.filter{$0.recovery != nil}.count,2)
        XCTAssertFalse(result.days.contains{$0.day==PersonalEvidenceData.ordinal("2026-11-13")! && $0.recovery != nil})
        XCTAssertNil(PersonalEvidenceData.ordinal("2026-02-30"))
        let stored=try await store.dailyMetrics(deviceId:"my-whoop-noop",from:days.first!,to:days.last!)
        XCTAssertEqual(stored.count,3)
    }
    func testReferenceStoreRefusesDuplicateWindowAndDoesNotBecomeCalibrationInput() throws {
        let suite="reference-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let row=PersonalReferenceStore.Record(id:"one",owner:"strap",start:1000,end:1060,kind:"steps",estimate:110,reference:100,method:PersonalReferenceStore.stepMethod(1),created:2000,rawTicks:110,scale:1)
        try PersonalReferenceStore.save([row],defaults:defaults)
        XCTAssertEqual(try PersonalReferenceStore.load(defaults:defaults),[row])
        var duplicate=row;duplicate.id="two"
        XCTAssertThrowsError(try PersonalReferenceStore.save([row,duplicate],defaults:defaults))
        XCTAssertNil(try GuidedCalibrationDraft.load(defaults:defaults))
        var invalid=row;invalid.reference = .nan
        XCTAssertThrowsError(try PersonalReferenceStore.save([invalid],defaults:defaults))
        defaults.set(Data("bad".utf8),forKey:PersonalReferenceStore.key)
        XCTAssertThrowsError(try PersonalReferenceStore.load(defaults:defaults))
    }
    func testExtremeReferenceTimestampsThrowWithoutArithmeticTrap() {
        let r=PersonalReferenceStore.Record(id:"x",owner:"strap",start:Int.min,end:Int.max,kind:"steps",estimate:110,reference:100,method:PersonalReferenceStore.stepMethod(1),created:Int.max,rawTicks:110,scale:1)
        XCTAssertThrowsError(try PersonalReferenceStore.validate([r]))
    }
    func testForecastArchiveIsFirstCaptureOnlyAndRejectsDayMismatch() throws {
        let suite="forecast-test-"+UUID().uuidString,defaults:UserDefaults
        defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let stamp=Int(ISO8601DateFormatter().date(from:"2026-11-15T21:00:00Z")!.timeIntervalSince1970)
        let row=PersonalForecastArchive.Record(owner:"strap",day:PersonalEvidenceData.ordinal("2026-11-15")!,observedAt:stamp,zone:"GMT",recovery:80,effort:30,era:"one")
        try PersonalForecastArchive.append(row,defaults:defaults)
        var changed=row;changed.recovery=20
        XCTAssertThrowsError(try PersonalForecastArchive.append(changed,defaults:defaults))
        XCTAssertEqual(try PersonalForecastArchive.load(defaults:defaults).first?.recovery,80)
        var invalid=row;invalid.day+=1
        XCTAssertThrowsError(try PersonalForecastArchive.append(invalid,defaults:defaults))
    }
    func testSnapshotCaptureRequiresMatchingOwnerAndCannotCrossMidnight() async throws {
        let store=try await WhoopStore.inMemory(),day="2026-11-15"
        let expected=try await RecipeTestFixture.populate(store,day:day)
        let now=ISO8601DateFormatter().date(from:"2026-11-15T21:00:00Z")!,zone=TimeZone(secondsFromGMT:0)!
        let result=try await PersonalForecastArchive.capture(store:store,owner:"strap",now:now,zone:zone,clock:{now})
        XCTAssertEqual(result.recovery,expected.0);XCTAssertEqual(result.effort,expected.1)
        do {_=try await PersonalForecastArchive.capture(store:store,owner:"other",now:now,zone:zone,clock:{now});XCTFail("Foreign owner accepted")}catch{}
        do {_=try await PersonalForecastArchive.capture(store:store,owner:"strap",now:now,zone:zone,clock:{now.addingTimeInterval(4*3600)});XCTFail("Midnight crossing accepted")}catch{}
        let snapshot=try await PersonalEvidenceData.load(store:store,owner:"strap",now:now.addingTimeInterval(-3600),zone:zone,archive:[result])
        XCTAssertEqual(snapshot.archived,0,"A future same-day capture must not enter the past")
        XCTAssertTrue(snapshot.forecasts.allSatisfy{$0.prediction==nil})
    }
}
