package com.noop.analytics
import com.noop.data.WhoopRepository
import com.noop.data.HrSample
import com.noop.data.RrInterval
import com.noop.data.GravitySample
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.concurrent.CancellationException

/** Bounded local prior-history capture; current scores and profile are never changed. */
object AlgorithmLabCapture {
    data class Capture(val lines: List<String>, val recoveryQuality: QualityRecovery.Quality?)
    suspend fun run(repo: WhoopRepository, owner: String, computedId: String, day: String,
                    dayStart: Long, now: Long, offset: Long, profile: UserProfile, manualMax: Double?,
                    result: DayResult, dayHR: List<HrSample>, dayGravity: List<GravitySample>, nightHR: List<HrSample>,
                    rr: List<RrInterval>, deepWindow: Boolean, workouts: Boolean, recovery: Boolean, sleep: Boolean, detectedOnly: Boolean, readCapped: Boolean): Capture {
        val lines = ArrayList<String>()
        if (workouts) {
            val q = SampleQuality.analyze(dayHR,dayStart,minOf(now,dayStart + 86_400))
            lines.add(AlgorithmLab.qualityLine(q,day,result.effortConfidence.name.lowercase(),result.strain != null && dayHR.size < 200_000 && dayGravity.size < 200_000))
            val peaks = ArrayList<ConfirmedHRmax.DayPeak>(); var errors = 0; var capped = 0
            if (manualMax == null) for (back in 1..7) {
                val start = dayStart - back * 86_400
                try {
                    val h = repo.hrSamplesForDevice(owner,start,start + 86_400 - 1,100_000)
                    val g = repo.gravitySamplesForDevice(owner,start,start + 86_400 - 1,100_000)
                    if (h.size >= 100_000 || g.size >= 100_000) { capped++; continue }
                    ConfirmedHRmax.dailyPeak(h,g)?.let { peaks.add(ConfirmedHRmax.DayPeak(start,it)) }
                } catch (e: Exception) { if (e is CancellationException) throw e; errors++ }
            }
            lines.add(AlgorithmLab.maximumLine(ConfirmedHRmax.estimate(peaks,dayStart,profile.age,manualMax),day,
                AlgorithmLab.incumbentMaximum(profile.age,manualMax),errors,capped))
        }
        if (sleep) {
            val from = LocalDate.ofEpochDay(Math.floorDiv(dayStart + offset,86_400) - 30).toString()
            val to = LocalDate.ofEpochDay(Math.floorDiv(dayStart + offset,86_400) - 1).toString()
            try {
                val days = repo.days(computedId).filter { it.day >= from && it.day <= to }
                // Stable native journal namespace, shared with JournalLog.JOURNAL_DEVICE_ID.
                val answers = repo.journal("noop-journal",from,to)
                val nights = days.mapNotNull { row ->
                    val minutes = row.totalSleepMin ?: return@mapNotNull null
                    val stamp = runCatching { LocalDate.parse(row.day).atStartOfDay().toEpochSecond(ZoneOffset.UTC) - offset }.getOrNull() ?: return@mapNotNull null
                    fun answer(key: String): Boolean? {
                        val a = answers.filter { it.day == row.day && it.question == key }
                        return a.firstOrNull()?.answeredYes?.takeIf { first -> a.all { it.answeredYes == first } }
                    }
                    ContextualSleepNeed.Night(stamp,minutes / 60,answer(ContextualSleepNeed.naturalWakeQuestion),
                        answer(ContextualSleepNeed.restedQuestion),answer(ContextualSleepNeed.disruptedQuestion))
                }
                lines.add(AlgorithmLab.sleepLine(ContextualSleepNeed.estimate(nights,dayStart,profile.age.toInt()),day))
            } catch (e: Exception) { if (e is CancellationException) throw e
                lines.add("lab sleepneed experimental=true model=nroop-lab-v1 day=$day status=history-read-error candidate=nil") }
        }
        if (recovery) lines.add(AlgorithmLab.concordanceLine(result.sleepSessions,nightHR,rr,deepWindow,detectedOnly && !readCapped,day))
        val q = if (recovery) AlgorithmLab.recoveryEvidence(result.sleepSessions,nightHR,rr,deepWindow,detectedOnly && !readCapped) else null
        return Capture(lines,q)
    }
}
