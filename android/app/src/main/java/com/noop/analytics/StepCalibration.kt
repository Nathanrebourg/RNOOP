package com.noop.analytics

/** Manual unscaled-tick walking-trial calculator. No counter decoding or physiological inference.
 * Swift twin: Packages/StrandAnalytics/Sources/StrandAnalytics/StepCalibration.swift. */
object StepCalibration {
    const val MINIMUM_TRIALS = 3
    const val MAXIMUM_TRIALS = 8
    const val MINIMUM_STEPS = 100.0
    const val MAXIMUM_STEPS = 10_000.0
    const val MAXIMUM_TICKS = 300_000.0
    const val MINIMUM_FACTOR = 0.5
    const val MAXIMUM_FACTOR = 30.0
    // Workflow threshold, not an empirically validated accuracy/confidence bound.
    const val MAXIMUM_RELATIVE_SPREAD = 0.20

    data class Trial(val id: String, val countedSteps: Double, val rawTicks: Double, val sourceConfirmed: Boolean)

    enum class Issue(val code: String) {
        UNCONFIRMED_SOURCE("unconfirmedSource"), INVALID_IDENTITY("invalidIdentity"),
        INVALID_STEPS("invalidSteps"), INVALID_TICKS("invalidTicks"), UNSUPPORTED_FACTOR("unsupportedFactor"),
        DUPLICATE_TRIAL("duplicateTrial"), INSUFFICIENT_TRIALS("insufficientTrials"),
        TOO_MANY_TRIALS("tooManyTrials"), INCONSISTENT_TRIALS("inconsistentTrials")
    }

    data class Result(val factor: Double?, val relativeSpread: Double?, val issue: Issue?)

    fun validate(trial: Trial): Issue? {
        if (!trial.sourceConfirmed) return Issue.UNCONFIRMED_SOURCE
        // IDs are opaque; reject empty/ASCII-blank input without platform-specific Unicode trimming.
        if (trial.id.all { it.code in listOf(9, 10, 13, 32) }) {
            return Issue.INVALID_IDENTITY
        }
        if (!trial.countedSteps.isFinite() || trial.countedSteps < MINIMUM_STEPS || trial.countedSteps > MAXIMUM_STEPS ||
            kotlin.math.truncate(trial.countedSteps) != trial.countedSteps) return Issue.INVALID_STEPS
        if (!trial.rawTicks.isFinite() || trial.rawTicks <= 0 || trial.rawTicks > MAXIMUM_TICKS ||
            kotlin.math.truncate(trial.rawTicks) != trial.rawTicks) return Issue.INVALID_TICKS
        val factor = trial.rawTicks / trial.countedSteps
        if (factor < MINIMUM_FACTOR || factor > MAXIMUM_FACTOR) return Issue.UNSUPPORTED_FACTOR
        return null
    }

    /** Never silently removes outliers. Equal observations cannot establish independent repetition. */
    fun evaluate(trials: List<Trial>): Result {
        fun rejected(issue: Issue) = Result(null, null, issue)
        if (trials.size > MAXIMUM_TRIALS) return rejected(Issue.TOO_MANY_TRIALS)
        for ((index, trial) in trials.withIndex()) {
            validate(trial)?.let { return rejected(it) }
            if (trials.take(index).any {
                it.id == trial.id || (it.countedSteps == trial.countedSteps && it.rawTicks == trial.rawTicks)
            }) return rejected(Issue.DUPLICATE_TRIAL)
        }
        if (trials.size < MINIMUM_TRIALS) return rejected(Issue.INSUFFICIENT_TRIALS)
        val factors = trials.map { it.rawTicks / it.countedSteps }.sorted()
        val middle = factors.size / 2
        val median = if (factors.size % 2 == 0) (factors[middle - 1] + factors[middle]) / 2 else factors[middle]
        val spread = (factors.last() - factors.first()) / median
        if (spread > MAXIMUM_RELATIVE_SPREAD) return Result(null, spread, Issue.INCONSISTENT_TRIALS)
        return Result(median, spread, null)
    }
}
