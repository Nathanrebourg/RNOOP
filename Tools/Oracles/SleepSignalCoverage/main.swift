import WhoopProtocol
let h: [HRSample] = [.init(ts: 31, bpm: 60)]
let g: [GravitySample] = [.init(ts:65,x:0,y:0,z:1)]
let cases: [(Int,Int,[HRSample],[GravitySample])] = [
 (7,101,h,g),(7,101,h+h,(g+g).reversed()),(0,60,[],[]),
 (0,30,[.init(ts:0,bpm:300),.init(ts:1,bpm:301)], [.init(ts:1,x:0,y:0,z:1)]),
 (7,30,[.init(ts:6,bpm:60)],[.init(ts:30,x:0,y:0,z:1)]),
 (0,30,[.init(ts:0,bpm:0)],[.init(ts:0,x:.nan,y:0,z:1),.init(ts:1,x:0,y:0,z:0)]),
 (0,172800,[],[]),(-1,10,[],[]),(0,172801,[],[]),(4102444770,4102444800,[],[]),
 (Int.max-1,Int.max,[],[])]
for (s,e,h,g) in cases { print(SleepSignalCoverage.analyze(start:s,end:e,hr:h,gravity:g).trace) }
