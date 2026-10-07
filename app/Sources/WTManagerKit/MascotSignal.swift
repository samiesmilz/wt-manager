import AppKit

/// Character art may vary. The status display has one size, palette and meaning.
/// Colour is isolated by a light outer border and dark inner border, and each
/// mood also has its own glyph so it remains distinguishable without colour.
public enum MascotSignal {
    public static let moods = ["lost", "working", "alarmed", "nudging", "burdened", "calm", "proud", "asleep"]
    public static let ink = "#171b26"
    public static let border = "#f6f8ff"
    public static let colors = ["lost": "#8b93a1", "working": "#4a9fd8", "alarmed": "#e0604c",
        "nudging": "#e0a33c", "burdened": "#e0a33c", "calm": "#4a9fd8", "proud": "#3fb27f", "asleep": "#3fb27f"]
    private static let glyphs = [
        "lost": ["##.", "..#", ".#.", "...", ".#."],
        "working": ["...", "...", ".#.", "...", "..."],
        "alarmed": [".#.", ".#.", ".#.", "...", ".#."],
        "nudging": ["#..", ".#.", "..#", ".#.", "#.."],
        "burdened": ["###", "...", "###", "...", "..."],
        "calm": ["...", "...", "###", "...", "..."],
        "proud": ["...", "..#", "#.#", ".#.", "..."],
        "asleep": ["###", "..#", ".#.", "#..", "###"]
    ]

    /// Nine pixels square at menu-bar size. The 5x5 colour field is constant;
    /// the glyph carries the meaning, not the amount of coloured decoration.
    public static func rows(mood: String) -> [String] {
        let glyph = glyphs[mood] ?? glyphs["lost"]!
        var rows = Array(repeating: Array(repeating: Character("l"), count: 9), count: 9)
        for y in 1..<8 { for x in 1..<8 { rows[y][x] = "k" } }
        for y in 2..<7 { for x in 2..<7 { rows[y][x] = "c" } }
        for y in 0..<5 { for (x, ch) in glyph[y].enumerated() where ch == "#" { rows[y + 2][x + 3] = "k" } }
        return rows.map { String($0) }
    }

    public static func adding(to image: NSImage, mood: String, tint: String? = nil,
                              facesLeft: Bool = false) -> NSImage {
        let result = NSImage(size: image.size)
        let scale: CGFloat = 1
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        if facesLeft {
            let context = NSGraphicsContext.current?.cgContext
            context?.saveGState(); context?.translateBy(x: image.size.width, y: 0); context?.scaleBy(x: -1, y: 1)
            image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            context?.restoreGState()
        } else { image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1) }
        draw(mood: mood, tint: tint, at: NSPoint(x: image.size.width - 9 * scale, y: 0), scale: scale)
        result.unlockFocus()
        return result
    }

    static func draw(mood: String, tint: String? = nil, at origin: NSPoint, scale: CGFloat) {
        let palette = ["l": Ink.color(border)!, "k": Ink.color(ink)!, "c": (tint.flatMap { Ink.color($0) } ?? Ink.color(colors[mood] ?? colors["lost"]!)!)]
        for (y, row) in rows(mood: mood).enumerated() {
            for (x, ch) in row.enumerated() {
                palette[String(ch)]?.setFill()
                NSRect(x: origin.x + CGFloat(x) * scale, y: origin.y + CGFloat(8 - y) * scale,
                       width: scale, height: scale).fill()
            }
        }
    }
}
