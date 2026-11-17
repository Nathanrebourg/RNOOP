import Foundation
import WhoopProtocol

/// Explicit stored-snapshot normalization; not a raw-wire beat detector or physiological cleaner.
public enum RRReplayIdentity {
    public struct Result {
        public let rows: [RRInterval]?
        public let duplicates: Int
        public let status: String
    }
    private struct Key: Hashable { let ts: Int, rr: Int, seq: Int }
    public static func normalize(_ rows: [RRInterval], declared: Bool) -> Result {
        guard declared else { return .init(rows:rows,duplicates:0,status:"identity-undeclared") }
        guard rows.allSatisfy({ $0.ts >= 0 && (0...65_535).contains($0.rrMs) && (0..<1_000_000).contains($0.seq)
            && ($0.ord == nil || (0..<1_000_000).contains($0.ord!)) && [5,7].contains($0.srcChannel?.rawValue ?? -1) }),
            Set(rows.compactMap { $0.srcChannel?.rawValue }).count <= 1 else {
            return .init(rows:nil,duplicates:0,status:"invalid-identity")
        }
        var unique:[Key:RRInterval]=[:], duplicates=0
        for r in rows {
            let k=Key(ts:r.ts,rr:r.rrMs,seq:r.seq)
            if let previous=unique[k] {
                guard previous.ord == r.ord, previous.srcChannel == r.srcChannel else {
                    return .init(rows:nil,duplicates:duplicates,status:"conflicting-identity")
                }
                duplicates += 1
            } else { unique[k]=r }
        }
        let sorted=unique.values.sorted { a,b in
            if a.ts != b.ts { return a.ts < b.ts }
            if a.ord != b.ord { return (a.ord ?? -1) < (b.ord ?? -1) }
            if a.rrMs != b.rrMs { return a.rrMs < b.rrMs }
            return a.seq < b.seq
        }
        return .init(rows:sorted,duplicates:duplicates,status:"normalized")
    }
}
