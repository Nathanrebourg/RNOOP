import Foundation

/// Names only persisted delivery/readback evidence. A match is not proof of a future vibration.
/// Unlike AlarmReadback's historical debug verdict, this UI requires timestamps for both halves.
public enum AlarmDeliveryEvidence {
    public static func status(enabled: Bool, protocolAllowed: Bool, plannedEpoch: Int?, currentDevice: String,
                              sentEpoch: Int?, reportedEpoch: Int?, sentDevice: String?, reportedDevice: String?,
                              sentAt: Double?, reportedAt: Double?, sentConnected: Bool?, now: Double) -> String {
        if !enabled { return "off" }
        if !protocolAllowed { return "experimental-blocked" }
        guard now.isFinite else { return "invalid-timestamps" }
        guard let plannedEpoch, (0...Int(clamping: 4_102_444_800 as Int64)).contains(plannedEpoch), Double(plannedEpoch)>now else { return "no-future-plan" }
        guard let sentEpoch, let sentAt, !currentDevice.isEmpty, let sentDevice, !sentDevice.isEmpty else { return "no-send-evidence" }
        guard sentDevice == currentDevice else { return "different-source" }
        guard (0...Int(clamping: 4_102_444_800 as Int64)).contains(sentEpoch), sentEpoch == plannedEpoch else { return "different-request" }
        guard now.isFinite, sentAt.isFinite, sentAt>0, sentAt<=now else { return "invalid-timestamps" }
        guard sentConnected == true else { return "queued-not-sent" }
        guard let reportedEpoch, let reportedAt, let reportedDevice, !reportedDevice.isEmpty else { return "readback-unavailable" }
        guard reportedDevice == currentDevice else { return "different-source" }
        guard reportedAt.isFinite, reportedAt>0, reportedAt<=now, (0...Int(clamping: 4_102_444_800 as Int64)).contains(reportedEpoch) else { return "invalid-timestamps" }
        guard reportedAt>=sentAt else { return "stale-readback" }
        return abs(reportedEpoch-sentEpoch)<=120 ? "last-readback-matches" : "last-readback-differs"
    }
}
