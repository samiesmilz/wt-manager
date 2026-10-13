import AppKit
import WTManagerKit

/// Everything needed to draw the disk balloon for one frame, in the floating
/// view's coordinates (points, origin bottom-left).
struct BalloonScene {
    var center: NSPoint
    /// Degrees from vertical; positive leans toward +x.
    var angle: Double
    var pixels: (w: Int, h: Int)
    var colour: DiskBalloon.Colour
    var number: String
    var unit: String
    /// The string's root. `nil` once the character has let go.
    var hand: NSPoint?
    /// How far the string bows against the motion, in points.
    var bow: CGFloat = 0
    var alpha: CGFloat = 1
    var tag: (text: String, colour: DiskBalloon.Colour, alpha: CGFloat)?

    /// What actually reaches the screen: positions snap to the 2-point pixel
    /// grid and the body to 2-degree steps, so most frames of a slow breeze
    /// draw exactly what the last one did and need not be drawn at all.
    var drawnKey: String {
        let px = BalloonPainter.pixel
        func q(_ v: CGFloat) -> Int { Int((v / px).rounded()) }
        let h = hand.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? "-"
        let t = tag.map { "\($0.text)/\(Int($0.alpha * 10))" } ?? "-"
        return "\(q(center.x)),\(q(center.y))/\(Int((angle / 2).rounded()))/\(pixels.w)x\(pixels.h)/\(colour)/\(number)/\(h)/\(Int(bow.rounded()))/\(Int(alpha * 20))/\(t)"
    }

    var frame: NSRect {
        let r = CGFloat(max(pixels.w, pixels.h)) * BalloonPainter.pixel / 2 + 4
        return NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    }
}

/// Draws the balloon as pixel art: two points to a pixel, like the character,
/// so the two read as one drawing. The body tilts with its string; the number
/// stays upright, because a number you have to tilt your head for is not
/// glanceable.
@MainActor
enum BalloonPainter {
    nonisolated static let pixel: CGFloat = 2
    /// From the hand to the balloon's centre. Long enough that a balloon
    /// drifting over the head clears it at every size.
    nonisolated static let stringLength: CGFloat = 80

    private static let ink = NSColor(srgbRed: 0.086, green: 0.102, blue: 0.133, alpha: 1)
    private static let stringColour = NSColor(srgbRed: 0.357, green: 0.384, blue: 0.439, alpha: 1)
    static func tones(_ c: DiskBalloon.Colour) -> (fill: NSColor, light: NSColor, shade: NSColor) {
        func hex(_ s: String) -> NSColor { Ink.color(s) ?? .gray }
        switch c {
        case .grey:   return (hex("#9aa1ad"), hex("#c7ccd4"), hex("#7b828e"))
        case .green:  return (hex("#4cc28a"), hex("#93e2bb"), hex("#2f9a68"))
        case .yellow: return (hex("#f0cc45"), hex("#fae79a"), hex("#c9a227"))
        case .orange: return (hex("#f27c32"), hex("#f9b07c"), hex("#c95a1a"))
        }
    }

