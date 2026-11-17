package com.noop.analytics
import com.noop.data.HrSample
import com.noop.data.GravitySample
import com.noop.data.RrInterval
import org.junit.Assert.*
import org.junit.Test

class AlgorithmLabTest {
    private val day=1_728_000_000L
    private fun hr(n: Int,start: Long=0,bpm: Int=70)=(0 until n).map { HrSample("test",start+it,bpm) }
    private fun grav(n: Int,start: Long=0)=(0 until n).map { GravitySample("test",start+it,if (it%2==0) 1.0 else 0.0,0.0,1.0) }
    @Test fun oneDenseHourCannotClaimAFullDaysCoverage() {
        val q=SampleQuality.analyze(hr(3600),0,86400)
        assertEquals(3600,q.observedSeconds);assertEquals(82800L,q.longestGap)
        assertEquals("calibrating",q.tier);assertTrue(q.reliability<0.05)
    }
    @Test fun completeEvidenceIsSolidAndDuplicatesNeverAddTime() {
        val h=hr(3600);val q=SampleQuality.analyze(h+h,0,3600)
        assertEquals(3600,q.observedSeconds);assertEquals(1.0,q.coverage,0.0)
        assertEquals(1.0,q.reliability,0.0);assertEquals("solid",q.tier);assertEquals(3600,q.duplicates)
    }
    @Test fun conflictsGapsAndInvalidRowsLowerEvidenceWithoutDeletingHighReadings() {
        val q=SampleQuality.analyze(hr(600,bpm=190)+listOf(HrSample("test",100,70),HrSample("test",601,0)),0,1200)
        assertEquals(599,q.observedSeconds);assertEquals(1,q.ambiguous);assertEquals(1,q.invalid)
        assertEquals(600L,q.longestGap);assertEquals("building",q.tier)
    }
    @Test fun emptyAndInvalidIntervalsHaveNoQuality() {
        assertEquals(0.0,SampleQuality.analyze(emptyList(),0,600).reliability,0.0)
        assertEquals("calibrating",SampleQuality.analyze(hr(10),10,0).tier)
    }
    @Test fun fullQualityRecoveryMatchesRealIncumbent() {
        val h=RecoveryScorer.DriverBaseline(60.0,10.0);val r=RecoveryScorer.DriverBaseline(55.0,5.0)
        val expected=RecoveryScorer.recovery(45.0,60.0,null,h,r,null,0.9)
        val c=QualityRecovery.compare(45.0,60.0,hrvBaseline=h,rhrBaseline=r,sleepPerf=0.9,quality=QualityRecovery.Quality(1.0,1.0,1.0))
        assertEquals(expected,c.original);assertEquals(expected!!,c.candidate!!,1e-12)
    }
    @Test fun unreliableEssentialRecoverySignalRefusesCandidate() {
        val b=RecoveryScorer.DriverBaseline(60.0,10.0)
        val c=QualityRecovery.compare(45.0,60.0,hrvBaseline=b,rhrBaseline=b,sleepPerf=0.9,quality=QualityRecovery.Quality(0.1,1.0,1.0))
        assertNotNull(c.original);assertNull(c.candidate);assertEquals("insufficient-essential-quality",c.status)
    }
    @Test fun lowerSleepQualityReducesItsInfluenceRatherThanFabricatingSleep() {
        val b=RecoveryScorer.DriverBaseline(60.0,10.0)
        fun c(q: Double)=QualityRecovery.compare(60.0,60.0,hrvBaseline=b,rhrBaseline=b,sleepPerf=0.2,quality=QualityRecovery.Quality(1.0,1.0,q))
        assertTrue(c(0.2).candidate!!>c(1.0).candidate!!);assertEquals(c(1.0).original,c(0.2).original)
    }
    @Test fun invalidQualityAndUnusableBaselineCannotScore() {
        val b=RecoveryScorer.DriverBaseline(60.0,10.0)
        assertNull(QualityRecovery.compare(60.0,60.0,hrvBaseline=b,rhrBaseline=b,quality=QualityRecovery.Quality(Double.NaN,1.0,1.0)).candidate)
        assertNull(QualityRecovery.compare(60.0,60.0,hrvBaseline=b,rhrBaseline=b,baselineUsable=false,quality=QualityRecovery.Quality(1.0,1.0,1.0)).candidate)
    }
    @Test fun isolatedHRPeakDoesNotBecomeConfirmedMaximum() {
        assertEquals(160.0,ConfirmedHRmax.dailyPeak(hr(300,bpm=160)+HrSample("test",150,230),grav(300))!!,0.0)
        assertNull(ConfirmedHRmax.dailyPeak(hr(10,bpm=200),grav(10)))
    }
    @Test fun maximumNeedsThreeIndependentPriorDaysAndPreservesManualOverride() {
        val history=(1..3).map { ConfirmedHRmax.DayPeak(day-it*86400,200.0) }
        val e=ConfirmedHRmax.estimate(history,day,30.0)
        assertEquals(200.0,e.candidate!!,0.0);assertEquals("confirmed-history",e.source)
        assertEquals(187.0,ConfirmedHRmax.estimate(history.take(2),day,30.0).candidate!!,0.0)
        assertEquals(195.0,ConfirmedHRmax.estimate(history,day,30.0,195.0).candidate!!,0.0)
    }
    @Test fun maximumRejectsFutureConflictingAndUnconfirmedMotion() {
        assertNull(ConfirmedHRmax.dailyPeak(hr(300,bpm=200),emptyList()))
        val p=ConfirmedHRmax.DayPeak(day,240.0)
        assertEquals(187.0,ConfirmedHRmax.estimate(listOf(p,p,p),day,30.0).candidate!!,0.0)
    }
    @Test fun contextIsExplicitAndOnlyPriorIndependentNightsCount() {
        val h=(1..10).map { ContextualSleepNeed.Night(day-it*86400,9.0) }
        assertNull(ContextualSleepNeed.estimate(h,day,30).candidateHours)
        val known=(1..7).map { ContextualSleepNeed.Night(day-it*86400,9.0,true,true,false) }
        val r=ContextualSleepNeed.estimate(known,day,30)
        assertEquals(9.0,r.candidateHours!!,0.0);assertEquals(7,r.eligibleNights)
    }
    @Test fun disruptionFalseAndMissingContextAreNotInterchangeable() {
        val h=(1..7).map { ContextualSleepNeed.Night(day-it*86400,9.0,true,true,true) }
        assertNull(ContextualSleepNeed.estimate(h,day,30).candidateHours)
        val f=ContextualSleepNeed.Night(day,12.0,true,true,false)
        assertNull(ContextualSleepNeed.estimate(List(7){f},day,30).candidateHours)
    }
    @Test fun threeTinyRRBurstsCannotClaimWholeNightQuality() {
        val s=DetectedSleep(0,28800,1.0,listOf(StageSegment(0,28800,"light")),60,30.0)
        val rr=listOf(0L,600L,1200L).flatMap { start -> (0 until 20).map { RrInterval("test",start+it,1000) } }
        assertTrue(AlgorithmLab.recoveryEvidence(listOf(s),hr(28800),rr,false).hrv<0.01)
    }
    @Test fun deepOnlyEvidenceUsesDeepDurationInsteadOfWholeNight() {
        val s=DetectedSleep(0,3600,1.0,listOf(StageSegment(0,900,"deep"),StageSegment(900,3600,"light")),60,30.0)
        val rr=(0 until 900).map { RrInterval("test",it.toLong(),1000) }
        assertEquals(1.0,AlgorithmLab.recoveryEvidence(listOf(s),hr(3600),rr,true).hrv,0.01)
    }
    @Test fun incumbentMaximumReportUsesProfileAgeAndManualOverride() {
        assertEquals(166.0,AlgorithmLab.incumbentMaximum(60.0,null),0.0)
        assertEquals(190.0,AlgorithmLab.incumbentMaximum(0.0,null),0.0)
        assertNull(ConfirmedHRmax.estimate(emptyList(),day,0.0).candidate)
        assertEquals(180.0,AlgorithmLab.incumbentMaximum(60.0,180.0),0.0)
    }
    @Test fun uniqueBriefSpikeIsRejectedButSustainedMaximumSurvives() {
        val h=hr(300,bpm=160).map { it.copy(bpm=if (it.ts==150L) 230 else it.bpm) }
        assertEquals(160.0,ConfirmedHRmax.dailyPeak(h,grav(300))!!,0.0)
        assertEquals(200.0,ConfirmedHRmax.dailyPeak(hr(300,bpm=200),grav(300))!!,0.0)
    }
    @Test fun fullQualityWithAllOptionalTermsMatchesTheRealScorer() {
        val b=RecoveryScorer.DriverBaseline(60.0,10.0);val r=RecoveryScorer.DriverBaseline(55.0,5.0);val p=RecoveryScorer.DriverBaseline(14.0,1.0)
        val c=QualityRecovery.compare(45.0,60.0,15.0,b,r,p,0.8,0.3,quality=QualityRecovery.Quality(1.0,1.0,1.0,1.0,1.0))
        assertEquals(c.original,c.candidate)
    }
    @Test fun conflictingHistoryCannotManufactureAnEligibleContextOrMaximum() {
        val h=(1..7).map { ContextualSleepNeed.Night(day-it*86400,9.0,true,true,false) }+
            ContextualSleepNeed.Night(day-86400,5.0,true,true,false)
        assertEquals(6,ContextualSleepNeed.estimate(h,day,30).eligibleNights)
        assertNull(ContextualSleepNeed.estimate(h,day,30).candidateHours)
        val p=listOf(ConfirmedHRmax.DayPeak(day-86400,200.0),ConfirmedHRmax.DayPeak(day-86400,220.0))
        assertEquals(0,ConfirmedHRmax.estimate(p,day,30.0).confirmedDays)
    }
    @Test fun providedOrEditedSleepCannotReuseDetectorQuality() {
        val s=DetectedSleep(0,900,1.0,listOf(StageSegment(0,900,"light")),60,40.0)
        val rr=(0 until 900).map { RrInterval("test",it.toLong(),1000) }
        assertEquals(0.0,AlgorithmLab.recoveryEvidence(listOf(s),hr(900),rr,false,false).hrv,0.0)
        val d=com.noop.data.DailyMetric(deviceId="test",day="2024-10-04")
        val r=AlgorithmLab.recoveryComparison(d,ProfileBaselines(),QualityRecovery.Quality(1.0,1.0,1.0),false)
        assertNull(r.candidate);assertEquals("edited-sleep",r.status)
    }
    @Test fun freshAndCachedDiagnosticsRespectTheirActualModes() {
        val lines=listOf("lab quality experimental=true","lab recovery experimental=true","lab sleepneed experimental=true","ordinary")
        repeat(2) {
            val regular=ArrayList<String>();val work=ArrayList<String>();val recovery=ArrayList<String>();val sleep=ArrayList<String>()
            for (line in lines) AlgorithmLab.replayDiagnostic(line,{regular.add(it)},{work.add(it)},{recovery.add(it)},{sleep.add(it)})
            assertEquals(listOf("ordinary"),regular);assertEquals(listOf(lines[0]),work);assertEquals(listOf(lines[1]),recovery);assertEquals(listOf(lines[2]),sleep)
            regular.clear()
            for (line in lines) AlgorithmLab.replayDiagnostic(line,{regular.add(it)},null)
            assertEquals(listOf("ordinary"),regular)
        }
    }

