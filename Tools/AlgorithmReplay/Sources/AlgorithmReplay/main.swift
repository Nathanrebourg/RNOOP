import Foundation
import CryptoKit
import StrandAnalytics
import WhoopProtocol

struct HR: Codable { let ts: Int; let bpm: Int }
struct Grav: Codable { let ts: Int; let x: Double; let y: Double; let z: Double }
struct Event: Codable { let ts: Int; let kind: String }
struct Band: Codable { let ts: Int; let state: Int }
struct HistoryStream: Codable { let owner: String; let dayStart: Int; let hr: [HR]; let gravity: [Grav] }
struct Night: Codable {
    let dayStart: Int; let source: String; let hours: Double?
    let hrv: Double?; let rhr: Double?; let resp: Double?
    let naturalWake: Bool?; let rested: Bool?; let disrupted: Bool?
    let evidence: HistoryEvidence?
}
struct Recording: Codable {
    let schema: Int; let origin: String; let caseID: String; let owner: String
    let dayStart: Int; let now: Int; let offset: Int; let age: Double
    let sex: String?; let manualHRmax: Double?; let useV2: Bool?; let deepWindow: Bool?
    let hr: [HR]; let gravity: [Grav]; let rr: [RRInterval]
    let events: [Event]; let band: [Band]; let history: [Night]; let historyStreams: [HistoryStream]
    let warnings: [String]?
    let rrIdentity: String?
}
struct Metric: Codable { let original: Double?; let candidate: Double?; let status: String; let unit: String }
struct Report: Codable {
    let schema: Int; let model: String; let origin: String; let caseID: String; let ownerHash: String
    let dayStart: Int; let inputSHA256: String; let baselineScope: String
    let metrics: [String: Metric]; let lines: [String]; let warnings: [String]
    let research: ResearchReport
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("AlgorithmReplay: " + message + "\n").utf8)); exit(2)
}
guard CommandLine.arguments.count == 3 else { fail("usage: AlgorithmReplay recording.json report.json") }
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]), outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
do {
    guard inputURL.standardizedFileURL.resolvingSymlinksInPath() != outputURL.standardizedFileURL.resolvingSymlinksInPath(),
          !FileManager.default.fileExists(atPath: outputURL.path) else { fail("output must be new and differ from input, including aliases") }
    let size = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 512 * 1024 * 1024 else { fail("recording exceeds 512 MiB") }
    let data = try Data(contentsOf: inputURL), r = try JSONDecoder().decode(Recording.self, from: data)
    guard r.schema == 1, ["synthetic","recorded"].contains(r.origin), !r.caseID.isEmpty, !r.owner.isEmpty,
          r.caseID.count <= 200, r.owner.count <= 200, r.dayStart >= 946_684_800, r.dayStart <= 4_102_444_800,
          r.now > r.dayStart, r.now <= r.dayStart + 86_400, (-50_400...50_400).contains(r.offset),
          (r.dayStart + r.offset) % 86_400 == 0, r.age.isFinite, (0...120).contains(r.age),
          r.hr.count + r.gravity.count + r.rr.count <= 1_000_000, r.historyStreams.count <= 7 else { fail("invalid schema, bounds or row limits") }
    guard r.manualHRmax == nil || (r.manualHRmax!.isFinite && (30...250).contains(r.manualHRmax!)),
          (r.rrIdentity == nil || r.rrIdentity == "store-key-v1"),
          r.rr.allSatisfy({ [5,7].contains($0.srcChannel?.rawValue ?? -1) }),
          Set(r.rr.compactMap { $0.srcChannel?.rawValue }).count <= 1 else { fail("invalid manual maximum or unverified/mixed WHOOP 5 R-R transports") }
    func validHR(_ rows: [HR]) -> Bool { rows.allSatisfy { (0...300).contains($0.bpm) } }
    func validGravity(_ rows: [Grav]) -> Bool { rows.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 && abs($0.z) <= 1_000_000 } }
    guard validHR(r.hr), validGravity(r.gravity), r.rr.allSatisfy({ (0...65_535).contains($0.rrMs) }),
          r.band.allSatisfy({ (0...3).contains($0.state) }) else { fail("corrupt sensor numeric domain; recording rejected without clipping") }
    let from = r.dayStart - 108_000
    guard r.hr.allSatisfy({ $0.ts >= from && $0.ts <= r.now }), r.gravity.allSatisfy({ $0.ts >= from && $0.ts <= r.now }),
          r.rr.allSatisfy({ $0.ts >= from && $0.ts <= r.now }),
          r.events.allSatisfy({ $0.ts >= from && $0.ts <= r.now }), r.band.allSatisfy({ $0.ts >= from && $0.ts <= r.now }),
          r.events.count <= 50_000, r.band.count <= 300_000, r.history.count <= 30 else { fail("out-of-window rows or excessive metadata") }
    let ownerDigest = SHA256.hash(data:Data(r.owner.utf8)).map { String(format:"%02x",$0) }.joined()
    var seen = Set<Int>()
    for n in r.history {
        guard n.source == "computed", n.dayStart < r.dayStart, n.dayStart >= r.dayStart - 30 * 86_400,
              (r.dayStart - n.dayStart) % 86_400 == 0, seen.insert(n.dayStart).inserted,
              [n.hours,n.hrv,n.rhr,n.resp].compactMap({$0}).allSatisfy({$0.isFinite}) else { fail("history must be distinct prior computed days") }
        if let e=n.evidence {
            guard e.version == "nroop-research-v1",e.origin == r.origin,e.ownerHash == ownerDigest,e.dayStart == n.dayStart,
                  e.useV2 == (r.useV2 ?? true),e.deepWindow == (r.deepWindow ?? false),e.rrIdentity == r.rrIdentity,
                  e.inputSHA256.count == 64,e.inputSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  e.hrv == n.hrv,e.rhr == n.rhr,[e.hrvQuality,e.rhrQuality].allSatisfy({$0.isFinite && (0...1).contains($0)})
            else { fail("historical evidence must match owner, recipe, origin, date and exact observed values") }
        }
    }
    seen.removeAll()
    var peaks: [ConfirmedHRmax.DayPeak] = []
    for s in r.historyStreams {
        guard s.owner == r.owner, s.dayStart < r.dayStart, s.dayStart >= r.dayStart - 7 * 86_400,
              (r.dayStart - s.dayStart) % 86_400 == 0, seen.insert(s.dayStart).inserted,
              s.hr.count < 100_000, s.gravity.count < 100_000, validHR(s.hr), validGravity(s.gravity),
              s.hr.allSatisfy({ $0.ts >= s.dayStart && $0.ts < s.dayStart + 86_400 }),
              s.gravity.allSatisfy({ $0.ts >= s.dayStart && $0.ts < s.dayStart + 86_400 }) else { fail("mixed owner, future, duplicate or clipped HRmax history") }
        if let peak = ConfirmedHRmax.dailyPeak(hr: s.hr.map { .init(ts:$0.ts,bpm:$0.bpm) }, gravity:s.gravity.map { .init(ts:$0.ts,x:$0.x,y:$0.y,z:$0.z) }) {
            peaks.append(.init(dayStart:s.dayStart,bpm:peak))
        }
    }
    let normalizedRR=RRReplayIdentity.normalize(r.rr,declared:r.rrIdentity == "store-key-v1")
    guard let rrRows=normalizedRR.rows else { fail("R-R snapshot " + normalizedRR.status) }
    let h = r.hr.map { HRSample(ts:$0.ts,bpm:$0.bpm) }, g = r.gravity.map { GravitySample(ts:$0.ts,x:$0.x,y:$0.y,z:$0.z) }
    let history = r.history.sorted { $0.dayStart < $1.dayStart }
    func baseline(_ key: String, _ value: (Night)->Double?) -> BaselineState {
        let byDay = Dictionary(uniqueKeysWithValues: history.map { ($0.dayStart,$0) })
        let padded = (1...30).reversed().map { back in byDay[r.dayStart - back * 86_400].flatMap(value) }
        return Baselines.foldHistory(padded, cfg: Baselines.metricCfg[key]!)
    }
    let baselines = AnalyticsEngine.ProfileBaselines(hrv:baseline("hrv",{$0.hrv}), restingHR:baseline("resting_hr",{$0.rhr}), resp:baseline("resp",{$0.resp}))
    let day = AnalyticsEngine.dayString(r.dayStart,offsetSec:r.offset)
    let dayHR = h.filter { $0.ts >= r.dayStart && $0.ts < r.now }
    let off = AnalyticsEngine.offWristIntervals(events:r.events.map { WhoopEvent(ts:$0.ts,kind:$0.kind,payload:[:]) }, windowEnd:r.now,hr:h)
    let result = AnalyticsEngine.analyzeDay(day:day,hr:h,rr:rrRows,gravity:g,dayHr:dayHR,
        profile:UserProfile(age:r.age,sex:r.sex ?? "male"),baselines:baselines,maxHROverride:r.manualHRmax,
        tzOffsetSeconds:r.offset,wristOff:off,bandSleepState:r.band.map { ($0.ts,$0.state) },useSleepStagerV2:r.useV2 ?? true,
        deepHrvWindow:r.deepWindow ?? false)
    let q = SampleQuality.analyze(dayHR,start:r.dayStart,end:r.now)
    let rq = AlgorithmLab.recoveryEvidence(sessions:result.sleepSessions,hr:h,rr:rrRows,deepWindow:r.deepWindow ?? false)
    let recovery = AlgorithmLab.recoveryComparison(daily:result.daily,baselines:baselines,quality:rq)
    let maximum = ConfirmedHRmax.estimate(history:peaks,before:r.dayStart,age:r.age,manual:r.manualHRmax)
    let need = ContextualSleepNeed.estimate(nights:history.compactMap { n in n.hours.map {
        .init(dayStart:n.dayStart,hours:$0,naturalWake:n.naturalWake,rested:n.rested,disrupted:n.disrupted)
    } },before:r.dayStart,age:Int(r.age))
    var lines = [AlgorithmLab.qualityLine(q,day:day,original:result.effortConfidence.rawValue,hasScore:result.strain != nil),
        AlgorithmLab.recoveryLine(recovery,q:rq,day:day,scope:"replay-prior-computed-baselines"),
        AlgorithmLab.maximumLine(maximum,day:day,original:AlgorithmLab.incumbentMaximum(age:r.age,manual:r.manualHRmax)),AlgorithmLab.sleepLine(need,day:day)]
    lines.append(AlgorithmLab.concordanceLine(sessions: result.sleepSessions,hr: h,rr: rrRows,deepWindow: r.deepWindow ?? false,eligible: true,day: day))
    let metrics = ["recovery":Metric(original:recovery.original,candidate:recovery.candidate,status:recovery.status,unit:"points/100"),
        "hrmax":Metric(original:AlgorithmLab.incumbentMaximum(age:r.age,manual:r.manualHRmax),candidate:maximum.candidate,status:maximum.source,unit:"bpm"),
        "sleep_need":Metric(original:need.originalHours,candidate:need.candidateHours,status:need.candidateHours == nil ? "insufficient-context" : "compared",unit:"hours")]
    let hash = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    let ownerHash = SHA256.hash(data:Data(r.owner.utf8)).map { String(format:"%02x",$0) }.joined()
    let byDay=Dictionary(uniqueKeysWithValues:history.map { ($0.dayStart,$0) })
    let padded=(1...30).reversed().map { byDay[r.dayStart-$0*86_400] }
    let hb=QualityBaseline.fold(values:padded.map { $0?.hrv },qualities:padded.map { $0?.evidence?.hrvQuality },cfg:Baselines.hrvCfg)
    let rb=QualityBaseline.fold(values:padded.map { $0?.rhr },qualities:padded.map { $0?.evidence?.rhrQuality },cfg:Baselines.metricCfg["resting_hr"]!)
    let daily=result.daily
    let rest=AnalyticsEngine.Rest.composite(daily:daily).map { $0/100 } ?? daily.efficiency
    var explanation:RecoveryExplanation.Result?, historyScore:Double?
    var historyStatus="insufficient-history-quality"
    if let hv=daily.avgHrv,let rh=daily.restingHr,let originalHB=baselines.hrv {
        explanation=RecoveryExplanation.describe(hrv:hv,rhr:Double(rh),resp:daily.respRateBpm,
            hrvBaseline:originalHB,rhrBaseline:baselines.restingHR,respBaseline:baselines.resp,sleepPerf:rest,skinTempDev:daily.skinTempDevC)
        if let candidateHB=hb.candidate, candidateHB.usable,let candidateRB=rb.candidate,candidateRB.usable {
            if rq.hrv >= 0.5 && rq.rhr >= 0.2 {
                historyScore=RecoveryScorer.recovery(hrv:hv,rhr:Double(rh),resp:daily.respRateBpm,hrvBaseline:candidateHB,
                    rhrBaseline:candidateRB,respBaseline:baselines.resp,sleepPerf:rest,skinTempDev:daily.skinTempDevC)
                historyStatus="compared"
            } else { historyStatus="insufficient-current-quality" }
        }
    }
    let research=ResearchReport(version:"nroop-research-v1",scope:"five-driver-prior-baselines; instrumentation-only; no-score-writes",
        recipe:.init(deepWindow:r.deepWindow ?? false,useV2:r.useV2 ?? true,rrIdentity:r.rrIdentity),observation:.init(hrv:daily.avgHrv,rhr:daily.restingHr.map(Double.init)),
        quality:.init(hrv:rq.hrv,rhr:rq.rhr,sleep:rq.sleep),hrvHistory:.init(hb),rhrHistory:.init(rb),
        baselineComparison:.init(original:recovery.original,candidate:historyScore,status:historyStatus,unit:"points/100"),
        explanation:explanation,sessions:result.sleepSessions.map {
            .init(start:$0.start,end:$0.end,signalSupport:SleepSignalCoverage.analyze(start:$0.start,end:$0.end,hr:h,gravity:g))
        },
        bands:["recovery":.init(original:recovery.original.map(RecoveryScorer.band),candidate:recovery.candidate.map(RecoveryScorer.band)),
               "baseline_recovery":.init(original:recovery.original.map(RecoveryScorer.band),candidate:historyScore.map(RecoveryScorer.band))],
        rrNormalization:.init(identity:r.rrIdentity,status:normalizedRR.status,inputRows:r.rr.count,outputRows:rrRows.count,duplicates:normalizedRR.duplicates))
    let report = Report(schema:1,model:"nroop-lab-v1",origin:r.origin,caseID:r.caseID,ownerHash:ownerHash,dayStart:r.dayStart,
        inputSHA256:hash,baselineScope:"strict-prior-computed-history; unedited raw detector; no provided hypnogram",
        metrics:metrics,lines:lines,warnings:r.warnings ?? [],research:research)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try encoder.encode(report).write(to:outputURL,options:.withoutOverwriting)
    print("Replayed \(r.caseID) (\(r.origin)); no source data or scores modified.")
} catch { fail(String(describing:error)) }
