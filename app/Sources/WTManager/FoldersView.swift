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
    /// How folders are ordered inside each group.
    @AppStorage("wtmanager.sort") private var sort = "needs"

    enum Verdict: String, CaseIterable {
        case safe, busy, agent, unsaved, kept
        /// For the sidebar, where four of them share one list.
        var short: String {
            switch self {
            case .safe: return "safe"
            case .busy: return "in progress"
            case .agent: return "agent running"
            case .unsaved: return "unsaved"
            case .kept: return "kept"
            }
        }
        var label: String {
            switch self {
            case .safe: return "Safe to delete"
            case .busy: return "In progress"
            case .agent: return "Agent running"
            case .unsaved: return "Unsaved work"
            case .kept: return "Kept"
            }
        }
        var tint: Color {
            switch self {
            case .safe: return Palette.reclaim
            // Grey-blue for yours, the brand blue for an agent's: the two sit
            // side by side in the sidebar and must not read as one colour.
            case .busy: return Palette.status("draft")
            case .agent: return Palette.brand
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
        /// Whose convention put the folder here, read from where it lives.
        var madeBy: String? {
            worktree.path.contains("/.claude/worktrees/") ? "Claude Code"
                : worktree.path.contains("/.codex/") ? "Codex" : nil
        }
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
        let maker: String? = store.madeByFilter
        let shown: [Worktree] = store.folderRows.filter { maker == nil || Store.madeBy($0.path) == maker }
        return shown.compactMap { w -> Row? in
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
        // The design's order: what needs you first, what can simply go after.
        let order: [Verdict] = [.unsaved, .agent, .busy, .safe, .kept]
        func sorted(_ rs: [Row]) -> [Row] {
            rs.sorted { a, b in
                switch sort {
                case "size":
                    if a.worktree.sizeKb != b.worktree.sizeKb { return a.worktree.sizeKb > b.worktree.sizeKb }
                case "age":
                    if a.worktree.ageDays != b.worktree.ageDays { return a.worktree.ageDays > b.worktree.ageDays }
                case "name":
                    break
                default:
                    let i = order.firstIndex(of: a.verdict)!, j = order.firstIndex(of: b.verdict)!
                    if i != j { return i < j }
                    if a.worktree.sizeKb != b.worktree.sizeKb { return a.worktree.sizeKb > b.worktree.sizeKb }
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
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

    /// The search field and the sidebar's location, by the one rule in Store.
    private func searched(_ row: Row) -> Bool { store.inScope(row.worktree) }

    var body: some View {
        let rows = allRows
        VStack(spacing: 0) {
            header(rows.filter(searched))
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView {
                        // No stack spacing under the anchor: it added a gap
                        // above the first card that nothing else had.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id(Self.top)
                            content(rows)
                        }
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
        // Esc clears the ticks; Delete reviews deleting them. Both go through
        // the same preview as the buttons.
        .onExitCommand { selected = [] }
        .onDeleteCommand {
            let chosen: [Row] = rows.filter { selected.contains($0.id) }
            if !chosen.isEmpty { delete(chosen) }
        }
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
            if store.locationFilter != nil {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).truncationMode(.head)
            }
            if let e = store.error { errorCard(e) }
            if let note = store.commandNote {
                HStack(spacing: 8) {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.ink(Palette.brand))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button { store.commandNote = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(Palette.brand)))
            }
            if let notices = store.envelope?.notices, !notices.isEmpty {
                notice(notices.joined(separator: "\n"), tint: Palette.status("stale"))
            }
            // One line: the two cleanups, each carrying its own size, then
            // what exists only here. The sizes are the "could free"; saying
            // it again in a chip above was the same number twice.
            // The figure on the left, the two sweeps on the right: outlined
            // for the delete, filled for the one that loses nothing.
            let actions = HStack(spacing: 10) {
                if !safe.isEmpty {
                    clearButton("Delete \(safe.count) safe · "
                                + Store.human(safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }),
                                rows: safe)
                }
                if !caches.isEmpty { cleanButton(caches) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    hero(caches: caches, safe: safe); Spacer(minLength: 8); actions
                }
                VStack(alignment: .leading, spacing: 10) { hero(caches: caches, safe: safe); actions }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chips(rows)
            if rows.count > 1 {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Sort by").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Picker("Sort by", selection: $sort) {
                        Text("What needs you").tag("needs")
                        Text("Size").tag("size")
                        Text("Oldest first").tag("age")
                        Text("Name").tag("name")
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
    }

    /// The number the page exists for, at the size of a headline: everything a
    /// cleanup could give back, and the two parts it is made of. The same
    /// figures sit on the two buttons beside it; this is their sum, said once.
    @ViewBuilder
    private func hero(caches: [Worktree], safe: [Row]) -> some View {
        let cacheKb: Int = caches.reduce(0) { $0 + max($1.reclaimKb, 0) }
        // A safe folder's caches are already inside its size: count them once.
        let safePaths: Set<String> = Set(safe.map { $0.id })
        let overlap: Int = caches.filter { safePaths.contains($0.path) }.reduce(0) { $0 + max($1.reclaimKb, 0) }
        let safeKb: Int = safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }
        let total: Int = cacheKb - overlap + safeKb
        if total > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("You could free")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(Store.human(total))
                    .font(.system(size: 44, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkReclaim)
                Text(heroParts(cacheKb: cacheKb, safeKb: safeKb, safeCount: safe.count))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    /// "18GB of rebuildable caches · 3.9GB in 6 safe folders", either half alone.
    private func heroParts(cacheKb: Int, safeKb: Int, safeCount: Int) -> String {
        var parts: [String] = []
        if cacheKb > 0 {
            let size: String = Store.human(cacheKb)
            parts.append(size + " of rebuildable caches")
        }
        if safeCount > 0 {
            let size: String = Store.human(safeKb)
            let folders: String = Store.count(safeCount, "safe folder")
            parts.append(size + " in " + folders)
        }
        return parts.joined(separator: " · ")
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
        if store.disk == nil && store.envelope != nil {
            HStack(spacing: 7) {
                if store.disk == nil, store.envelope != nil {
                    chip(store.phase == "measuring disk" ? "measuring disk…" : "disk not measured yet",
                         "internaldrive", Palette.status("empty"))
                }
                if commits < 0 {
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
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink(tint)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Palette.wash(tint))
            .overlay(Capsule().strokeBorder(Palette.edge(tint), lineWidth: 1)))
    }

    /// What went wrong, what still works, and the one thing to do about it.
    private func errorCard(_ text: String) -> some View {
        Banner(tone: .error, symbol: "exclamationmark.triangle",
               title: "Something could not be read",
               detail: "What is listed below is from the last scan that worked. " + text,
               outer: 0) {
            Button("Try again") { store.refresh(measureDisk: false) }.disabled(store.busy)
        }
    }

    /// The scan, as steps: which pass it is on and how far through.
    private func progressCard(_ p: Engine.Progress) -> some View {
        let label: String = p.label.isEmpty ? "Working" : String(p.label.prefix(1)).uppercased() + String(p.label.dropFirst())
        return CardBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Step \(p.step) of \(p.steps) · " + label).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if p.total > 0 {
                        Text("\(p.done) of \(p.total)").font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                }
                Bar(fraction: p.fraction, tint: Palette.safeInk)
                Text("Names and verdicts are ready. Sizes fill in as each folder is measured; you can already open and review rows.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
    }

    private func notice(_ text: String, tint: Color, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, design: mono ? .monospaced : .default))
            .foregroundStyle(Palette.ink(tint)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(tint)))
    }

    /// Caches in every checkout, main ones included: most build output lives
    /// in the repos themselves, which no folder delete reaches.
    private func cleanButton(_ ws: [Worktree]) -> some View {
        let kb = ws.reduce(0) { $0 + max($1.reclaimKb, 0) }
        return Button {
            store.preview(Store.Action(kind: .clean, paths: ws.map(\.path)))
        } label: {
            Text("Clean caches · \(Store.human(kb))")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                // The one filled button on the page: ink on the ground's
                // opposite, so it leads in both appearances.
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary))
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
            if let p = store.scanProgress { progressCard(p) }
            if !empties.isEmpty { emptyCard(empties) }
            if rows.isEmpty && !empties.isEmpty {
                // Only the empty folders: nothing more to say.
            } else if rows.isEmpty {
                VStack(spacing: 6) {
                    if store.envelope == nil {
                        // Placeholder rows where the folders will be, so the
                        // page has its shape before it has its contents.
                        VStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                                    .frame(height: 44)
                            }
                        }
                        .frame(maxWidth: 520).padding(.bottom, 10).accessibilityHidden(true)
                    } else {
                        WityView(store: store, height: 96).frame(width: 96, height: 96)
                            .padding(.bottom, 6).accessibilityHidden(true)
                    }
                    Text(store.envelope == nil ? "Reading your repos…" : "No extra worktree folders")
                        .font(.system(size: 20, weight: .semibold))
                    if store.envelope != nil {
                        Text("Every checkout here is a repo's main one. New worktrees show up here as soon as they are created.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center).frame(maxWidth: 380)
                        HStack(spacing: 10) {
                            if !store.cacheCandidates.isEmpty { cleanButton(store.cacheCandidates) }
                            Button { store.showingSettings = true } label: {
                                Text("Watch another folder")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.cardFill)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 56)
            } else if groups.isEmpty, let only {
                if empties.isEmpty {
                    Text("No folders are \(only.short).")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            } else if groups.isEmpty {
                HStack(spacing: 6) {
                    Text("No folders match.").foregroundStyle(Palette.muted)
                    Button("Clear the filters") {
                        store.query = ""; store.verdictFilter = nil
                        store.locationFilter = nil; store.madeByFilter = nil
                    }
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
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(groups) { card($0) }
                Text("Main checkouts are not listed: they are the repos themselves, and git never deletes one.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
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
                Image(systemName: "folder").font(.system(size: 20))
                    .foregroundStyle(Palette.reclaim).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Empty folders").font(.system(size: 13, weight: .semibold))
                    Text("left where worktrees used to be · nothing inside")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    store.removeEmptyLocations(paths)
                } } label: {
                    Label("Remove \(Store.count(paths.count, "empty folder"))", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(Palette.ink(Palette.reclaim))
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(Palette.reclaim)))
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
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardFill)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1))
    }

    /// What one delete of the ticked folders would do, said on its button.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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
        // A floating bar over the list, not a strip under it: it belongs to
        // the ticked rows and goes when they do.
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 20).padding(.bottom, 12)
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
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                // A fixed deep green, not the ink: ink turns light in dark
                // mode, and white on light green could not be read.
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? (warning ? Palette.badge : Color(red: 0.17, green: 0.44, blue: 0.31))
                                    : Palette.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.22), lineWidth: 1)))
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
        // Claude Code keeps every repo's worktrees in `<repo>/.claude/worktrees`,
        // so the last step is "worktrees" for all of them. The repo is the name.
        let agentHome = !g.elsewhere && name == "worktrees"
            && (parent as NSString).lastPathComponent == ".claude"
        let repo = ((parent as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let named = Text(g.elsewhere ? g.id : agentHome ? repo : name).fontWeight(.semibold).lineLimit(1)
        // The whole way, then only its last step, then the name alone. Cut
        // with an ellipsis, the way shrank to a stray dot beside the name.
        let near = (parent as NSString).lastPathComponent
        _ = near
        return named.truncationMode(.middle)
        .font(.system(size: 15))
        .help(g.elsewhere ? "Folders that sit alone in their parent" : g.id)
    }

    /// Where a group's folders live, the way the design writes it under the
    /// name: `.claude/worktrees` for an agent's home, the tilde path otherwise.
    private func groupWhere(_ g: Group) -> String {
        if g.elsewhere { return "" }
        let parent = (g.id as NSString).deletingLastPathComponent
        if (g.id as NSString).lastPathComponent == "worktrees"
            && (parent as NSString).lastPathComponent == ".claude" { return ".claude/worktrees" }
        return (g.id as NSString).abbreviatingWithTildeInPath
    }

    private func card(_ g: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    pathTitle(g)
                    (Text(groupWhere(g)).font(.system(size: 12, design: .monospaced))
                     + Text((groupWhere(g).isEmpty ? "" : " · ") + (g.elsewhere
                         ? "one folder in each of \(g.rows.count) places · " + Store.human(g.kb)
                         : Store.count(g.rows.count, "folder") + " · " + Store.human(g.kb)))
                        .font(.system(size: 12)))
                        .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                // Only folders that lose nothing. Unsaved work is ticked one
                // at a time: "select all" to clear a card must not sweep up
                // the one folder that still holds something.
                let pickable = Set(g.rows.filter(\.verdict.lossless).map(\.id))
                if pickable.count > 1 {
                    let all = pickable.isSubset(of: selected)
                    Button(all ? "Deselect" : "Select all") {
                        if all { selected.subtract(pickable) } else { selected.formUnion(pickable) }
                    }
                    .buttonStyle(.wt(.quiet))
                    .help("Ticks the folders that lose nothing; unsaved work is ticked one at a time")
                }
                if !g.safe.isEmpty {
                    clearButton("Delete \(g.safe.count) safe · "
                                + Store.human(g.safe.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }),
                                rows: g.safe)
                } else if pickable.count > 1 {
                    // Nothing here is finished, but they may all be done with:
                    // the review still checks each one and saves what it must.
                    let rest: [Row] = g.rows.filter(\.verdict.lossless)
                    clearButton("Delete all \(rest.count) · "
                                + Store.human(rest.reduce(0) { $0 + max($1.worktree.sizeKb, 0) }) + "…",
                                rows: rest)
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
                                  withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                                      open = open == row.id ? nil : row.id
                                  }
                              },
                              delete: { delete([row]) })
                        .id(row.id)
                }
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardFill)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line)))
    }
}

