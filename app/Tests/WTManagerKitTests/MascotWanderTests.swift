import XCTest
@testable import WTManagerKit

final class MascotWanderTests: XCTestCase {
    func testOnlyActiveInteractionAndAccessibilityPauseMovement() {
        XCTAssertTrue(MascotWander.isEnabled(wandering: true, floating: true,
                                            committing: false, reduceMotion: false))
        XCTAssertFalse(MascotWander.isEnabled(wandering: true, floating: true,
                    committing: false, reduceMotion: false, interacting: true))
        for disabledInput in 0..<4 {
            XCTAssertFalse(MascotWander.isEnabled(wandering: disabledInput != 0,
                floating: disabledInput != 1,
                committing: disabledInput == 2, reduceMotion: disabledInput == 3))
        }
    }

    func testOnlyThePalmStaysRootedAndItsGustIsUnhurried() {
        XCTAssertTrue(MascotWander.staysRooted(figure: "palm"))
        for figure in ["cat", "crab", "robot", "rabbit", "antenna", "pup", "rex"] {
            XCTAssertFalse(MascotWander.staysRooted(figure: figure), figure)
        }
        // The gust is drawn frames, not a rotation; at 0.06s a frame the
        // fronds flapped rather than swayed.
        XCTAssertGreaterThanOrEqual(MascotWander.gustFrameInterval, 0.15)
        XCTAssertGreaterThan(MascotWander.gustDuration / MascotWander.gustFrameInterval, 8)
    }
    func testDestinationsStayInsideTheCurrentDisplayAndChangeLocation() {
        var wander = MascotWander(seed: 3)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = CGRect(x: 100, y: 100, width: 84, height: 84)
        for _ in 0..<30 {
            let point = try! XCTUnwrap(wander.destination(from: current, size: current.size,
                                                           displays: [screen]))
            XCTAssertGreaterThanOrEqual(point.x, screen.minX + 20)
            XCTAssertGreaterThanOrEqual(point.y, screen.minY + 20)
            XCTAssertLessThanOrEqual(point.x + current.width, screen.maxX - 20)
            XCTAssertLessThanOrEqual(point.y + current.height, screen.maxY - 20)
            XCTAssertGreaterThanOrEqual(hypot(point.x-current.minX, point.y-current.minY), 80)
            XCTAssertLessThanOrEqual(abs(point.x-current.minX), 280)
            XCTAssertLessThanOrEqual(abs(point.y-current.minY), 25)
        }
    }

    func testNoUsableDisplayHasNoDestination() {
        var wander = MascotWander(seed: 3)
        XCTAssertNil(wander.destination(from: .zero, size: CGSize(width: 84, height: 84),
                                        displays: [CGRect(x: 0, y: 0, width: 100, height: 100)]))
    }

    func testTravelPaceAndFacingAreStable() {
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 300, y: 400)), 500.0/12.0, accuracy: 0.34)
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 10000, y: 0)), 10000.0/12.0, accuracy: 0.34)
        XCTAssertTrue(MascotWander.facesLeft(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 40, y: 0)))
        XCTAssertFalse(MascotWander.facesLeft(from: CGPoint(x: 40, y: 0), to: CGPoint(x: 100, y: 0)))
    }

    func testEveryAlternatingPoseAdvancesWithoutExtraHold() {
        let samples = (0...8).map { MascotWander.stepSample(distance: 100, elapsed: Double($0) * MascotWander.poseInterval) }
        XCTAssertEqual(samples.map(\.frame), [0, 1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(samples.map(\.travelled), [0, 2, 4, 6, 8, 10, 12, 14, 16])
        for tick in 0..<8 {
            let between = MascotWander.stepSample(distance: 100, elapsed: Double(tick) * MascotWander.poseInterval + MascotWander.poseInterval * 0.95)
            XCTAssertEqual(between.frame, samples[tick].frame)
            XCTAssertEqual(between.travelled, samples[tick].travelled)
        }
    }

    func testFinalPartialStepStopsExactlyAtDestination() {
        for figure in ["cat", "crab", "rabbit", "snowman", "robot"] {
            for distance in [0.0, 1, 7, 12, 13, 100, 500, 10000] {
                let duration = MascotWander.travelTime(from: .zero,
                    to: CGPoint(x: distance, y: 0), figure: figure)
                let done = MascotWander.stepSample(distance: distance, elapsed: duration, figure: figure)
                XCTAssertTrue(done.finished)
                XCTAssertEqual(done.travelled, distance)
                if distance > 0 {
                    XCTAssertFalse(MascotWander.stepSample(distance: distance,
                        elapsed: duration - 0.001, figure: figure).finished)
                }
            }
        }
    }

    func testEachCharacterKeepsTheGentleAveragePace() {
        for figure in ["cat", "crab", "rabbit", "snowman", "robot", "antenna", "pup", "rex"] {
            let cycle = 16 * MascotWander.poseInterval(figure: figure)
            let sample = MascotWander.stepSample(distance: 1000, elapsed: cycle, figure: figure)
            XCTAssertEqual(sample.travelled / cycle, 12, accuracy: 0.001)
            XCTAssertEqual(sample.frame, 0)
        }
        // Walkers on the shared leg gait advance exactly one art pixel per
        // pose; any other rhythm makes their planted foot skate.
        for figure in ["pup", "rex", "robot", "antenna"] {
            for tick in 1...16 {
                let sample = MascotWander.stepSample(distance: 1000,
                    elapsed: Double(tick) * MascotWander.poseInterval(figure: figure), figure: figure)
                XCTAssertEqual(sample.travelled, Double(2 * tick), accuracy: 0.001, "\(figure) \(tick)")
            }
        }
        let crouched = MascotWander.stepSample(distance: 100, elapsed: 2 * MascotWander.poseInterval, figure: "rabbit")
        let airborne = MascotWander.stepSample(distance: 100, elapsed: 8 * MascotWander.poseInterval, figure: "rabbit")
        XCTAssertGreaterThan((airborne.travelled-crouched.travelled)/6, crouched.travelled/2)
    }

    func testFirstStrollStartsSoonAfterEnabling() {
        var wander = MascotWander(seed: 17)
        for _ in 0..<100 {
            XCTAssertTrue((1.5...3.5).contains(wander.firstPause()))
        }
    }
}
