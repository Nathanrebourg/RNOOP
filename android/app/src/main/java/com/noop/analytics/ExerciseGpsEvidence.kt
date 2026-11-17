package com.noop.analytics

import kotlin.math.*

/** Descriptive GPS/HR measurements; generic workouts never produce oxygen uptake. */
object ExerciseGpsEvidence {
    data class Fix(var lat: Double, var lon: Double, var time: Double?, var accuracyM: Double?)
    data class HeartRate(var time: Double, var bpm: Double, var owner: String)
    data class Input(var start: Double, var end: Double, var sport: String, var owner: String?, var storedDistanceM: Double?, var fixes: List<Fix>, var heartRates: List<HeartRate>)
    data class Result(var distanceM: Double? = null, var speedMps: Double? = null, var meanHr: Double? = null, var hrCoveredS: Double = 0.0, var metersPerBeat: Double? = null, var reasons: List<String> = emptyList()) { val vo2max: Double? get() = null }
    data class KlineEstimate(val litersPerMinute: Double, val mlKgMin: Double)
    fun evaluate(input: Input): Result {
        val r = Result()
        val reasons = mutableListOf<String>()
        fun finish(): Result { r.reasons = reasons + listOf("slope-unknown", "protocol-unverified"); return r }
        val span = input.end-input.start
        if (!input.start.isFinite() || !input.end.isFinite() || input.start < 0 || span < 600 || span > 21600) { reasons += "window-invalid"; return finish() }
        if (input.sport !in listOf("running","walking")) reasons += "sport-unsupported"
        if (input.fixes.size !in 2..100000) { reasons += "gps-missing"; return finish() }
        if (!input.fixes.all { it.lat.isFinite() && it.lon.isFinite() && abs(it.lat)<=90 && abs(it.lon)<=180 }) { reasons += "gps-invalid"; return finish() }
        var distance=0.0; var gpsTime=0.0; var stopped=0.0
        var timing=true; var accuracy=true; var gpsGap=false; var gpsSpeed=false
        for (fix in input.fixes) {
            val t=fix.time; val a=fix.accuracyM
            if (t==null || !t.isFinite() || t<input.start || t>input.end) timing=false
            if (a==null || !a.isFinite() || a<0 || a>20) accuracy=false
        }
        for (i in 1 until input.fixes.size) {
            val a=input.fixes[i-1]; val b=input.fixes[i]
            val dl=(b.lat-a.lat)*Math.PI/180; val dn=(b.lon-a.lon)*Math.PI/180
            val h=sin(dl/2)*sin(dl/2)+cos(a.lat*Math.PI/180)*cos(b.lat*Math.PI/180)*sin(dn/2)*sin(dn/2)
            val d=6371000*2*atan2(sqrt(max(0.0,min(1.0,h))),sqrt(max(0.0,1-h)))
            distance+=d
            val t0=a.time; val t1=b.time
            if (t0!=null && t1!=null && t0.isFinite() && t1.isFinite()) {
                val dt=t1-t0
                if (dt<=0) timing=false
                else { gpsTime+=dt; if(dt>15) gpsGap=true; if(d/dt>8) gpsSpeed=true; if(d/dt<0.5) stopped+=dt }
            }
        }
        r.distanceM=distance; r.speedMps=distance/span
        if(distance<1000) reasons+="distance-short"
        if(!timing) reasons+="gps-timing-missing"
        if(!accuracy) reasons+=if(input.fixes.any{it.accuracyM==null}) "gps-accuracy-missing" else "gps-accuracy"
        if(gpsGap) reasons+="gps-gap"
        if(gpsSpeed) reasons+="gps-speed"
        if(!timing || gpsTime/span<0.9) reasons+="gps-coverage"
        if(gpsTime>0 && stopped/gpsTime>0.1) reasons+="stops"
        val stored=input.storedDistanceM
        if(stored!=null && (!stored.isFinite() || stored<0 || abs(stored-distance)>max(50.0,distance*0.1))) reasons+="distance-mismatch"
        val owner=input.owner?:""
        if(owner.isEmpty()) reasons+="hr-owner-unknown"
        val hr=input.heartRates
        if(owner.isNotEmpty() && hr.any{it.owner!=owner}) reasons+="hr-owner-mismatch"
        var valid=hr.size in 2..100000; var weighted=0.0; var covered=0.0; var hrGap=false
        for(i in hr.indices) {
            val p=hr[i]
            if(!p.time.isFinite() || !p.bpm.isFinite() || p.time<input.start || p.time>input.end || p.bpm<40 || p.bpm>220) valid=false
            if(i>0) {
                val previous=hr[i-1]; val dt=p.time-previous.time
                if(dt<=0 || !dt.isFinite()) valid=false
                else if(dt>10) hrGap=true
                else { covered+=dt; weighted+=previous.bpm*dt }
            }
        }
        if(!valid) reasons+="hr-invalid"
        if(hrGap) reasons+="hr-gap"
        if(covered<600 || covered/span<0.9) reasons+="hr-coverage"
        if(valid && owner.isNotEmpty() && "hr-owner-mismatch" !in reasons && covered>0) { r.hrCoveredS=covered; r.meanHr=weighted/covered }
        if(reasons.isEmpty() && r.meanHr!=null) r.metersPerBeat=distance/span*60/r.meanHr!!
        return finish()
    }
    /** Kline 1987 PMID3600239 absolute equation, pounds/minutes/bpm -> L/min. */
    fun kline(age: Double, weightKg: Double, sex: Int, seconds: Double, repeatSeconds: Double, fourthQuarterHr: Double, confirmed: Boolean): KlineEstimate? {
        if(!confirmed || !age.isFinite() || age !in 30.0..69.0 || !weightKg.isFinite() || weightKg !in 30.0..250.0 || sex !in 0..1 || !seconds.isFinite() || !repeatSeconds.isFinite() || seconds !in 600.0..1800.0 || repeatSeconds<seconds || repeatSeconds-seconds>30 || !fourthQuarterHr.isFinite() || fourthQuarterHr !in 40.0..220.0) return null
        val liters=6.9652+0.0091*(weightKg/0.45359237)-0.0257*age+0.5955*sex-0.2240*(seconds/60)-0.0115*fourthQuarterHr
        if(liters<=0) return null
        return KlineEstimate(liters,liters*1000/weightKg)
    }
}
