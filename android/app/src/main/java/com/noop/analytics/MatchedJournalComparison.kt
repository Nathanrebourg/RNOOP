package com.noop.analytics
import kotlin.math.*
/** Exploratory weekly paired sign test; does not establish causal independence. */
object MatchedJournalComparison {
 data class Row(val day:Int,val context:String,val answer:Boolean?,val outcome:Double?)
 data class Experiment(val id:String,val rows:List<Row>)
 data class Result(val id:String,val pairs:Int,val nonzero:Int,val medianDelta:Double?,val p:Double?,val adjustedP:Double?,val association:Boolean)
 fun analyze(experiments:List<Experiment>):List<Result> {
  if(experiments.size>50 || experiments.map{it.id}.toSet().size!=experiments.size || experiments.any{!PersonalEvidenceMath.ascii(it.id)||it.rows.size>400})return emptyList()
  val raw=experiments.sortedBy{it.id}.map { e ->
   val rows=e.rows.groupBy{it.day}.values.mapNotNull {g->val a=g.first();if(g.any{it.day!=a.day||it.context!=a.context||it.answer!=a.answer||!PersonalEvidenceMath.same(it.outcome,a.outcome)}||a.day !in 0..1000000||!PersonalEvidenceMath.ascii(a.context)||a.answer==null||a.outcome==null||!a.outcome.isFinite()||a.outcome !in 0.0..100.0)null else a}
   val deltas=mutableListOf<Double>()
   for(block in rows.groupBy{(it.day+3)/7}.keys.sorted()) {
    val items=rows.filter{(it.day+3)/7==block}.sortedBy{it.day};var gapBest:Int?=null;var keyBest=0;var deltaBest=0.0
    for(yes in items.filter{it.answer==true}) for(no in items.filter{it.answer==false && it.context==yes.context}) {
     val gap=abs(yes.day-no.day);val key=min(yes.day,no.day)
     if(gapBest==null||gap<gapBest||gap==gapBest&&key<keyBest){gapBest=gap;keyBest=key;deltaBest=yes.outcome!!-no.outcome!!}
    }
    if(gapBest!=null)deltas.add(deltaBest)
   }
   val nz=deltas.filter{it!=0.0};val n=nz.size;val k=min(nz.count{it>0},nz.count{it<0});var p:Double?=null
   if(n>=8&&n<=60){var term=0.5.pow(n);var sum=term;for(i in 1..k){term*=(n-i+1).toDouble()/i;sum+=term};p=min(1.0,2*sum)}
   Result(e.id,deltas.size,n,PersonalEvidenceMath.median(deltas),p,null,false)
  }
  val indices=raw.indices.sortedWith(compareBy<Int>{raw[it].p?:1.0}.thenBy{raw[it].id});var previous=0.0;val adjusted=mutableMapOf<Int,Double>()
  for((rank,index)in indices.withIndex()){previous=max(previous,min(1.0,(raw[index].p?:1.0)*(raw.size-rank)));if(raw[index].p!=null)adjusted[index]=previous}
  return raw.mapIndexed{i,a->a.copy(adjustedP=adjusted[i],association=adjusted[i]?.let{it<0.05}?:false)}
 }
}
