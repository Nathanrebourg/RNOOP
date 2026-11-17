package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import com.noop.data.RespSample
import com.noop.data.RrInterval
import com.noop.data.WhoopRepository

/** Local read-only history collection for the newest day's opt-in detector comparison. No candidate writes. */
object SleepBaselineExperiment {
    suspend fun run(repo: WhoopRepository, owner: String, day: String, dayStart: Long, readStart: Long,
                    offset: Long, hr: List<HrSample>, rr: List<RrInterval>, resp: List<RespSample>,
                    gravity: List<GravitySample>, wristOff: List<Pair<Long, Long>>,
                    bandSleepState: List<Pair<Long, Int>>, useSleepStagerV2: Boolean): String {
        val history = ArrayList<SleepBaselineComparison.Observation>()
        for (window in SleepBaselineComparison.historyWindows(readStart, offset)) {
            val rows = repo.hrSamplesForDevice(owner, window.start, window.end - 1, 50_000)
            SleepBaselineComparison.observation(rows, window)?.let { history.add(it) }
        }
        return SleepBaselineComparison.compare(dayStart, readStart, history, hr, rr, resp, gravity, offset,
            wristOff, bandSleepState, useSleepStagerV2,
            readCapped = hr.size >= StreamReadCap.HR || rr.size >= StreamReadCap.RR ||
                gravity.size >= StreamReadCap.GRAVITY || resp.size >= 200_000).trace(day)
    }
}