    @Test fun matchesCompiledSwiftOracle() {
        val key="2024-10-04";val actual=ArrayList<String>()
        val cases=listOf(hr(3600) to 3600L,hr(3600) to 86400L,(hr(3600)+hr(3600)) to 3600L,
            (hr(600)+listOf(HrSample("test",100,190),HrSample("test",601,0))) to 1200L)
        for ((h,end) in cases) actual.add(AlgorithmLab.qualityLine(SampleQuality.analyze(h,0,end),key,"solid",true))
        val hb=RecoveryScorer.DriverBaseline(60.0,10.0);val rb=RecoveryScorer.DriverBaseline(55.0,5.0);val pb=RecoveryScorer.DriverBaseline(14.0,1.0)
        for (q in listOf(QualityRecovery.Quality(1.0,1.0,1.0,1.0,1.0),QualityRecovery.Quality(1.0,1.0,0.2,1.0,1.0),
            QualityRecovery.Quality(0.1,1.0,1.0),QualityRecovery.Quality(1.0,0.1,1.0))) {
            val r=QualityRecovery.compare(45.0,60.0,15.0,hb,rb,pb,0.8,0.3,quality=q)
            actual.add(AlgorithmLab.recoveryLine(r,q,key))
        }
        val history=(1..3).map { ConfirmedHRmax.DayPeak(day-it*86400,200.0) }
        for (e in listOf(ConfirmedHRmax.estimate(history,day,30.0),ConfirmedHRmax.estimate(history.take(2),day,30.0),
            ConfirmedHRmax.estimate(history,day,30.0,195.0),ConfirmedHRmax.estimate(emptyList(),day,0.0),ConfirmedHRmax.estimate(emptyList(),day,60.0))) {
            actual.add(AlgorithmLab.maximumLine(e,key,187.0))
        }
        val known=(1..7).map { ContextualSleepNeed.Night(day-it*86400,9.0,true,true,false) }
        val unknown=(1..7).map { ContextualSleepNeed.Night(day-it*86400,9.0) }
        for (n in listOf(known,unknown,known.take(6),known+ContextualSleepNeed.Night(day-86400,5.0,true,true,false)))
            actual.add(AlgorithmLab.sleepLine(ContextualSleepNeed.estimate(n,day,30),key))
        for (deep in listOf(false,true)) {
            val duration=if (deep) 3600 else 28800
            val stages=if (deep) listOf(StageSegment(0,900,"deep"),StageSegment(900,duration.toLong(),"light")) else listOf(StageSegment(0,duration.toLong(),"light"))
            val s=DetectedSleep(0,duration.toLong(),1.0,stages,60,40.0)
            val rr=if (deep) (0 until 900).map { RrInterval("test",it.toLong(),1000) } else listOf(0L,600L,1200L).flatMap { x -> (0 until 20).map { RrInterval("test",x+it,1000) } }
            val q=AlgorithmLab.recoveryEvidence(listOf(s),hr(duration),rr,deep)
            actual.add(AlgorithmLab.recoveryLine(QualityRecovery.compare(45.0,60.0,hrvBaseline=hb,rhrBaseline=rb,sleepPerf=0.8,quality=q),q,key))
        }
        // Literal stdout of an executable linked to the real Swift production modules.
        val expected=listOf(
            "lab quality experimental=true model=nroop-lab-v1 day=2024-10-04 scope=elapsed-day-1hz original=solid candidate=solid expectedSec=3600 observedSec=3600 coverage=1.00 longestGapSec=0 reliability=1.00 duplicates=0 ambiguous=0 invalid=0",
            "lab quality experimental=true model=nroop-lab-v1 day=2024-10-04 scope=elapsed-day-1hz original=solid candidate=calibrating expectedSec=86400 observedSec=3600 coverage=0.04 longestGapSec=82800 reliability=0.00 duplicates=0 ambiguous=0 invalid=0",
            "lab quality experimental=true model=nroop-lab-v1 day=2024-10-04 scope=elapsed-day-1hz original=solid candidate=solid expectedSec=3600 observedSec=3600 coverage=1.00 longestGapSec=0 reliability=1.00 duplicates=3600 ambiguous=0 invalid=0",
            "lab quality experimental=true model=nroop-lab-v1 day=2024-10-04 scope=elapsed-day-1hz original=solid candidate=building expectedSec=1200 observedSec=599 coverage=0.50 longestGapSec=600 reliability=0.10 duplicates=0 ambiguous=1 invalid=1",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=23.56 candidate=23.56 status=compared qHrv=1.00 qRhr=1.00 qSleep=1.00 qResp=1.00 qSkin=1.00",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=23.56 candidate=21.59 status=compared qHrv=1.00 qRhr=1.00 qSleep=0.20 qResp=1.00 qSkin=1.00",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=23.56 candidate=nil status=insufficient-essential-quality qHrv=0.10 qRhr=1.00 qSleep=1.00 qResp=0.00 qSkin=0.00",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=23.56 candidate=nil status=insufficient-essential-quality qHrv=1.00 qRhr=0.10 qSleep=1.00 qResp=0.00 qSkin=0.00",
            "lab maxhr experimental=true model=nroop-lab-v1 day=2024-10-04 scope=calibration-only original=187.00 candidate=200.00 source=confirmed-history confirmedDays=3 readErrors=0 cappedDays=0",
            "lab maxhr experimental=true model=nroop-lab-v1 day=2024-10-04 scope=calibration-only original=187.00 candidate=187.00 source=tanaka confirmedDays=2 readErrors=0 cappedDays=0",
            "lab maxhr experimental=true model=nroop-lab-v1 day=2024-10-04 scope=calibration-only original=187.00 candidate=195.00 source=manual confirmedDays=0 readErrors=0 cappedDays=0",
            "lab maxhr experimental=true model=nroop-lab-v1 day=2024-10-04 scope=calibration-only original=187.00 candidate=nil source=insufficient-history confirmedDays=0 readErrors=0 cappedDays=0",
            "lab maxhr experimental=true model=nroop-lab-v1 day=2024-10-04 scope=calibration-only original=187.00 candidate=166.00 source=tanaka confirmedDays=0 readErrors=0 cappedDays=0",
            "lab sleepneed experimental=true model=nroop-lab-v1 day=2024-10-04 scope=prior-computed-context original=9.00 candidate=9.00 eligibleNights=7 status=compared",
            "lab sleepneed experimental=true model=nroop-lab-v1 day=2024-10-04 scope=prior-computed-context original=9.00 candidate=nil eligibleNights=0 status=insufficient-context",
            "lab sleepneed experimental=true model=nroop-lab-v1 day=2024-10-04 scope=prior-computed-context original=8.00 candidate=nil eligibleNights=6 status=insufficient-context",
            "lab sleepneed experimental=true model=nroop-lab-v1 day=2024-10-04 scope=prior-computed-context original=8.00 candidate=nil eligibleNights=6 status=insufficient-context",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=22.35 candidate=nil status=insufficient-essential-quality qHrv=0.00 qRhr=1.00 qSleep=1.00 qResp=0.00 qSkin=0.00",
            "lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=22.35 candidate=22.35 status=compared qHrv=1.00 qRhr=1.00 qSleep=1.00 qResp=0.00 qSkin=0.00"
        )
        assertEquals(expected,actual)
    }

    @Test fun computedZeroHRVRemainsAValueInsteadOfMissingData() {
        val h=RecoveryScorer.DriverBaseline(60.0,10.0);val r=RecoveryScorer.DriverBaseline(55.0,5.0)
        val expected=RecoveryScorer.recovery(0.0,60.0,null,h,r,null,0.8)
        val observed=QualityRecovery.compare(0.0,60.0,hrvBaseline=h,rhrBaseline=r,sleepPerf=0.8,quality=QualityRecovery.Quality(1.0,1.0,1.0))
        assertNotNull(expected);assertEquals(expected,observed.original);assertEquals(expected,observed.candidate)
        assertEquals("lab recovery experimental=true model=nroop-lab-v1 day=2024-10-04 scope=final-current-baselines original=0.85 candidate=0.85 status=compared qHrv=1.00 qRhr=1.00 qSleep=1.00 qResp=0.00 qSkin=0.00",AlgorithmLab.recoveryLine(observed,QualityRecovery.Quality(1.0,1.0,1.0),"2024-10-04"))
    }

}
