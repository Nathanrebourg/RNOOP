package com.noop.analytics
import com.noop.data.RrInterval

/** Explicit stored snapshot normalization; never a raw-wire or physiological beat cleaner. */
object RRReplayIdentity {
    data class Result(val rows: List<RrInterval>?,val duplicates: Int,val status: String)
    private data class Key(val ts: Long,val rr: Int,val seq: Int)
    fun normalize(rows: List<RrInterval>,declared: Boolean): Result {
        if (!declared) return Result(rows,0,"identity-undeclared")
        if (rows.map { it.deviceId }.distinct().size>1 || rows.any { it.ts<0 || it.rrMs !in 0..65535 || it.seq !in 0 until 1000000
            || (it.ord!=null && it.ord !in 0 until 1000000) || it.srcChannel !in listOf(5,7) } || rows.map { it.srcChannel }.distinct().size>1)
            return Result(null,0,"invalid-identity")
        val unique=linkedMapOf<Key,RrInterval>();var duplicates=0
        for (r in rows) {
            val k=Key(r.ts,r.rrMs,r.seq);val previous=unique[k]
            if (previous!=null) {
                if (previous.ord!=r.ord || previous.srcChannel!=r.srcChannel) return Result(null,duplicates,"conflicting-identity")
                duplicates++
            } else unique[k]=r
        }
        val sorted=unique.values.sortedWith(compareBy<RrInterval> {it.ts}.thenBy {it.ord?:-1}.thenBy {it.rrMs}.thenBy {it.seq})
        return Result(sorted,duplicates,"normalized")
    }
}
