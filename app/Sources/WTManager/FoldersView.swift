import SwiftUI
import WTManagerKit

/// Worktrees as what they are on disk: folders, grouped by the folder they
/// sit in.
///
/// Developers clear a sprint by deleting a worktrees folder. That loses
/// whatever was not pushed and leaves git's bookkeeping behind. This page
/// is that same gesture with the check in front of it. Each folder is judged
/// by the engine on one question: would deleting it lose anything? The
/// verdict comes from the blocker `reap --folders` applies, so a folder
/// called safe here is one the button removes.
struct FoldersView: View {
    @ObservedObject var store: Store
    /// The window scrolls; the snapshot draws the whole page at once.
    var scrolls = true
    /// The folders ticked for one delete, by path.
    @State var selected: Set<String> = []
    /// The tally pressed, if any: the page shows only folders with that verdict.
    @State var only: Verdict? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Verdict: String, CaseIterable {
        case safe, busy, unsaved, kept
        /// For the tally, where four of them share one line.
        var short: String {
            switch self {
            case .safe: return "safe"
            case .busy: return "in progress"
            case .unsaved: return "unsaved"
            case .kept: return "kept"
            }
        }
        var label: String {
            switch self {
            case .safe: return "Safe to delete"
            case .busy: return "In progress"
            case .unsaved: return "Unsaved work"
            case .kept: return "Kept"
            }
        }
        var tint: Color {
            switch self {
            case .safe: return Palette.reclaim
            case .busy: return Palette.status("waiting")
            case .unsaved: return Palette.risk
            case .kept: return Palette.status("empty")
            }
        }
        /// Deletes without asking you to give anything up. In progress loses
        /// nothing either; it is only left out of "clear", which is a sweep.
        var lossless: Bool { self == .safe || self == .busy }
    }

    struct Row: Identifiable {
        let worktree: Worktree
        let verdict: Verdict
        let reason: String
        let parent: String
        /// For unsaved and kept: whether "delete anyway" can act on it.
        let anyway: Bool
        var id: String { worktree.path }
        var name: String { URL(fileURLWithPath: worktree.path).lastPathComponent }
        var deletable: Bool { verdict.lossless || anyway }
    }

    struct Group: Identifiable {
        let id: String
        let rows: [Row]
        /// The folders that sit alone in their parent, gathered into one card
        /// so a long tail of one-folder cards does not bury the full ones.
        var elsewhere = false
        var kb: Int { rows.reduce(0) { $0 + max($1.worktree.sizeKb, 0) } }
        var safe: [Row] { rows.filter { $0.verdict == .safe } }
    }

    static let elsewhereID = "Elsewhere"

    private var allRows: [Row] {
        let home = NSHomeDirectory()
        return store.folderRows.compactMap { w -> Row? in
            guard let f = w.folder else { return nil }
            let parent = (w.path as NSString).deletingLastPathComponent
            let shown = parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
            return Row(worktree: w, verdict: Verdict(rawValue: f.verdict) ?? .kept,
                       reason: f.reason, parent: String(shown), anyway: f.anyway ?? false)
        }
    }

    /// Grouped by parent folder over every row, then filtered, so a folder
    /// does not move to "Elsewhere" just because a filter hid its neighbours.
    private func groups(_ rows: [Row]) -> [Group] {
        let order = Verdict.allCases
        func sorted(_ rs: [Row]) -> [Row] {
            rs.sorted { a, b in
                let i = order.firstIndex(of: a.verdict)!, j = order.firstIndex(of: b.verdict)!
                return i != j ? i < j : a.worktree.sizeKb > b.worktree.sizeKb
            }
        }
        let byParent = Dictionary(grouping: rows, by: \.parent)
        var full: [Group] = [], lone: [Row] = []
        for (parent, rs) in byParent {
            if rs.count == 1 { lone += rs } else { full.append(Group(id: parent, rows: sorted(rs))) }
        }
        full.sort { ($0.safe.count, $0.kb) > ($1.safe.count, $1.kb) }
        if !lone.isEmpty { full.append(Group(id: Self.elsewhereID, rows: sorted(lone), elsewhere: true)) }
        guard let only else { return full }
        return full.compactMap { g in
            let kept = g.rows.filter { $0.verdict == only }
            return kept.isEmpty ? nil : Group(id: g.id, rows: kept, elsewhere: g.elsewhere)
        }
    }

