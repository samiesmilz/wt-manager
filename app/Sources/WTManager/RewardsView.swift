import SwiftUI
import WTManagerKit

struct UpdateBanner: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: UpdateChecker
    var body: some View {
        if let url = updates.availableURL, let release = updates.release,
           (release.tagName != store.dismissedUpdate || updates.showStatus) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.brand)
                Text("wt-manager \(release.tagName) is ready")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Link("See update", destination: url).font(.system(size: 12))
                Button { store.dismissedUpdate = release.tagName; updates.showStatus = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss this update")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Palette.brand.opacity(0.08))
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

struct CleanupScoreCard: View {
    @ObservedObject var store: Store
    private var growth: String {
        guard let change = store.history.growthKb else { return "One more full scan will establish a growth trend." }
        if change == 0 { return "No change since the previous full measurement." }
        return "\(change > 0 ? "+" : "−")\(Store.human(abs(change))) since the previous full measurement"
    }
    var body: some View {
        Card(title: "your space", tint: Palette.reclaim, symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.history.rank).font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("\(store.history.reclaimedKb == 0 ? "0 B" : Store.human(store.history.reclaimedKb)) reclaimed · \(store.history.cleanups) cleanup\(store.history.cleanups == 1 ? "" : "s")")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: store.history.level == 0 ? "leaf.fill" : "star.circle.fill")
                        .font(.system(size: 26)).foregroundStyle(Palette.inkReclaim)
                }
                ProgressView(value: store.history.levelFraction)
                    .tint(Palette.reclaim)
                    .accessibilityLabel("Progress toward next reclaim milestone")
                if let next = store.history.nextMilestoneKb {
                    Text("\(Store.human(next - store.history.reclaimedKb)) to the next badge")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                } else {
                    Text("Space Legend unlocked. Every safe cleanup still counts.")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.inkReclaim)
                }
                Hairline()
                if let sample = store.history.latest {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Store.human(sample.totalKb)).font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("in watched checkouts").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Text(growth).font(.system(size: 11, weight: .medium))
                        .foregroundStyle((store.history.growthKb ?? 0) > 0 ? Palette.inkRisk : Palette.inkReclaim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Store.human(sample.rebuildableKb)) rebuildable · measured \(sample.at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.history.samples.count > 1 {
                        SpaceSparkline(samples: store.history.samples).frame(height: 34)
                    }
                } else {
                    Text("A full disk scan starts your local space history.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Text("Rewards count confirmed reclaimed space, including partial successes. Estimates stay on this Mac.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SpaceSparkline: View {
    let samples: [DiskSample]
    var body: some View {
        Canvas { context, size in
            let values = Array(samples.suffix(48)).map { Double($0.totalKb) }
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                                    y: 3 + (1 - (v - low) / span) * (size.height - 6))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(Palette.reclaim), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityLabel("Watched checkout size over the last \(min(samples.count, 48)) full scans")
        .accessibilityHidden(true) // The adjacent text carries the measured values.
    }
}

/// One bounded burst, driven only by a confirmed result. No forever-running timer.
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