    /// A teardrop rasterised at this tilt: pixel offsets from the centre
    /// (y down, as the art is written) with a tone each, and the knot.
    private struct Raster { var fill: [(Int, Int, Int)]; var ring: [(Int, Int)]; var knot: (Double, Double) }
    private static var cache: [String: Raster] = [:]
    private static func raster(w: Int, h: Int, angle: Double) -> Raster {
        let key = "\(w)x\(h)@\(Int((angle / 2).rounded()) * 2)"
        if let hit = cache[key] { return hit }
        let a = Double(w) / 2, b = Double(h) / 2
        let th = Double(Int((angle / 2).rounded()) * 2) * .pi / 180
        let cs = cos(th), sn = sin(th)
        var fill: [(Int, Int, Int)] = []
        var solid = Set<Int>()
        let r = max(w, h) / 2 + 3
        func key2(_ x: Int, _ y: Int) -> Int { (y + 64) * 256 + (x + 64) }
        for y in -r...r {
            for x in -r...r {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                let lx = fx * cs + fy * sn, ly = -fx * sn + fy * cs
                let dx = lx / a, dy = ly / b
                let sq = 1 + max(0, dy) * 0.18
                let r2 = (dx * sq) * (dx * sq) + dy * dy
                guard r2 <= 1 else { continue }
                var tone = 0
                if r2 > 0.62 && dx + dy > 0.35 { tone = 2 }
                if dx > -0.62 && dx < -0.34 && dy > -0.66 && dy < -0.38 { tone = 1 }
                fill.append((x, y, tone)); solid.insert(key2(x, y))
            }
        }
        let kx = -(b + 1) * sn, ky = (b + 1) * cs
        for (ox, oy) in [(0, 0), (-1, 0), (1, 0), (0, 1)] {
            let p = (Int(kx.rounded()) + ox, Int(ky.rounded()) + oy)
            fill.append((p.0, p.1, 2)); solid.insert(key2(p.0, p.1))
        }
        var ring: [(Int, Int)] = [], seen = Set<Int>()
        for (x, y, _) in fill {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let k = key2(x + dx, y + dy)
                if !solid.contains(k), seen.insert(k).inserted { ring.append((x + dx, y + dy)) }
            }
        }
        let out = Raster(fill: fill, ring: ring, knot: (kx, ky + 2))
        cache[key] = out
        return out
    }

    /// Where the string meets the balloon, in view points.
    static func knot(_ s: BalloonScene) -> NSPoint {
        let r = raster(w: s.pixels.w, h: s.pixels.h, angle: s.angle)
        let c = snapped(s.center)
        return NSPoint(x: c.x + (CGFloat(r.knot.0) + 0.5) * pixel, y: c.y - CGFloat(r.knot.1) * pixel)
    }

    private static func snapped(_ p: NSPoint) -> NSPoint {
        NSPoint(x: (p.x / pixel).rounded() * pixel, y: (p.y / pixel).rounded() * pixel)
    }

    /// The body, tilt and number, drawn once into an image and reused: a
    /// swinging balloon only moves, and filling a few hundred pixels one at a
    /// time on every frame it moves was most of what the balloon cost.
    private static var bodies: [String: (image: NSImage, half: CGFloat)] = [:]
    private static func body(_ s: BalloonScene) -> (image: NSImage, half: CGFloat) {
        let bucket = Int((s.angle / 2).rounded()) * 2
        let key = "\(s.pixels.w)x\(s.pixels.h)@\(bucket)/\(s.colour)/\(s.number)/\(s.unit)"
        if let hit = bodies[key] { return hit }
        if bodies.count > 400 { bodies.removeAll() }
        let r = raster(w: s.pixels.w, h: s.pixels.h, angle: s.angle)
        let half = CGFloat(max(s.pixels.w, s.pixels.h) / 2 + 4) * pixel
        let image = NSImage(size: NSSize(width: 2 * half, height: 2 * half))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        let c = NSPoint(x: half, y: half), t = tones(s.colour)
        func px(_ x: Int, _ y: Int) -> NSRect {
            NSRect(x: c.x + CGFloat(x) * pixel, y: c.y - CGFloat(y + 1) * pixel, width: pixel, height: pixel)
        }
        ink.setFill()
        for (x, y) in r.ring { px(x, y).fill() }
        for (x, y, tone) in r.fill {
            (tone == 0 ? t.fill : tone == 1 ? t.light : t.shade).setFill()
            px(x, y).fill()
        }
        let big = rounded(size: s.pixels.w > 20 ? 14 : 12, weight: .heavy)
        let small = rounded(size: 7.5, weight: .bold)
        drawCentered(s.number, font: big, colour: ink, at: NSPoint(x: c.x + 1, y: c.y + 3))
        if !s.unit.isEmpty { drawCentered(s.unit, font: small, colour: ink, at: NSPoint(x: c.x + 1, y: c.y - 8)) }
        image.unlockFocus()
        bodies[key] = (image, half)
        return (image, half)
    }

    static func drawBody(_ s: BalloonScene) {
        let b = body(s), c = snapped(s.center)
        NSGraphicsContext.current?.imageInterpolation = .none
        b.image.draw(in: NSRect(x: c.x - b.half, y: c.y - b.half, width: 2 * b.half, height: 2 * b.half),
                     from: .zero, operation: .sourceOver, fraction: s.alpha)
    }

    static func drawString(from knot: NSPoint, to hand: NSPoint, bow: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath()
        path.move(to: knot)
        let mid = NSPoint(x: (knot.x + hand.x) / 2 + bow, y: (knot.y + hand.y) / 2)
        path.curve(to: hand, controlPoint1: mid, controlPoint2: mid)
        path.lineWidth = 1
        stringColour.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    static func drawTag(_ text: String, colour: DiskBalloon.Colour, alpha: CGFloat,
                        near s: BalloonScene, within bounds: NSRect) {
        let font = rounded(size: 8, weight: .heavy)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = size.width + 10, h = size.height + 3
        let top = snapped(s.center).y + CGFloat(s.pixels.h) * pixel / 2
        var x = snapped(s.center).x + CGFloat(s.pixels.w) * pixel / 2 - w / 2
        x = min(max(x, bounds.minX + 2), bounds.maxX - w - 2)
        let y = min(top - h / 2, bounds.maxY - h - 2)
        let rect = NSRect(x: x, y: y, width: w, height: h)
        let pill = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
        tones(colour).fill.withAlphaComponent(alpha).setFill(); pill.fill()
        pill.lineWidth = 1; ink.withAlphaComponent(alpha).setStroke(); pill.stroke()
        drawCentered(text, font: font, colour: ink.withAlphaComponent(alpha),
                     at: NSPoint(x: rect.midX, y: rect.midY))
    }

    /// Built once each: making a font is far dearer than drawing with one,
    /// and this draws fifteen times a second.
    private static var fonts: [String: NSFont] = [:]
    private static func rounded(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let key = "\(size)/\(weight.rawValue)"
        if let f = fonts[key] { return f }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let f = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        fonts[key] = f
        return f
    }

    private static func drawCentered(_ text: String, font: NSFont, colour: NSColor, at p: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2),
                                withAttributes: attrs)
    }
}
