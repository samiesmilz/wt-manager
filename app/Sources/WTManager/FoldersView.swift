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
    /// The verdict picked in the sidebar, if any.
    private var only: Verdict? { store.verdictFilter.flatMap(Verdict.init(rawValue:)) }
    /// The folder opened to its details, as a row of the old list opened.
    @State var open: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Verdict: String, CaseIterable {
        case safe, busy, unsaved, kept
        /// For the sidebar, where four of them share one list.
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
    private static let top = "top"

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
        return full.compactMap { g in
            let kept = g.rows.filter { (only == nil || $0.verdict == only) && searched($0) }
            return kept.isEmpty ? nil : Group(id: g.id, rows: kept, elsewhere: g.elsewhere)
        }
    }

    /// The search field and the project filter, by the one rule in Store.
    /// The search field and the sidebar's location, by the one rule in Store.
    private func searched(_ row: Row) -> Bool { store.inScope(row.worktree) }

    var body: some View {
        let rows = allRows
        VStack(spacing: 0) {
            header(rows.filter(searched))
            if !rows.isEmpty { FilterBar(store: store) }
            Divider().opacity(0.35)
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id(Self.top)
                        content(rows)
                    }
                        .safeAreaInset(edge: .bottom) { if !selected.isEmpty { selectionBar(rows) } }
                        // Another page asked for this folder: open it and
                        // bring it into view, then let go of the request.
                        .onAppear { reveal(store.focusPath, proxy) }
                        .onChange(of: store.focusPath) { reveal($0, proxy) }
                        // A filter from the sidebar shortens the list. Left
                        // where it was scrolled, the page showed the space
                        // below two folders: blank, as if the place were empty.
                        .onChange(of: store.locationFilter) { _ in proxy.scrollTo(Self.top, anchor: .top) }
                        .onChange(of: store.verdictFilter) { _ in proxy.scrollTo(Self.top, anchor: .top) }
                        .onChange(of: store.query) { _ in proxy.scrollTo(Self.top, anchor: .top) }
                }
            } else {
                if !selected.isEmpty { selectionBar(rows) }
                content(rows)
            }
        }
        // A folder that went, by this page or any other, is no longer ticked.
        .onChange(of: Set(rows.map(\.id))) { paths in selected.formIntersection(paths) }
    }

    // MARK: header

    /// Title, what could be freed, and the two sweeps: caches everywhere,
    /// and every folder that loses nothing. It stays put while the folders
    /// scroll.
    private func header(_ rows: [Row]) -> some View {
        let safe = rows.filter { $0.verdict == .safe }
        // Every checkout's caches, main ones included, unless the sidebar
        // narrowed the page to one place: then that place's folders.
        let caches = store.locationFilter == nil && store.query.isEmpty
            ? store.cacheCandidates : rows.map(\.worktree).filter { $0.reclaimKb > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            if store.locationFilter != nil {
                // The way back to the place list, where this one was opened.
                Button { store.locationFilter = nil; store.page = .locations } label: {
                    Label("All locations", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.ink(Palette.status("trunk")))
                .padding(.bottom, -4)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1).truncationMode(.head)
                Text(verbatim: "\(rows.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink(Palette.reclaim))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.wash(Palette.reclaim)))
                    .accessibilityLabel(Store.count(rows.count, "folder"))
                Spacer()
            }
            if let e = store.error {
                notice(e, tint: Palette.status("blocked"), mono: true)
            }
            if let notices = store.envelope?.notices, !notices.isEmpty {
                notice(notices.joined(separator: "\n"), tint: Palette.status("stale"))
            }
            // One line: the two cleanups, each carrying its own size, then
            // what exists only here. The sizes are the "could free"; saying
            // it again in a chip above was the same number twice.
            let actions = HStack(spacing: 8) {
                if !caches.isEmpty { cleanButton(caches) }
                if !safe.isEmpty {
                    clearButton("Delete \(safe.count) safe · "
                                + Store.human(safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }),
                                rows: safe, prominent: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions; chips(rows); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) { actions; chips(rows) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    }

    /// The place picked in the sidebar, or the page's own name.
    private var title: String {
        guard let l = store.locationFilter else { return "Folders" }
        return store.locationLabel(l)
    }

    /// What exists only here, in colour, and a way in: it opens the folders
    /// holding that work. Before the disk is measured, a word saying so.
    @ViewBuilder
    private func chips(_ rows: [Row]) -> some View {
        let commits = rows.reduce(0) { $0 + max($1.worktree.atRisk, 0) }
        let unsaved = rows.filter { $0.verdict == .unsaved }.count
        if commits > 0 || (store.disk == nil && store.envelope != nil) {
            HStack(spacing: 7) {
                if store.disk == nil, store.envelope != nil {
                    chip(store.phase == "measuring disk" ? "measuring disk…" : "disk not measured yet",
                         "internaldrive", Palette.status("empty"))
                }
                if commits > 0 {
                    Button { store.verdictFilter = only == .unsaved ? nil : FoldersView.Verdict.unsaved.rawValue } label: {
                        chip(Store.count(commits, "commit") + " only here"
                             + (unsaved > 0 ? " · " + Store.count(unsaved, "folder") : ""),
                             "arrow.up.circle", Palette.risk)
                    }
                    .buttonStyle(RowButtonStyle(radius: 12))
                    .help("Show the folders holding work that is on no remote")
                }
            }
        }
    }

    private func chip(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink(tint)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Palette.wash(tint))
            .overlay(Capsule().strokeBorder(Palette.edge(tint), lineWidth: 1)))
    }

    private func notice(_ text: String, tint: Color, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, design: mono ? .monospaced : .default))
            .foregroundStyle(Palette.ink(tint)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.wash(tint)))
    }

    /// Caches in every checkout, main ones included: most build output lives
    /// in the repos themselves, which no folder delete reaches.
    private func cleanButton(_ ws: [Worktree]) -> some View {
        let kb = ws.reduce(0) { $0 + max($1.reclaimKb, 0) }
        return Button {
            store.preview(Store.Action(kind: .clean, paths: ws.map(\.path)))
        } label: {
            Label("Clean caches · \(Store.human(kb))", systemImage: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(Palette.ink(Palette.reclaim))
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.wash(Palette.reclaim)))
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Build output and dependencies in every checkout, main ones included. "
              + "Preview first; an install or build puts them back.")
    }

    // MARK: content

    private func content(_ rows: [Row]) -> some View {
        let groups = self.groups(rows)
        let empties = shownEmpties
        return VStack(alignment: .leading, spacing: 14) {
            if !empties.isEmpty { emptyCard(empties) }
            if rows.isEmpty && !empties.isEmpty {
                // Only the empty folders: nothing more to say.
            } else if rows.isEmpty {
                Text(store.envelope == nil ? "Reading your repos…"
                     : "No worktree folders. Every checkout here is a repo's main one.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else if groups.isEmpty, let only {
                if empties.isEmpty {
                    Text("No folders are \(only.short).")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            } else if groups.isEmpty {
                HStack(spacing: 6) {
                    Text("No folders match.").foregroundStyle(Palette.muted)
                    Button("Clear the filters") { store.query = ""; store.verdictFilter = nil; store.locationFilter = nil }
                        .buttonStyle(.link)
                }
                .font(.system(size: 12))
            } else {
                if only == nil, empties.isEmpty, !rows.contains(where: { $0.verdict == .safe }) {
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

    /// Empty folders left where worktrees were, when the page is showing
    /// what is safe: all of it, or the safe filter, with no narrower search.
    private var shownEmpties: [String] {
        guard only == nil || only == .safe, store.locationFilter == nil, store.query.isEmpty else { return [] }
        return store.emptyLocations
    }

    /// Folders that held worktrees and hold nothing now. Safe by definition,
    /// so one button, and no preview: there is nothing in them to show.
    private func emptyCard(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder").font(.system(size: 18))
                    .foregroundStyle(Palette.reclaim).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Empty folders").font(.system(size: 13, weight: .semibold))
                    Text("left where worktrees used to be · nothing inside")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    store.removeEmptyLocations(paths)
                } } label: {
                    Label("Remove \(Store.count(paths.count, "empty folder"))", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(Palette.ink(Palette.reclaim))
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.wash(Palette.reclaim)))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("Each is checked again first; a folder with anything in it is left alone.")
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(paths, id: \.self) { p in
                    let home = NSHomeDirectory()
                    Text(p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            .padding(.leading, 30)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08))))
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

    private func reveal(_ path: String?, _ proxy: ScrollViewProxy) {
        guard let path else { return }
        open = path
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(path, anchor: .top) }
            store.focusPath = nil
        }
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
                    FolderRow(store: store, row: row, elsewhere: g.elsewhere,
                              selected: Binding(
                                get: { selected.contains(row.id) },
                                set: { on in if on { selected.insert(row.id) } else { selected.remove(row.id) } }),
                              expanded: open == row.id,
                              toggle: {
                                  withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                                      open = open == row.id ? nil : row.id
                                  }
                              },
                              delete: { delete([row]) })
                        .id(row.id)
                }
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08))))
    }
}

