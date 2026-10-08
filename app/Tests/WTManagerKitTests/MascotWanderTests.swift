import XCTest
@testable import WTManagerKit

final class MascotWanderTests: XCTestCase {
    func testOnlyActiveInteractionAndAccessibilityPauseMovement() {
        XCTAssertTrue(MascotWander.isEnabled(wandering: true, floating: true, windowOpen: false,
                                            committing: false, reduceMotion: false))
        XCTAssertFalse(MascotWander.isEnabled(wandering: true, floating: true, windowOpen: false,
                    committing: false, reduceMotion: false, interacting: true))
        for disabledInput in 0..<5 {
            XCTAssertFalse(MascotWander.isEnabled(wandering: disabledInput != 0,
                floating: disabledInput != 1, windowOpen: disabledInput == 2,
                committing: disabledInput == 3, reduceMotion: disabledInput == 4))
        }
    }

    func testPalmTopplesInPlaceAndRecoversWithoutDrift() {
        XCTAssertTrue(MascotWander.staysRooted(figure: "palm"))
        XCTAssertFalse(MascotWander.staysRooted(figure: "antenna"))
        XCTAssertEqual(MascotWander.rootedAngle(progress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(MascotWander.rootedAngle(progress: 0.5), 76, accuracy: 0.001)
        XCTAssertEqual(MascotWander.rootedAngle(progress: 1), 0, accuracy: 0.001)
        for step in 0...100 {
            let p = Double(step) / 100
            XCTAssertTrue((-8...76).contains(MascotWander.rootedAngle(progress: p)))
            if step > 0 {
                XCTAssertLessThan(abs(MascotWander.rootedAngle(progress: p)
                                     - MascotWander.rootedAngle(progress: p - 0.01)), 4)
            }
        }
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
            XCTAssertGreaterThanOrEqual(hypot(point.x-current.minX, point.y-current.minY), 150)
        }
    }

    func testNoUsableDisplayHasNoDestination() {
        var wander = MascotWander(seed: 3)
        XCTAssertNil(wander.destination(from: .zero, size: CGSize(width: 84, height: 84),
                                        displays: [CGRect(x: 0, y: 0, width: 100, height: 100)]))
    }

    func testTravelPaceAndFacingAreStable() {
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 300, y: 400)), 12.5, accuracy: 0.01)
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 10000, y: 0)), 60)
        XCTAssertTrue(MascotWander.facesLeft(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 40, y: 0)))
        XCTAssertFalse(MascotWander.facesLeft(from: CGPoint(x: 40, y: 0), to: CGPoint(x: 100, y: 0)))
    }

    func testLegsFollowTravelDistanceRatherThanAnIndependentClock() {
        XCTAssertEqual(MascotWander.gaitFrame(distance: 100, elapsed: 0, duration: 10), 0)
        XCTAssertEqual(MascotWander.gaitFrame(distance: 100, elapsed: 5, duration: 10), 2)
        XCTAssertEqual(MascotWander.gaitFrame(distance: 100, elapsed: 2.5, duration: 5), 2)
        XCTAssertEqual(MascotWander.gaitFrame(distance: 0, elapsed: 5, duration: 10), 0)
        XCTAssertEqual(MascotWander.gaitFrame(distance: 100, elapsed: 5, duration: 0), 0)
    }

    func testFirstStrollStartsSoonAfterEnabling() {
        var wander = MascotWander(seed: 17)
        for _ in 0..<100 {
            XCTAssertTrue((1.5...3.5).contains(wander.firstPause()))
        }
    }
}
