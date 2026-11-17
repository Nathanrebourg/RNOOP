import Foundation
import GRDB

/// An observed calculation, retained independently of the current score pointer.
public struct ScoreCalculationEvidence: Equatable, Codable, Sendable {
    public let day: String
    public let key: String
    public let sourceId: String
    public let methodId: String
    public let fingerprint: String
    public let payload: String
    public let value: Double
    public let capturedAt: Int

    public init(day: String, key: String, sourceId: String, methodId: String, fingerprint: String,
                payload: String, value: Double, capturedAt: Int) {
        self.day = day; self.key = key; self.sourceId = sourceId; self.methodId = methodId
        self.fingerprint = fingerprint; self.payload = payload; self.value = value; self.capturedAt = capturedAt
    }
}

public enum ScoreCalculationEvidenceError: Error {
    case invalidEvidence
    case fingerprintCollision
}

extension WhoopStore {
    public func scoreCalculationHistory(deviceId: String, day: String, key: String,
                                        limit: Int = 8) async throws -> [ScoreCalculationEvidence] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM scoreCalculationEvidence WHERE deviceId = ? AND day = ? AND key = ?
                ORDER BY capturedAt DESC, fingerprint DESC LIMIT ?
                """, arguments: [deviceId, day, key, min(8, max(0, limit))]).map(Self.calculationEvidence)
        }
    }

    public func scoreCalculationCurrent(deviceId: String, day: String,
                                        key: String) async throws -> ScoreCalculationEvidence? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT e.* FROM scoreCalculationEvidence e JOIN scoreCalculationHead h
                ON e.deviceId = h.deviceId AND e.day = h.day AND e.key = h.key AND e.fingerprint = h.fingerprint
                WHERE h.deviceId = ? AND h.day = ? AND h.key = ?
                """, arguments: [deviceId, day, key]).map(Self.calculationEvidence)
        }
    }

    private static func calculationEvidence(_ row: Row) -> ScoreCalculationEvidence {
        .init(day: row["day"], key: row["key"], sourceId: row["sourceId"], methodId: row["methodId"],
              fingerprint: row["fingerprint"], payload: row["payload"], value: row["value"], capturedAt: row["capturedAt"])
    }

    private static func isCalculationDay(_ day: String) -> Bool {
        let bytes = Array(day.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(day.prefix(4)), year > 0,
              let month = Int(day.dropFirst(5).prefix(2)), let date = Int(day.suffix(2)),
              (1...12).contains(month), date > 0 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return date <= [31, leap ? 29 : 28, 31,30,31,30,31,31,30,31,30,31][month - 1]
    }

    static func persistCalculationEvidence(_ rows: [ScoreCalculationEvidence], deviceId: String, from: String, to: String,
        dailyMetrics: [DailyMetric], metricPoints: [MetricPoint], provenance: [ScoreInputProvenanceRow], in db: Database) throws {
        try db.execute(sql: "DELETE FROM scoreCalculationHead WHERE deviceId = ? AND day >= ? AND day <= ?",
                       arguments: [deviceId, from, to])
        for row in rows {
            let suppliedValue: Double?
            switch row.key {
            case "recovery": suppliedValue = dailyMetrics.last(where: { $0.day == row.day })?.recovery
            case "strain": suppliedValue = dailyMetrics.last(where: { $0.day == row.day })?.strain
            case "sleep_performance": suppliedValue = metricPoints.last(where: { $0.day == row.day && $0.key == row.key })?.value
            default: throw ScoreCalculationEvidenceError.invalidEvidence
            }
            guard isCalculationDay(row.day), row.day >= from, row.day <= to,
                  dailyMetrics.contains(where: { $0.day == row.day }),
                  row.value.isFinite, (0...100).contains(row.value), suppliedValue == row.value,
                  (1...Int(clamping: 4_102_444_800 as Int64)).contains(row.capturedAt), row.payload.utf8.count <= 16_384,
                  !row.payload.isEmpty, !row.sourceId.isEmpty, !row.methodId.isEmpty, !row.fingerprint.isEmpty,
                  provenance.last(where: { $0.day == row.day && $0.key == row.key })?.sourceId == row.sourceId,
                  try String.fetchOne(db, sql: "SELECT sourceId FROM scoreInputProvenance WHERE deviceId = ? AND day = ? AND key = ?",
                                      arguments: [deviceId, row.day, row.key]) == row.sourceId else {
                throw ScoreCalculationEvidenceError.invalidEvidence
            }
            let scoreSQL = row.key == "sleep_performance"
                ? "SELECT value FROM metricSeries WHERE deviceId = ? AND day = ? AND key = 'sleep_performance'"
                : "SELECT \(row.key) FROM dailyMetric WHERE deviceId = ? AND day = ?"
            guard try Double.fetchOne(db, sql: scoreSQL, arguments: [deviceId, row.day]) == row.value else {
                throw ScoreCalculationEvidenceError.invalidEvidence
            }
            if let existing = try Row.fetchOne(db, sql: """
                SELECT * FROM scoreCalculationEvidence WHERE deviceId = ? AND day = ? AND key = ? AND fingerprint = ?
                """, arguments: [deviceId, row.day, row.key, row.fingerprint]) {
                let old = calculationEvidence(existing)
                // Capture time is metadata: identical recomputation preserves its first observed revision.
                guard old.payload == row.payload, old.value == row.value, old.sourceId == row.sourceId,
                      old.methodId == row.methodId else { throw ScoreCalculationEvidenceError.fingerprintCollision }
            } else {
                try db.execute(sql: """
                    INSERT INTO scoreCalculationEvidence(deviceId,day,key,fingerprint,capturedAt,sourceId,methodId,value,payload)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    """, arguments: [deviceId,row.day,row.key,row.fingerprint,row.capturedAt,row.sourceId,row.methodId,row.value,row.payload])
            }
            try db.execute(sql: """
                INSERT INTO scoreCalculationHead(deviceId,day,key,fingerprint) VALUES (?,?,?,?)
                ON CONFLICT(deviceId,day,key) DO UPDATE SET fingerprint = excluded.fingerprint
                """, arguments: [deviceId,row.day,row.key,row.fingerprint])
        }
        // Protect current recipes before audit revisions; equal timestamps still have a total order.
        for cell in Set(rows.map { CalculationCell(day: $0.day, key: $0.key) }) {
            try db.execute(sql: """
                DELETE FROM scoreCalculationEvidence WHERE rowid IN (
                SELECT e.rowid FROM scoreCalculationEvidence e WHERE e.deviceId = ? AND e.day = ? AND e.key = ?
                ORDER BY EXISTS (SELECT 1 FROM scoreCalculationHead h WHERE h.deviceId = e.deviceId
                AND h.day = e.day AND h.key = e.key AND h.fingerprint = e.fingerprint) DESC,
                e.capturedAt DESC,e.fingerprint DESC LIMIT -1 OFFSET 8)
                """, arguments: [deviceId,cell.day,cell.key])
        }
        try db.execute(sql: """
            DELETE FROM scoreCalculationEvidence WHERE rowid IN (
            SELECT e.rowid FROM scoreCalculationEvidence e WHERE e.deviceId = ?
            ORDER BY EXISTS (SELECT 1 FROM scoreCalculationHead h WHERE h.deviceId = e.deviceId
            AND h.day = e.day AND h.key = e.key AND h.fingerprint = e.fingerprint) DESC,
            e.capturedAt DESC,e.day DESC,e.key DESC,e.fingerprint DESC LIMIT -1 OFFSET 12000)
            """, arguments: [deviceId])
        try db.execute(sql: """
            DELETE FROM scoreCalculationHead WHERE deviceId = ? AND NOT EXISTS (
            SELECT 1 FROM scoreCalculationEvidence e WHERE e.deviceId = scoreCalculationHead.deviceId
            AND e.day = scoreCalculationHead.day AND e.key = scoreCalculationHead.key
            AND e.fingerprint = scoreCalculationHead.fingerprint)
            """, arguments: [deviceId])
    }
}

private struct CalculationCell: Hashable { let day: String; let key: String }
