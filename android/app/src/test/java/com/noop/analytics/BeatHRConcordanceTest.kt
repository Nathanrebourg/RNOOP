package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.RrInterval
import org.junit.Assert.*
import org.junit.Test

class BeatHRConcordanceTest {
    private fun h(bpm: Int=60)=(0 until 120).map { HrSample("test",it.toLong(),bpm) }
    private fun rr()=(0 until 120).map { RrInterval("test",it.toLong(),1000,srcChannel=5) }
    @Test fun matchingIndependentSignalsHaveNoDiscrepancy() {
        val r=BeatHRConcordance.analyze(h(),rr(),0,120)
        assertEquals("observed",r.status);assertEquals(120,r.matchedSeconds)
        assertEquals(0.0,r.medianAbsoluteBPM!!,0.0);assertEquals(0,r.discrepantSeconds)
    }
    @Test fun systematicMismatchIsDescribedWithoutChangingEitherStream() {
        val hr=h(100);val beats=rr();val r=BeatHRConcordance.analyze(hr,beats,0,120)
        assertEquals(40.0,r.medianAbsoluteBPM!!,0.0);assertEquals(40.0,r.medianSignedBPM!!,0.0)
        assertEquals(120,r.discrepantSeconds);assertEquals(100,hr.first().bpm);assertEquals(1000,beats.first().rrMs)
    }
    @Test fun duplicateDeliveriesCannotInflateIndependentSeconds() {
        val h=h();val b=rr();val r=BeatHRConcordance.analyze(h+h,b+b,0,120)
        assertEquals(120,r.matchedSeconds);assertEquals(0.0,r.medianAbsoluteBPM!!,0.0)
    }
    @Test fun conflictingHeartRatesAndTooLittleOverlapCannotScore() {
        val r=BeatHRConcordance.analyze(h()+h(100),rr(),0,120)
        assertNull(r.medianAbsoluteBPM);assertEquals(0,r.matchedSeconds)
        val sparse=BeatHRConcordance.analyze(h().take(59),rr(),0,120)
        assertEquals("insufficient-overlap",sparse.status);assertNull(sparse.medianAbsoluteBPM)
    }
    @Test fun transportAndSessionProvenanceAreRequired() {
        assertEquals("unverified-rr-source",BeatHRConcordance.analyze(h(),rr().map { it.copy(srcChannel=null) },0,120).status)
        assertEquals("ineligible-session",BeatHRConcordance.analyze(h(),rr(),0,120,false).status)
        assertEquals("mixed-rr-source",BeatHRConcordance.analyze(h(),rr()+RrInterval("test",0,1000,srcChannel=7),0,120).status)
    }
    @Test fun nonmatchingTimestampsAndOutOfWindowDataAreNotInvented() {
        val r=BeatHRConcordance.analyze(h(),rr().map { it.copy(ts=it.ts+1000) },0,120)
        assertEquals(0,r.matchedSeconds);assertNull(r.medianAbsoluteBPM)
    }
    @Test fun burstDeliveryHasOnlyOneVotePerSecond() {
        val b=List(1000) { RrInterval("test",0,500,srcChannel=5) }
        val r=BeatHRConcordance.analyze(h(),rr()+b,0,120)
        assertEquals(120,r.matchedSeconds);assertEquals(0.0,r.medianAbsoluteBPM!!,0.0);assertEquals(1,r.discrepantSeconds)
    }
    @Test fun signedDiscrepancyAndStrictToleranceRemainDescriptive() {
        val r=BeatHRConcordance.analyze(h(50),rr(),0,120)
        assertEquals(-10.0,r.medianSignedBPM!!,0.0);assertEquals(0,r.discrepantSeconds)
        assertTrue(r.trace("2024-10-04").contains("noScoreEffect=true"))
        val regular=ArrayList<String>();val recovery=ArrayList<String>()
        AlgorithmLab.replayDiagnostic(r.trace("2024-10-04"),{regular.add(it)},null,{recovery.add(it)})
        assertTrue(regular.isEmpty());assertEquals(1,recovery.size)
    }
    @Test fun deepWindowWrapperKeepsOnlyItsOwnPeriods() {
        val h=(0 until 240).map { HrSample("test",it.toLong(),if (it<120) 60 else 100) }
        val rr=(0 until 240).map { RrInterval("test",it.toLong(),1000,srcChannel=5) }
        val s=DetectedSleep(0,240,1.0,listOf(StageSegment(0,120,"deep"),StageSegment(120,240,"light")),60,40.0)
        val deep=AlgorithmLab.concordanceLine(listOf(s),h,rr,true,true,"2024-10-04")
        val whole=AlgorithmLab.concordanceLine(listOf(s),h,rr,false,true,"2024-10-04")
        assertTrue(deep.contains("matchedSec=120 medianAbsBpm=0.00"))
        assertTrue(whole.contains("matchedSec=240 medianAbsBpm=20.00"))
    }

    @Test fun matchesCompiledSwiftOracle() {
        val actual=(0 until 8).map { i ->
            val h=(0 until if (i==6) 59 else 120).map { HrSample("test",it.toLong(),if (i==1) 100 else if (i==2) 50 else 60) }
            var rr=(0 until 120).map { RrInterval("test",it.toLong(),1000,srcChannel=if (i==4) null else 5) }
            if (i==3) rr=rr+List(1000) { RrInterval("test",0,500,srcChannel=5) }
            if (i==5) rr=rr+RrInterval("test",0,1000,srcChannel=7)
            BeatHRConcordance.analyze(h,rr,0,120,i!=7).trace("2024-10-04")
        }
        // Literal records from the real compiled Swift observer.
        val expected=listOf(
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=observed matchedSec=120 medianAbsBpm=0.00 medianSignedBpm=0.00 aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=observed matchedSec=120 medianAbsBpm=40.00 medianSignedBpm=40.00 aboveToleranceSec=120 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=observed matchedSec=120 medianAbsBpm=10.00 medianSignedBpm=-10.00 aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=observed matchedSec=120 medianAbsBpm=0.00 medianSignedBpm=0.00 aboveToleranceSec=1 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=unverified-rr-source matchedSec=0 medianAbsBpm=nil medianSignedBpm=nil aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=mixed-rr-source matchedSec=0 medianAbsBpm=nil medianSignedBpm=nil aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=insufficient-overlap matchedSec=59 medianAbsBpm=nil medianSignedBpm=nil aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true",
            "lab concordance experimental=true model=nroop-concordance-v1 day=2024-10-04 scope=exact-second-selected-hrv-period status=ineligible-session matchedSec=0 medianAbsBpm=nil medianSignedBpm=nil aboveToleranceSec=0 toleranceBpm=10 noScoreEffect=true"
        )
        assertEquals(expected,actual)
    }

}
