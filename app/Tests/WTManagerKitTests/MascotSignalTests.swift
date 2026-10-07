import XCTest
@testable import WTManagerKit

final class MascotSignalTests: XCTestCase {
    func testEveryMoodHasADifferentGlyphEvenWithoutColor() {
        let variants = MascotSignal.moods.map { MascotSignal.rows(mood: $0).joined(separator: "\n") }
        XCTAssertEqual(Set(variants).count, MascotSignal.moods.count)
    }
    func testSignalHasOneFrameAndEnoughColoredPixelsForEveryMood() {
        for mood in MascotSignal.moods {
            let rows = MascotSignal.rows(mood: mood)
            XCTAssertEqual(rows.count, 9)
            XCTAssertTrue(rows.allSatisfy { $0.count == 9 })
            XCTAssertGreaterThanOrEqual(rows.joined().filter { $0 == "c" }.count, 16)
            XCTAssertEqual(rows.first, "lllllllll")
            XCTAssertEqual(rows.last, "lllllllll")
        }
    }
    func testSignalContrastOnBothMenuBarBackgrounds() {
        // A graphical signal needs 3:1 contrast. The two borders cover light
        // and dark surfaces; the foreground glyph contrasts with its field.
        func luminance(_ hex: String) -> Double {
            let v = UInt32(hex.dropFirst(), radix: 16)!
            func channel(_ n: UInt32) -> Double { let c = Double(n)/255; return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4) }
            return channel((v >> 16)&255)*0.2126 + channel((v >> 8)&255)*0.7152 + channel(v&255)*0.0722
        }
        func contrast(_ a: String, _ b: String) -> Double { let x=luminance(a), y=luminance(b); return (max(x,y)+0.05)/(min(x,y)+0.05) }
        XCTAssertGreaterThan(contrast(MascotSignal.ink, "#ffffff"), 3)
        XCTAssertGreaterThan(contrast(MascotSignal.border, "#232323"), 3)
        for color in MascotSignal.colors.values { XCTAssertGreaterThanOrEqual(contrast(color, MascotSignal.ink), 3) }
    }
}
