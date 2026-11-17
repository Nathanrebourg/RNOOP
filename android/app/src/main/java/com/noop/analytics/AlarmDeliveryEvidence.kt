package com.noop.analytics

/** Persisted evidence only; a matching readback cannot guarantee a vibration. Times are Unix seconds. */
object AlarmDeliveryEvidence {
    fun status(enabled:Boolean,protocolAllowed:Boolean,plannedEpoch:Long?,currentDevice:String,
               sentEpoch:Long?,reportedEpoch:Long?,sentDevice:String?,reportedDevice:String?,
               sentAt:Double?,reportedAt:Double?,sentConnected:Boolean?,now:Double):String {
        if(!enabled) return "off"
        if(!protocolAllowed) return "experimental-blocked"
        if(!now.isFinite()) return "invalid-timestamps"
        if(plannedEpoch==null || plannedEpoch !in 0..4102444800L || plannedEpoch.toDouble()<=now) return "no-future-plan"
        if(sentEpoch==null || sentAt==null || currentDevice.isEmpty() || sentDevice.isNullOrEmpty()) return "no-send-evidence"
        if(sentDevice!=currentDevice) return "different-source"
        if(sentEpoch !in 0..4102444800L || sentEpoch!=plannedEpoch) return "different-request"
        if(!now.isFinite() || !sentAt.isFinite() || sentAt<=0 || sentAt>now) return "invalid-timestamps"
        if(sentConnected!=true) return "queued-not-sent"
        if(reportedEpoch==null || reportedAt==null || reportedDevice.isNullOrEmpty()) return "readback-unavailable"
        if(reportedDevice!=currentDevice) return "different-source"
        if(!reportedAt.isFinite() || reportedAt<=0 || reportedAt>now || reportedEpoch !in 0..4102444800L) return "invalid-timestamps"
        if(reportedAt<sentAt) return "stale-readback"
        return if(kotlin.math.abs(reportedEpoch-sentEpoch)<=120) "last-readback-matches" else "last-readback-differs"
    }
}
