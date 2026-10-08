import XCTest
@testable import WTManagerKit

final class MascotWanderTests: XCTestCase {
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
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 300, y: 400)), 3.333, accuracy: 0.01)
        XCTAssertEqual(MascotWander.travelTime(from: .zero, to: CGPoint(x: 10000, y: 0)), 8.5)
        XCTAssertTrue(MascotWander.facesLeft(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 40, y: 0)))
        XCTAssertFalse(MascotWander.facesLeft(from: CGPoint(x: 40, y: 0), to: CGPoint(x: 100, y: 0)))
    }

    func testFirstStrollStartsSoonAfterEnabling() {
        var wander = MascotWander(seed: 17)
        for _ in 0..<100 {
            XCTAssertTrue((1.5...3.5).contains(wander.firstPause()))
        }
    }
}
