import XCTest
@testable import WTManagerKit

final class RemovalTests: XCTestCase {
    private func row(removal: String = "", dirty: Int = 0, branch: String = "null") throws -> Worktree {
        let json = """
        {"repo":"demo","branch":\(branch),"status":"merged","meaning":"landed","path":"/w/review-17",
        "ahead":0,"behind":0,"dirty":\(dirty),"deleted":0,"unpushed":0,"age_days":1,
        "size_kb":100,"reclaim_kb":0,"last_commit":1,"base":"origin/main","base_source":"origin/HEAD",
        "primary":false,"is_base":false,"solo_log":[],"pr":null\(removal)}
        """
        return try JSONDecoder().decode(Worktree.self, from: Data(json.utf8))
    }
    func testOlderEngineDoesNotImplyRemovalApproval() throws {
        let w = try row()
        XCTAssertFalse(w.removalReady)
        XCTAssertFalse(w.removalBlocked)
        XCTAssertEqual(w.name, "Detached · review-17")
    }
    func testEngineCapabilityAndStateChangesAreObserved() throws {
        let ready = try row(removal: #","removal":{"state":"ready","reason":"files checked"}"#)
        let blocked = try row(removal: #","removal":{"state":"blocked","reason":"local changes"}"#, dirty: 1)
        XCTAssertTrue(ready.removalReady)
        XCTAssertTrue(blocked.removalBlocked)
        XCTAssertNotEqual(ready.removalFingerprint, blocked.removalFingerprint)
    }
}
