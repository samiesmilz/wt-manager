import XCTest
@testable import WTManagerKit

final class PRLifecycleTests: XCTestCase {
    private func tree(_ state: String, path: String = "/tmp/pr-checkout", blocked: Bool = false) throws -> Worktree {
        let json = """
        {"repo":"sample","repo_id":"repo","branch":"feature","status":"\(state == "MERGED" ? "merged" : "active")","meaning":"test","path":"\(path)","ahead":0,"behind":0,"dirty":0,"unpushed":0,"age_days":1,"size_kb":100,"reclaim_kb":50,"last_commit":1,"base":"main","base_source":"pr","primary":false,"is_base":false,"solo_log":[],"removal":{"state":"\(blocked ? "blocked" : "ready")","reason":"test"},"pr":{"number":7,"state":"\(state)","draft":false,"checks":"none","review":"none","distinct_failing":[],"endemic":[],"url":"https://github.com/example/repo/pull/7","merged_at":"","author":"me"}}
        """
        return try JSONDecoder().decode(Worktree.self, from: Data(json.utf8))
    }
    func testBaselineIsQuietAndDuplicateCheckoutsCountOnce() throws {
        let rows = [try tree("MERGED"), try tree("MERGED",path:"/tmp/other")]
        var tracker = PRLifecycle(); tracker.observe(rows)
        XCTAssertTrue(tracker.pending.isEmpty)
        XCTAssertEqual(LinkedPRStats(worktrees: rows).merged, 1)
    }
    func testObservedMergeIsPersistentDeduplicatedAndKeepsBlockedPaths() throws {
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")])
        tracker.observe([try tree("MERGED",blocked:true),try tree("MERGED",path:"/tmp/other")])
        XCTAssertEqual(tracker.pending.count,1); XCTAssertTrue(tracker.pending[0].blocked)
        XCTAssertEqual(tracker.pending[0].occupiedKb,200)
        let data = try JSONEncoder().encode(tracker)
        var restored = try JSONDecoder().decode(PRLifecycle.self,from:data)
        restored.observe([try tree("MERGED",blocked:true),try tree("MERGED",path:"/tmp/other")])
        XCTAssertEqual(restored.pending.count,1)
        restored.dismiss(restored.pending[0].id)
        restored.observe([try tree("MERGED")]); XCTAssertTrue(restored.pending.isEmpty)
    }
    func testUnknownPartialScanDoesNotEraseObservedOpenOrPendingNotice() throws {
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")])
        tracker.observe([],complete:false); tracker.observe([try tree("MERGED")])
        XCTAssertEqual(tracker.pending.count,1)
        tracker.observe([],complete:false); XCTAssertEqual(tracker.pending.count,1)
        tracker.observe([]); XCTAssertTrue(tracker.pending.isEmpty)
    }
    func testPendingMessageUsesCurrentPathsAndNewBlockers() throws {
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")])
        tracker.observe([try tree("MERGED"), try tree("MERGED", path: "/tmp/other")])
        tracker.observe([try tree("MERGED", blocked: true)])
        let nudge = try XCTUnwrap(tracker.pending.first)
        XCTAssertEqual(nudge.paths, ["/tmp/pr-checkout"])
        XCTAssertEqual(nudge.occupiedKb, 100)
        XCTAssertTrue(nudge.blocked)
    }

    func testClosedWithoutMergeDoesNotNudgeOrCountAsMerged() throws {
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")])
        tracker.observe([try tree("CLOSED")]); XCTAssertTrue(tracker.pending.isEmpty)
        let stats = LinkedPRStats(worktrees:[try tree("CLOSED")])
        XCTAssertEqual(stats.closed,1); XCTAssertEqual(stats.merged,0)
    }
    func testActivityMetadataCanNudgeWhileRemovalClassificationStaysActive() throws {
        let original = try tree("MERGED", blocked: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoderFixture(original)) as? [String: Any])
        json["pr_activity"] = json["pr"]; json.removeValue(forKey: "pr"); json["status"] = "active"
        let newer = try JSONDecoder().decode(Worktree.self, from: JSONSerialization.data(withJSONObject: json))
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")]); tracker.observe([newer])
        XCTAssertNil(newer.pr); XCTAssertEqual(newer.status, "active")
        XCTAssertEqual(LinkedPRStats(worktrees: [newer]).merged, 1)
        XCTAssertTrue(try XCTUnwrap(tracker.pending.first).blocked)
    }
    private func JSONEncoderFixture(_ tree: Worktree) throws -> Data {
        // Worktree is a read model. Build from the same minimal wire fixture.
        let state = tree.pr?.state ?? "OPEN"
        let json = """
        {"repo":"sample","repo_id":"repo","branch":"feature","status":"merged","meaning":"test","path":"/tmp/pr-checkout","ahead":1,"behind":0,"dirty":0,"unpushed":1,"age_days":1,"size_kb":100,"reclaim_kb":50,"last_commit":1,"base":"main","base_source":"pr","primary":false,"is_base":false,"solo_log":[],"removal":{"state":"blocked","reason":"new work"},"pr":{"number":7,"state":"\(state)","draft":false,"checks":"none","review":"none","distinct_failing":[],"endemic":[],"url":"https://github.com/example/repo/pull/7","merged_at":"","author":"me"}}
        """
        return Data(json.utf8)
    }

    func testReopenedAndConflictingPRStatesDoNotInviteOldRemoval() throws {
        var tracker = PRLifecycle(); tracker.observe([try tree("OPEN")]); tracker.observe([try tree("MERGED")])
        tracker.observe([try tree("OPEN")]); XCTAssertTrue(tracker.pending.isEmpty)
        tracker.observe([try tree("MERGED"),try tree("OPEN",path:"/tmp/other")])
        XCTAssertTrue(tracker.pending.isEmpty)
        XCTAssertEqual(LinkedPRStats(worktrees:[try tree("MERGED"),try tree("OPEN",path:"/tmp/other")]).unconfirmed,2)
    }
}
