package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.RrInterval
import com.noop.data.GravitySample
import kotlin.math.abs
import kotlin.math.sqrt

/** Default-off read-only Rest instrumentation; Swift twin SleepClockStressComparison.swift.
 * Frozen v1 weights 40/25/20/15 are an engineering hypothesis, not validated mental stress. */
object SleepClockStressComparison {
    data class Stage(val start: Long, val end: Long, val kind: String)
    data class Night(val day: Int, val start: Long, val end: Long, val bedtimeMinute: Int, val wakeMinute: Int,
                     val stages: List<Stage>?, val sparse: Boolean)
    data class Physiology(val day: Int, val start: Long, val end: Long, val channel: Int?, val hr: Double?,
                          val rmssd: Double?, val coverage: Double, val windows: Int, val status: String)
    data class Result(val status: String, val duration: Double?, val efficiency: Double?, val clock: Double?,
                      val calmness: Double?, val candidate: Double?, val coverage: Double, val priorNights: Int,
                      val baselineNights: Int, val stressStatus: String)
    fun circularDistance(a: Int, b: Int): Int { val d=abs(a-b);return minOf(d,1440-d) }
    private fun valid(n: Night) = n.start>=0 && n.end<=4102444800L && n.end>n.start && n.end.toDouble()-n.start.toDouble()>=10_800 &&
        n.end.toDouble()-n.start.toDouble()<=57_600 && n.bedtimeMinute in 0 until 1440 && n.wakeMinute in 0 until 1440 && n.day>=0
    private fun median(xs: List<Double>): Double {val s=xs.sorted();val m=s.size/2;return if(s.size%2==0)(s[m-1]+s[m])/2 else s[m]}
    private fun segments(n: Night): List<Stage>? {
        val stages=n.stages ?: return null
        if(!valid(n)||n.sparse||stages.isEmpty()||stages.any{it.start<0||it.end<=it.start||it.kind !in listOf("awake","light","deep","rem")})return null
        val sorted=stages.filter{it.end>n.start&&it.start<n.end}.map{Stage(maxOf(n.start,it.start),minOf(n.end,it.end),it.kind)}
            .sortedWith(compareBy<Stage>{it.start}.thenBy{it.end}.thenBy{it.kind}).distinct()
        var cursor=n.start
        for(s in sorted){if(s.start!=cursor)return null;cursor=s.end}
        return sorted.takeIf{cursor==n.end}
    }
    private fun qualified(p:Physiology,n:Night):Boolean {
        val h=p.hr;val r=p.rmssd;val stage=segments(n)?:return false
        if(p.day!=n.day||p.start!=n.start||p.end!=n.end||p.status!="qualified"||p.channel !in listOf(5,7)||
            h==null||!h.isFinite()||h !in 30.0..250.0||r==null||!r.isFinite()||r<=0||r>2000||
            !p.coverage.isFinite()||p.coverage !in 0.7..1.0||p.windows<12||p.windows>(n.end-n.start)/300)return false
        val asleep=stage.filter{it.kind!="awake"}.sumOf{it.end-it.start}
        return asleep>0 && abs(p.coverage-p.windows*300.0/asleep)<1e-9
    }
    fun analyze(target: Night, history: List<Night>, now: Long, physiology: Physiology?=null,
                priorPhysiology: List<Physiology> = emptyList()): Result {
        fun result(status:String,d:Double?=null,e:Double?=null,c:Double?=null,n:Double?=null,cov:Double=0.0,
                   count:Int=0,baselines:Int=0,stress:String="night-stress-provenance-unavailable"):Result {
            val candidate=if(d!=null&&e!=null&&c!=null&&n!=null)100*(0.40*d+0.25*e+0.20*c+0.15*n) else null
            return Result(status,d,e,c,n,candidate,cov,count,baselines,stress)
        }
        if(!valid(target))return result("invalid-night")
        if(target.end>now)return result("unfinished-night")
        val prior=history.filter{valid(it)&&it.day<target.day&&target.day-it.day<=28&&it.end<=target.start}.groupBy{it.day}.values
            .mapNotNull{rows->rows.first().takeIf{n->rows.all{it==n}}}
        val clock=if(prior.size>=3)maxOf(0.0,1-(median(prior.map{circularDistance(target.bedtimeMinute,it.bedtimeMinute).toDouble()})+
            median(prior.map{circularDistance(target.wakeMinute,it.wakeMinute).toDouble()}))/240) else null
        val stage=segments(target)
        val asleep=stage?.filter{it.kind!="awake"}?.sumOf{it.end-it.start}?.toDouble()
        val d=asleep?.let{minOf(1.0,it/28_800)};val e=asleep?.let{it/(target.end-target.start).toDouble()}
        val p=physiology
        if(p==null||!qualified(p,target))
            return result("candidate-withheld",d,e,clock,null,if(stage==null)0.0 else 1.0,prior.size,0,p?.status?:"night-stress-provenance-unavailable")
        val priorKeys=prior.associateBy{it.day}
        val ps=priorPhysiology.filter{p0->priorKeys[p0.day]?.let{n0->p0.channel==p.channel && qualified(p0,n0)}?:false}
            .groupBy{it.day}.values.mapNotNull{rows->rows.singleOrNull()}.sortedBy{it.day}
        if(ps.size<3)return result("candidate-withheld",d,e,clock,null,if(stage==null)0.0 else 1.0,prior.size,ps.size,"insufficient-prior-night-baseline")
        val hrs=ps.mapNotNull{it.hr};val rrs=ps.mapNotNull{it.rmssd}
        fun mean(xs:List<Double>)=xs.sum()/xs.size
        fun spread(xs:List<Double>):Double {val m=mean(xs);return sqrt(xs.sumOf{(it-m)*(it-m)}/xs.size)}
        val raw=(p.hr!!-mean(hrs))/maxOf(5.0,spread(hrs))-(p.rmssd!!-mean(rrs))/maxOf(10.0,spread(rrs))
        val calm=1-DaytimeStress.squash(raw)/3
        return result(if(d!=null&&clock!=null)"compared" else "candidate-withheld",d,e,clock,calm,
            if(stage==null)0.0 else 1.0,prior.size,ps.size,"qualified-nocturnal-activation-proxy")
    }
    fun physiology(night:Night,hr:List<HrSample>,rr:List<RrInterval>,gravity:List<GravitySample>,
                   confirmedWhoop5:Boolean,readCapped:Boolean=false):Physiology {
        fun out(status:String,channel:Int?=null,h:Double?=null,r:Double?=null,coverage:Double=0.0,windows:Int=0)=
            Physiology(night.day,night.start,night.end,channel,h,r,coverage,windows,status)
        if(readCapped||hr.size>60000||rr.size>120000||gravity.size>60000)return out("read-capped")
        if(!confirmedWhoop5)return out("unconfirmed-whoop5-source")
        val stage=segments(night)?:return out("incomplete-or-sparse-stages")
        val beats=rr.filter{it.ts>=night.start&&it.ts<night.end}
        val channels=beats.mapNotNull{it.srcChannel}.toSet()
        val channel=channels.singleOrNull()
        if(channel==null||channel !in listOf(5,7)||beats.any{it.srcChannel!=channel})return out("rr-source-unavailable-or-mixed")
        val rs=RRReplayIdentity.normalize(beats,true).rows?:return out("conflicting-rr-identity")
        val hs=SampleQuality.uniqueHR(hr.filter{it.ts>=night.start&&it.ts<night.end&&it.bpm in 30..250})
        val gs=gravity.filter{it.ts>=night.start&&it.ts<night.end&&it.x.isFinite()&&it.y.isFinite()&&it.z.isFinite()&&
            abs(it.x)<=100&&abs(it.y)<=100&&abs(it.z)<=100&&(it.x!=0.0||it.y!=0.0||it.z!=0.0)}.groupBy{it.ts}.values.mapNotNull{rows->
            rows.first().takeIf{a->rows.all{it.x==a.x&&it.y==a.y&&it.z==a.z}}
        }.sortedBy{it.ts}
        val activity=WorkoutDetector.activitySeries(gs)
        val hg=hs.groupBy{(it.ts-night.start)/300};val gg=gs.groupBy{(it.ts-night.start)/300}
        val rg=rs.groupBy{(it.ts-night.start)/300};val ag=activity.groupBy{(it.ts-night.start)/300}
        fun covered(ts:List<Long>,start:Long)=ts.size>=240&&ts.first()-start<=15&&start+299-ts.last()<=15&&ts.zipWithNext().all{(a,b)->b-a<=15}
        val means=mutableListOf<Double>();val rmssds=mutableListOf<Double>()
        for(i in 0 until (night.end-night.start)/300){
            val lo=night.start+i*300;val hi=lo+300
            val sleeping=stage.filter{it.kind!="awake"}.sumOf{maxOf(0L,minOf(hi,it.end)-maxOf(lo,it.start))}
            if(sleeping!=300L)continue
            val h=hg[i]?:emptyList();val g=gg[i]?:emptyList();val a=ag[i]?:emptyList();val r=rg[i]?:emptyList()
            if(!covered(h.map{it.ts},lo)||!covered(g.map{it.ts},lo)||a.isEmpty()||
                a.count{it.intensity>WorkoutDetector.motionThreshold}.toDouble()/a.size>=DaytimeStress.activityMaskFraction)continue
            val q=NightlyHRVQuality.analyze(lo,hi,r);val rmssd=q.weightedRMSSD
            if(rmssd==null||rmssd<=0||q.coverage<0.8||q.overCounted||q.inputBeats<=0||q.rejectedBeats.toDouble()/q.inputBeats>0.1)continue
            means.add(h.sumOf{it.bpm.toDouble()}/h.size);rmssds.add(rmssd)
        }
        val asleep=stage.filter{it.kind!="awake"}.sumOf{it.end-it.start}
        val cov=if(asleep>0)means.size*300.0/asleep else 0.0
        if(means.size<12||cov<0.7)return out("insufficient-night-signal",channel,null,null,cov,means.size)
        return out("qualified",channel,means.sum()/means.size,rmssds.sum()/rmssds.size,cov,means.size)
    }
}
