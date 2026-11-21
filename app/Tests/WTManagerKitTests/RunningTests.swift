import XCTest
@testable import WTManagerKit

final class RunningTests: XCTestCase {
    private let full = """
    {"version":"0.13.0","error":null,
     "worktrees":[{"path":"/Users/me/dev/storefront-web/.claude/worktrees/cart-drawer","name":"cart-drawer",
       "repo":"storefront-web","branch":"worktree-cart-drawer","primary":false,"behind":3,"base":"origin/main",
       "env":[{"folder":"apps/web","present":[".env.local"],"missing":[]},
              {"folder":"apps/admin","present":[],"missing":[".env.local"]}],
       "servers":[{"pid":4101,"command":"node","started":"Fri Nov 20 09:14:02 2026","ports":[3000],
         "cwd":"/Users/me/dev/storefront-web/.claude/worktrees/cart-drawer/apps/web","folder":"apps/web",
         "stoppable":true,
         "also":[{"pid":4099,"command":"sh","started":"Fri Nov 20 09:14:01 2026"},
                 {"pid":4090,"command":"node","started":"Fri Nov 20 09:14:00 2026"}]}]}],
     "other":[{"pid":800,"command":"ControlCenter","started":"Wed Nov 18 06:00:00 2026","ports":[5000,7000],"cwd":"/"}]}
    """

