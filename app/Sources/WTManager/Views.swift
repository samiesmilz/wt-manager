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
            .fill(Palette.line)
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
                WityView(store: store, height: 56).frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(found.isEmpty ? "Where do you keep your repositories?"
                                       : "Found your repositories")
                        .font(.system(size: 20, weight: .semibold))
                    Text(found.isEmpty
                         ? "Nothing turned up in the usual folders, so point me at yours."
                         : "These are the usual places code lives on this Mac. Untick any you don’t want watched.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !found.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Hairline() }
                            row(c)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Palette.line, lineWidth: 1))
                }

                HStack(spacing: 10) {
                    if !found.isEmpty {
                        Button(store.adopting ? "Reading…" : "Watch \(chosen.count == 1 ? "this folder" : "these \(chosen.count) folders")") {
                            store.adopt(roots: found.map(\.root).filter(chosen.contains))
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.wt(.primary))
                        .disabled(chosen.isEmpty || store.adopting)
                    }
                    Button(found.isEmpty ? "Choose a folder…" : "Choose another…") {
                        store.chooseRoot()
                    }
                    .buttonStyle(.wt(found.isEmpty ? .primary : .secondary))
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
                Image(systemName: chosen.contains(c.root) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(chosen.contains(c.root) ? Palette.action : Palette.muted)
                Text(c.display).font(.system(size: 12, design: .monospaced))
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


/// One shape for everything the window tells you between pages: a cleanup's
/// result, a merged pull request, an update. A tinted card, never a strip.
struct BannerCard: ViewModifier {
    var tint: Color
    var outer: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.wash(tint))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.edge(tint), lineWidth: 1)))
            .padding(.horizontal, outer).padding(.vertical, 8)
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
        return plan.action.kind == .reap ? "Deleted \(Store.count(r.removed, "folder"))" : "Cleanup complete"
    }
    /// Where this run put what it saved: edits, bundles, set-aside files.
    /// Said here because the sheet that named it has closed by the time
    /// anyone wonders where their work went.
    private var savedIn: String? {
        guard let p = plan.preview else { return nil }
        let dir = !p.changesKeptIn.isEmpty ? p.changesKeptIn : p.keptIn
        return dir.isEmpty ? nil : dir
    }
    private var headline: String {
        guard let r = plan.result else { return title }
        if issues, !r.completedPaths.isEmpty, plan.action.kind == .reap {
            return "Deleted \(r.completedPaths.count) of \(r.completedPaths.count + r.failed) folders"
        }
        if !issues, r.freedKb > 0 { return "Freed " + Store.human(r.freedKb) }
        return title
    }
    private var detail: String {
        guard let r = plan.result else { return "" }
        if issues {
            return (r.failed == 1 ? "One folder was" : "\(r.failed) folders were") + " left in place. Nothing was lost."
        }
        var parts: [String] = []
        if plan.action.kind == .reap {
            parts.append(Store.count(max(r.removed, r.completedPaths.count), "folder") + " deleted")
        } else {
            parts.append("Build output only; the folders are still there")
        }
        if store.history.reclaimedKb > 0 { parts.append(Store.human(store.history.reclaimedKb) + " freed so far") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        Banner(tone: issues ? .warning : .success,
               symbol: issues ? "exclamationmark.triangle" : "checkmark",
               title: headline, detail: detail,
               onDismiss: { store.completion = nil }) {
            if savedIn != nil, !(plan.result?.completedPaths.isEmpty ?? true), plan.action.kind == .reap {
                Button("See what was kept") { store.page = .kept; store.completion = nil }
            }
            Button(issues ? "Details" : "View result") { store.plan = plan }
        }
    }
}

struct MergeSpeechBanner: View {
    @ObservedObject var store: Store
    let nudge: MergeNudge
    var compact = false
    var onReview: (() -> Void)? = nil
    var body: some View {
        if compact {
            compactBody
        } else {
            Banner(tone: .info, symbol: "arrow.triangle.merge",
                   title: "PR #\(nudge.number) merged", detail: message,
                   onDismiss: { store.dismissMerge(nudge.id) }) {
                Button("Review") { store.preview(Store.Action(kind: .reap, paths: nudge.paths)); onReview?() }
                    .disabled(store.busy || store.plan != nil)
            }
        }
    }
    private var compactBody: some View {
        HStack(alignment: .top, spacing: 10) {
            if !compact { WityView(store: store, height: 32).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "PR #\(nudge.number) merged").font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 11)).lineLimit(compact ? 3 : nil).help(message).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Review checkout") { store.preview(Store.Action(kind: .reap, paths: nudge.paths)); onReview?() }
                        .buttonStyle(.wt(.quiet)).disabled(store.busy || store.plan != nil)
                    if let row = LinkedPRSummary.groups(store.envelope?.worktrees ?? []).first(where: { $0.id == nudge.id }),
                       let url = row.webURL {
                        Link("Open PR", destination: url).controlSize(.small)
                    }
                    Button("Dismiss") { store.dismissMerge(nudge.id) }.buttonStyle(.wt(.quiet))
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(BannerCard(tint: Palette.brand, outer: compact ? 0 : 20))
        .accessibilityElement(children: .contain)
    }
    private var message: String {
        if compact { return "\(nudge.repo) — let’s review this local checkout before removing anything." }
        let space = nudge.occupiedKb.map { $0 == 0 ? " This checkout uses 0 B." : " About \(Store.human($0)) is still on disk." } ?? " Space has not been measured yet."
        return "\(nudge.repo): the local checkout can be reviewed." + space
            + (nudge.blocked ? " Local work or another blocker needs attention." : " Removal is checked again before anything changes.")
    }
}

