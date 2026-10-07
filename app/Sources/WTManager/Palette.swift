import AppKit
import SwiftUI

/// One palette, used wherever the thing it describes appears.
///
/// Colour here is not decoration — it is the fastest channel the window has, and
/// spending it on anything other than meaning makes it useless for meaning. So
/// every hue is owned by exactly one idea: a branch that is blocked is the same
/// red in the sidebar, in its status dot, in its filter chip and in its row. You
/// learn the vocabulary once.
///
/// Saturated colour is reserved for small marks — dots, icons, bar segments.
/// Anything filling area gets the same hue at low opacity, so a window with
/// eight colours in it still reads as calm. And anything *read* — a word, a
/// number — never gets the mark colour itself: measured against a light window,
/// every status hue fails as text (1.9–3.3:1 against the 4.5 a small label
/// needs). Text takes the `ink` variant, the same hue pulled toward the ground's
/// opposite until it passes, in both appearances.
enum Palette {
    static let brand = Color(red: 0.16, green: 0.39, blue: 0.82)
    /// Semantic, and deliberately not a rainbow: red and orange are the only
    /// warm colours, so warmth always means "this wants something from you".
    static func status(_ s: String) -> Color {
        switch s {
        case "blocked", "review": return Color(red: 0.88, green: 0.32, blue: 0.28)
        case "stale":             return Color(red: 0.91, green: 0.62, blue: 0.20)
        case "waiting":           return Color(red: 0.36, green: 0.66, blue: 0.86)
        case "draft":             return Color(red: 0.55, green: 0.58, blue: 0.66)
        case "active":            return Color(red: 0.35, green: 0.72, blue: 0.55)
        case "merged":            return Color(red: 0.58, green: 0.46, blue: 0.82)
        case "empty":             return Color(red: 0.58, green: 0.60, blue: 0.66)
        case "trunk":             return Color(red: 0.30, green: 0.66, blue: 0.68)
        default:                  return Color.secondary
        }
    }

    /// A section takes the colour of whatever it holds.
    static func section(_ id: String) -> Color {
        switch id {
        case "all":    return Color.accentColor
        case "need":   return status("blocked")
        case "forgot": return status("stale")
        case "flight": return status("active")
        case "others": return status("waiting")
        case "done":   return status("merged")
        case "repos":  return status("trunk")
        case "disk":   return reclaim
        default:       return Color.accentColor
        }
    }

    static let reclaim = Color(red: 0.30, green: 0.70, blue: 0.52)
    static let risk    = Color(red: 0.91, green: 0.55, blue: 0.20)

    /// The engine names an idea, not a colour: the palette owns the mapping.
    static func tint(named name: String) -> Color {
        switch name {
        case "reclaim": return reclaim
        case "risk":    return risk
        case "neutral": return Color(red: 0.55, green: 0.58, blue: 0.66)
        default:        return status(name)
        }
    }

    // MARK: ink — the same hues, for reading

    /// A mark colour made readable as text. In a light appearance the hue is
    /// pulled 38% toward black; in a dark one 18% toward white. Measured: those
    /// are the smallest pulls at which every hue in this palette clears 4.5:1
    /// against a translucent window in that appearance.
    static func ink(_ mark: Color) -> Color {
        dynamic(light: pull(mark, toward: .black, by: 0.38),
                dark: pull(mark, toward: .white, by: 0.18))
    }

    static func ink(status s: String) -> Color { ink(status(s)) }
    static let inkReclaim = ink(reclaim)
    static let inkRisk = ink(risk)

    /// Text that is quieter than the main text but still meant to be read.
    /// Apple's `.secondary` measures 3.85:1 in a light appearance, `.tertiary`
    /// 1.9 and `.quaternary` 1.25 — the last two are not text colours. This is
    /// primary at 62%, which is 5.9 light and 6.5 dark.
    static let muted = Color.primary.opacity(0.62)
    /// Decoration only — chevrons, hairlines, placeholders. Never a word.
    static let faint = Color.primary.opacity(0.32)