/// One folder. Clicking it opens its details, as a row of the list did; the
/// checkbox ticks it for one delete. Its one button deletes a folder that
/// loses nothing. Deleting unsaved work is never a lone click: it is ticked
/// and deleted from the bar, or chosen from the row's menu, and both go
/// through the preview.
private func quick(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 11, weight: .medium))
            .frame(width: 24, height: 22)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
    }
    .buttonStyle(.plain).foregroundStyle(Palette.muted)
    .help(label).accessibilityLabel(label)
}

private struct FolderRow: View {
    @ObservedObject var store: Store
    let row: FoldersView.Row
    let elsewhere: Bool
    @Binding var selected: Bool
    let expanded: Bool
    let toggle: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    @State private var confirmingTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line
            if expanded {
                WorktreeDetail(store: store, worktree: row.worktree)
                    .padding(.leading, 29).padding(.top, 2).padding(.bottom, 12)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }

    private var line: some View {
        let w = row.worktree, v = row.verdict
        return HStack(alignment: .center, spacing: 14) {
            Button { selected.toggle() } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? Palette.action : Palette.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(selected ? Palette.action : Palette.controlLine, lineWidth: 1.5))
                    .overlay {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Palette.onAction)
                            .scaleEffect(selected ? 1 : 0.3).opacity(selected ? 1 : 0)
                    }
                    .animation(.spring(response: 0.24, dampingFraction: 0.62), value: selected)
                    .frame(width: 16, height: 16)
                    .opacity(row.deletable ? 1 : 0.4)
                    .padding(4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.deletable)
            .accessibilityAddTraits(selected ? .isSelected : [])
                .help(v.lossless ? "Select for one delete"
                                 : row.anyway ? "Tick to delete anyway: its work is saved first" : row.reason)
                .accessibilityLabel("Select \(row.name)")
            // Name over branch.
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                        Text(row.madeBy ?? "By hand").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
                            .fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.name).font(.system(size: 13, weight: .semibold))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Text(row.madeBy ?? "By hand").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
                            .fixedSize()
                    }
                }
                Text(w.branch ?? "detached")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .help(w.path)
            // Verdict over reason, in its own column.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(v.tint).frame(width: 8, height: 8)
                    Text(v.label).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink(v.tint))
                }
                Text(row.reason.prefix(1).uppercased() + row.reason.dropFirst()).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).help(row.reason)
            }
            .frame(minWidth: 150, idealWidth: 250, maxWidth: 250, alignment: .leading)
            .overlay(alignment: .trailing) {
                if hovering {
                    HStack(spacing: 4) {
                        if store.editorChoice != nil {
                            quick("chevron.left.forwardslash.chevron.right", "Open in editor") { store.openInEditor(w) }
                        }
                        quick("terminal", "Open in terminal") { store.openInTerminal(w) }
                        quick("folder", "Reveal in Finder") { store.reveal(w) }
                    }
                    .padding(.leading, 10).padding(.vertical, 4)
                    .background(selected ? Color.clear : Palette.hoverFill)
                    .transition(.opacity)
                }
            }
            // The size, and under it what a build would put back.
            VStack(alignment: .trailing, spacing: 3) {
                if w.sizeKb <= 0 && store.busy {
                    // Still being measured: a placeholder the size of a figure.
                    Capsule().fill(Palette.line).frame(width: 56, height: 10)
                        .accessibilityLabel("Measuring")
                } else {
                    Text(w.sizeKb > 0 ? Store.human(w.sizeKb) : "—")
                        .font(.system(size: 13)).monospacedDigit()
                }
                if w.reclaimKb > 0 {
                    Button("clean \(Store.human(w.reclaimKb))") {
                        store.preview(Store.Action(kind: .clean, paths: [w.path]))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkReclaim)
                    .help("Clean this folder's caches (preview first). The folder stays.")
                    .accessibilityLabel("Clean \(Store.human(w.reclaimKb)) of caches in \(row.name)")
                }
            }
            .frame(width: 92, alignment: .trailing)
            SwiftUI.Group {
                if v.lossless {
                    Button(action: delete) { Image(systemName: "trash").font(.system(size: 13)) }
                        .buttonStyle(TrashButtonStyle())
                    .help("Delete this folder (preview first)")
                    .accessibilityLabel("Delete \(row.name)")
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Palette.wash(v.tint) : (hovering ? Palette.hoverFill : Color.clear))
            .padding(.horizontal, -8))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .contextMenu {
            if v.lossless {
                Button("Delete…", action: delete)
            } else if row.anyway {
                Button("Delete anyway…", action: delete)
            }
            if row.deletable && v != .agent {
                Button("Move to Trash instead…") { confirmingTrash = true }
            }
            if w.reclaimKb > 0 {
                Button("Clean caches · \(Store.human(w.reclaimKb))…") {
                    store.preview(Store.Action(kind: .clean, paths: [w.path]))
                }
            }
            Button("Copy name") { FoldersView.copy(row.name) }
            Button("Copy path") { FoldersView.copy(w.path) }
            if let branch = w.branch { Button("Copy branch") { FoldersView.copy(branch) } }
            Divider()
            Button(expanded ? "Hide details" : "Show details", action: toggle)
            Button("Reveal in Finder") { store.reveal(w) }
            Button("Open in Terminal") { store.openInTerminal(w) }
        }
        .confirmationDialog("Move \(row.name) to the Trash?", isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Move to Trash") { store.moveToTrash(w) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The whole folder goes to the Trash as it is, unsaved work included, and git is told it is gone. No space is freed until you empty the Trash. The branch stays.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(v.label), \(row.reason)")
        .accessibilityHint(expanded ? "Hides its details" : "Shows its details")
    }
}
