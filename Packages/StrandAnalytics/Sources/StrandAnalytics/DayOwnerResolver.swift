import Foundation

/// Decides which single device owns a given day's displayed/scored metrics, so scores are never
/// computed from a mix of sources (invariant I2). Pure — the caller supplies candidates (each device
/// that has any data near the day, with a priority) and any locked override from the dayOwnership table.
public enum DayOwnerResolver {
    public struct Candidate: Equatable {
        public let deviceId: String
        public let priority: Int     // 0 = active strap, 1 = other live straps, 2 = imports (lower wins)
        public let hasData: Bool
        public init(deviceId: String, priority: Int, hasData: Bool) {
            self.deviceId = deviceId; self.priority = priority; self.hasData = hasData
        }
    }
    /// Returns the owning deviceId, or nil if no candidate has data for the day.
    public static func resolve(day: String, lockedOwner: String?, candidates: [Candidate]) -> String? {
        if let locked = lockedOwner { return locked }
        return candidates.filter { $0.hasData }.sorted { $0.priority < $1.priority }.first?.deviceId
    }

    /// NROOP: among several LIVE straps that are all WHOOPs (the active row plus other WHOOP rows), the one
    /// holding the MOST HR rows in the read window owns the day. Still exactly one owner (invariant I2, no
    /// merge). The first-with-any-data probe let a WHOOP row holding a few stray rows in the window's
    /// 30 h lookback (the active registry row, while the connected strap is attributed to another WHOOP
    /// row by #1881) own a day whose samples all live under the other row, so that day read hr=0.
    /// `counts` is in priority order; ties keep the earlier (higher-priority) one. nil when none has rows.
    public static func mostCovered(_ counts: [(deviceId: String, hrRows: Int)]) -> String? {
        var best: (deviceId: String, hrRows: Int)? = nil
        for c in counts where c.hrRows > 0 {
            if best == nil || c.hrRows > best!.hrRows { best = c }
        }
        return best?.deviceId
    }
}
