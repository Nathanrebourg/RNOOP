import Foundation
import XCTest
import StrandAnalytics
final class PersonalEvidenceOracleTests:XCTestCase {
func testActualCompiledSwiftLiteralReversePin() {
func transcript()->String {
 func n(_ x:Double?)->String {x.map{String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),$0)} ?? "nil"}
 var lines:[String]=[]
 func journal(_ delta:Double)->[MatchedJournalComparison.Row] {(0..<8).flatMap{i in [MatchedJournalComparison.Row(day:10000+i*7,context:"same",answer:true,outcome:60+delta),.init(day:10001+i*7,context:"same",answer:false,outcome:60)]}}
 for index in 0..<5 {
  var x=journal(index==1 ? 0:10)
  if index==2 {x.removeFirst(4)}
  if index==3 {x[1] = .init(day:x[1].day,context:"other",answer:false,outcome:60)}
  if index==4 {x.append(.init(day:x[1].day,context:"same",answer:true,outcome:60))}
  let rows=MatchedJournalComparison.analyze([.init(id:"a",rows:x),.init(id:"b",rows:journal(0))])
  let a=rows[0];lines.append("journal|\(a.pairs)|\(a.nonzero)|\(n(a.medianDelta))|\(n(a.p))|\(n(a.adjustedP))|\(a.association ? 1:0)")
 }
 for index in 0..<5 {
  var rows=(1...35).map{BaselineShiftEvidence.Sample(age:$0,value:$0<=7 ? (index==1 ? 60:70):60,era:"one")}
  if index==2 {rows=Array(rows.dropFirst(4))}
  if index==3 {rows[0] = .init(age:1,value:70,era:"two")}
  if index==4 {rows.append(.init(age:1,value:80,era:"one"))}
  let a=BaselineShiftEvidence.analyze(rows,floor:3,bounds:20...250)
  lines.append("shift|\(a.status)|\(a.recentCount)|\(a.priorCount)|\(n(a.recentMedian))|\(n(a.priorMedian))|\(n(a.scaledDelta))|\(a.shift ? 1:0)")
 }
 for index in 0..<5 {
  var rows=(0...180).map{TrainingResponseForecast.Day(day:$0,recovery:$0>0 && ($0-1)%3==0 ? 40:80,effort:$0%3==0 ? 100:0,era:"one")}
  if index==2 {rows.removeLast()}
  if index==3 {rows[180] = .init(day:180,recovery:80,effort:100,era:"two")}
  if index==4 {rows.append(.init(day:181,recovery:100,effort:100,era:"one"));rows.reverse()}
  let a=TrainingResponseForecast.analyze(rows,origin:180,horizon:index==1 ? 2:1)
  lines.append("forecast|\(a.status)|\(n(a.prediction))|\(a.training)|\(a.evaluated)|\(n(a.modelMAE))|\(n(a.baselineMAE))")
 }
 for index in 0..<5 {
  var rows=(0..<20).map{ReferenceValidation.Observation(id:"r\($0)",order:$0,method:"m",kind:"steps",estimate:$0<10 ? 110:105,reference:100,usedForCalibration:false)}
  if index==1 {rows.append(rows[0])}
  if index==2 {rows.append(.init(id:"r0",order:0,method:"m",kind:"steps",estimate:111,reference:100,usedForCalibration:false))}
  if index==3 {rows=rows.map{.init(id:$0.id,order:$0.order,method:$0.method,kind:$0.kind,estimate:$0.estimate,reference:$0.reference,usedForCalibration:true)}}
  if index==4 {rows=rows.map{.init(id:$0.id,order:$0.order,method:"other",kind:$0.kind,estimate:$0.estimate,reference:$0.reference,usedForCalibration:false)}}
  let a=ReferenceValidation.analyze(rows,method:"m",kind:"steps")
  lines.append("validation|\(a.count)|\(a.excluded)|\(n(a.mae))|\(n(a.bias))|\(n(a.recentMAE))|\(n(a.priorMAE))")
 }
 let j=(0..<8).flatMap{i in [MatchedJournalComparison.Row(day:10000+i*7,context:"x",answer:true,outcome:0),.init(day:10001+i*7,context:"x",answer:false,outcome:0)]}+[.init(day:10000,context:"x",answer:true,outcome:-0.0)]
 let a=MatchedJournalComparison.analyze([.init(id:"x",rows:j)])[0]
 let b=BaselineShiftEvidence.analyze((1...35).map{.init(age:$0,value:0,era:"x")}+[.init(age:1,value:-0.0,era:"x")],floor:5,bounds:0...1000)
 let c=TrainingResponseForecast.analyze((0...180).map{.init(day:$0,recovery:80,effort:0,era:"x")}+[.init(day:180,recovery:80,effort:-0.0,era:"x")],origin:180,horizon:1)
 let d=ReferenceValidation.analyze([.init(id:"x",order:1,method:"m",kind:"steps",estimate:0,reference:100,usedForCalibration:false),.init(id:"x",order:1,method:"m",kind:"steps",estimate:-0.0,reference:100,usedForCalibration:false)],method:"m",kind:"steps")
 lines.append("signed-zero|\(a.pairs)|\(b.recentCount)|\(c.status)|\(d.count)")
 let e=BaselineShiftEvidence.analyze((1...35).map{.init(age:$0,value:Double.greatestFiniteMagnitude,era:"x")},floor:Double.leastNormalMagnitude,bounds:0...Double.greatestFiniteMagnitude)
 lines.append("extreme|\(e.status)|\(n(e.scaledDelta))")
 return lines.joined(separator:"\n")
}

XCTAssertEqual(transcript(),"""
journal|8|8|10.000000|0.007812|0.015625|1
journal|8|0|0.000000|nil|nil|0
journal|6|6|10.000000|nil|nil|0
journal|7|7|10.000000|nil|nil|0
journal|7|7|10.000000|nil|nil|0
shift|compared|7|28|70.000000|60.000000|3.333333|1
shift|compared|7|28|60.000000|60.000000|0.000000|0
shift|insufficient-days|3|28|70.000000|60.000000|nil|0
shift|context-changed|7|28|70.000000|60.000000|nil|0
shift|compared|6|28|70.000000|60.000000|3.333333|1
forecast|qualified-experimental|40.000000|30|30|0.000000|40.000000
forecast|no-improvement|nil|30|30|0.000000|0.000000
forecast|origin-unavailable|nil|0|0|nil|nil
forecast|insufficient-training|nil|0|0|nil|nil
forecast|qualified-experimental|40.000000|30|30|0.000000|40.000000
validation|20|0|7.500000|7.500000|5.000000|10.000000
validation|20|1|7.500000|7.500000|5.000000|10.000000
validation|19|2|7.368421|7.368421|5.000000|nil
validation|0|20|nil|nil|nil|nil
validation|0|20|nil|nil|nil|nil
signed-zero|8|7|no-improvement|1
extreme|invalid-input|nil
""")
}
}
