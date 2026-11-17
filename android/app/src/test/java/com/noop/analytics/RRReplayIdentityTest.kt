package com.noop.analytics
import com.noop.data.RrInterval
import org.junit.Assert.*
import org.junit.Test

class RRReplayIdentityTest {
    private fun row(ts:Long,rr:Int=1000,seq:Int=0,ord:Int?=null)=RrInterval("test",ts,rr,seq=seq,ord=ord,srcChannel=5)
    @Test fun distinctBeatIdentitiesSurviveAndMetadataConflictsRefuse() {
        val a=row(100,1000,0,0);val b=row(100,1000,1,1)
        val x=RRReplayIdentity.normalize(listOf(b,a,a,b),true)
        assertEquals(listOf(a,b),x.rows);assertEquals(2,x.duplicates)
        assertNull(RRReplayIdentity.normalize(listOf(a,row(100,1000,0,1)),true).rows)
    }
    @Test fun undeclaredIdentityCannotSilentlyDeduplicate() {
        val r=listOf(row(101),row(100),row(100));assertEquals(r,RRReplayIdentity.normalize(r,false).rows)
    }
    @Test fun compiledSwiftOracleIsByteIdentical() {
        val a=row(100,1000,0,0);val b=row(100,1000,1,1)
        val cases=listOf(listOf(b,a,a,b) to true,listOf(row(101),row(100),row(100)) to false,listOf(a,row(100,1000,0,1)) to true,
            listOf(row(100,1010,0,2),row(100,1000,1,null),row(100,1000,0,null),row(99,980),row(100,990,0,1)) to true,
            listOf(row(100,1000,-1)) to true,listOf(row(100),RrInterval("test",101,1000,srcChannel=7)) to true,
            emptyList<RrInterval>() to true,listOf(RrInterval("test",100,1000)) to true)
        val actual=cases.map { (r,declared)->val x=RRReplayIdentity.normalize(r,declared)
            val line=x.rows?.joinToString(","){"${it.ts}:${it.rrMs}:${it.seq}:${it.ord?.toString()?:"N"}"}?:"nil"
            "${x.status}|${x.duplicates}|$line"
        }.joinToString("\n")
        assertEquals(EXPECTED.trim(),actual)
    }
    companion object {
        // Literal output from standalone Swift linked against actual compiled analytics modules.
        private val EXPECTED="""
normalized|2|100:1000:0:0,100:1000:1:1
identity-undeclared|0|101:1000:0:N,100:1000:0:N,100:1000:0:N
conflicting-identity|0|nil
normalized|0|99:980:0:N,100:1000:0:N,100:1000:1:N,100:990:0:1,100:1010:0:2
invalid-identity|0|nil
invalid-identity|0|nil
normalized|0|
invalid-identity|0|nil
"""
    }
}
