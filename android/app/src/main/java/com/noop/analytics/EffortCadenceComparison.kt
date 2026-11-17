package com.noop.analytics

import com.noop.data.HrSample
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/** Measurement-only alternative to the fixed two-minute duration ceiling. Swift twin:
 * EffortCadenceComparison.swift. Never smooths heart rate or supplies stored/live Effort. */
object EffortCadenceComparison {
    const val neighbours = 5
    const val maximumReferenceGapSeconds = 60.0
    const val cadenceAllowance = 2.0

    data class Summary(
        val candidateScore: Double?, val candidateTRIMP: Double?, val durationsSeconds: List<Double>,
        val supportedSeconds: Double, val creditedSeconds: Double, val unsupportedSeconds: Double,
        val uniqueReadings: Int, val duplicatesRemoved: Int, val ambiguousTimestamps: Int,
        val invalidReadings: Int, val gapsClipped: Int, val configurationValid: Boolean,
    ) {
        fun trace(original: Double?): String =
            "effort cadence experimental=true scale=0-100 original=${number(original)} " +
                "candidate=${number(candidateScore)} supportedSec=${number(supportedSeconds)} " +
                "tailSec=${number(durationsSeconds.lastOrNull() ?: 0.0)} " +
                "unsupportedSec=${number(unsupportedSeconds)} readings=$uniqueReadings " +
                "duplicates=$duplicatesRemoved ambiguous=$ambiguousTimestamps invalid=$invalidReadings " +
                "clipped=$gapsClipped configValid=$configurationValid"
    }

    /** Route both fresh and cached diagnostics identically; never leak a disabled comparison. */
    fun replayDiagnostic(line: String, regularSink: (String) -> Unit, comparisonSink: ((String) -> Unit)?) {
        if (line.startsWith("effort cadence experimental=")) comparisonSink?.invoke(line)
        else regularSink(line)
    }

    /** Local cadence excludes the tested gap and reference gaps above a minute. The slower supported
     * side preserves real cadence changes. These are provisional credit rules, not wear detection. */
    fun analyze(hr: List<HrSample>, maxHR: Double? = null,
                restingHR: Double = StrainScorer.defaultRestingHR,
                method: StrainScorer.Method = StrainScorer.Method.EDWARDS,
                sex: String = "male", denominator: Double? = null): Summary {
        val invalid = hr.count { it.bpm <= 0 }
        val sorted = hr.filter { it.bpm > 0 }.sortedWith(compareBy<HrSample> { it.ts }.thenBy { it.bpm })
        val samples = ArrayList<HrSample>()
        var duplicates = 0
        var ambiguous = 0
        var cursor = 0
        while (cursor < sorted.size) {
            val first = cursor
            while (cursor < sorted.size && sorted[cursor].ts == sorted[first].ts) cursor++
            if (sorted[first].bpm != sorted[cursor - 1].bpm) {
                ambiguous++
            } else {
                samples.add(sorted[first])
                duplicates += cursor - first - 1
            }
        }
        val gaps = (1 until samples.size).map { samples[it].ts.toDouble() - samples[it - 1].ts.toDouble() }
        fun median(from: Int, to: Int): Double? {
            val valid = gaps.subList(from, to).filter { it > 0 && it <= maximumReferenceGapSeconds }.sorted()
            if (valid.isEmpty()) return null
            val middle = valid.size / 2
            return if (valid.size % 2 == 0) (valid[middle - 1] + valid[middle]) / 2 else valid[middle]
        }
        val durations = ArrayList<Double>()
        var clipped = 0
        for (i in gaps.indices) {
            val before = median(max(0, i - neighbours), i) ?: 0.0
            val after = median(i + 1, min(gaps.size, i + neighbours + 1)) ?: 0.0
            val ceiling = min(StrainScorer.maxSampleGapMin * 60, cadenceAllowance * max(before, after))
            val credit = min(gaps[i], ceiling)
            durations.add(credit)
            if (credit < gaps[i]) clipped++
        }
        val supported = durations.sum()
        val tail = median(max(0, gaps.size - neighbours), gaps.size) ?: 0.0
        if (samples.isNotEmpty()) durations.add(tail)
        val credited = supported + tail
        val span = gaps.sum()
        val effMax = maxHR ?: StrainScorer.defaultMaxHR().toDouble()
        val resolvedDenominator = denominator ?: StrainScorer.logMapDenominator(method, sex)
        val valid = effMax.isFinite() && restingHR.isFinite() && effMax > restingHR &&
            resolvedDenominator.isFinite() && resolvedDenominator > 1
        val enough = samples.size >= StrainScorer.minSparseReadings && supported >= StrainScorer.minSpanSeconds
        var trimp: Double? = null
        var score: Double? = null
        if (valid && enough) {
            val minutes = durations.map { it / 60 }
            trimp = when (method) {
                StrainScorer.Method.EDWARDS -> StrainScorer.edwardsTRIMP(samples, restingHR, effMax - restingHR, minutes)
                StrainScorer.Method.BANISTER -> {
                    val c = StrainScorer.banisterCoefficients(sex.lowercase().startsWith("f"))
                    StrainScorer.banisterTRIMP(samples, restingHR, effMax - restingHR, minutes, c,
                        floorRatePerMinute = StrainScorer.banisterBaselineRatePerMinute(c))
                }
            }
            score = StrainScorer.trimpToStrain(trimp, resolvedDenominator)
        }
        return Summary(score, trimp, durations, supported, credited, max(0.0, span - supported),
            samples.size, duplicates, ambiguous, invalid, clipped, valid)
    }

    private fun number(value: Double?): String {
        if (value == null || !value.isFinite() || value < 0 || value >= 1_000_000_000) return "nil"
        val hundredths = (value * 100).roundToLong()
        return "${hundredths / 100}.${(hundredths % 100).toString().padStart(2, '0')}"
    }
}
