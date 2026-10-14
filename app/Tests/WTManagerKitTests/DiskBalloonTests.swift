import XCTest
@testable import WTManagerKit

final class DiskBalloonTests: XCTestCase {
    private func row(status: String, size: Int, reclaim: Int, isBase: Bool = false,
                     removal: String = "ready", primary: Bool = false) throws -> Worktree {
        let json = """
        {"repo":"demo","branch":"b","status":"\(status)","meaning":"","path":"/w/\(UUID().uuidString)",
        "ahead":0,"behind":0,"dirty":0,"deleted":0,"unpushed":0,"age_days":1,
        "size_kb":\(size),"reclaim_kb":\(reclaim),"last_commit":1,"base":"origin/main","base_source":"origin/HEAD",
        "primary":\(primary),"is_base":\(isBase),"solo_log":[],"pr":null,
        "removal":{"state":"\(removal)","reason":""}}
        """
        return try JSONDecoder().decode(Worktree.self, from: Data(json.utf8))
    }

    func testFreeableCountsFinishedWorktreesWholeAndEverythingElseByItsCaches() throws {
        let rows = [
            try row(status: "merged", size: 900, reclaim: 400),              // whole: 900
            try row(status: "empty", size: 300, reclaim: 0),                 // whole: 300
            try row(status: "active", size: 5000, reclaim: 700),             // caches: 700
            try row(status: "merged", size: 800, reclaim: 50, isBase: true), // main checkout: 50
            try row(status: "merged", size: 600, reclaim: 20, removal: "blocked"), // blocked: 20
        ]
        XCTAssertEqual(DiskBalloon.freeableKb(rows), 900 + 300 + 700 + 50 + 20)
    }

    func testTheBreakdownMatchesTheRemoveButtonsOwnRule() throws {
        // The balloon counts a worktree whole exactly when the Disk page's
        // remove button would offer it; a primary checkout is not one click away.
        let rows = [
            try row(status: "merged", size: 900, reclaim: 400),
            try row(status: "merged", size: 700, reclaim: 30, primary: true),
            try row(status: "active", size: 5000, reclaim: 600),
        ]
        XCTAssertEqual(rows.map(\.removable), [true, false, false])
        let f = try XCTUnwrap(DiskBalloon.freeable(rows))
        XCTAssertEqual(f.finishedKb, 900)
        XCTAssertEqual(f.finishedCount, 1)
        XCTAssertEqual(f.cachesKb, 30 + 600)
        XCTAssertEqual(f.totalKb, DiskBalloon.freeableKb(rows))
    }

    func testASaveFirstRemovalIsNotOfferedAsAPlainOne() throws {
        // The plain remove refuses it; counting it whole would promise space
        // that one click on the Disk page cannot free.
        let held = try row(status: "merged", size: 900, reclaim: 40, removal: "discard")
        XCTAssertTrue(held.removalDiscards)
        XCTAssertFalse(held.removable)
        XCTAssertEqual(DiskBalloon.freeableKb([held]), 40)
    }

    func testTheRunningTotalNamesTheNextRank() {
        var h = CleanupHistory()
        _ = h.reward(id: UUID(), done: true, completed: 7, freedKb: 52 * 1_048_576)
        XCTAssertEqual(h.rank, "Disk Guardian")
        XCTAssertEqual(h.nextRank, "Storage Hero")
        XCTAssertEqual(h.nextMilestoneKb.map { $0 - h.reclaimedKb }, 48 * 1_048_576)
        _ = h.reward(id: UUID(), done: true, completed: 1, freedKb: 600 * 1_048_576)
        XCTAssertNil(h.nextRank, "the top rank has nowhere further to go")
    }

    func testNothingMeasuredIsUnknownNotZero() throws {
        // Zero would let go of the balloon on a fresh launch, before anything
        // was measured; unknown shows the grey "…" instead.
        XCTAssertNil(DiskBalloon.freeableKb([try row(status: "active", size: -1, reclaim: -1)]))
        XCTAssertNil(DiskBalloon.freeableKb([]))
    }

    func testColourBandsRiseAtOnceAndFallOnlyPastTheMargin() {
        var l = DiskBalloon.level(gb: 4.9, freeFraction: 0.5, previous: nil)
        XCTAssertEqual(l.colour, .green)
        l = DiskBalloon.level(gb: 5.0, freeFraction: 0.5, previous: l)
        XCTAssertEqual(l.colour, .yellow)
        l = DiskBalloon.level(gb: 4.8, freeFraction: 0.5, previous: l)
        XCTAssertEqual(l.colour, .yellow, "flickered back at the boundary")
        l = DiskBalloon.level(gb: 4.4, freeFraction: 0.5, previous: l)
        XCTAssertEqual(l.colour, .green)
        XCTAssertEqual(DiskBalloon.level(gb: 26, freeFraction: 0.5, previous: nil).colour, .orange)
    }

