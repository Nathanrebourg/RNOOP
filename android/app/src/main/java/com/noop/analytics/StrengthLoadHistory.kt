package com.noop.analytics

/** Logged perceived load, not muscular strain or cardiovascular Effort. */
object StrengthLoadHistory {
    data class Session(val id:String,val dayAge:Int,val durationSec:Int,val rpe:Double?)
    data class Window(val ratedSessions:Int,val unratedSessions:Int,val loadAU:Double?)
    data class Result(val recent7:Window,val context28:Window,val conflictingSessions:Int)
    fun summarize(rows:List<Session>):Result {
        val groups=rows.filter { it.id.isNotEmpty() && it.dayAge in 0..27 && it.durationSec in 1..86400 }
            .map { it.copy(rpe=it.rpe?.takeIf { r -> r.isFinite() && r>0 && r<=10 }) }.groupBy { it.id }
        val valid=mutableListOf<Session>();var conflicts=0
        for (key in groups.keys.sorted()) {
            val group=groups.getValue(key);val first=group.first()
            if (group.all { it==first }) valid.add(first) else conflicts++
        }
        fun window(days:Int):Window {
            val selected=valid.filter { it.dayAge<days };val rated=selected.filter { it.rpe!=null }
            return Window(rated.size,selected.size-rated.size,if(rated.isEmpty()) null else rated.sumOf { it.rpe!!*(it.durationSec/60.0) })
        }
        return Result(window(7),window(28),conflicts)
    }
}
