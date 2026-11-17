package com.noop.analytics
import kotlin.math.*
/** Frozen median model, evaluated only against chronologically prior mature outcomes. */
object TrainingResponseForecast {
 data class Day(val day:Int,val recovery:Double?,val effort:Double?,val era:String)
 data class Result(val status:String,val prediction:Double?,val training:Int,val evaluated:Int,val modelMAE:Double?,val baselineMAE:Double?)
 private fun bucket(x:Double)=if(x<33)0 else if(x<66)1 else 2
 fun analyze(input:List<Day>,origin:Int,horizon:Int):Result {
  fun out(s:String,p:Double?=null,n:Int=0,e:Int=0,m:Double?=null,b:Double?=null)=Result(s,p,n,e,m,b)
  if(input.size>400||origin !in 0..1000000||horizon !in 1..3)return out("invalid-input")
  val days=mutableMapOf<Int,Day>()
  for((key,g)in input.filter{it.day>=0&&it.day<=origin}.groupBy{it.day}) {
   val a=g.first();if(g.all{it.day==a.day&&it.era==a.era&&PersonalEvidenceMath.same(it.recovery,a.recovery)&&PersonalEvidenceMath.same(it.effort,a.effort)}&&PersonalEvidenceMath.ascii(a.era)&&(a.recovery?.let{it.isFinite()&&it in 0.0..100.0}?:true)&&(a.effort?.let{it.isFinite()&&it in 0.0..100.0}?:true))days[key]=a
  }
  val target=days[origin]?:return out("origin-unavailable")
  if(target.effort==null||target.recovery==null)return out("origin-unavailable")
  fun matches(d:Day,t:Day)=d.era==t.era&&d.effort!=null&&d.recovery!=null&&t.effort!=null&&t.recovery!=null&&bucket(d.effort)==bucket(t.effort)&&bucket(d.recovery)==bucket(t.recovery)
  fun fit(t:Day):Pair<Double?,Int> {
   val deltas=mutableListOf<Double>();var last=Int.MAX_VALUE
   for(key in days.keys.sortedDescending().filter{it+horizon<t.day&&it>=t.day-180}) {
    val d=days[key]?:continue;val y=days[key+horizon]?:continue
    if(key+horizon>=last||!matches(d,t)||y.era!=t.era||y.recovery==null||d.recovery==null)continue
    deltas.add(y.recovery-d.recovery);last=key;if(deltas.size==30)break
   }
   val delta=PersonalEvidenceMath.median(deltas)
   if(deltas.size<8||delta==null||t.recovery==null)return null to deltas.size
   return max(0.0,min(100.0,t.recovery+delta)) to deltas.size
  }
  val current=fit(target);val forecast=current.first?:return out("insufficient-training",n=current.second)
  val errors=mutableListOf<Double>();val baseline=mutableListOf<Double>();var last=Int.MAX_VALUE
  for(key in days.keys.sortedDescending().filter{it+horizon<=origin&&it>=origin-90}) {
   val d=days[key]?:continue;val y=days[key+horizon]?:continue
   if(key+horizon>=last||!matches(d,target)||y.era!=target.era||y.recovery==null||d.recovery==null)continue
   val prediction=fit(d).first?:continue
   errors.add(abs(prediction-y.recovery));baseline.add(abs(d.recovery-y.recovery));last=key;if(errors.size==30)break
  }
  if(errors.size<8)return out("insufficient-evaluation",n=current.second,e=errors.size)
  val mae=errors.sum()/errors.size;val base=baseline.sum()/baseline.size
  if(base<=0||mae>base*0.9)return out("no-improvement",n=current.second,e=errors.size,m=mae,b=base)
  return out("qualified-experimental",forecast,current.second,errors.size,mae,base)
 }
}
