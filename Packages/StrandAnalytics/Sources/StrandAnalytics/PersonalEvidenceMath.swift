import Foundation

enum PersonalEvidenceMath {
    static func median(_ x:[Double])->Double? {let s=x.sorted();guard !s.isEmpty else{return nil};return s.count%2==0 ? (s[s.count/2-1]+s[s.count/2])/2:s[s.count/2]}
    static func ascii(_ s:String)->Bool {!s.isEmpty && s.utf8.count<=200 && s.utf8.allSatisfy{(32...126).contains($0)}}
}