    /// The ground of a tinted card, and its edge. A 6% wash is invisible on a
    /// light window (1.05:1 against the ground); these are the values at which
    /// the wash is seen as a surface in both appearances without becoming a fill.
    static func wash(_ tint: Color) -> Color {
        dynamic(light: tint.opacity(0.10), dark: tint.opacity(0.13))
    }
    static func edge(_ tint: Color) -> Color {
        dynamic(light: tint.opacity(0.22), dark: tint.opacity(0.28))
    }

    /// The ground under a selected sidebar row. Accent, not grey, so the rail
    /// says which app it belongs to — but faint, because a selection marks
    /// where you are and does not need to be seen from across the room.
    static let selection = dynamic(light: Color.accentColor.opacity(0.14),
                                   dark: Color.accentColor.opacity(0.24))

    /// Quiet material for information cards. Colour identifies the topic on
    /// the small mark; the reading surface stays consistent across topics.
    static let surface = dynamic(light: Color.white.opacity(0.72),
                                 dark: Color.white.opacity(0.055))
    static let surfaceEdge = dynamic(light: Color.black.opacity(0.085),
                                     dark: Color.white.opacity(0.11))

    /// Solid ground for a badge that carries white text. Constant, not dynamic:
    /// a lighter red in the dark appearance would lose the white on top of it.
    static let badge = pull(status("blocked"), toward: .black, by: 0.25)

    // MARK: categorical

    /// Distinct hues for repos in the disk breakdown. Opacity steps of one hue
    /// read as "more" and "less" of the same thing, which is exactly the wrong
    /// reading for categories that are merely different.
    static let categorical: [Color] = [
        Color(red: 0.36, green: 0.60, blue: 0.86),
        Color(red: 0.38, green: 0.74, blue: 0.58),
        Color(red: 0.90, green: 0.63, blue: 0.27),
        Color(red: 0.72, green: 0.52, blue: 0.84),
        Color(red: 0.88, green: 0.44, blue: 0.42),
        Color(red: 0.34, green: 0.70, blue: 0.72),
        Color(red: 0.80, green: 0.56, blue: 0.44),
        Color(red: 0.52, green: 0.60, blue: 0.72),
    ]

    static func categorical(_ i: Int) -> Color { categorical[i % categorical.count] }

    /// How long something has sat, as a temperature. A gradient rather than a
    /// threshold, because decay is continuous and a cliff at fourteen days would
    /// imply the thirteenth is fine.
    static func age(_ upperDays: Int) -> Color {
        switch upperDays {
        case ..<2:   return status("active")
        case ..<8:   return Color(red: 0.42, green: 0.70, blue: 0.62)
        case ..<15:  return Color(red: 0.72, green: 0.70, blue: 0.34)
        case ..<32:  return status("stale")
        case ..<93:  return Color(red: 0.88, green: 0.46, blue: 0.24)
        default:     return status("blocked")
        }
    }

    // MARK: mechanics

    /// A colour that resolves per appearance, the way system colours do. SwiftUI
    /// has no scheme-aware `Color` of its own; AppKit's dynamic provider follows
    /// the view's effective appearance, which is what `preferredColorScheme`
    /// sets on the window.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    private static func pull(_ c: Color, toward target: NSColor, by k: CGFloat) -> Color {
        guard let a = NSColor(c).usingColorSpace(.sRGB),
              let b = target.usingColorSpace(.sRGB) else { return c }
        return Color(nsColor: NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * k,
                                      green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                                      blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k,
                                      alpha: 1))
    }
}

/// Hover and press for a row or a list entry. A plain button gives neither, and
/// a row that does not answer the pointer reads as a label; one that does not
/// answer a press reads as broken for the fraction of a second it takes to act.
struct RowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var radius: CGFloat = 7
    var inset: CGFloat = 0
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.11 : (hover ? 0.055 : 0)))
                    .padding(.horizontal, inset)
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.995 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Palette.brand.opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.38)))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