    var body: some View {
        let rows = allRows
        VStack(spacing: 0) {
            header(rows)
            Divider().opacity(0.35)
            if scrolls {
                ScrollView { content(rows) }
                    .safeAreaInset(edge: .bottom) { if !selected.isEmpty { selectionBar(rows) } }
            } else {
                if !selected.isEmpty { selectionBar(rows) }
                content(rows)
            }
        }
        // A folder that went, by this page or any other, is no longer ticked.
        .onChange(of: Set(rows.map(\.id))) { paths in selected.formIntersection(paths) }
    }

    // MARK: header

    /// The same header as the worktree lists: title, one line of what the
    /// page is, a count, and below them the controls. It stays put while the
    /// folders scroll.
    private func header(_ rows: [Row]) -> some View {
        let safe = rows.filter { $0.verdict == .safe }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Folders")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("deleting a folder loses only what isn't on GitHub")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(verbatim: "\(rows.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink(Palette.section("folders")))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.wash(Palette.section("folders"))))
                    .accessibilityLabel("\(rows.count) folders")
            }
            if !rows.isEmpty {
                let tallies = HStack(spacing: 7) {
                    // All four, always: a pill that comes and goes moves the
                    // others under the pointer.
                    ForEach(Verdict.allCases, id: \.self) { v in tally(v, rows) }
                }
                let sweep = clearButton("Clear everything safe · \(Store.count(safe.count, "folder")), "
                                        + Store.human(safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }),
                                        rows: safe, prominent: true)
                // One line when it fits; the sweep on its own line when not.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        tallies
                        Spacer(minLength: 8)
                        if !safe.isEmpty { sweep }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        tallies
                        if !safe.isEmpty { sweep }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    /// A filter, since a count that looks like a pill gets clicked. A zero is
    /// drawn hollow and does nothing: filled, "0 safe" looked as live as
    /// "12 unsaved" and led to an empty page.
    private func tally(_ v: Verdict, _ rows: [Row]) -> some View {
        let on = only == v
        let n = rows.filter { $0.verdict == v }.count
        return Button { only = on ? nil : v } label: {
            HStack(spacing: 5) {
                Circle().fill(n == 0 ? Palette.faint : v.tint).frame(width: 7, height: 7)
                Text(verbatim: "\(n)").font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(n == 0 ? Palette.muted : Color.primary)
                Text(v.short).font(.system(size: 11.5))
                    .foregroundStyle(on ? Palette.ink(v.tint) : Palette.muted)
            }
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(n == 0 ? Color.clear : Palette.wash(v.tint)))
            .overlay(Capsule().strokeBorder(on ? Palette.ink(v.tint)
                                            : n == 0 ? Color.primary.opacity(0.10) : .clear, lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(n == 0 && !on)
        .help(on ? "Show every folder" : "Show only folders that are \(v.short)")
        .accessibilityLabel("\(n) \(v.short)")
        .accessibilityHint(on ? "Shows every folder" : "Shows only these folders")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: content

    private func content(_ rows: [Row]) -> some View {
        let groups = self.groups(rows)
        return VStack(alignment: .leading, spacing: 14) {
            if rows.isEmpty {
                Text(store.envelope == nil ? "Reading your repos…"
                     : "No worktree folders. Every checkout here is a repo's main one.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else if groups.isEmpty, let only {
                Text("No folders are \(only.short).")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else {
                if only == nil, !rows.contains(where: { $0.verdict == .safe }) {
                    // After a cleanup this is the usual state, and a page with
                    // no sweep button and no word about why looks unfinished.
                    let held = rows.contains { !$0.verdict.lossless }
                    Text("Nothing is safe to delete right now."
                         + (held ? " Push or commit the work below, or tick a folder to delete it anyway." : ""))
                        .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(groups) { card($0) }
                Text("Main checkouts are not listed: they are the repos themselves, and git never deletes one.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Deleted folders leave, and the rest close up, rather than the page
        // jumping to its new shape.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: rows.map(\.id))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: only)
    }

    /// What one delete of the ticked folders would do, said on its button.
    private func selectionBar(_ all: [Row]) -> some View {
        let rows = all.filter { selected.contains($0.id) }
        let kb = rows.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }
        let unsaved = rows.filter { !$0.verdict.lossless }.count
        return HStack(spacing: 12) {
            Text(verbatim: "\(rows.count) selected · \(Store.human(kb))")
                .font(.system(size: 12, weight: .semibold))
            if unsaved > 0 {
                Text("\(unsaved) with unsaved work")
                    .font(.system(size: 11)).foregroundStyle(Palette.inkRisk)
            }
            Spacer(minLength: 8)
            Button("Clear selection") { selected = [] }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            clearButton(unsaved > 0 ? "Delete \(rows.count), unsaved work included" : "Delete \(rows.count)",
                        rows: rows, prominent: true, warning: unsaved > 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    /// One action for any set: the paths, plus the flags the set needs.
    private func delete(_ rows: [Row]) {
        store.preview(Store.Action(kind: .reap, paths: rows.map(\.worktree.path),
                                   discardChanges: rows.contains { $0.worktree.removalDiscards },
                                   folders: true,
                                   discardWork: rows.contains { !$0.verdict.lossless }))
    }

    private func show(_ row: Row) {
        store.repoFilter = row.worktree.repo
        store.query = row.worktree.branch ?? ""
        store.section = "all"
    }

    /// `warning`: unsaved work is in the set, so it is drawn in the app's
    /// destructive red rather than the calm green of a delete that loses
    /// nothing.
    private func clearButton(_ title: String, rows: [Row], prominent: Bool = false,
                             warning: Bool = false) -> some View {
        Button { delete(rows) } label: {
            Label(title, systemImage: "trash")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(prominent ? Color.white : Palette.ink(Palette.reclaim))
                // A fixed deep green, not the ink: ink turns light in dark
                // mode, and white on light green could not be read.
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(prominent ? (warning ? Palette.badge : Color(red: 0.17, green: 0.44, blue: 0.31))
                                    : Palette.wash(Palette.reclaim)))
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Preview first: nothing is deleted until you confirm")
    }

    /// The folder's own name in weight, the way to it muted, in the window's
    /// type: a narrow window cuts the way, never the name. Bold monospace was
    /// the heaviest thing on the page and lost the name first.
    private func pathTitle(_ g: Group) -> some View {
        let parent = (g.id as NSString).deletingLastPathComponent
        let name = (g.id as NSString).lastPathComponent
        return HStack(spacing: 0) {
            if !g.elsewhere && !parent.isEmpty {
                Text(parent + "/").foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.head)
            }
            Text(g.elsewhere ? g.id : name).fontWeight(.semibold)
                .lineLimit(1).layoutPriority(1)
        }
        .font(.system(size: 13))
        .help(g.elsewhere ? "Folders that sit alone in their parent" : g.id)
    }

    private func card(_ g: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: g.elsewhere ? "folder" : "folder.fill")
                    .font(.system(size: 18)).foregroundStyle(Palette.status("trunk"))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    pathTitle(g)
                    Text(g.elsewhere
                         ? "one folder in each of \(g.rows.count) places · " + Store.human(g.kb)
                         : Store.count(g.rows.count, "folder") + " · " + Store.human(g.kb))
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                // Only folders that lose nothing. Unsaved work is ticked one
                // at a time: "select all" to clear a card must not sweep up
                // the one folder that still holds something.
                let pickable = Set(g.rows.filter(\.verdict.lossless).map(\.id))
                if !pickable.isEmpty {
                    let all = pickable.isSubset(of: selected)
                    // Named for what it ticks when a card has nothing safe.
                    let label = g.safe.isEmpty ? "Select in progress" : "Select all"
                    Button(all ? "Deselect" : label) {
                        if all { selected.subtract(pickable) } else { selected.formUnion(pickable) }
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize()
                    .help("Ticks the folders that lose nothing; unsaved work is ticked one at a time")
                }
                if !g.safe.isEmpty {
                    clearButton("Clear \(g.safe.count) safe · "
                                + Store.human(g.safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }),
                                rows: g.safe)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Hairline() }
                    FolderRow(row: row, elsewhere: g.elsewhere,
                              selected: Binding(
                                get: { selected.contains(row.id) },
                                set: { on in if on { selected.insert(row.id) } else { selected.remove(row.id) } }),
                              delete: { delete([row]) },
                              show: { show(row) },
                              reveal: { store.reveal(row.worktree) })
                }
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08))))
    }
}

/// One folder. The whole row ticks it; its one button deletes a folder that
/// loses nothing, or shows what an unsaved one holds. Deleting unsaved work
/// is never a lone click: it is ticked and deleted from the bar, or chosen
/// from the row's menu, and both go through the preview.
private struct FolderRow: View {
    let row: FoldersView.Row
    let elsewhere: Bool
    @Binding var selected: Bool
    let delete: () -> Void
    let show: () -> Void
    let reveal: () -> Void
    @State private var hovering = false

    var body: some View {
        let w = row.worktree, v = row.verdict
        HStack(spacing: 10) {
            // A slot either way, so the names line up.
            Toggle("", isOn: $selected).toggleStyle(.checkbox).labelsHidden()
                .disabled(!row.deletable)
                .opacity(row.deletable ? 1 : 0)
                .help(v.lossless ? "Select for one delete"
                                 : "Tick to delete anyway: its work is saved first")
                .accessibilityLabel("Select \(row.name)")
                .accessibilityHidden(!row.deletable)
            // Two lines that each share their width: the name with its
            // verdict, then where it lives with why. A fixed reason column
            // beside both cut every name to "copy-serm…hts-update".
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    // A dot carries the colour; the word stays quiet. Twelve
                    // bold orange "Unsaved work" labels were most of the page.
                    HStack(spacing: 5) {
                        Circle().fill(v.tint).frame(width: 6, height: 6)
                        Text(v.label).font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text((w.branch ?? "detached") + " · " + (elsewhere ? row.parent : w.repo))
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(row.reason).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                        .help(row.reason)
                }
            }
            .help(w.path)
            Text(w.sizeKb > 0 ? Store.human(w.sizeKb) : "—")
                .font(.system(size: 11, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.muted).frame(width: 52, alignment: .trailing)
            SwiftUI.Group {
                if v.lossless {
                    Button(action: delete) { Image(systemName: "trash") }
                        .help("Delete this folder (preview first)")
                        .accessibilityLabel("Delete \(row.name)")
                } else {
                    Button(action: show) { Image(systemName: "arrow.right.circle") }
                        .help("Show what is in it")
                        .accessibilityLabel("Show what \(row.name) holds")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(hovering ? Palette.ink(v.tint) : Palette.muted)
            .frame(width: 22)
        }
        .padding(.vertical, 7).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(selected ? Palette.wash(v.tint) : hovering ? Color.primary.opacity(0.04) : .clear))
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture { if row.deletable { selected.toggle() } }
        .onHover { hovering = $0 }
        .contextMenu {
            if v.lossless {
                Button("Delete…", action: delete)
            } else if row.anyway {
                Button("Delete anyway…", action: delete)
            }
            Button("Show in worktree list", action: show)
            Button("Reveal in Finder", action: reveal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(v.label), \(row.reason)")
    }
}
