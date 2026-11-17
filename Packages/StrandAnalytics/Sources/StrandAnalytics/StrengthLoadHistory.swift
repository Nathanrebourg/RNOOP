import Foundation

/// Descriptive Foster sRPE × minutes for logged lifting sessions; never cardiovascular Effort,
/// sensor-measured muscular strain, an injury predictor or an acute:chronic ratio.
public enum StrengthLoadHistory {
    public struct Session: Equatable, Sendable {
        public let id: String, dayAge: Int, durationSec: Int
        public let rpe: Double?
        public init(id: String, dayAge: Int, durationSec: Int, rpe: Double?) {
            self.id=id; self.dayAge=dayAge; self.durationSec=durationSec; self.rpe=rpe
        }
    }
    public struct Window: Equatable, Sendable {
        public let ratedSessions: Int, unratedSessions: Int
        public let loadAU: Double?
    }
    public struct Result: Equatable, Sendable {
        public let recent7: Window, context28: Window
        public let conflictingSessions: Int
    }
    public static func summarize(_ rows: [Session]) -> Result {
        let normalized=rows.filter { !$0.id.isEmpty && (0..<28).contains($0.dayAge) && (1...86400).contains($0.durationSec) }.map { s in
            Session(id:s.id,dayAge:s.dayAge,durationSec:s.durationSec,
                    rpe:s.rpe.flatMap { $0.isFinite && $0 > 0 && $0 <= 10 ? $0 : nil })
        }
        let groups=Dictionary(grouping:normalized,by: \.id)
        var valid: [Session]=[], conflicts=0
        for key in groups.keys.sorted() {
            let group=groups[key]!, first=group[0]
            if group.allSatisfy({ $0 == first }) { valid.append(first) } else { conflicts += 1 }
        }
        func window(_ days: Int)->Window {
            let selected=valid.filter { $0.dayAge < days }, rated=selected.filter { $0.rpe != nil }
            return Window(ratedSessions:rated.count,unratedSessions:selected.count-rated.count,
                          loadAU:rated.isEmpty ? nil : rated.reduce(0) { $0 + $1.rpe! * (Double($1.durationSec)/60) })
        }
        return Result(recent7:window(7),context28:window(28),conflictingSessions:conflicts)
    }
}
