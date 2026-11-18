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

struct PixelCelebration: View {
    var previewElapsed: TimeInterval? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { clock in
                Canvas { context, size in
                    let elapsed = previewElapsed ?? clock.date.timeIntervalSince(started)
                    guard elapsed >= 0, elapsed < 2.8 else { return }
                    let t = elapsed / 2.8
                    let colors: [Color] = [Palette.reclaim, Palette.brand, .orange, .purple]
                    for i in 0..<44 {
                        let seed = Double((i * 37) % 101) / 100
                        let spread = (seed - 0.5) * size.width * 0.92
                        let x = size.width / 2 + spread * min(1, t * 2.4)
                        let y = size.height * 0.24 - sin(t * .pi) * (70 + Double(i % 7) * 9) + t * t * size.height * 0.65
                        let side = CGFloat(3 + i % 4)
                        context.opacity = min(1, (1 - t) * 2)
                        context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(colors[i % colors.count]))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}
