package com.noop.analytics

/** Pure quality gate for a user-declared walking interval. Swift twin: `GuidedWalkingTrial`. */
object GuidedWalkingTrial {
    // Workflow limits, not validated accuracy/confidence thresholds.
    const val MINIMUM_DURATION = 60L
    const val MAXIMUM_DURATION = 3600L
    const val MAXIMUM_EDGE_GAP = 3L
    const val MAXIMUM_SAMPLE_GAP = 5L
    const val MAXIMUM_UNIX_TIMESTAMP = 4_102_444_800L

    data class Sample(val ts: Long, val counter: Int, val activityClass: Int?)
    enum class Issue {
        INVALID_WINDOW, INVALID_DURATION, INVALID_TIMESTAMP, INVALID_COUNTER, CONFLICTING_SAMPLE,
        INSUFFICIENT_SAMPLES, INCOMPLETE_COVERAGE, SAMPLE_GAP, COUNTER_DECREASED,
        IMPLAUSIBLE_INCREMENT, NON_WALKING_INCREMENT, MOVING_BOUNDARY, NO_MOVEMENT
    }
    data class Result(
        val retainedTicks: Int?, val issue: Issue?, val observedStartTs: Long?, val observedEndTs: Long?,
        val sampleCount: Int, val usesActivityClasses: Boolean
    )

    /** Caller selects ONE source before mapping; this type cannot verify ownership. Only records
     * within [startTs, endTs] contribute. No rejected increment is silently omitted. */
    fun evaluate(startTs: Long, endTs: Long, samples: List<Sample>): Result {
        val observed = mutableListOf<Sample>()
        var classed = false
        fun finish(issue: Issue?, ticks: Int? = null) = Result(
            ticks, issue, observed.firstOrNull()?.ts, observed.lastOrNull()?.ts, observed.size, classed
        )
        if (startTs <= 0 || endTs <= startTs || endTs > MAXIMUM_UNIX_TIMESTAMP) return finish(Issue.INVALID_WINDOW)
        val duration = endTs - startTs
        if (duration !in MINIMUM_DURATION..MAXIMUM_DURATION) return finish(Issue.INVALID_DURATION)
        if (samples.any { it.ts <= 0 || it.ts > MAXIMUM_UNIX_TIMESTAMP }) return finish(Issue.INVALID_TIMESTAMP)
        val ordered = samples.filter { it.ts in startTs..endTs }.sortedBy { it.ts }
        for (sample in ordered) {
            if (sample.counter !in 0..65535) return finish(Issue.INVALID_COUNTER)
            val previous = observed.lastOrNull()
            if (previous?.ts == sample.ts) {
                if (previous != sample) return finish(Issue.CONFLICTING_SAMPLE)
            } else observed.add(sample)
        }
        classed = observed.any { it.activityClass != null }
        if (observed.size < 4) return finish(Issue.INSUFFICIENT_SAMPLES)
        if (observed.first().ts - startTs > MAXIMUM_EDGE_GAP || endTs - observed.last().ts > MAXIMUM_EDGE_GAP) {
            return finish(Issue.INCOMPLETE_COVERAGE)
        }
        var total = 0
        for (index in 1 until observed.size) {
            val previous = observed[index - 1]
            val current = observed[index]
            val elapsed = current.ts - previous.ts
            if (elapsed > MAXIMUM_SAMPLE_GAP) return finish(Issue.SAMPLE_GAP)
            // A drop may be either wrap or reset; these fields cannot identify which.
            if (current.counter < previous.counter) return finish(Issue.COUNTER_DECREASED)
            val delta = current.counter - previous.counter
            if (delta == 0) continue
            // Exactly StepsCounter's positive increment acceptance, before coefficient application.
            if (delta >= 512 || delta > elapsed * 4) return finish(Issue.IMPLAUSIBLE_INCREMENT)
            if (classed && current.activityClass != 1 && current.activityClass != 2) return finish(Issue.NON_WALKING_INCREMENT)
            total += delta
        }
        // Observed stationary edges reduce ambiguity; they do not prove a complete walk.
        if (observed[0].counter != observed[1].counter ||
            observed[observed.lastIndex - 1].counter != observed.last().counter) return finish(Issue.MOVING_BOUNDARY)
        if (total <= 0) return finish(Issue.NO_MOVEMENT)
        return finish(null, total)
    }
}
