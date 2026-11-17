import Foundation
import StrandAnalytics

/// Bounded Apple-local UI observations, excluded from shared backup/wire formats.
enum PersonalReferenceStore {
    struct Record:Codable,Equatable,Identifiable {
        var id:String,owner:String,start:Int,end:Int,kind:String,estimate:Double,reference:Double,method:String,created:Int
        var rawTicks:Int? = nil
        var scale:Double? = nil
        var observation:ReferenceValidation.Observation {.init(id:id,order:created,method:method,kind:kind,estimate:estimate,reference:reference,usedForCalibration:false)}
    }
    static let key="personalEvidence.references.local.v1"
    static func load(defaults:UserDefaults = .standard)throws->[Record] {
        guard let data=defaults.data(forKey:key) else{return []}
        guard data.count<=131072 else{throw failure()}
        let rows=try JSONDecoder().decode([Record].self,from:data);try validate(rows);return rows
    }
    static func failure()->NSError {NSError(domain:"PersonalReference",code:1,userInfo:[NSLocalizedDescriptionKey:String(localized:"Reference records are invalid or duplicated. Review or clear the local records.")])}
    static func validate(_ rows:[Record])throws {
        guard rows.count<=256,Set(rows.map(\.id)).count==rows.count else{throw failure()}
        var windows=Set<String>()
        for row in rows {
            guard !row.id.isEmpty,row.id.count<=128,!row.owner.isEmpty,row.owner.count<=200,
                  row.start>0,row.end>row.start,row.end<=4_102_444_800,row.end-row.start<=57600,
                  row.created>=row.end,row.created<=4_102_444_800,row.method.utf8.count<=200,
                  row.method.utf8.allSatisfy({(32...126).contains($0)}),
                  windows.insert("\(row.owner)|\(row.start)|\(row.end)|\(row.kind)").inserted,
                  ReferenceValidation.analyze([row.observation],method:row.method,kind:row.kind).count==1 else{throw failure()}
            if row.kind=="steps" {
                guard let ticks=row.rawTicks,(1...300000).contains(ticks),let scale=row.scale,scale.isFinite,(0.5...30).contains(scale),
                      row.method==stepMethod(scale),(100...10000).contains(row.reference),
                      row.end-row.start>=60,row.end-row.start<=3600,abs(row.estimate-(Double(ticks)/scale).rounded())<1e-9 else{throw failure()}
            }
        }
    }
    static func save(_ rows:[Record],defaults:UserDefaults = .standard)throws {
        try validate(rows);let data=try JSONEncoder().encode(rows);guard data.count<=131072 else{throw failure()};defaults.set(data,forKey:key)
    }
    static func add(_ rows:[Record],defaults:UserDefaults = .standard)throws {try save(load(defaults:defaults)+rows,defaults:defaults)}
    static func clear(defaults:UserDefaults = .standard) {defaults.removeObject(forKey:key)}
    static func stepMethod(_ scale:Double)->String {"steps-v1-scale-"+String(scale.bitPattern,radix:16)}
}
