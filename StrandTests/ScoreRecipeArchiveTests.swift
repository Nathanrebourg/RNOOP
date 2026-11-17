import XCTest
import WhoopStore
import WhoopProtocol
import StrandAnalytics
@testable import Strand

enum RecipeTestFixture {
    static func populate(_ store:WhoopStore,day:String="2026-11-15",source:String="strap",settings:[String:String]=["pipeline":"fixture-v1"])async throws->(Double,Double) {
        let base=DailyMetric(day:day,totalSleepMin:480,efficiency:1,deepMin:60,remMin:90,lightMin:330,disturbances:0,restingHr:60,avgHrv:40,recovery:nil,strain:nil,exerciseCount:0)
        let b=BaselineState(baseline:40,spread:5,nValid:14,nightsSinceUpdate:0,status:.trusted)
        let baselines=AnalyticsEngine.ProfileBaselines(hrv:b,restingHR:.init(baseline:60,spread:3,nValid:14,nightsSinceUpdate:0,status:.trusted))
        let recovery=try XCTUnwrap(ScoreRecipe.recovery(daily:base,baselines:baselines,source:source)?.withContext(settings))
        let hr=(1000..<1600).map{HRSample(ts:$0,bpm:100)}
        let effort=try XCTUnwrap(ScoreRecipe.effort(hr:hr,maxHR:190,restingHR:60,method:.edwards,sex:"male",source:source)?.withContext(settings))
        let daily=DailyMetric(day:day,totalSleepMin:480,efficiency:1,deepMin:60,remMin:90,lightMin:330,disturbances:0,restingHr:60,avgHrv:40,recovery:recovery.score,strain:effort.score,exerciseCount:0)
        let rows=[recovery,effort].map{ScoreCalculationEvidence(day:day,key:$0.key,sourceId:source,methodId:$0.methodId,fingerprint:$0.fingerprint,payload:$0.payload,value:$0.score,capturedAt:1_794_740_400)}
        try await store.persistComputedScores(dailyMetrics:[daily],metricPoints:[],provenance:[.init(day:day,key:"recovery",sourceId:source),.init(day:day,key:"strain",sourceId:source)],deviceId:"my-whoop-noop",from:day,to:day,calculationEvidence:rows)
        return (recovery.score,effort.score)
    }
}
final class ScoreRecipeArchiveTests:XCTestCase {
    func testStableRecipeContextPreservesCapturesAcrossMarketingVersionsAndSeparatesChangedSettings() async throws {
        let store=try await WhoopStore.inMemory();_=try await RecipeTestFixture.populate(store)
        let now=ISO8601DateFormatter().date(from:"2026-11-15T21:00:00Z")!,zone=TimeZone(secondsFromGMT:0)!
        let a=try await PersonalForecastArchive.capture(store:store,owner:"strap",now:now,zone:zone,clock:{now})
        XCTAssertEqual(a.compatibilityVersion,LearningCompatibility.version)
        var cosmetic=a;cosmetic.captureVersion="99.0.0"
        XCTAssertEqual(a.input,cosmetic.input,"Marketing version is display metadata, not training identity")
        _=try await RecipeTestFixture.populate(store,settings:["pipeline":"fixture-v1","age":"changed"])
        let changed=try await PersonalForecastArchive.capture(store:store,owner:"strap",now:now,zone:zone,clock:{now})
        XCTAssertNotEqual(a.era,changed.era)
    }
    func testLegacyArchiveRoundTripDoesNotInventRecipeCompatibility() throws {
        let suite="recipe-legacy-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let t=Int(ISO8601DateFormatter().date(from:"2026-11-15T21:00:00Z")!.timeIntervalSince1970)
        let old=PersonalForecastArchive.Record(owner:"strap",day:PersonalEvidenceData.ordinal("2026-11-15")!,observedAt:t,zone:"GMT",recovery:80,effort:30,era:"legacy-unknown")
        try PersonalForecastArchive.append(old,defaults:defaults)
        let loaded=try PersonalForecastArchive.load(defaults:defaults)
        XCTAssertEqual(loaded,[old]);XCTAssertNil(loaded[0].compatibilityVersion)
    }
    func testNoExactRecipeCannotBecomeCompatibleForecastEvidence() async throws {
        let store=try await WhoopStore.inMemory(),day="2026-11-15"
        let d=DailyMetric(day:day,totalSleepMin:480,efficiency:1,deepMin:0,remMin:0,lightMin:480,disturbances:0,restingHr:60,avgHrv:40,recovery:80,strain:30,exerciseCount:0)
        try await store.persistComputedScores(dailyMetrics:[d],metricPoints:[],provenance:[.init(day:day,key:"recovery",sourceId:"strap"),.init(day:day,key:"strain",sourceId:"strap")],deviceId:"my-whoop-noop",from:day,to:day)
        let now=ISO8601DateFormatter().date(from:"2026-11-15T21:00:00Z")!
        do {_=try await PersonalForecastArchive.capture(store:store,owner:"strap",now:now,zone:TimeZone(secondsFromGMT:0)!,clock:{now});XCTFail("A recipe was invented for a legacy score")}catch{}
    }
}
