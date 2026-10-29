import SwiftUI
import WTManagerKit

// MARK: - shared

struct WityView: View {
    @ObservedObject var store: Store
    /// The clock, observed here and nowhere else in the window, so a tail that
    /// moves does not re-lay out a list of fifty worktrees behind it.
    @ObservedObject private var pulse = Pulse.shared
    /// The height to draw at — of the bitmap *and* of the view.
    ///
    /// It used to size only the bitmap: the image was `.resizable()` with no
    /// frame, so the view took whatever its parent offered and a 44pt
    /// character came out 460pt tall in the first layout that did not happen
    /// to wrap it. A parameter called `height` that does not set the height is
    /// a trap with one survivor — the call site that already knew.
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let image = store.image(height: height, frame: reduceMotion ? 0 : pulse.wag, blinking: !reduceMotion && pulse.blinking, detailed: height >= 32) {
            if height >= 32 && !store.usingOwnImage && store.mascot?.companion?.sprites["\(store.figure)/open/0"] != nil {
                Image(nsImage: image).interpolation(.none).frame(width: height, height: height)
            } else {
                Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: height)
            }
        } else {
            Image(systemName: "leaf").font(.system(size: height * 0.5)).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x8b93a1
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// One hairline, used for every division in the app.
///
/// `Divider()` picks its own colour and inset per context, so a window full of
/// them is a window full of subtly different lines. A single rule, drawn the
/// same way at the same weight, is what makes a list read as one table rather
/// than as rows that happen to be near each other.
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The first run: one screen, with the question already answered.
///
/// Not a wizard. The tool has exactly one setting that matters — where the
/// repositories are — and it can find them itself in about a second, so the
/// screen that would have asked arrives holding the answer. A wizard is a
/// sequence, one value is not a sequence, and the people who skip a wizard are
/// exactly the people who then have nothing configured.
///
/// This is also the empty state the window needed anyway. It had none, which
/// is why a fresh install rendered `wt-manager exited 2:` in a card headed
/// "error" — the tool's very first sentence to a new person was a fault report
/// about a question it could have answered without asking.
struct FirstRun: View {
    @ObservedObject var store: Store
    @State private var chosen: Set<String> = []

    private var found: [RootCandidate] { store.candidates }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(found.isEmpty ? "Where do you keep your repositories?"
                                       : "Found your repositories.")
                        .font(.system(size: 15, weight: .semibold))
                    Text(found.isEmpty
                         ? "Nothing turned up in the usual folders, so point me at yours."
                         : "Scanned the usual folders. Pick the ones to watch.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if !found.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Hairline() }
                            row(c)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                }

                HStack(spacing: 10) {
                    if !found.isEmpty {
                        Button(store.adopting ? "Reading…" : "Watch \(chosen.count == 1 ? "this folder" : "these \(chosen.count) folders")") {
                            store.adopt(roots: found.map(\.root).filter(chosen.contains))
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen.isEmpty || store.adopting)
                    }
                    Button(found.isEmpty ? "Choose a folder…" : "Choose another…") {
                        store.chooseRoot()
                    }
                    .disabled(store.adopting)
                    if store.adopting { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }

                // Said once, here, because this is the only screen where
                // someone is deciding whether to hand a tool their whole
                // source tree.
                Text("Nothing is written to your repositories. Reading them takes a few seconds; "
                     + "measuring what they hold on disk runs after, and takes longer.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Everything found is on by default: the common case is "yes, those",
        // and a list of unticked boxes makes the person do the work the scan
        // just did for them.
        .onAppear { chosen = Set(found.map(\.root)) }
        .onChange(of: found) { c in chosen = Set(c.map(\.root)) }
    }

    private func row(_ c: RootCandidate) -> some View {
        Button {
            if chosen.contains(c.root) { chosen.remove(c.root) } else { chosen.insert(c.root) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: chosen.contains(c.root) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(chosen.contains(c.root) ? Color.accentColor : Palette.muted)
                Text(c.display).font(.system(size: 12.5))
                Spacer(minLength: 8)
                Text("\(c.repos) repo\(c.repos == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(radius: 8))
    }
}


/// A settled result stays visible after its modal closes.
struct CompletionBanner: View {
    @ObservedObject var store: Store
    let plan: Store.Plan
    private var issues: Bool { (plan.result?.failed ?? 0) > 0 }
    private var tint: Color { issues ? Palette.status((plan.result?.completedPaths.isEmpty ?? true) ? "blocked" : "stale") : Palette.reclaim }
    private var title: String {
        guard let r = plan.result else { return "Operation finished" }
        if issues && r.completedPaths.isEmpty { return "Operation needs attention" }
        if issues { return "Finished with \(r.failed) issue\(r.failed == 1 ? "" : "s")" }
        if plan.action.folders { return "Deleted \(r.removed) folder\(r.removed == 1 ? "" : "s")" }
        return plan.action.kind == .reap ? "Removed \(r.removed) worktree\(r.removed == 1 ? "" : "s")" : "Cleanup complete"
    }
    /// Where this run put what it saved: edits, bundles, set-aside files.
    /// Said here because the sheet that named it has closed by the time
    /// anyone wonders where their work went.
    private var savedIn: String? {
        guard let p = plan.preview else { return nil }
        let dir = !p.changesKeptIn.isEmpty ? p.changesKeptIn : p.keptIn
        return dir.isEmpty ? nil : dir
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: issues ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 19)).foregroundStyle(Palette.ink(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(issues ? "Some work could not finish. Review the result for details."
                     : (plan.result?.freedKb ?? 0) > 0 ? "\(Store.human(plan.result?.freedKb ?? 0)) freed" : "Operation confirmed · review the details")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if (plan.result?.freedKb ?? 0) > 0 && !(plan.result?.completedPaths.isEmpty ?? true) {
                    // The running total, worded apart from this cleanup's own
                    // figure above it: two "reclaimed" numbers side by side
                    // read as one contradicting the other.
                    Text("✦ \(store.history.rank) · \(Store.human(store.history.reclaimedKb)) freed in all"
                         + (store.history.nextMilestoneKb.map { next in
                             " · \(Store.human(next - store.history.reclaimedKb)) to \(store.history.nextRank ?? "")" } ?? ""))
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.inkReclaim)
                }
            }
            Spacer(minLength: 4)
            if let savedIn, !(plan.result?.completedPaths.isEmpty ?? true) {
                Button("Show saved work") { NSWorkspace.shared.open(URL(fileURLWithPath: savedIn)) }
                    .controlSize(.small)
                    .help(savedIn)
            }
            Button("View result") { store.plan = plan }.controlSize(.small)
            Button { store.completion = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss operation result")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(tint.opacity(0.09))
        .accessibilityElement(children: .contain)
    }
}

struct MergeSpeechBanner: View {
    @ObservedObject var store: Store
    let nudge: MergeNudge
    var compact = false
    var onReview: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !compact { WityView(store: store, height: 32).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "PR #\(nudge.number) merged!").font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(message).font(.system(size: 11)).lineLimit(compact ? 3 : nil).help(message).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Review checkout") { store.preview(Store.Action(kind: .reap, paths: nudge.paths)); onReview?() }
                        .controlSize(.small).disabled(store.busy || store.plan != nil)
                    if let row = LinkedPRSummary.groups(store.envelope?.worktrees ?? []).first(where: { $0.id == nudge.id }),
                       let url = row.webURL {
                        Link("Open PR", destination: url).controlSize(.small)
                    }
                    Button("Dismiss") { store.dismissMerge(nudge.id) }.controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.green.opacity(0.09))
        .overlay(Rectangle().stroke(Color.green.opacity(0.4), lineWidth: 2))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
    private var message: String {
        if compact { return "\(nudge.repo) — let’s review this local checkout before removing anything." }
        let space = nudge.occupiedKb.map { $0 == 0 ? " This checkout uses 0 B." : " About \(Store.human($0)) is still on disk." } ?? " Space has not been measured yet."
        return "\(nudge.repo) — let’s review the local checkout." + space
            + (nudge.blocked ? " Local work or another blocker needs attention." : " Removal is checked again before anything changes.")
    }
}
