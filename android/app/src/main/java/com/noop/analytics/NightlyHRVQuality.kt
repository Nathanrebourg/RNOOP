package com.noop.analytics

import com.noop.data.RrInterval
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Measurement-only nightly RMSSD experiment; never supplies a daily score or personal baseline.
 * Weights five-minute means by clean beat-time, retained fraction and temporal continuity.
 * The weights are an unvalidated engineering hypothesis. Swift twin: NightlyHRVQuality.swift.
 * Only the default-off HRV Test Centre trace calls this from the app. */
object NightlyHRVQuality {
    const val windowSeconds = 300
    const val maxSessionSeconds = 172_800

    data class Summary(
        val weightedRMSSD: Double?, val coverage: Double, val totalWindows: Int,
        val usableWindows: Int, val inputBeats: Int, val rejectedBeats: Int,
        val usablePairs: Int, val longGaps: Int, val overCounted: Boolean,
    ) {
        /** Explicitly enabled comparison report, with no timestamps or identifiers. */
        fun trace(original: Double?): String =
            "hrv quality experimental=true original=${ms(original)} candidate=${ms(weightedRMSSD)} " +
                "coveragePct=${(coverage * 100).roundToInt()} windows=$usableWindows/$totalWindows " +
                "input=$inputBeats rejected=$rejectedBeats pairs=$usablePairs " +
                "longGaps=$longGaps overCounted=$overCounted"
    }

    /** Stable ordering preserves within-second emission order. Windows are half-open except for the
     * session endpoint. The 48-hour safety bound limits work on corrupt spans, not sleep detection. */
    fun analyze(start: Long, end: Long, rr: List<RrInterval>): Summary {
        val span = end - start
        if (end <= start || span <= 0 || span > maxSessionSeconds) {
            return Summary(null, 0.0, 0, 0, 0, 0, 0, 0, false)
        }
        val samples = rr.withIndex().filter { it.value.ts in start..end }
            .sortedWith(compareBy<IndexedValue<RrInterval>> { it.value.ts }.thenBy { it.index }).map { it.value }
        val rawCoverage = HrvAnalyzer.rrCoverage(samples.map { it.ts }, samples.map { it.rrMs.toDouble() })
        val overCounted = !HrvAnalyzer.successiveDiffIsTrustworthy(HrvAnalyzer.classifyCoverage(rawCoverage, rawCoverage))
        val totalWindows = ((span + windowSeconds - 1) / windowSeconds).toInt()
        var weightedSum = 0.0
        var totalWeight = 0.0
        var acceptedSeconds = 0.0
        var usableWindows = 0
        var rejected = 0
        var pairs = 0
        var longGaps = 0
        var cursor = 0
        for (window in 0 until totalWindows) {
            val lo = start + window.toLong() * windowSeconds
            val duration = min(windowSeconds.toLong(), end - lo)
            val final = window == totalWindows - 1
            val first = cursor
            while (cursor < samples.size && (final || samples[cursor].ts < lo + duration)) cursor++
            val bucket = samples.subList(first, cursor)
            if (bucket.isEmpty()) continue
            val cleaned = HrvAnalyzer.cleanRRGapAware(bucket.map { it.rrMs.toDouble() })
            rejected += bucket.size - cleaned.nn.size
            val contiguous = cleaned.contiguous.toMutableList()
            var validPairs = 0
            for (i in 1 until cleaned.nn.size) {
                val dt = (bucket[cleaned.sourceIndices[i]].ts - bucket[cleaned.sourceIndices[i - 1]].ts).toDouble()
                val tooFar = dt > max(2.0, cleaned.nn[i] / 1_000 + 1)
                if (tooFar) { longGaps++; contiguous[i] = false }
                if (contiguous[i]) validPairs++
            }
            pairs += validPairs
            val localCoverage = HrvAnalyzer.rrCoverage(bucket.map { it.ts }, bucket.map { it.rrMs.toDouble() })
            if (cleaned.nn.size < HrvAnalyzer.MIN_BEATS || validPairs < HrvAnalyzer.MIN_BEATS - 1 ||
                localCoverage <= 0 || !HrvAnalyzer.successiveDiffIsTrustworthy(
                    HrvAnalyzer.classifyCoverage(localCoverage, localCoverage))) continue
            val rmssd = HrvAnalyzer.rmssdGapAware(cleaned.nn, contiguous) ?: continue
            if (!rmssd.isFinite()) continue
            val seconds = min(duration.toDouble(), cleaned.nn.sum() / 1_000)
            val retained = cleaned.nn.size.toDouble() / bucket.size
            val continuity = validPairs.toDouble() / (cleaned.nn.size - 1)
            val weight = seconds * retained * continuity
            weightedSum += rmssd * weight
            totalWeight += weight
            acceptedSeconds += seconds
            usableWindows++
        }
        return Summary(if (!overCounted && totalWeight > 0) weightedSum / totalWeight else null,
            if (overCounted) 0.0 else min(1.0, acceptedSeconds / span), totalWindows, usableWindows,
            samples.size, rejected, pairs, longGaps, overCounted)
    }

    private fun ms(value: Double?): String {
        if (value == null || !value.isFinite() || value < 0 || value >= 1_000_000) return "nil"
        val hundredths = (value * 100).roundToInt()
        return "${hundredths / 100}.${(hundredths % 100).toString().padStart(2, '0')}ms"
    }
}
