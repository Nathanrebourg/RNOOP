import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class RRReplayIdentityTests:XCTestCase {
    func row(_ ts:Int,_ rr:Int=1000,_ seq:Int=0,_ ord:Int?=nil)->RRInterval { .init(ts:ts,rrMs:rr,srcChannel:RRSourceChannel(rawValue:5),ord:ord,seq:seq) }
    func testEqualRealBeatsSurviveWhileIdenticalSnapshotRowsCollapse() {
        let a=row(100,1000,0,0),b=row(100,1000,1,1)
        let x=RRReplayIdentity.normalize([b,a,a,b],declared:true)
        XCTAssertEqual(x.rows,[a,b]);XCTAssertEqual(x.duplicates,2);XCTAssertEqual(x.status,"normalized")
    }
    func testUndeclaredIdentityPreservesLegacyDataAndOrdering() {
        let a=[row(101),row(100),row(100)]
        let x=RRReplayIdentity.normalize(a,declared:false)
        XCTAssertEqual(x.rows,a);XCTAssertEqual(x.duplicates,0);XCTAssertEqual(x.status,"identity-undeclared")
    }
    func testSameStorageKeyWithConflictingMetadataCannotBeGuessed() {
        let x=RRReplayIdentity.normalize([row(100,1000,0,0),row(100,1000,0,1)],declared:true)
        XCTAssertNil(x.rows);XCTAssertEqual(x.status,"conflicting-identity")
    }
    func testCanonicalOrderMatchesNullFirstOrdThenValueAndSequence() {
        let a=[row(100,1010,0,2),row(100,1000,1,nil),row(100,1000,0,nil),row(99,980),row(100,990,0,1)]
        XCTAssertEqual(RRReplayIdentity.normalize(a,declared:true).rows,[a[3],a[2],a[1],a[4],a[0]])
    }
    func testInvalidAndMixedTransportMetadataIsRefused() {
        XCTAssertNil(RRReplayIdentity.normalize([row(100,1000,-1)],declared:true).rows)
        let mixed=[row(100),RRInterval(ts:101,rrMs:1000,srcChannel:RRSourceChannel(rawValue:7))]
        XCTAssertNil(RRReplayIdentity.normalize(mixed,declared:true).rows)
    }
    func testReversePinnedCompiledOracleRecords() {
        var lines:[String]=[]
  let a=row(100,1000,0,0),b=row(100,1000,1,1)
  let cases:[([RRInterval],Bool)]=[([b,a,a,b],true),([row(101),row(100),row(100)],false),([a,row(100,1000,0,1)],true),
   ([row(100,1010,0,2),row(100,1000,1,nil),row(100,1000,0,nil),row(99,980),row(100,990,0,1)],true),
   ([row(100,1000,-1)],true),([row(100),RRInterval(ts:101,rrMs:1000,srcChannel:RRSourceChannel(rawValue:7))],true),([],true),([RRInterval(ts:100,rrMs:1000)],true)]
  for (rows,declared) in cases {
   let x=RRReplayIdentity.normalize(rows,declared:declared)
   let line=x.rows.map{$0.map{"\($0.ts):\($0.rrMs):\($0.seq):\($0.ord.map(String.init) ?? "N")"}.joined(separator:",")} ?? "nil"
   lines.append("\(x.status)|\(x.duplicates)|\(line)")
  }
        XCTAssertEqual(lines.joined(separator:"\n"),"""
normalized|2|100:1000:0:0,100:1000:1:1
identity-undeclared|0|101:1000:0:N,100:1000:0:N,100:1000:0:N
conflicting-identity|0|nil
normalized|0|99:980:0:N,100:1000:0:N,100:1000:1:N,100:990:0:1,100:1010:0:2
invalid-identity|0|nil
invalid-identity|0|nil
normalized|0|
invalid-identity|0|nil
""")
    }

}
