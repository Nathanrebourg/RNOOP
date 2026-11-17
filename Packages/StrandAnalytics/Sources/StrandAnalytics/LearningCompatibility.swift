import Foundation

/// Semantic learning context. Marketing/build versions are deliberately not inputs.
public enum LearningCompatibility {
    public static let version="learning.recipe-context.v1"
    public static func manifest(source:String,zone:String,recoveryMethod:String,effortMethod:String,settings:[String:String])->String? {
        func ascii(_ s:String,_ limit:Int)->Bool {!s.isEmpty && s.utf8.count<=limit && s.utf8.allSatisfy{(33...126).contains($0)}}
        guard !source.isEmpty,source.utf8.count<=512,!zone.isEmpty,zone.utf8.count<=128,
              ascii(recoveryMethod,80),ascii(effortMethod,80),!settings.isEmpty,settings.count<=64,
              settings["pipeline"] != nil,settings.keys.allSatisfy({ascii($0,64) && $0.utf8.allSatisfy{(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}}),
              settings.values.allSatisfy({!$0.isEmpty && $0.utf8.count<=512}),
              !settings.keys.contains(where:{["appVersion","build","theme"].contains($0)}) else{return nil}
        func hex(_ s:String)->String {s.utf8.map{String(format:"%02x",$0)}.joined()}
        var lines=[version,"owner:"+hex(source),"zone:"+hex(zone),"recovery:"+hex(recoveryMethod),"effort:"+hex(effortMethod)]
        lines+=settings.keys.sorted().map{"ctx."+$0+":"+hex(settings[$0]!)}
        return lines.joined(separator:"\n")+"\n"
    }
}
