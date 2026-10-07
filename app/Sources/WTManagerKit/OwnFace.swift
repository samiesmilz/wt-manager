import AppKit

/// A picture the person chose, reduced to the grid the cast is drawn on.
///
/// The hard part is not drawing it. It is that the mascot is an *instrument* —
/// its eyes, its colour and its motion carry the mood — and none of those
/// channels exist on someone's photo of their dog. Painting eyes onto an
/// arbitrary image is not possible; pretending the image carries a state it
/// cannot carry would be worse, because the one thing this app must never do
/// is look confident while saying nothing.
///
/// So the image keeps the identity and gives up the instrument, and the status
/// moves to the outline drawn around it, in the same tint the character would
/// have used. One honest channel instead of three that would all be lying.
///
/// And it is *pixelated*, to the same 22 cells the characters occupy. A
/// photograph dropped in beside them at full resolution does not read as a
/// different mascot, it reads as a bug — the whole window is drawn at one
/// pixel density and a smooth image is the only thing in it that is not.
public enum OwnFace {
    /// Tests use a private directory so adopting a picture never writes to the
    /// user's actual Application Support folder.
    static var storageDirectoryOverride: URL?

    /// The grid. The same width as a sprite, so a face lands on the same cells
    /// the cast's faces land on and the two can sit side by side.
    public static let side = 22

    /// Levels per channel. Five is the fewest that keeps a face recognisable
    /// and the most that still reads as chosen rather than photographed:
    /// above about eight the banding disappears and it is a small photo again.
    public static let levels = 5

    /// Where a chosen image is kept.
    ///
    /// Copied in rather than referenced where it was found: someone who picks
    /// a file out of their Downloads folder and then tidies up should not have
    /// their mascot vanish, and a sandboxed read of a path from six months ago
    /// is a permission prompt at launch.
    public static var storedURL: URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride.appendingPathComponent("mascot.png")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("wt-manager/mascot.png")
    }

    public static var exists: Bool {
        FileManager.default.isReadableFile(atPath: storedURL.path)
    }

    /// Crop square, reduce to the grid, flatten the palette, store.
    ///
    /// Downsampled with `.high` and not with nearest: averaging each cell over
    /// the region it covers is what keeps a face legible at 22 pixels, where
    /// sampling one pixel out of every hundred returns whatever that pixel
    /// happened to be. The blockiness comes from the grid; it does not need
    /// help from a bad filter.
    @discardableResult
    public static func adopt(_ source: URL) -> Bool {
        guard let image = NSImage(contentsOf: source) else { return false }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        // Centre-cropped to a square. A tall photo letterboxed into a round
        // mask is two slivers of face and a lot of background.
        let edge = Swift.min(size.width, size.height)
        let crop = NSRect(x: (size.width - edge) / 2, y: (size.height - edge) / 2,
                          width: edge, height: edge)
        let n = side
        guard let small = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n),
                   from: crop, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // Flatten the palette in place. Posterising *after* the downsample,
        // not before: averaging first and quantising second keeps the bands
        // where the shapes are, which is what a person drawing this by hand
        // would do.
        let step = 255.0 / Double(levels - 1)
        for y in 0..<n {
            for x in 0..<n {
                guard let c = small.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }
                func snap(_ v: CGFloat) -> CGFloat {
                    CGFloat((Double(v) * 255 / step).rounded() * step / 255)
                }
                small.setColor(NSColor(deviceRed: snap(c.redComponent),
                                       green: snap(c.greenComponent),
                                       blue: snap(c.blueComponent),
                                       alpha: 1),
                               atX: x, y: y)
            }
        }
        guard let png = small.representation(using: .png, properties: [:])
        else { return false }
        do {
            try FileManager.default.createDirectory(
                at: storedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try png.write(to: storedURL, options: .atomic)
            cache = nil
            return true
        } catch {
            return false
        }
    }

    public static func forget() {
        try? FileManager.default.removeItem(at: storedURL)
        cache = nil
    }

    /// Decoded once. The menu bar redraws several times a second, and reading
    /// a PNG off disk for each of those is the kind of cost that only shows up
    /// as a warm laptop.
    private static var cache: NSBitmapImageRep?

    /// Which cells are inside the face, and which ring it.
    ///
    /// A disc computed on the grid, not a smooth circle clipped afterwards: a
    /// clipped circle has an antialiased edge, and one soft edge in a window
    /// of hard ones is the thing that looks wrong. The ring is derived from
    /// the disc exactly the way the sprites derive their outline — a cell
    /// outside the mass that touches it — so the two are outlined by the same
    /// rule and cannot disagree about what an edge looks like.
    static func disc(_ n: Int) -> (inside: [[Bool]], ring: [[Bool]]) {
        let c = Double(n - 1) / 2
        let r = Double(n) / 2 - 0.5
        var inside = Array(repeating: Array(repeating: false, count: n), count: n)
        for y in 0..<n {
            for x in 0..<n {
                let dx = Double(x) - c, dy = Double(y) - c
                inside[y][x] = dx * dx + dy * dy <= r * r
            }
        }
        var ring = Array(repeating: Array(repeating: false, count: n), count: n)
        for y in 0..<n {
            for x in 0..<n where !inside[y][x] {
                for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + ox, ny = y + oy
                    if nx >= 0, nx < n, ny >= 0, ny < n, inside[ny][nx] { ring[y][x] = true }
                }
            }
        }
        return (inside, ring)
    }

    /// The face at a size, with the mood as its outline.
    ///
    /// `nil` tint draws the outline dark, the way a sprite's is — which is
    /// what "we do not know yet" should look like, rather than a grey ring
    /// that reads as a state of its own.
    public static func image(fitting height: CGFloat, tint: NSColor?) -> NSImage? {
        if cache == nil, let data = try? Data(contentsOf: storedURL) {
            cache = NSBitmapImageRep(data: data)
        }
        guard let art = cache, art.pixelsWide > 0 else { return nil }

        let n = Swift.min(art.pixelsWide, art.pixelsHigh)
        // Integral cells, and never fewer than one: the whole point is that
        // this lands on the same grid the characters do, and a fractional
        // cell is the smudge that grid exists to avoid.
        let scale = Swift.max(1, floor(height / CGFloat(n)))
        let edge = CGFloat(n) * scale
        let (inside, ring) = disc(n)
        let outline = tint ?? NSColor(srgbRed: 0.10, green: 0.086, blue: 0.078, alpha: 1)

        let out = NSImage(size: NSSize(width: edge, height: edge))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        for y in 0..<n {
            for x in 0..<n {
                let colour: NSColor?
                if inside[y][x] {
                    colour = art.colorAt(x: x, y: y)
                } else if ring[y][x] {
                    colour = outline
                } else {
                    colour = nil
                }
                guard let colour else { continue }
                colour.setFill()
                // The bitmap's rows run top-down; AppKit's origin is bottom-left.
                NSRect(x: CGFloat(x) * scale, y: CGFloat(n - 1 - y) * scale,
                       width: scale, height: scale).fill()
            }
        }
        out.unlockFocus()
        return out
    }
}
