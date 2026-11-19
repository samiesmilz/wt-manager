import SwiftUI
import WTManagerKit

struct UpdateBanner: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: UpdateChecker
    var body: some View {
        if let url = updates.availableURL, let release = updates.release,
           (release.tagName != store.dismissedUpdate || updates.showStatus) {
            Banner(tone: .info, symbol: "arrow.up",
                   title: "wt-manager \(release.tagName) is available",
                   detail: "Updates are announced, never installed for you",
                   onDismiss: { store.dismissedUpdate = release.tagName; updates.showStatus = false }) {
                Button("Release notes") { NSWorkspace.shared.open(url) }
            }
        } else if updates.showStatus {
            HStack(spacing: 10) {
                if updates.checking { ProgressView().controlSize(.small) }
                Text(updates.status).font(.system(size: 11))
                Spacer(minLength: 4)
                Button { updates.showStatus = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss update check status")
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
    }
}

/// A cleanup landing: a burst of pixels from the figure that just changed, in
/// the app's own colours, gone in under two seconds. Squares on a whole-pixel
/// grid, like the mascot they belong with.
struct PixelCelebration: View {
    var previewElapsed: TimeInterval? = nil
    /// Where the burst starts, as a fraction of the view.
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.3)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    private static let life: Double = 1.8

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { clock in
                Canvas { context, size in
                    let elapsed: Double = previewElapsed ?? clock.date.timeIntervalSince(started)
                    guard elapsed >= 0, elapsed < Self.life else { return }
                    let colors: [Color] = [Palette.safeInk, Palette.rust, Palette.reclaim, Palette.risk, Color.primary]
                    let ox: Double = size.width * origin.x, oy: Double = size.height * origin.y
                    // Air drag: fast out of the gate, then drifting.
                    let reach: Double = (1 - exp(-3.2 * elapsed)) / 3.2
                    let fade: Double = min(1, max(0, (Self.life - elapsed) / 0.55))
                    for i in 0..<64 {
                        let a: Double = Double((i * 73) % 101) / 100
                        let b: Double = Double((i * 41) % 97) / 96
                        // A fan opening upward, a little wider than a half circle.
                        let angle: Double = -Double.pi * (0.04 + 0.92 * a)
                        let speed: Double = 260 + 520 * b
                        let late: Double = Double(i % 4) * 0.035
                        let t: Double = max(0, elapsed - late)
                        let r: Double = (1 - exp(-3.2 * t)) / 3.2
                        var x: Double = ox + cos(angle) * speed * r
                        var y: Double = oy + sin(angle) * speed * r + 380 * t * t
                        _ = reach
                        let side: Double = Double(3 + i % 4)
                        // Whole pixels: the squares step, they do not glide.
                        x = (x / 2).rounded() * 2
                        y = (y / 2).rounded() * 2
                        context.opacity = fade * (t > 0 ? 1 : 0)
                        context.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                                     with: .color(colors[i % colors.count]))
                        // Every sixth one is a four-point spark.
                        if i % 6 == 0 {
                            context.fill(Path(CGRect(x: x - side, y: y, width: side * 3, height: side)),
                                         with: .color(colors[i % colors.count]))
                            context.fill(Path(CGRect(x: x, y: y - side, width: side, height: side * 3)),
                                         with: .color(colors[i % colors.count]))
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}
