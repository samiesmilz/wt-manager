import XCTest
@testable import WTManagerKit

final class EngagementTests: XCTestCase {
    func testNumericVersionsAndMalformedTags() throws {
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("v0.10.0")), try XCTUnwrap(ReleaseVersion("0.9.9")))
        for tag in ["0.3", "v0.3.0-beta", "0.-3.0", "latest", "0..0"] { XCTAssertNil(ReleaseVersion(tag)) }
    }
    func testReleaseLinksCannotLeaveTheProjectOrAdvertiseDrafts() throws {
        func release(_ url: String, _ extra: String = "") throws -> PublishedRelease {
            let text = "{\"tag_name\":\"v0.4.0\",\"html_url\":\"\(url)\",\"draft\":false,\"prerelease\":false\(extra)}"
            return try JSONDecoder().decode(PublishedRelease.self, from: Data(text.utf8))
        }
        let real = try release("https://github.com/samiesmilz/wt-manager/releases/tag/v0.4.0")
        XCTAssertNotNil(real.updateURL(current: "0.3.0"))
        XCTAssertNil(real.updateURL(current: "0.4.0"))
        for url in ["http://github.com/samiesmilz/wt-manager/releases/tag/v0.4.0", "https://evil.example/releases/tag/v0.4.0", "https://github.com/other/repo/releases/tag/v0.4.0"] {
            XCTAssertNil(try release(url).updateURL(current: "0.3.0"))
        }
        let draft = try JSONDecoder().decode(PublishedRelease.self, from: Data("{\"tag_name\":\"v0.4.0\",\"html_url\":\"https://github.com/samiesmilz/wt-manager/releases/tag/v0.4.0\",\"draft\":true,\"prerelease\":false}".utf8))
        XCTAssertNil(draft.updateURL(current: "0.3.0"))
    }
    func testGrowthNeedsTwoComparableMeasurementsAndScopeChangesResetIt() {
        var history = CleanupHistory()
        history.measure(roots: ["a", "b"], totalKb: 100, rebuildableKb: 30)
        XCTAssertNil(history.growthKb)
        history.measure(roots: ["b", "a"], totalKb: 150, rebuildableKb: 60)
        XCTAssertEqual(history.growthKb, 50)
        history.measure(roots: ["a"], totalKb: 80, rebuildableKb: 20)
        XCTAssertNil(history.growthKb)
        history.measure(roots: ["a"], totalKb: 50, rebuildableKb: 0)
        XCTAssertEqual(history.growthKb, -30)
    }
    func testPreviewFailureNoOpAndRepeatedResultsDoNotEarnRewards() {
        var history = CleanupHistory(); let id = UUID()
        XCTAssertFalse(history.reward(id: id, done: false, completed: 2, freedKb: 20))
        XCTAssertFalse(history.reward(id: id, done: true, completed: 0, freedKb: 20))
        XCTAssertFalse(history.reward(id: id, done: true, completed: 1, freedKb: 0))
        XCTAssertTrue(history.reward(id: id, done: true, completed: 1, freedKb: 1024 * 1024))
        XCTAssertFalse(history.reward(id: id, done: true, completed: 1, freedKb: 1024 * 1024))
        XCTAssertEqual(history.cleanups, 1); XCTAssertEqual(history.rank, "Space Scout")
        XCTAssertEqual(history.reclaimedKb, 1024 * 1024)
    }
    func testPersistedHistoryKeepsRewardDeduplicationAndBoundsSamples() throws {
        var history = CleanupHistory(); let id = UUID(); let now = Date()
        for i in 0..<800 { history.measure(roots: ["a"], totalKb: i, rebuildableKb: 0, at: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(history.samples.count, 720)
        history.reward(id: id, done: true, completed: 1, freedKb: 5 * 1024 * 1024)
        var restored = try JSONDecoder().decode(CleanupHistory.self, from: JSONEncoder().encode(history))
        XCTAssertFalse(restored.reward(id: id, done: true, completed: 1, freedKb: 10))
        XCTAssertEqual(restored.level, 2)
        XCTAssertEqual(restored.levelFraction, 0)
    }
}
