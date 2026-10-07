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

struct Card<C: View>: View {
    let title: String
    var trailing: String?
    /// The card's subject, which colours its mark and tints its ground. Every
    /// card being the same grey is what made the window look like a form.
    var tint: Color = .secondary
    var symbol: String?
    @ViewBuilder var content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink(tint))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.wash(tint)))
                }
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
                    .tracking(0.7).foregroundStyle(Palette.ink(tint))
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                }
            }
            content()
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [tint.opacity(0.055), .clear],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(tint.opacity(0.20), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

// MARK: - overview

/// What nothing else on this window answers.
///
/// It used to be four cards: one recommendation, a risk list, a *verbatim copy*
/// of the three reclaim buttons that are already the whole of the Disk section,
/// and a histogram of how long ago each branch was touched. Half of it was
/// duplication and the histogram was a shape rather than a decision — pretty,
/// and never once acted on. What replaced them is the question the rest of the
/// window cannot answer: the sidebar counts by kind across every repo at once,
/// the list is fifty-seven flat rows, Disk counts bytes — and nothing said
/// *which project* the mess is in.
struct Overview: View {
    @ObservedObject var store: Store
    /// Whether the risk card lists every worktree or only the top five.
    @State private var showAllRisk = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                if let e = store.error {
                    Card(title: "error", tint: Palette.status("blocked"),
                         symbol: "exclamationmark.triangle.fill") {
                        Text(e).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.ink(status: "blocked")).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if store.envelope == nil && store.error == nil {
                    // First launch, before anything is known. Every card below
                    // would otherwise state a fact about an empty machine -
                    // "everything is pushed" - that nothing has established.
                    Card(title: "reading your repos", tint: .secondary, symbol: "hourglass") {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Every worktree is being asked what it holds. Counts come first; disk follows.")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    movesCard
                    CleanupScoreCard(store: store)
                    repoCard
                    riskCard
                }
                if let notices = store.envelope?.notices, !notices.isEmpty {
                    Card(title: "not everything could be read",
                         tint: Palette.status("stale"), symbol: "eye.slash.fill") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(notices, id: \.self) {
                                Text($0).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var movesCard: some View {
        let moves = store.moves
        if !moves.isEmpty {
            // The accent, not the urgency of the first move. This card holds a
            // blocked PR and two reclaim offers at once, and washing all three
            // in the red of the first one says the green ones are alarming
            // too. The colour each move owns is on its own bar; the card is
            // the app talking, and the app has one voice.
            Card(title: "do this next", tint: .accentColor, symbol: "arrow.right.circle.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(moves.enumerated()), id: \.element.id) { i, move in
                        HStack(alignment: .center, spacing: 11) {
                            RoundedRectangle(cornerRadius: 2).fill(move.tint).frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(move.title).font(.system(size: 13, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(move.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if let action = move.action {
                                Button(action.kind == .reap ? "Review removal" : "Review cleanup") {
                                    store.preview(action)
                                }
                                    .controlSize(.small)
                                    .foregroundStyle(Palette.ink(move.tint))
                                    .help("Preview the exact action before anything changes")
                            } else if let w = move.handoff {
                                Button("Open in Terminal") { store.openInTerminal(w) }
                                    .controlSize(.small)
                                    .foregroundStyle(Palette.ink(move.tint))
                                    .help(w.path)
                            }
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 9).fill(move.tint.opacity(0.065)))
                    }
                }
            }
        }
    }

    /// Six rows, because the seventh is never the one you act on. The rest are
    /// reachable by name from the worktree list's filter, which is where you
    /// would go next anyway.
    private static let shown = 6

    @ViewBuilder
    private var repoCard: some View {
        let rows = store.repoRows
        if !rows.isEmpty {
            Card(title: "by project",
                 trailing: "\(rows.count) with something in them",
                 tint: Palette.status("active"), symbol: "square.stack.3d.up.fill") {
                RepoLedger(rows: Array(rows.prefix(Self.shown)), hidden: rows.count - Self.shown) { repo in
                    // Land on the flat list, filtered to this project: the
                    // question "what is going on in ec-website" is answered by
                    // the rows, not by another summary.
                    store.query = ""
                    store.repoFilter = repo
                    store.section = "all"
                }
            }
        }
    }

    private var riskCard: some View {
        let r = store.risk
        return Card(title: "at risk",
                    tint: r.items.isEmpty ? Palette.status("active") : Palette.risk,
                    symbol: r.items.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill") {
            if r.items.isEmpty {
                Text("Everything you wrote is pushed and committed. Nothing would be lost if this machine died today.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    riskLead(r)
                    VStack(spacing: 0) {
                        let shown = showAllRisk ? r.items : Array(r.items.prefix(Self.riskShown))
                        ForEach(Array(shown.enumerated()), id: \.element.path) { i, w in
                            if i > 0 { Hairline() }
                            RiskRow(worktree: w) {
                                // Land on its row: the list, narrowed to this
                                // branch, where the commits it holds are listed.
                                store.repoFilter = w.repo
                                store.query = w.branch ?? ""
                                store.section = "all"
                            }
                        }
                    }
                    if r.items.count > Self.riskShown {
                        Button(showAllRisk ? "Show fewer"
                                           : "Show \(r.items.count - Self.riskShown) more") {
                            withAnimation(.easeOut(duration: 0.15)) { showAllRisk.toggle() }
                        }
                        .buttonStyle(.link).font(.system(size: 11))
                    }
                    if r.others > 0 {
                        // Said, not subtracted silently: the number above used
                        // to include these, and a total that shrinks without a
                        // reason reads as data going missing.
                        Text("Not counted: \(Store.count(r.others, "commit")) by other people in "
                             + "\(Store.count(r.othersIn, "checkout")), "
                             + "such as a colleague's PR you checked out to review.")
                            .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static let riskShown = 5

    /// The figure that is actually the risk, and what it is made of.
    ///
    /// It leads with whichever number is the risk. A machine whose work is all
    /// pushed but not all committed once got a 26pt "0" under AT RISK, while
    /// the uncommitted files that *were* the risk sat in grey below it.
    private func riskLead(_ r: Store.Risk) -> some View {
        let commits = r.commits > 0
        let figure = commits ? r.commits : r.dirtyFiles
        let what = commits
            ? (r.commits == 1 ? "commit of yours exists only on this machine"
                              : "commits of yours exist only on this machine")
            : (r.dirtyFiles == 1 ? "change is not committed anywhere"
                                 : "changes are not committed anywhere")
        var parts: [String] = []
        // Worktrees, not branches: a detached checkout holds commits too, and
        // has no branch to count.
        if commits { parts.append("in " + Store.count(r.withCommits, "worktree")) }
        if commits && r.withChanges > 0 {
            parts.append("\(r.withChanges) with uncommitted changes")
        } else if !commits {
            parts.append("in " + Store.count(r.withChanges, "worktree"))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(figure)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.inkRisk)
            VStack(alignment: .leading, spacing: 2) {
                Text(what).font(.system(size: 12.5, weight: .medium))
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// One worktree holding work nowhere else: the branch first, because that is
/// what you recognise, and the repo under it in full rather than cut to
/// "elevation-church-…" — the part a long repo name loses is the part that
/// tells two of them apart.
private struct RiskRow: View {
    let worktree: Worktree
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(worktree.repo)
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                // A fixed column, so the figures line up down the card whether
                // a row has one fact or two.
                VStack(alignment: .trailing, spacing: 2) {
                    if worktree.atRisk > 0 {
                        Text(Store.count(worktree.atRisk, "commit"))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkRisk)
                    }
                    if worktree.wouldLose > 0 {
                        Text("\(worktree.wouldLose) uncommitted")
                            .font(.system(size: 10.5, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(minWidth: 96, alignment: .trailing)
            }
            .padding(.vertical, 8).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.045) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .help("Show \(worktree.name) in \(worktree.repo)")
    }
}

/// The ledger's column widths, in one place, so the head and the rows cannot
/// drift apart — which is the only way a right-aligned numeric column ever
/// goes wrong.
private enum Ledger {
    static let needs: CGFloat = 50
    static let forgot: CGFloat = 52
    static let only: CGFloat = 62
    static let age: CGFloat = 46
    static let reclaim: CGFloat = 58

}

/// One row per project, plus its head.
///
/// `ViewThatFits` and not a measured width: the whole table makes one choice,
/// during layout, with no state to arrive a frame late. Measuring it instead —
/// a `GeometryReader` writing to `@State` — worked in the window and silently
/// did nothing offscreen, where the snapshot that is supposed to catch this
/// kind of thing is rendered.
///
/// The full variant's ideal width is the longest project name plus five
/// columns; when that will not fit, two columns stand down: how long ago (the
/// rows are still ranked by urgency without it) and how much is rebuildable
/// (Disk is one click away and is entirely about that number). A per-row
/// choice would let one row drop a column its neighbours kept, and a
/// right-aligned table whose columns move between rows is worse than no table.
private struct RepoLedger: View {
    let rows: [Store.RepoRow]
    let hidden: Int
    let open: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            table(dense: false)
            table(dense: true)
        }
    }

    private func table(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head(dense: dense)
            ForEach(rows) { row in
                Hairline()
                RepoLedgerRow(row: row, dense: dense,
                              ambiguous: rows.filter { $0.name == row.name }.count > 1) {
                    open(row.id)
                }
            }
            if hidden > 0 {
                Text("and \(hidden) more, quieter")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    .padding(.top, 9)
            }
        }
    }

    private func head(dense: Bool) -> some View {
        HStack(spacing: 0) {
            Text("PROJECT").frame(maxWidth: .infinity, alignment: .leading)
            Text("NEEDS").frame(width: Ledger.needs, alignment: .trailing)
            Text("FORGOT").frame(width: Ledger.forgot, alignment: .trailing)
            Text("ONLY HERE").frame(width: Ledger.only, alignment: .trailing)
            if !dense {
                Text("OLDEST").frame(width: Ledger.age, alignment: .trailing)
                Text("RECLAIM").frame(width: Ledger.reclaim, alignment: .trailing)
            }
        }
        .font(.system(size: 9, weight: .semibold)).tracking(0.5)
        .foregroundStyle(Palette.muted)
        .padding(.bottom, 6)
    }
}

private struct RepoLedgerRow: View {
    let row: Store.RepoRow
    let dense: Bool
    let ambiguous: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                        .help(row.path)
                    Text(ambiguous ? row.path
                         : (row.worktrees == 1 ? "1 worktree" : "\(row.worktrees) worktrees"))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                cell(row.needs, width: Ledger.needs, tint: Palette.status("blocked"))
                cell(row.stale, width: Ledger.forgot, tint: Palette.status("stale"))
                cell(row.unpushed, width: Ledger.only, tint: Palette.risk)
                if !dense {
                    // A gradient, not a threshold: thirty-one days and
                    // thirty-two are the same amount of forgotten, and a cliff
                    // between them would claim otherwise.
                    Text(row.oldestDays > 0 ? "\(row.oldestDays)d" : "–")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(row.oldestDays > 0
                                         ? Palette.ink(Palette.age(row.oldestDays)) : Palette.faint)
                        .frame(width: Ledger.age, alignment: .trailing)
                    Text(row.reclaim > 0 ? Store.human(row.reclaim) : "–")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(row.reclaim > 0 ? Palette.inkReclaim : Palette.faint)
                        .frame(width: Ledger.reclaim, alignment: .trailing)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .help("Show \(row.id) in the worktree list")
    }

    /// A zero is a dash, never a "0". Five columns of zeroes is a wall the eye
    /// has to read past to find the one number that is not.
    private func cell(_ n: Int, width: CGFloat, tint: Color) -> some View {
        Text(n > 0 ? "\(n)" : "–")
            .font(.system(size: 12, weight: n > 0 ? .semibold : .regular, design: .rounded))
            .foregroundStyle(n > 0 ? Palette.ink(tint) : Palette.faint)
            .frame(width: width, alignment: .trailing)
    }
}

// MARK: - disk

struct DiskDetail: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CleanupScoreCard(store: store)
                if store.disk == nil {
                    Card(title: "disk", tint: Palette.reclaim, symbol: "internaldrive.fill") {
                        Text(store.phase == "measuring disk"
                             ? "Measuring. This walks every worktree, so it takes a minute."
                             : "Not measured yet — press refresh.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                } else {
                    Card(title: "by repo",
                         trailing: store.disk.map { "\(Store.human($0.reclaim)) of \(Store.human($0.total)) rebuildable" },
                         tint: Palette.reclaim, symbol: "chart.bar.fill") {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(store.weights.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { Hairline() }
                                RepoBar(item: item, max: store.weights.first?.total ?? 1,
                                        hue: Palette.categorical(i))
                            }
                        }
                    }
                    Card(title: "reclaim", tint: Palette.reclaim, symbol: "sparkles") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !store.removalCandidates.isEmpty {
                                ActionButton(action: Store.Action(kind: .reap, paths: store.removalCandidates.map(\.path)),
                                             detail: "Only candidates that have no known removal blocker. Files are checked again in the preview.") { store.preview($0) }
                            } else {
                                Text("No finished worktrees are eligible for removal. Open Finished to see what is being kept and why.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            if !store.reclaimCandidates(staleOnly: true).isEmpty {
                                ActionButton(action: Store.Action(kind: .clean, paths: store.reclaimCandidates(staleOnly: true).map(\.path), staleOnly: true),
                                             detail: "Build output in forgotten and finished worktrees.") { store.preview($0) }
                            }
                            if !store.reclaimCandidates().isEmpty {
                                ActionButton(action: Store.Action(kind: .clean, paths: store.reclaimCandidates().map(\.path)),
                                             detail: "Build output in the measured folders, including work in flight. A build or install recreates it.") { store.preview($0) }
                            } else {
                                Text("No rebuildable output was found in the latest measurement.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Text("Each one shows you exactly what it would remove before anything happens.")
                                .font(.system(size: 10.5)).foregroundStyle(Palette.muted).padding(.top, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
        }
    }
}

struct RepoBar: View {
    let item: Store.RepoWeight
    let max: Int
    var hue: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(hue).frame(width: 7, height: 7)
                Text(item.id).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                Text(Store.human(item.reclaim)).font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Palette.inkReclaim)
                Text(Store.human(item.total)).font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Palette.muted).frame(width: 50, alignment: .trailing)
            }
            GeometryReader { geo in
                let w = geo.size.width * CGFloat(item.total) / CGFloat(Swift.max(max, 1))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                    // Pale is what a build would put back; solid is what it holds
                    // that nothing else can.
                    RoundedRectangle(cornerRadius: 3).fill(hue.opacity(0.32))
                        .frame(width: w)
                    RoundedRectangle(cornerRadius: 3).fill(hue)
                        .frame(width: w * CGFloat(item.keep) / CGFloat(Swift.max(item.total, 1)))
                }
            }
            .frame(height: 9)
        }
    }
}

struct ActionButton: View {
    let action: Store.Action
    let detail: String
    let run: (Store.Action) -> Void

    var body: some View {
        Button { run(action) } label: {
            HStack(spacing: 9) {
                Image(systemName: action.kind.icon).font(.system(size: 11))
                    .foregroundStyle(action.kind == .reap ? Palette.status("merged") : Palette.reclaim)
                    .frame(width: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
        }
        .buttonStyle(RowButtonStyle())
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
        return plan.action.kind == .reap ? "Removed \(r.removed) worktree\(r.removed == 1 ? "" : "s")" : "Cleanup complete"
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: issues ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 19)).foregroundStyle(Palette.ink(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(issues ? "Some work could not finish. Review the result for details."
                     : (plan.result?.freedKb ?? 0) > 0 ? "\(Store.human(plan.result?.freedKb ?? 0)) reclaimed" : "Operation confirmed · review the details")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if (plan.result?.freedKb ?? 0) > 0 && !(plan.result?.completedPaths.isEmpty ?? true) {
                    Text("✦ \(store.history.rank) · \(Store.human(store.history.reclaimedKb)) reclaimed so far")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.inkReclaim)
                }
            }
            Spacer(minLength: 4)
            Button("View result") { store.plan = plan }.controlSize(.small)
            Button { store.completion = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss operation result")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(tint.opacity(0.09))
        .accessibilityElement(children: .contain)
    }
}
