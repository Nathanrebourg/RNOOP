import XCTest
@testable import StrandAnalytics

final class SiblingStreamMergeTests: XCTestCase {
    private struct S: Equatable { let ts: Int; let v: Int }

    func testSiblingFillsOnlyMinutesTheOwnerLacks() {
        // Owner covers minutes 0 and 1; sibling has rows in minutes 1 (duplicate) and 2, 3.
        let owner = [S(ts: 0, v: 1), S(ts: 30, v: 1), S(ts: 65, v: 1)]
        let sibling = [S(ts: 70, v: 9), S(ts: 125, v: 9), S(ts: 185, v: 9)]
        let covered = SiblingStreamMerge.coveredMinutes(ownerHrTs: owner.map(\.ts))
        let merged = SiblingStreamMerge.fill(owner: owner, siblings: [sibling], covered: covered, ts: { $0.ts })
        XCTAssertEqual(merged.map(\.ts), [0, 30, 65, 125, 185])
        XCTAssertEqual(merged.filter { $0.v == 9 }.count, 2)   // the minute-1 sibling row is NOT added
    }

    func testNoSiblingRowsReturnsOwnerUnchanged() {
        let owner = [S(ts: 5, v: 1), S(ts: 1, v: 2)]            // deliberately unsorted: must not be reordered
        let merged = SiblingStreamMerge.fill(owner: owner, siblings: [[]], covered: [], ts: { $0.ts })
        XCTAssertEqual(merged, owner)
    }

    func testCandidateIdsOnlyForAWhoopOwner() {
        let ids = SiblingStreamMerge.candidateIds(owner: "whoop-x", registeredWhoop: ["whoop-x"],
            registeredOther: ["oura-1"], storeIds: ["my-whoop", "oura-1", "my-whoop-noop", "whoop-x"],
            legacyIds: ["my-whoop"])
        XCTAssertEqual(ids, ["my-whoop"])
        XCTAssertEqual(SiblingStreamMerge.candidateIds(owner: "oura-1", registeredWhoop: ["whoop-x"],
            registeredOther: ["oura-1"], storeIds: ["my-whoop"], legacyIds: []), [])
    }
}