    func testDecodesWhatTheEngineSends() throws {
        let env = try JSONDecoder().decode(RunningEnvelope.self, from: Data(full.utf8))
        XCTAssertEqual(env.serverCount, 1)
        XCTAssertEqual(env.headline, "1 server running in 1 worktree")
        let wt = try XCTUnwrap(env.worktrees.first)
        XCTAssertEqual(wt.behindLabel(), "3 behind origin/main · as of last fetch")
        XCTAssertEqual(wt.behindLabel(0), "Up to date with origin/main · as of last fetch")
        XCTAssertEqual(wt.env.map(\.label), ["web", "admin"])
        XCTAssertEqual(wt.env.map(\.complete), [true, false])
        let server = try XCTUnwrap(wt.servers.first)
        XCTAssertEqual(server.portLabel, ":3000")
        XCTAssertEqual(server.url?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(env.other.first?.portLabel, ":5000 :7000")
    }

    func testAnOlderEngineMissingFieldsStillDecodesAndOffersNoStop() throws {
        let old = #"{"worktrees":[{"path":"/w/a","servers":[{"pid":7}]}]}"#
        let env = try JSONDecoder().decode(RunningEnvelope.self, from: Data(old.utf8))
        let wt = try XCTUnwrap(env.worktrees.first)
        XCTAssertEqual(wt.name, "a")
        XCTAssertNil(wt.behindLabel())
        XCTAssertEqual(wt.servers.first?.stoppable, false)
        XCTAssertNil(wt.servers.first?.url)
        XCTAssertTrue(env.other.isEmpty)
        XCTAssertEqual(env.headline, "1 server running in 1 worktree")
    }

    func testStopCarriesTheWholeIdentityNotJustThePid() throws {
        let env = try JSONDecoder().decode(RunningEnvelope.self, from: Data(full.utf8))
        let server = try XCTUnwrap(env.worktrees.first?.servers.first)
        XCTAssertEqual(server.stopArguments(),
                       ["--json", "stop", "--pid", "4101", "--started", "Fri Nov 20 09:14:02 2026", "--command", "node"])
        XCTAssertEqual(server.stopArguments(force: true).last, "--force")
        XCTAssertNotEqual(server.id, "4101")
    }

    func testTheConfirmationNamesEverythingThatWillBeSignalled() throws {
        let env = try JSONDecoder().decode(RunningEnvelope.self, from: Data(full.utf8))
        let server = try XCTUnwrap(env.worktrees.first?.servers.first)
        let detail = server.stopDetail(in: "cart-drawer")
        XCTAssertTrue(detail.contains("node (pid 4101) is running in cart-drawer/apps/web"))
        XCTAssertTrue(detail.contains("sh (pid 4099) and node (pid 4090)"))
        XCTAssertTrue(detail.contains("they stop too"))
    }

    func testNothingRunningIsSaidPlainly() throws {
        let env = try JSONDecoder().decode(RunningEnvelope.self, from: Data(#"{"worktrees":[],"other":[]}"#.utf8))
        XCTAssertEqual(env.headline, "Nothing is running in your worktrees")
    }

    func testStopResultsReadAsOneSentence() throws {
        func result(_ json: String) throws -> StopResult {
            try JSONDecoder().decode(StopResult.self, from: Data(json.utf8))
        }
        let stopped = try result(#"{"status":"stopped","reason":"","stopped":[{"pid":2,"command":"sh"},{"pid":3,"command":"node"}],"remaining":[]}"#)
        XCTAssertTrue(stopped.ended)
        XCTAssertEqual(stopped.sentence, "Stopped sh, node.")
        let deaf = try result(#"{"status":"still_running","reason":"did not exit when asked","stopped":[],"remaining":[{"pid":3,"command":"node"}]}"#)
        XCTAssertFalse(deaf.ended)
        XCTAssertTrue(deaf.canForce)
        XCTAssertEqual(deaf.sentence, "node did not exit when asked.")
        let refused = try result(#"{"status":"refused","reason":"process 3 is now vim, started later"}"#)
        XCTAssertFalse(refused.canForce)
        XCTAssertEqual(refused.sentence, "Process 3 is now vim, started later.")
        XCTAssertTrue(try result(#"{"status":"gone"}"#).ended)
    }
}

final class DesignCompareTests: XCTestCase {
    func testOnePageHasOneSpelling() {
        XCTAssertEqual(ComparePair.normalised("checkout"), "/checkout")
        XCTAssertEqual(ComparePair.normalised("  /checkout "), "/checkout")
        XCTAssertEqual(ComparePair.normalised(""), "/")
        XCTAssertEqual(ComparePair.normalised("http://localhost:3000/cart?step=2"), "/cart?step=2")
        XCTAssertEqual(ComparePair.normalised("http://localhost:3000"), "/")
    }

    func testAPairIsItsWorktreePathAndWidth() {
        let a = ComparePair(worktree: "/w/a", path: "checkout", width: 390)
        XCTAssertEqual(a.key, ComparePair(worktree: "/w/a", path: "/checkout", width: 390).key)
        XCTAssertNotEqual(a.key, ComparePair(worktree: "/w/a", path: "/checkout", width: 600).key)
        XCTAssertNotEqual(a.key, ComparePair(worktree: "/w/b", path: "/checkout", width: 390).key)
        XCTAssertNotEqual(a.key, ComparePair(worktree: "/w/a", path: "/cart", width: 390).key)
        XCTAssertEqual(a.key.count, 20)
    }

    func testTheCapturedPageIsAlwaysOnThisMachine() {
        let pair = ComparePair(worktree: "/w/a", path: "https://example.com/cart?step=2", width: 390)
        XCTAssertEqual(pair.url(port: 3000)?.absoluteString, "http://localhost:3000/cart?step=2")
        XCTAssertEqual(ComparePair(worktree: "/w/a", path: "/a b", width: 390).url(port: 8080)?.host, "localhost")
    }

    func testImagesAreKeptPerPairAndSideInAPrivateFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wt-compare-\(UUID().uuidString)")
        CompareLibrary.storageDirectoryOverride = dir
        defer {
            CompareLibrary.storageDirectoryOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let pair = ComparePair(worktree: "/w/a", path: "/", width: 390)
        let wider = ComparePair(worktree: "/w/a", path: "/", width: 1440)
        XCTAssertFalse(CompareLibrary.has(.design, for: pair))
        XCTAssertTrue(CompareLibrary.store(Data([1, 2, 3]), as: .design, for: pair))
        XCTAssertTrue(CompareLibrary.has(.design, for: pair))
        XCTAssertFalse(CompareLibrary.has(.capture, for: pair))
        XCTAssertFalse(CompareLibrary.has(.design, for: wider))
        XCTAssertEqual(try Data(contentsOf: CompareLibrary.url(.design, for: pair)), Data([1, 2, 3]))
        XCTAssertTrue(CompareLibrary.url(.design, for: pair).path.hasPrefix(dir.path))
        CompareLibrary.remove(.design, for: pair)
        XCTAssertFalse(CompareLibrary.has(.design, for: pair))
    }

    func testDifferentProportionsAreSaidNotStretchedAway() {
        // A 2x design export against a 1x capture of a longer page.
        let g = CompareGeometry(design: CGSize(width: 780, height: 1600), capture: CGSize(width: 390, height: 1040))
        XCTAssertEqual(g.heights(atWidth: 390).design, 800)
        XCTAssertEqual(g.heights(atWidth: 390).capture, 1040)
        XCTAssertEqual(g.note(atWidth: 390), "Both are scaled to 390pt wide. The running page is 240pt taller than the design.")
        let shorter = CompareGeometry(design: CGSize(width: 390, height: 900), capture: CGSize(width: 390, height: 844))
        XCTAssertEqual(shorter.note(atWidth: 390), "Both are scaled to 390pt wide. The design is 56pt taller than the running page.")
        XCTAssertNil(CompareGeometry(design: CGSize(width: 780, height: 1688), capture: CGSize(width: 390, height: 844)).note(atWidth: 390))
        XCTAssertNil(CompareGeometry(design: .zero, capture: CGSize(width: 390, height: 844)).note(atWidth: 390))
    }
}

final class CaptureDeviceTests: XCTestCase {
    func testOnlyBootedSimulatorsAreListed() {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
          {"udid":"AAAA-1","name":"iPhone 17 Pro","state":"Booted","isAvailable":true},
          {"udid":"BBBB-2","name":"iPad mini","state":"Shutdown"}],
         "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"CCCC-3","name":"iPhone 16","state":"Booted"}]}}
        """
        let found = CaptureDevice.simulators(fromJSON: Data(json.utf8))
        XCTAssertEqual(found.map(\.name), ["iPhone 16", "iPhone 17 Pro"])
        XCTAssertEqual(found.first?.kind, .simulator)
        XCTAssertTrue(CaptureDevice.simulators(fromJSON: Data("not json".utf8)).isEmpty)
    }

    func testOnlyAndroidDevicesThatCanAnswerAreListed() {
        let text = """
        List of devices attached
        emulator-5554          device product:sdk_gphone64 model:Pixel_9 device:emu64a transport_id:1
        R58M12ABCDE            unauthorized usb:1-1 transport_id:2
        0A1B2C3D               offline

        """
        let found = CaptureDevice.androids(fromList: text)
        XCTAssertEqual(found, [CaptureDevice(kind: .android, id: "emulator-5554", name: "Pixel 9")])
        XCTAssertTrue(CaptureDevice.androids(fromList: "List of devices attached\n").isEmpty)
    }

    func testEachKindIsAskedForItsOwnScreenByItsOwnTool() {
        let sim = CaptureDevice(kind: .simulator, id: "AAAA-1", name: "iPhone 17 Pro")
        XCTAssertEqual(sim.screenshotCommand(adb: "/x/adb", file: "/tmp/s.png"),
                       ["/usr/bin/xcrun", "simctl", "io", "AAAA-1", "screenshot", "--type=png", "/tmp/s.png"])
        let phone = CaptureDevice(kind: .android, id: "emulator-5554", name: "Pixel 9")
        XCTAssertEqual(phone.screenshotCommand(adb: "/x/adb", file: "/tmp/s.png"),
                       ["/x/adb", "-s", "emulator-5554", "exec-out", "screencap", "-p"])
        XCTAssertNotEqual(sim.pairOwner, phone.pairOwner)
    }
}
