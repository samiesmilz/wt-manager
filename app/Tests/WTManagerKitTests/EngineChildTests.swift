import XCTest
@testable import WTManagerKit

final class EngineChildTests: XCTestCase {
    private func sleeper() -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["10"]
        return task
    }
    func testQuitTerminatesAnOwnedReadOnlyChild() throws {
        let owner = EngineChild(); let task = sleeper()
        try owner.launch(task)
        XCTAssertTrue(task.isRunning)
        owner.shutdown()
        task.waitUntilExit()
        XCTAssertFalse(task.isRunning)
        XCTAssertEqual(task.terminationReason, .uncaughtSignal)
    }
    func testQueuedWorkCannotStartAfterQuit() {
        let owner = EngineChild(); owner.shutdown()
        let task = sleeper()
        XCTAssertThrowsError(try owner.launch(task))
        XCTAssertFalse(task.isRunning)
    }
    func testFinishedChildAllowsNextReadOnlyOperation() throws {
        let owner = EngineChild()
        let first = Process(); first.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try owner.launch(first); first.waitUntilExit(); owner.finished()
        let next = sleeper(); try owner.launch(next)
        owner.shutdown(); next.waitUntilExit()
        XCTAssertFalse(next.isRunning)
    }
}
