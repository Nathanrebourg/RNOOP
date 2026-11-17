package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.HrSample
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/** Versioned sufficient evidence, retaining summaries rather than raw sensor rows. Swift twin: ScoreRecipe. */
class ScoreRecipe private constructor(
    val key: String, val sourceId: String, val methodId: String,
    val payload: String, val fingerprint: String, val score: Double,
    private val fields: Map<String, String>,
) {
    override fun equals(other: Any?): Boolean = other is ScoreRecipe && payload == other.payload
    override fun hashCode(): Int = payload.hashCode()
    val numericInputs: Map<String, Double> get() = fields.mapNotNull { (key, value) ->
        value.takeIf { it.startsWith("d") }?.drop(1)?.toULongOrNull(16)
            ?.let { Double.fromBits(it.toLong()) }?.takeIf { it.isFinite() }?.let { key to it }
    }.toMap()
    val textInputs: Map<String, String> get() = fields.mapNotNull { (key, value) -> text(value)?.let { key to it } }.toMap()
    val context: Map<String, String> get() = fields.filterKeys { it.startsWith("ctx.") }
        .mapKeys { it.key.removePrefix("ctx.") }.mapValues { text(it.value)!! }
    fun withContext(context: Map<String, String>): ScoreRecipe? {
        if (!context.keys.all(::validName)) return null
        return make(fields.filterKeys { !it.startsWith("ctx.") } + context.mapKeys { "ctx.${it.key}" }.mapValues { string(it.value) })
    }
    fun withEffortWindow(startInclusive: Long, endExclusive: Long, kind: String = "sleep-onset"): ScoreRecipe? {
        if (key != "strain") return null
        return make(fields + mapOf("windowStart" to integer(startInclusive), "windowEnd" to integer(endExclusive), "windowKind" to string(kind)))
    }
    fun changedFields(from: ScoreRecipe): List<String> = (fields.keys + from.fields.keys)
        .filter { fields[it] != from.fields[it] }.sorted()
    fun replay(): Double? = evaluate(fields, methodId, key)

    companion object {
        const val recoveryMethod = "recovery.logistic.v1"
        const val restMethod = "rest.daily-composite.v1"
        const val edwardsMethod = "effort.edwards-hrr-log.v1"
        const val banisterMethod = "effort.banister-sedentary-log.v1"
        fun recovery(daily: DailyMetric, baselines: ProfileBaselines, source: String): ScoreRecipe? {
            val h = daily.avgHrv ?: return null
            val r = daily.restingHr ?: return null
            if (baselines.hrv?.usable != true) return null
            val f = base("recovery", source, recoveryMethod)
            f["hrv"] = number(h); f["rhr"] = number(r.toDouble())
            f["resp"] = number(daily.respRateBpm); f["skin"] = number(daily.skinTempDevC)
            f["sleep"] = number(RestScorer.restFromDaily(daily)?.div(100.0) ?: daily.efficiency)
            for ((name, state) in listOf("hrv" to baselines.hrv, "rhr" to baselines.restingHR, "resp" to baselines.resp, "skin" to baselines.skinTemp)) {
                f[name + "Mean"] = number(state?.baseline)
                f[name + "Spread"] = number(state?.spread)
                f[name + "NValid"] = state?.let { integer(it.nValid.toLong()) } ?: "n"
                f[name + "NightsSinceUpdate"] = state?.let { integer(it.nightsSinceUpdate.toLong()) } ?: "n"
                f[name + "Status"] = state?.let { string(it.status.name.lowercase()) } ?: "n"
            }
            return make(f)
        }
        fun rest(daily: DailyMetric, source: String): ScoreRecipe? {
            val t = daily.totalSleepMin?.takeIf { it > 0 } ?: return null
            val e = daily.efficiency ?: return null
            val f = base("sleep_performance", source, restMethod)
            f["minutes"] = number(t); f["efficiency"] = number(e)
            f["deepMinutes"] = number(daily.deepMin); f["remMinutes"] = number(daily.remMin)
            return make(f)
        }
        fun effort(hr: List<HrSample>, maxHR: Double?, restingHR: Double, method: StrainScorer.Method,
                   sex: String, source: String): ScoreRecipe? {
            if (hr.isEmpty()) return null
            val actual = StrainScorer.strain(hr, maxHR, restingHR, method, sex) ?: return null
            val maximum = maxHR ?: StrainScorer.defaultMaxHR().toDouble()
            if (!maximum.isFinite() || !restingHR.isFinite() || maximum <= restingHR) return null
            val durations = StrainScorer.sampleDurationsMinutes(hr)
            val reserve = maximum - restingHR
            val trimp = when (method) {
                StrainScorer.Method.EDWARDS -> StrainScorer.edwardsTRIMP(hr, restingHR, reserve, durations)
                StrainScorer.Method.BANISTER -> {
                    val c = StrainScorer.banisterCoefficients(sex.lowercase().startsWith("f"))
                    StrainScorer.banisterTRIMP(hr, restingHR, reserve, durations, c,
                        StrainScorer.banisterBaselineRatePerMinute(c))
                }
            }
            val f = base("strain", source, if (method == StrainScorer.Method.EDWARDS) edwardsMethod else banisterMethod)
            f["trimp"] = number(trimp); f["denominator"] = number(StrainScorer.logMapDenominator(method, sex))
            f["maxHR"] = number(maximum); f["restingHR"] = number(restingHR)
            f["sex"] = string(if (sex.lowercase().startsWith("f")) "female" else "male")
            f["count"] = integer(hr.size.toLong()); f["firstTs"] = integer(hr.minOf { it.ts })
            f["lastTs"] = integer(hr.maxOf { it.ts }); f["creditedMinutes"] = number(durations.sum())
            f["stream"] = string(hash(hr.joinToString(";") { "${it.ts}:${it.bpm}" }))
            val last = hr.maxOf { it.ts }; if (last == Long.MAX_VALUE) return null
            f["windowStart"] = integer(hr.minOf { it.ts }); f["windowEnd"] = integer(last + 1)
            f["windowKind"] = string("observed-samples")
            return make(f)?.takeIf { it.score == actual }
        }
        private fun base(key: String, source: String, method: String) = mutableMapOf(
            "schema" to "i1", "key" to string(key), "source" to string(source), "method" to string(method))
        private fun number(v: Double?): String = v?.let { "d" + it.toRawBits().toULong().toString(16).padStart(16, '0') } ?: "n"
        private fun integer(v: Long) = "i$v"
        private fun string(s: String) = "s" + s.toByteArray(Charsets.UTF_8).joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }
        private fun text(v: String): String? {
            if (!v.startsWith("s") || v.length % 2 != 1) return null
            val bytes = v.drop(1).chunked(2).map { it.toIntOrNull(16)?.toByte() ?: return null }.toByteArray()
            val decoded = bytes.toString(Charsets.UTF_8)
            return decoded.takeIf { string(it) == v }
        }
        private fun validName(s: String) = s.isNotEmpty() && s.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it in "._-" }
        private fun hash(s: String): String {
            var h = 14695981039346656037UL
            for (c in s.toByteArray(Charsets.UTF_8)) h = (h xor (c.toInt() and 255).toULong()) * 1099511628211UL
            return h.toString(16).padStart(16, '0')
        }
        fun decode(payload: String): ScoreRecipe? {
            if (payload.isEmpty() || payload.toByteArray(Charsets.UTF_8).size > 16384 || payload.any { it.code >= 128 }) return null
            val f = mutableMapOf<String, String>()
            for (row in payload.split('\n')) {
                val pair = row.split('=', limit = 2)
                if (pair.size != 2 || !validName(pair[0]) || pair[0] in f) return null
                val v = pair[1]
                when {
                    v == "n" -> Unit
                    v.startsWith("s") -> if (text(v) == null) return null
                    v.startsWith("d") -> {
                        val bits = v.drop(1).toULongOrNull(16) ?: return null
                        val d = Double.fromBits(bits.toLong())
                        if (v.length != 17 || !d.isFinite() || number(d) != v) return null
                    }
                    v.startsWith("i") -> {
                        val i = v.drop(1).toLongOrNull() ?: return null
                        if (integer(i) != v) return null
                    }
                    else -> return null
                }
                f[pair[0]] = v
            }
            return make(f)?.takeIf { it.payload == payload }
        }
        private fun make(f: Map<String, String>): ScoreRecipe? {
            val payload = f.toSortedMap().entries.joinToString("\n") { "${it.key}=${it.value}" }
            if (payload.toByteArray(Charsets.UTF_8).size > 16384 || f["schema"] != "i1") return null
            val key = f["key"]?.let(::text) ?: return null
            val source = f["source"]?.let(::text)?.takeIf { it.isNotEmpty() } ?: return null
            val method = f["method"]?.let(::text) ?: return null
            if (!f.filterKeys { it.startsWith("ctx.") }.all { validName(it.key.removePrefix("ctx.")) && text(it.value) != null }) return null
            if (f.values.any { it.startsWith("d") && it.drop(1).toULongOrNull(16)?.let { b -> Double.fromBits(b.toLong()).isFinite() } != true }) return null
            val score = evaluate(f, method, key)?.takeIf { it.isFinite() && it in 0.0..100.0 } ?: return null
            return ScoreRecipe(key, source, method, payload, hash(payload), score, f.toMap())
        }
        // Frozen v1 replay branches. New numerical behavior requires a new method ID.
        private fun evaluate(f: Map<String, String>, method: String, key: String): Double? {
            fun d(k: String): Double? = f[k]?.takeIf { it.startsWith("d") }?.drop(1)?.toULongOrNull(16)
                ?.let { Double.fromBits(it.toLong()) }?.takeIf { it.isFinite() }
            val common = setOf("schema", "key", "source", "method")
            val allowed = when (method) {
                recoveryMethod -> setOf("hrv", "rhr", "resp", "skin", "sleep") + listOf("hrv", "rhr", "resp", "skin").flatMap { name -> listOf("Mean", "Spread", "NValid", "NightsSinceUpdate", "Status").map { name + it } }
                restMethod -> setOf("minutes", "efficiency", "deepMinutes", "remMinutes")
                edwardsMethod, banisterMethod -> setOf("trimp", "denominator", "maxHR", "restingHR", "sex", "count", "firstTs", "lastTs", "creditedMinutes", "stream", "windowStart", "windowEnd", "windowKind")
                else -> return null
            }
            if (f.keys.filterNot { it.startsWith("ctx.") }.toSet() != common + allowed) return null
            if (!(allowed - setOf("sex", "count", "firstTs", "lastTs", "stream", "windowStart", "windowEnd", "windowKind")).filterNot { it.endsWith("NValid") || it.endsWith("NightsSinceUpdate") || it.endsWith("Status") }.all { f[it] == "n" || d(it) != null }) return null
            return when (method) {
                recoveryMethod -> {
                    for (name in listOf("hrv", "rhr", "resp", "skin")) {
                        val keys = listOf("Mean", "Spread", "NValid", "NightsSinceUpdate", "Status").map { name + it }
                        if (keys.all { f[it] == "n" }) continue
                        fun integerField(k: String) = f[k]?.takeIf { it.startsWith("i") }?.drop(1)?.toLongOrNull()?.let { it >= 0 } == true
                        if (d(name + "Mean") == null || d(name + "Spread") == null || !integerField(name + "NValid") || !integerField(name + "NightsSinceUpdate") || f[name + "Status"]?.let(::text) !in listOf("calibrating", "provisional", "trusted", "stale")) return null
                    }
                    fun usable(name: String) = f[name + "Status"]?.let(::text) in listOf("trusted", "provisional")
                    if (key != "recovery" || !usable("hrv")) return null
                    val h = d("hrv") ?: return null; val r = d("rhr") ?: return null
                    val hm = d("hrvMean") ?: return null; val hs = d("hrvSpread") ?: return null
                    fun z(v: Double, m: Double, s: Double) = (v - m) / max(1.253 * s, 1e-9)
                    val terms = mutableListOf(z(h, hm, hs) to 0.55)
                    val rm = d("rhrMean"); val rs = d("rhrSpread")
                    if (usable("rhr") && rm != null && rs != null) terms += z(rm, r, rs) to 0.20
                    val resp = d("resp"); val pm = d("respMean"); val ps = d("respSpread")
                    if (usable("resp") && resp != null && pm != null && ps != null) terms += z(pm, resp, ps) to 0.05
                    d("sleep")?.let { terms += ((it - 0.85) / 0.12) to 0.15 }
                    d("skin")?.let { terms += (-kotlin.math.abs(it) / 1.0) to 0.05 }
                    val z = terms.sumOf { it.first * it.second } / terms.sumOf { it.second }
                    max(0.0, min(100.0, 100.0 / (1.0 + exp(-1.6 * (z - -0.20)))))
                }
                restMethod -> {
                    if (key != "sleep_performance") return null
                    val t = d("minutes")?.takeIf { it > 0 } ?: return null; val e = d("efficiency") ?: return null
                    fun clamp(x: Double) = max(0.0, min(1.0, x))
                    val seconds = t * 60.0; val deep = (d("deepMinutes") ?: 0.0) * 60.0
                    val restorative = deep + (d("remMinutes") ?: 0.0) * 60.0
                    val factor = 0.5 + (1.0 - 0.5) * clamp((deep / seconds) / 0.13)
                    val weighted = 0.50 * clamp(seconds / (8.0 * 3600.0)) + 0.20 * clamp(e) +
                        0.20 * clamp((restorative / seconds) / 0.50) * factor + 0.10 * 0.5
                    (weighted * 10000).roundToLong() / 100.0
                }
                else -> {
                    if (key != "strain") return null
                    val t = d("trimp")?.takeIf { it >= 0 } ?: return null
                    val denominator = d("denominator")?.takeIf { it > 1 } ?: return null
                    val maximum = d("maxHR") ?: return null; val resting = d("restingHR") ?: return null
                    if (maximum <= resting || d("creditedMinutes")?.let { it > 0 } != true) return null
                    fun i(k: String) = f[k]?.takeIf { it.startsWith("i") }?.drop(1)?.toLongOrNull()
                    val count = i("count") ?: return null; val lo = i("firstTs") ?: return null; val hi = i("lastTs") ?: return null
                    val start = i("windowStart") ?: return null; val end = i("windowEnd") ?: return null
                    if (start > lo || end <= hi || f["windowKind"]?.let(::text) !in listOf("observed-samples", "sleep-onset", "calendar")) return null
                    if (count <= 0 || hi < lo || f["sex"]?.let(::text) !in listOf("male", "female") || f["stream"]?.let(::text)?.length != 16) return null
                    if (t <= 0) 0.0 else (100 * ln(t + 1.0) / ln(denominator) * 100).roundToLong() / 100.0
                }
            }
        }
    }
}
