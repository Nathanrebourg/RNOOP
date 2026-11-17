import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Bounded, read-only newest-day capture. History is strictly prior; no profile/score/baseline writes.
enum AlgorithmLabCapture {
    struct Capture { let lines: [String]; let recoveryQuality: QualityRecovery.Quality? }
    static func run(store: WhoopStore, owner: String, computedId: String, journalId: String,
                    day: String, dayStart: Int, now: Int, offset: Int, profile: UserProfile, manualMax: Double?,
                    result: AnalyticsEngine.DayResult, dayHR: [HRSample], dayGravity: [GravitySample],
                    nightHR: [HRSample], rr: [RRInterval], deepWindow: Bool,
                    workouts: Bool, recovery: Bool, sleep: Bool, detectedOnly: Bool, readCapped: Bool) async -> Capture {
        var lines: [String] = []
        if workouts {
            let q = SampleQuality.analyze(dayHR, start: dayStart, end: min(now,dayStart + 86_400))
            lines.append(AlgorithmLab.qualityLine(q, day: day, original: result.effortConfidence.rawValue, hasScore: result.strain != nil && dayHR.count < 200_000 && dayGravity.count < 200_000))
            var peaks: [ConfirmedHRmax.DayPeak] = [], errors = 0, capped = 0
            if manualMax == nil {
                for back in 1...7 {
                    if Task.isCancelled { break }
                    let start = dayStart - back * 86_400
                    do {
                        let hr = try await store.hrSamples(deviceId: owner, from: start, to: start + 86_400 - 1, limit: 100_000)
                        let grav = try await store.gravitySamples(deviceId: owner, from: start, to: start + 86_400 - 1, limit: 100_000)
                        if hr.count >= 100_000 || grav.count >= 100_000 { capped += 1; continue }
                        if let p = ConfirmedHRmax.dailyPeak(hr: hr, gravity: grav) { peaks.append(.init(dayStart: start, bpm: p)) }
                    } catch { errors += 1 }
                }
            }
            let e = ConfirmedHRmax.estimate(history: peaks, before: dayStart, age: profile.age, manual: manualMax)
            lines.append(AlgorithmLab.maximumLine(e, day: day, original: AlgorithmLab.incumbentMaximum(age: profile.age, manual: manualMax), readErrors: errors, cappedDays: capped))
        }
        if sleep {
            let from = AnalyticsEngine.dayString(dayStart - 30 * 86_400, offsetSec: offset)
            let to = AnalyticsEngine.dayString(dayStart - 1, offsetSec: offset)
            do {
                let days = try await store.dailyMetrics(deviceId: computedId, from: from, to: to)
                let answers = try await store.journalEntries(deviceId: journalId, from: from, to: to)
                let nights = days.compactMap { row -> ContextualSleepNeed.Night? in
                    guard let minutes = row.totalSleepMin else { return nil }
                    let parser = ISO8601DateFormatter()
                    guard let date = parser.date(from: row.day + "T00:00:00Z") else { return nil }
                    func answer(_ key: String) -> Bool? {
                        let a = answers.filter { $0.day == row.day && $0.question == key }
                        guard let first = a.first, a.allSatisfy({ $0.answeredYes == first.answeredYes }) else { return nil }
                        return first.answeredYes
                    }
                    return .init(dayStart: Int(date.timeIntervalSince1970) - offset, hours: minutes / 60,
                        naturalWake: answer(ContextualSleepNeed.naturalWakeQuestion), rested: answer(ContextualSleepNeed.restedQuestion),
                        disrupted: answer(ContextualSleepNeed.disruptedQuestion))
                }
                lines.append(AlgorithmLab.sleepLine(ContextualSleepNeed.estimate(nights: nights, before: dayStart, age: Int(profile.age)), day: day))
            } catch { lines.append("lab sleepneed experimental=true model=nroop-lab-v1 day=\(day) status=history-read-error candidate=nil") }
        }
        if recovery { lines.append(AlgorithmLab.concordanceLine(sessions: result.sleepSessions,hr: nightHR,rr: rr,
            deepWindow: deepWindow,eligible: detectedOnly && !readCapped,day: day)) }
        let q = recovery ? AlgorithmLab.recoveryEvidence(sessions: result.sleepSessions, hr: nightHR, rr: rr, deepWindow: deepWindow, detectedOnly: detectedOnly && !readCapped) : nil
        return Capture(lines: lines, recoveryQuality: q)
    }
}