    func testANearlyFullDiskStepsTheColourUpButNotTheSize() {
        var l = DiskBalloon.level(gb: 6, freeFraction: 0.07, previous: nil)
        XCTAssertEqual(l.colour, .orange)
        XCTAssertEqual(l.size, .medium)
        l = DiskBalloon.level(gb: 6, freeFraction: 0.11, previous: l)
        XCTAssertEqual(l.colour, .orange, "released before the margin")
        l = DiskBalloon.level(gb: 6, freeFraction: 0.13, previous: l)
        XCTAssertEqual(l.colour, .yellow)
        XCTAssertEqual(DiskBalloon.level(gb: 30, freeFraction: 0.05, previous: nil).colour, .orange,
                       "orange is the top; a full disk cannot go past it")
    }

    func testLabelsAreWrittenTheWayTheDiskPageWritesThem() {
        let g = DiskBalloon.gb
        // The case that was reported: one measurement, "56GB" on the Disk
        // page and "57" on the balloon.
        let kb = Int(56.6 * g)
        let l = DiskBalloon.label(kb: kb)
        XCTAssertEqual(l.number + l.unit, DiskSize.human(kb))
        XCTAssertEqual(DiskSize.human(kb), "57GB", "rounds, as the engine's human() does")
        XCTAssertEqual(DiskSize.human(Int(8.5 * g)), "8.5GB")
        XCTAssertEqual(DiskSize.human(Int(5.0 * g)), "5.0GB")
        XCTAssertEqual(DiskSize.human(Int(0.84 * g)), "860MB")
        XCTAssertEqual(DiskSize.human(Int(1234 * g)), "1.2TB")
        XCTAssertEqual(DiskSize.human(0), "—")
        for v in [0.3, 0.84, 1, 4.95, 9.96, 26.4, 56.6, 999, 1234] {
            let k = Int(v * g), b = DiskBalloon.label(kb: k)
            XCTAssertEqual(b.number + b.unit, DiskSize.human(k), "\(v) GB")
        }
    }

    func testGrowthIsAnnouncedInHalfGigabyteSteps() {
        let g = DiskBalloon.gb
        XCTAssertTrue(DiskBalloon.crossedStep(from: Int(8.0 * g), to: Int(8.6 * g)))
        XCTAssertFalse(DiskBalloon.crossedStep(from: Int(8.0 * g), to: Int(8.4 * g)))
        // A wobble across a step boundary is not growth worth a tag.
        XCTAssertFalse(DiskBalloon.crossedStep(from: Int(8.49 * g), to: Int(8.51 * g)))
        XCTAssertEqual(DiskBalloon.delta(from: Int(8.0 * g), to: Int(8.6 * g)), "+0.6 GB")
        XCTAssertEqual(DiskBalloon.delta(from: Int(8.5 * g), to: Int(2.1 * g)), "−6.4 GB")
    }

    // MARK: swing

    private func run(_ s: inout BalloonSwing, seconds: Double, straining: Bool = false,
                     drift: Double = 0) -> [Double] {
        (0..<Int(seconds * 15)).map { _ in s.step(dt: 1.0 / 15, drift: drift, straining: straining) }
    }

    func testTheSwingStaysWithinItsRangeCalmOrStraining() {
        for straining in [false, true] {
            var s = BalloonSwing(seed: 7)
            for a in run(&s, seconds: 600, straining: straining) {
                XCTAssertTrue(BalloonSwing.range.contains(a), "\(a) straining=\(straining)")
            }
        }
    }

    func testItReachesBothOutToTheSideAndAlmostOverhead() {
        var s = BalloonSwing(seed: 3)
        let angles = run(&s, seconds: 120)
        XCTAssertGreaterThan(angles.max()!, 10)
        XCTAssertLessThan(angles.min()!, -12)
    }

    func testStrainingMovesFasterThanCalm() {
        func speed(_ straining: Bool) -> Double {
            var s = BalloonSwing(seed: 11)
            var total = 0.0
            for _ in 0..<(15 * 120) { s.step(dt: 1.0 / 15, straining: straining); total += abs(s.velocity) }
            return total
        }
        XCTAssertGreaterThan(speed(true), 1.5 * speed(false))
    }

    func testSettingOffSwingsItBackAndWalkingTrailsIt() {
        var s = BalloonSwing(seed: 5)
        _ = run(&s, seconds: 3)
        let before = s.angle
        s.step(dt: 1.0 / 15, accel: 180)                  // 12 pt/s reached in one tick
        for _ in 0..<4 { s.step(dt: 1.0 / 15) }
        XCTAssertLessThan(s.angle, before, "did not swing back on setting off")

        var calm = BalloonSwing(seed: 9), walking = BalloonSwing(seed: 9)
        let c = run(&calm, seconds: 30), w = run(&walking, seconds: 30, drift: -14)
        XCTAssertLessThan(w.reduce(0, +) / Double(w.count), c.reduce(0, +) / Double(c.count) - 8)
    }

    func testLimitsKeepTheBalloonInsideTheWindow() {
        var s = BalloonSwing(seed: 2)
        for _ in 0..<(15 * 120) {
            let a = s.step(dt: 1.0 / 15, straining: true, limits: -20...9)
            XCTAssertTrue((-20.0...9.0).contains(a))
        }
    }
}