/// One folder. Clicking it opens its details, as a row of the list did; the
/// checkbox ticks it for one delete. Its one button deletes a folder that
/// loses nothing. Deleting unsaved work is never a lone click: it is ticked
/// and deleted from the bar, or chosen from the row's menu, and both go
/// through the preview.
private struct FolderRow: View {
    @ObservedObject var store: Store
    let row: FoldersView.Row
    let elsewhere: Bool
    @Binding var selected: Bool
    let expanded: Bool
    let toggle: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line
            if expanded {
                WorktreeDetail(store: store, worktree: row.worktree)
                    .padding(.leading, 52).padding(.top, 2).padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    private var line: some View {
        let w = row.worktree, v = row.verdict
        return HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(Palette.faint).frame(width: 8)
                .accessibilityHidden(true)
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
                            .foregroundStyle(Palette.ink(v.tint))
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
            // The size, and under it the part a build puts back. A folder
            // holding unsaved work cannot go, but its caches can: measured,
            // 44GB of a 45GB Rust worktree was `target/`.
            VStack(alignment: .trailing, spacing: 2) {
                Text(w.sizeKb > 0 ? Store.human(w.sizeKb) : "—")
                    .font(.system(size: 11, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.muted)
                if w.reclaimKb > 0 {
                    Button("clean \(Store.human(w.reclaimKb))") {
                        store.preview(Store.Action(kind: .clean, paths: [w.path]))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.inkReclaim)
                    .help("Clean this folder's caches (preview first). The folder stays.")
                    .accessibilityLabel("Clean \(Store.human(w.reclaimKb)) of caches in \(row.name)")
                }
            }
            .frame(width: 72, alignment: .trailing)
            SwiftUI.Group {
                if v.lossless {
                    Button(action: delete) { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .help("Delete this folder (preview first)")
                        .accessibilityLabel("Delete \(row.name)")
                } else {
                    Color.clear
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(hovering ? Palette.ink(v.tint) : Palette.muted)
            .frame(width: 22, height: 16)
        }
        .padding(.vertical, 7).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(selected ? Palette.wash(v.tint) : hovering ? Color.primary.opacity(0.04) : .clear))
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .contextMenu {
            if v.lossless {
                Button("Delete…", action: delete)
            } else if row.anyway {
                Button("Delete anyway…", action: delete)
            }
            if w.reclaimKb > 0 {
                Button("Clean caches · \(Store.human(w.reclaimKb))…") {
                    store.preview(Store.Action(kind: .clean, paths: [w.path]))
                }
            }
            Button(expanded ? "Hide details" : "Show details", action: toggle)
            Button("Reveal in Finder") { store.reveal(w) }
            Button("Open in Terminal") { store.openInTerminal(w) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(v.label), \(row.reason)")
        .accessibilityHint(expanded ? "Hides its details" : "Shows its details")
    }
}