// MARK: the design's banner

enum BannerTone { case success, info, warning, error }

/// One pattern for everything the window says between pages: a mark, a bold
/// line, one muted line under it, its action on the right, and a close box.
/// White for news; the warm ground for what needs attention.
struct Banner<Actions: View>: View {
    let tone: BannerTone
    let symbol: String
    let title: String
    let detail: String
    var outer: CGFloat = 28
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    private var ink: Color {
        switch tone {
        case .success: return Palette.safeInk
        case .info: return Palette.agentInk
        case .warning: return Palette.riskInk
        case .error: return Palette.danger
        }
    }
    private var warm: Bool { tone == .warning || tone == .error }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { actions() }.buttonStyle(.wt(.quiet))
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(warm ? Palette.warnFill : Palette.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(warm ? Palette.warnLine : Palette.line, lineWidth: 1))
        .padding(.horizontal, outer).padding(.top, outer > 0 ? 14 : 0)
        .accessibilityElement(children: .contain)
    }
}

/// The sidebar, folded into a strip of chips for a narrow window.
struct ChipBar: View {
    @ObservedObject var store: Store

    private struct Chip {
        let title: String
        let dot: Color?
        let on: Bool
        let run: () -> Void
    }

    private var chips: [Chip] {
        var out: [Chip] = []
        let rows: [Worktree] = store.folderRows
        let plain: Bool = store.page == .folders && store.verdictFilter == nil && store.locationFilter == nil
        out.append(Chip(title: "All \(rows.count)", dot: nil, on: plain) {
            store.page = .folders; store.verdictFilter = nil; store.locationFilter = nil
        })
        for v in FoldersView.Verdict.allCases {
            let n: Int = rows.filter { $0.folder?.verdict == v.rawValue }.count
            if n == 0 { continue }
            let on: Bool = store.page == .folders && store.verdictFilter == v.rawValue
            let short: String = ["safe": "Safe", "busy": "In progress", "agent": "Agent",
                                 "unsaved": "Unsaved", "kept": "Kept"][v.rawValue] ?? v.label
            out.append(Chip(title: short + " \(n)", dot: v.tint, on: on) {
                store.page = .folders
                store.verdictFilter = on ? nil : v.rawValue
            })
        }
        out.append(Chip(title: "Locations", dot: nil, on: store.page == .locations) {
            store.locationFilter = nil; store.page = .locations
        })
        out.append(Chip(title: "Kept files", dot: nil, on: store.page == .kept) { store.page = .kept })
        out.append(Chip(title: "Mascots", dot: nil, on: store.page == .mascots) { store.page = .mascots })
        out.append(Chip(title: "Settings", dot: nil, on: false) { store.showingSettings = true })
        return out
    }

    private func row(_ items: [Chip]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, chip in
                Button(action: chip.run) {
                    HStack(spacing: 6) {
                        if let dot = chip.dot { Circle().fill(dot).frame(width: 8, height: 8) }
                        Text(chip.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(chip.on ? Palette.onAction : Color.primary)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(chip.on ? Palette.action : Palette.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(chip.on ? Palette.action : Palette.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chip.on ? .isSelected : [])
            }
        }
    }

    var body: some View {
        let all: [Chip] = chips
        let half: Int = (all.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            row(all)
            VStack(alignment: .leading, spacing: 8) {
                row(Array(all.prefix(max(half, 5))))
                row(Array(all.dropFirst(max(half, 5))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Palette.rail)
    }
}

/// The menu-bar menu's summary, as the design draws it: what could be freed,
/// then each verdict with folders in it.
struct MenuSummary: View {
    let free: String?
    let rows: [(String, Color, Int, Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let free {
                VStack(alignment: .leading, spacing: 1) {
                    Text(free).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.safeInk)
                    Text("you could free").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                .padding(.bottom, rows.isEmpty ? 0 : 10)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 9) {
                    Circle().fill(r.1).frame(width: 8, height: 8)
                    Text(r.0).font(.system(size: 13, weight: r.3 ? .semibold : .regular))
                    Spacer(minLength: 16)
                    Text("\(r.2)").font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.muted)
                }
                .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 280, alignment: .leading)
    }
}
