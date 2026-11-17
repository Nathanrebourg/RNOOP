package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File
import java.sql.DriverManager

/** Executes production migration/retention SQL with SQLite, without a device or Robolectric. */
class ScoreCalculationEvidenceSqliteTest {
    private fun daoQuery(method: String): String {
        var root = File(System.getProperty("user.dir") ?: ".").canonicalFile
        repeat(5) {
            val source = listOf(File(root, "android/app/src/main/java/com/noop/data/WhoopDao.kt"),
                File(root, "app/src/main/java/com/noop/data/WhoopDao.kt")).firstOrNull { it.isFile }
            if (source != null) {
                return Regex("@Query\\(\"([^\"]+)\"\\)\\s+suspend fun $method\\(")
                    .find(source.readText())!!.groupValues[1]
            }
            root = root.parentFile ?: root
        }
        error("WhoopDao.kt not found")
    }

    @Test
    fun additiveMigrationHasExactColumnsAndPreservesScores() {
        DriverManager.getConnection("jdbc:sqlite::memory:").use { db ->
            db.createStatement().use { s ->
                s.execute("CREATE TABLE dailyMetric(deviceId TEXT,day TEXT,recovery REAL)")
                s.execute("INSERT INTO dailyMetric VALUES ('strap-noop','2026-11-15',71)")
                WhoopDatabase.SCORE_CALCULATION_MIGRATION_SQL.forEach { s.execute(it) }
                for ((table, expected) in listOf(
                    "scoreCalculationEvidence" to listOf("deviceId","day","key","fingerprint","capturedAt","sourceId","methodId","value","payload"),
                    "scoreCalculationHead" to listOf("deviceId","day","key","fingerprint"),
                )) {
                    val names = mutableListOf<String>()
                    s.executeQuery("PRAGMA table_info($table)").use { rows ->
                        while (rows.next()) { names += rows.getString("name"); assertEquals(1, rows.getInt("notnull")) }
                    }
                    assertEquals(expected, names)
                }
                s.executeQuery("SELECT recovery FROM dailyMetric").use { rows -> rows.next(); assertEquals(71.0, rows.getDouble(1), 0.0) }
            }
        }
    }

    @Test
    fun retentionUsesTotalOrderClearsDanglingHeadsAndRetainsDailyScores() {
        DriverManager.getConnection("jdbc:sqlite::memory:").use { db ->
            db.createStatement().use { s ->
                s.execute("CREATE TABLE dailyMetric(deviceId TEXT,day TEXT,recovery REAL)")
                s.execute("INSERT INTO dailyMetric VALUES ('strap-noop','2026-11-15',71)")
                WhoopDatabase.SCORE_CALCULATION_MIGRATION_SQL.forEach { s.execute(it) }
                for (index in 0..9) {
                    s.execute("INSERT INTO scoreCalculationEvidence VALUES ('strap-noop','2026-11-15','recovery','$index',100,'strap','method',71,'recipe')")
                }
                s.execute("INSERT INTO scoreCalculationHead VALUES ('strap-noop','2026-11-15','recovery','0')")
                val bindings = mapOf("deviceId" to "strap-noop", "day" to "2026-11-15", "key" to "recovery")
                for (method in listOf("trimScoreCalculationCell", "deleteDanglingScoreCalculationHeads")) {
                    var sql = daoQuery(method)
                    for ((key,value) in bindings) sql = sql.replace(":$key", "'$value'")
                    s.execute(sql)
                }
                s.executeQuery("SELECT COUNT(*) FROM scoreCalculationEvidence").use { r -> r.next(); assertEquals(8, r.getInt(1)) }
                s.executeQuery("SELECT fingerprint FROM scoreCalculationHead").use { r -> r.next(); assertEquals("0", r.getString(1)) }
                s.executeQuery("SELECT fingerprint FROM scoreCalculationEvidence ORDER BY fingerprint").use { r ->
                    r.next(); assertEquals("0", r.getString(1)); r.next(); assertEquals("3", r.getString(1))
                }
                s.execute("DELETE FROM dailyMetric")
                s.executeQuery("SELECT * FROM scoreCalculationHead").use { assertFalse(it.next()) }
                s.executeQuery("SELECT COUNT(*) FROM scoreCalculationEvidence").use { r -> r.next(); assertEquals(8, r.getInt(1)) }
            }
        }
    }
}
