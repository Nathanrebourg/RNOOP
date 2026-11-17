package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.HrSample
import org.junit.Assert.*
import org.junit.Test

class ScoreRecipeTest {
    private fun daily() = DailyMetric("", "2026-11-15", totalSleepMin = 420.0, efficiency = 0.9,
        deepMin = 60.0, remMin = 90.0, restingHr = 54, avgHrv = 61.0, skinTempDevC = -0.2, respRateBpm = 14.2)
    private fun fixtures(): List<ScoreRecipe> {
        val d = daily()
        val h = BaselineState(55.0, 8.0, 21, 0, BaselineStatus.TRUSTED)
        val r = BaselineState(57.0, 4.0, 15, 1, BaselineStatus.PROVISIONAL)
        val p = BaselineState(14.6, 0.7, 17, 0, BaselineStatus.TRUSTED)
        val stale = BaselineState(33.0, 0.4, 44, 9, BaselineStatus.STALE)
        val recipes = mutableListOf(ScoreRecipe.rest(d, "strap-α")!!,
            ScoreRecipe.recovery(d, ProfileBaselines(h, r, p, stale), "strap-α")!!,
            ScoreRecipe.recovery(d, ProfileBaselines(h, stale), "strap-α")!!)
        val hr = (0 until 180).map { HrSample("", 1000L + it * 30 + (if (it > 100) 600 else 0), listOf(60, 100, 145, 180)[it % 4]) }
        for (method in listOf(StrainScorer.Method.EDWARDS, StrainScorer.Method.BANISTER)) {
            for (sex in listOf("male", "female")) recipes += ScoreRecipe.effort(hr, 190.0, 55.0, method, sex, "strap-α")!!
                .withEffortWindow(900, 8000)!!
        }
        recipes += recipes[0].withContext(mapOf("zone" to "Europe/Paris", "setting" to "α=\n🫀"))!!
        return recipes
    }
    fun transcript(): String = fixtures().joinToString("\n") {
        "${it.key}|${it.methodId}|${it.fingerprint}|${it.score.toRawBits().toULong().toString(16).padStart(16, '0')}|${it.payload.toByteArray(Charsets.UTF_8).size}"
    }
    @Test fun swiftCompiledOracleAndReplay() {
        assertEquals(SWIFT_ORACLE, transcript())
        for (recipe in fixtures()) {
            assertEquals(recipe, ScoreRecipe.decode(recipe.payload))
            assertEquals(recipe.score, recipe.replay())
            assertEquals(if (recipe.key == "sleep_performance") 0.9 else null, recipe.numericInputs["efficiency"])
            assertEquals(recipe.sourceId, recipe.textInputs["source"])
        }
    }
    @Test fun calendarScopePreservesActualQueryBoundsAndScore() {
        val original = fixtures()[3]
        val calendar = original.withEffortWindow(0, 86400, "calendar")!!
        assertEquals("calendar", calendar.textInputs["windowKind"])
        assertTrue(calendar.payload.contains("windowStart=i0"))
        assertTrue(calendar.payload.contains("windowEnd=i86400"))
        assertEquals(original.score, calendar.replay())
        assertEquals(calendar, ScoreRecipe.decode(calendar.payload))
        assertEquals(listOf("windowEnd", "windowKind", "windowStart"), calendar.changedFields(original))
        assertNull(original.withEffortWindow(0, 86400, "invented"))
    }
    @Test fun contextAndMalformedPayloads() {
        val r = fixtures()[0]
        val context = mapOf("zone" to "Europe/Paris", "setting" to "α=\n🫀")
        assertEquals(context, r.withContext(context)!!.context)
        assertEquals(listOf("ctx.setting", "ctx.zone"), r.withContext(context)!!.changedFields(r))
        for (s in listOf(r.payload + "\n", r.payload + "\nkey=s78", "x".repeat(16385), r.payload.replace("efficiency=d3feccccccccccccd", "efficiency=d7ff8000000000000"))) assertNull(ScoreRecipe.decode(s))
        assertNull(r.withContext(mapOf("bad key" to "x")))
        assertNull(ScoreRecipe.rest(daily().copy(totalSleepMin = null), "strap"))
        assertNull(ScoreRecipe.effort(emptyList(), 190.0, 55.0, StrainScorer.Method.EDWARDS, "male", "strap"))
        assertNull(fixtures()[3].withEffortWindow(1100, 8000))
    }
    @Test fun staleBaselineMetadataChangesIdentityWithoutInventingUsability() {
        val d = daily()
        val h = BaselineState(55.0, 8.0, 21, 0, BaselineStatus.TRUSTED)
        val stale = BaselineState(33.0, 0.4, 44, 9, BaselineStatus.STALE)
        val a = ScoreRecipe.recovery(d, ProfileBaselines(h, stale), "strap")!!
        val b = ScoreRecipe.recovery(d, ProfileBaselines(h, stale.copy(nValid = 45)), "strap")!!
        assertEquals(a.score, b.score, 0.0)
        assertEquals(listOf("rhrNValid"), b.changedFields(a))
        assertNull(ScoreRecipe.recovery(d, ProfileBaselines(stale), "strap"))
    }
    companion object {
        // Verbatim stdout from the compiled Swift Tools/Oracles/ScoreRecipe executable.
        val SWIFT_ORACLE = """sleep_performance|rest.daily-composite.v1|a8d7abf541faede8|4054428f5c28f5c3|243
recovery|recovery.logistic.v1|a35573149d4acb73|40522cef0c1d2113|705
recovery|recovery.logistic.v1|94eb51d031fe2dfe|4051bfff0286b5dd|599
strain|effort.edwards-hrr-log.v1|dc0070bb3ccc3116|404c83d70a3d70a4|412
strain|effort.edwards-hrr-log.v1|e253c9635a25b5e3|404c83d70a3d70a4|416
strain|effort.banister-sedentary-log.v1|85c960db12bc336a|404b5851eb851eb8|426
strain|effort.banister-sedentary-log.v1|2c6e15eb5d5812e6|404bb33333333333|430
sleep_performance|rest.daily-composite.v1|079fdb31099cc3ff|4054428f5c28f5c3|308"""
    }
}
