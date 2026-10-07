import AppKit
import XCTest
@testable import WTManagerKit

/// The bring-your-own-picture path, which has no other way of being checked:
/// every step of it is behind a file picker, and the failure modes are
/// silent — an image that does not decode, a ring that is not drawn, a photo
/// squashed instead of cropped.
final class OwnFaceTests: XCTestCase {
    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-own-face-tests-\(UUID().uuidString)")
        OwnFace.storageDirectoryOverride = testDirectory
        OwnFace.forget()
    }

    override func tearDown() {
        OwnFace.forget()
        OwnFace.storageDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }

    /// A wide image, so a crop and a squash are distinguishable.
    private func source(width: CGFloat, height: CGFloat) throws -> URL {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wt-own-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    func testAPictureIsReducedToTheGridTheCharactersUse() throws {
        OwnFace.forget()
        XCTAssertFalse(OwnFace.exists)
        XCTAssertTrue(OwnFace.adopt(try source(width: 900, height: 300)))
        XCTAssertTrue(OwnFace.exists)
        // Square, so the menu bar gets a face and not two slivers of one, and
        // exactly as many cells as a sprite, so the two sit side by side at
        // the same pixel density.
        let stored = try XCTUnwrap(NSBitmapImageRep(
            data: try Data(contentsOf: OwnFace.storedURL)))
        XCTAssertEqual(stored.pixelsWide, OwnFace.side)
        XCTAssertEqual(stored.pixelsHigh, OwnFace.side)
    }

    func testThePaletteIsFlattened() throws {
        // A photograph has thousands of colours and the characters have six.
        // Left alone it does not read as a different mascot, it reads as the
        // one thing in the window that is not pixel art.
        let wide = NSImage(size: NSSize(width: 256, height: 256))
        wide.lockFocus()
        // A smooth ramp: every column a slightly different grey.
        for x in 0..<256 {
            NSColor(white: CGFloat(x) / 255, alpha: 1).setFill()
            NSRect(x: CGFloat(x), y: 0, width: 1, height: 256).fill()
        }
        wide.unlockFocus()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wt-ramp-\(UUID().uuidString).png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(wide.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)

        XCTAssertTrue(OwnFace.adopt(url))
        let art = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: OwnFace.storedURL)))
        var seen = Set<String>()
        for y in 0..<art.pixelsHigh {
            for x in 0..<art.pixelsWide {
                if let c = art.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    seen.insert("\(Int(c.redComponent * 255))")
                }
            }
        }
        XCTAssertLessThanOrEqual(seen.count, OwnFace.levels,
                                 "a ramp came back with \(seen.count) greys")
    }

    func testTheOutlineIsDerivedTheWayASpritesIs() {
        // A cell outside the mass that touches it — the same rule the art
        // uses, so the two cannot disagree about what an edge looks like.
        let (inside, ring) = OwnFace.disc(OwnFace.side)
        XCTAssertTrue(inside[OwnFace.side / 2][OwnFace.side / 2], "the middle is not inside")
        XCTAssertFalse(inside[0][0], "a corner is inside a disc")
        XCTAssertTrue(ring.contains { $0.contains(true) }, "nothing is outlined")
        for y in 0..<OwnFace.side {
            for x in 0..<OwnFace.side {
                XCTAssertFalse(inside[y][x] && ring[y][x], "a cell is both")
            }
        }
    }

    func testSomethingThatIsNotAnImageIsRefusedRatherThanStored() throws {
        OwnFace.forget()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wt-own-\(UUID().uuidString).png")
        try Data("not a png".utf8).write(to: url)
        XCTAssertFalse(OwnFace.adopt(url))
        XCTAssertFalse(OwnFace.exists, "a rejected file must not leave a mascot behind")
    }

    func testTheRingIsTheOnlyChannelAPictureHas() throws {
        // A photograph cannot blink, so the status has to arrive some other
        // way. If the tinted and untinted renders were identical the picture
        // would be carrying no state at all — which is the failure this whole
        // design is trying to avoid, and it would be invisible.
        XCTAssertTrue(OwnFace.adopt(try source(width: 200, height: 200)))
        let plain = try XCTUnwrap(OwnFace.image(fitting: 44, tint: nil))
        let red = try XCTUnwrap(OwnFace.image(fitting: 44, tint: .systemRed))
        XCTAssertEqual(plain.size, red.size)
        XCTAssertNotEqual(try png(plain), try png(red), "the tint changed nothing")
    }

    func testNoPictureMeansNoImageRatherThanABlankOne() {
        OwnFace.forget()
        XCTAssertNil(OwnFace.image(fitting: 44, tint: .systemRed),
                     "a blank square is indistinguishable from a broken renderer")
    }

    private func png(_ image: NSImage) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
