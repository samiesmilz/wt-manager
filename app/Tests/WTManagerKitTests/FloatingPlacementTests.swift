import XCTest
@testable import WTManagerKit

final class FloatingPlacementTests: XCTestCase {
    private let main = CGRect(x: 0, y: 24, width: 1440, height: 850)
    private let size = CGSize(width: 104, height: 108)
    func testSavedPositionSurvivesOnSecondDisplay() {
        let other = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let p = CGPoint(x: -800, y: 500)
        XCTAssertEqual(FloatingPlacement.frame(origin: p, size: size, screens: [main, other]).origin, p)
    }
    func testUnpluggedDisplayRecoversCompanion() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: -800, y: 500), size: size, screens: [main])
        XCTAssertTrue(main.contains(frame))
    }
    func testPartlyOffscreenDragIsKeptReachable() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 1420, y: 850), size: size, screens: [main])
        XCTAssertTrue(main.contains(frame))
        XCTAssertEqual(frame.maxX, main.maxX)
        XCTAssertEqual(frame.maxY, main.maxY)
    }
    func testInvalidSavedCoordinatesRecover() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), size: size, screens: [main])
        XCTAssertTrue(main.contains(frame))
    }
}
