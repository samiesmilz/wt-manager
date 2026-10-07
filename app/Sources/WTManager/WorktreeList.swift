import SwiftUI
import WTManagerKit

/// One section's worktrees, with the detail folded into the row.
///
/// Expanding in place rather than opening a third column: at this width a
/// detail pane squeezes both neighbours, and the details are only wanted for one
/// row at a time anyway.
struct WorktreeList: View {
    @ObservedObject var store: Store
    let section: String
    /// Which row starts expanded. Only the offscreen renderer passes it: the
    /// detail is most of what a row is for, and a snapshot of fifty collapsed
    /// rows is a snapshot of the part that was already visible.
    @State private var open: String?

    init(store: Store, section: String, initiallyOpen: String? = nil) {
        self.store = store
        self.section = section
        // Seeded in the initialiser rather than from `onAppear`: the offscreen
        // renderer makes a bounded number of passes and a state change that
        // arrives on appearance may never be laid out.
        _open = State(initialValue: initiallyOpen)
    }

    private var group: Store.Group? { store.groups.first { $0.id == section } }
    private var emptyText: String {
        if store.filtering { return "Nothing matches that filter." }
        return store.allGroups.first { $0.id == section }?.emptyText ?? "Nothing here."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.allGroups.first { $0.id == section }?.title ?? "Worktrees")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(store.allGroups.first { $0.id == section }?.hint ?? "")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("\(group?.items.count ?? 0)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink(Palette.section(section)))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.wash(Palette.section(section))))
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 5)
            FilterBar(store: store)
            Divider().opacity(0.35)
            if let group, !group.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(group.items, id: \.path) { w in
                            WorktreeRow(store: store, worktree: w,
                                        expanded: open == w.path) {
                                withAnimation(.easeOut(duration: 0.14)) {
                                    open = open == w.path ? nil : w.path
                                }
                            }
                            Hairline(inset: 20)
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text(emptyText)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                    if store.filtering {
                        Button("Clear the filter") {
                            store.query = ""; store.statusFilter = []; store.repoFilter = nil
                        }
                            .buttonStyle(.link).font(.system(size: 11))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct WorktreeRow: View {
    @ObservedObject var store: Store
    let worktree: Worktree
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(Palette.faint).frame(width: 8)
                    StatusDot(status: worktree.status)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(worktree.repo).font(.system(size: 11)).foregroundStyle(Palette.muted)
                            Text(worktree.name).font(.system(size: 13, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Text(store.reason(worktree)).font(.system(size: 11))
                            .foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if worktree.sizeKb > 0 {
                        Text(Store.human(worktree.sizeKb))
                            .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Palette.muted)
                    }
                    Text(Store.ago(worktree.ageDays))
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .frame(width: 92, alignment: .trailing)
                }
                .padding(.horizontal, 20).padding(.vertical, 11)
            }
            .buttonStyle(RowButtonStyle(radius: 0))

            if expanded { detail }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.fixed(104), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 5) {
                field("Status", worktree.status + " — " + worktree.meaning)
                field("Path", worktree.path, mono: true)
                field("Base", "\(worktree.base)  ·  \(worktree.baseSource)")
                field("Ahead / behind", "\(worktree.ahead) ahead, \(worktree.behind) behind")
                field("Last commit", "\(Store.date(worktree.lastCommit))  ·  \(Store.ago(worktree.ageDays))")
                if worktree.dirty > 0 { field("Uncommitted", "\(worktree.dirty) files") }
                if worktree.unpushed > 0 {
                    let others = worktree.unpushed - worktree.atRisk
                    field("Unpushed", worktree.atRisk > 0
                          ? Store.count(worktree.atRisk, "commit") + " of yours, only on this machine"
                            + (others > 0 ? "  ·  \(others) more by others" : "")
                          : Store.count(others, "commit") + " by others, on no remote here",
                          tint: worktree.atRisk > 0 ? Palette.inkRisk : nil)
                }
                if worktree.sizeKb > 0 {
                    field("On disk", "\(Store.human(worktree.sizeKb))"
                          + (worktree.reclaimKb > 0 ? "  ·  \(Store.human(worktree.reclaimKb)) rebuildable" : ""))
                }
            }

            if !worktree.soloLog.isEmpty { soloCommits }

            if let pr = worktree.pr { prProof(pr) }

            HStack(spacing: 7) {
                small("Reveal", "folder") { store.reveal(worktree) }
                small("Terminal", "terminal") { store.openInTerminal(worktree) }
                if worktree.pr?.url.isEmpty == false {
                    small("Pull request", "arrow.up.forward.square") { store.openPR(worktree) }
                }
                Spacer(minLength: 8)
                if worktree.reclaimKb > 0 {
                    small("Review cleanup", "sparkles", tint: Palette.reclaim) {
                        store.preview(Store.Action(kind: .clean, paths: [worktree.path]))
                    }
                }
                if worktree.status == "merged" || worktree.status == "empty" {
                    // A button that can never succeed is worse than no
                    // button: pressing it opened a sheet that thought about
                    // it and said "nothing to do here", which reads as the
                    // app being broken rather than as the answer being no.
                    // Git will not remove a repo's main checkout or the
                    // checkout of its base branch, ever, so the row says so
                    // instead of offering.
                    if let why = refusal {
                        Text("Kept in place")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .help(why)
                    } else {
                        small("Review removal", "scissors", tint: Palette.status("blocked")) {
                            store.preview(Store.Action(kind: .reap, paths: [worktree.path]))
                        }
                    }
                }
            }
            if let why = refusal, ["merged", "empty"].contains(worktree.status) {
                Label(why, systemImage: "lock")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 14)
        .padding(.leading, 16)
    }

    /// What the unpushed commits actually are.
    ///
    /// The row said "6 unpushed" and stopped, which names a stake without
    /// naming what is at stake — and the only way to find out was to open a
    /// terminal, which is the window handing back the question it raised. Five
    /// subjects is enough to recognise the work; the point is recognition, not
    /// a log viewer.
    private var soloCommits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On this machine only")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.inkRisk)
            ForEach(Array(worktree.soloLog.enumerated()), id: \.offset) { _, subject in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(Palette.inkRisk.opacity(0.55))
                        .frame(width: 4, height: 4).padding(.top, 5)
                    Text(subject).font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            if worktree.unpushed > worktree.soloLog.count {
                Text("…and \(worktree.unpushed - worktree.soloLog.count) more")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
            if worktree.dirty > 0 {
                // Said next to the commits, because "push" reads as "safe" and
                // this is the part it does not cover — and on this machine the
                // uncommitted half is the larger one.
                Text("\(worktree.dirty) uncommitted file\(worktree.dirty == 1 ? "" : "s") "
                     + "would stay here even after a push")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(Palette.inkRisk)))
    }

    /// Why this one cannot be removed, if it cannot. Both conditions are
    /// permanent facts about the checkout rather than things that might pass
    /// tomorrow, which is why they are stated rather than left to the plan.
    private var refusal: String? {
        if worktree.removalBlocked { return worktree.removal?.reason }
        if worktree.primary { return "The repo's main checkout — git cannot remove it" }
        if worktree.isBase { return "This is \(worktree.base) itself" }
        return nil
    }

    /// "Merged" is a claim. This is the evidence behind it, with a link to check.
    private func prProof(_ pr: PRInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: pr.state == "MERGED" ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(pr.state == "MERGED" ? Palette.status("merged") : .secondary)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("#\(pr.number) \(pr.state.lowercased())"
                     + (pr.draft ? " · draft" : ""))
                    .font(.system(size: 11.5, weight: .medium))
                Text(proofLine(pr)).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if !pr.url.isEmpty {
                Button("Check") { store.openPR(worktree) }
                    .buttonStyle(.link).font(.system(size: 10.5))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func proofLine(_ pr: PRInfo) -> String {
        if pr.state == "MERGED" {
            var s = "merged"
            if let when = Store.stamp(pr.mergedAt) { s += " " + when }
            if !pr.author.isEmpty { s += " · opened by " + pr.author }
            return s
        }
        if !pr.distinctFailing.isEmpty { return "failing: " + pr.distinctFailing.joined(separator: ", ") }
        if !pr.endemic.isEmpty { return "\(pr.endemic.count) checks failing across the whole repo, not this branch" }
        if pr.review == "CHANGES_REQUESTED" { return "changes requested" }
        if pr.review == "APPROVED" { return "approved" }
        return "checks " + pr.checks
    }

    /// Two cells of the grid, not one view. @ViewBuilder rather than Group
    /// because `Group` is ambiguous here — the store already defines one.
    @ViewBuilder
    private func field(_ label: String, _ value: String,
                       mono: Bool = false, tint: Color? = nil) -> some View {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 10.5, design: mono ? .monospaced : .default))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    private func small(_ title: String, _ icon: String, tint: Color? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .foregroundStyle(tint.map(Palette.ink) ?? .primary)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(tint.map(Palette.wash) ?? Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(tint.map(Palette.edge) ?? Color.primary.opacity(0.10), lineWidth: 1)))
        }
        .buttonStyle(RowButtonStyle(radius: 6))
    }
}

struct StatusDot: View {
    let status: String
    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
    private var color: Color { Palette.status(status) }
}

/// Wraps its children onto as many rows as it needs.
///
/// The chips previously sat in a horizontal ScrollView and simply ran off the
/// right edge — clipped mid-word, with nothing to say more existed. Scrolling
/// sideways to find a filter is a filter nobody uses.
struct Flow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct FilterBar: View {
    @ObservedObject var store: Store
    @FocusState private var focused: Bool

    private var filteredRepoName: String {
        guard let id = store.repoFilter else { return "project" }
        return store.envelope?.worktrees.first {
            ($0.repoId ?? $0.repo) == id
        }?.repo ?? "project"
    }

    private var present: [String] {
        let order = ["blocked", "review", "active", "waiting", "draft", "stale", "merged", "empty", "trunk"]
        let sectionStatuses = Set(Store.spec.first { $0.0 == store.section }?.3 ?? [])
        let have = Set((store.envelope?.worktrees ?? [])
            .map(\.status).filter(sectionStatuses.contains))
        return order.filter(have.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    TextField("filter by repo or branch", text: $store.query)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .focused($focused)
                    if !store.query.isEmpty {
                        Button { store.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.06)))
                Spacer(minLength: 0)
                if store.filtering {
                    Button("clear") {
                        store.query = ""; store.statusFilter = []; store.repoFilter = nil
                    }
                        .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            if let repoFilter = store.repoFilter {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text("Project: \(filteredRepoName)")
                    Button { store.repoFilter = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).accessibilityLabel("Clear project filter")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.muted)
                .help(repoFilter)
            }
            if present.count > 1 { Flow(spacing: 5) {
                ForEach(present, id: \.self) { status in
                    let on = store.statusFilter.contains(status)
                    Button {
                        if on { store.statusFilter.remove(status) }
                        else { store.statusFilter.insert(status) }
                    } label: {
                        // The hue is on the dot and the ground; the word is ink.
                        // White on the stale orange measures 2.1:1, so a selected
                        // chip is a heavier wash with an edge, never a solid fill.
                        HStack(spacing: 5) {
                            Circle().fill(Palette.status(status)).frame(width: 6, height: 6)
                            Text(status).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Palette.ink(status: status) : .primary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3.5)
                        .background(Capsule()
                            .fill(on ? Palette.status(status).opacity(0.20) : Color.primary.opacity(0.05))
                            .overlay(Capsule().strokeBorder(
                                on ? Palette.edge(Palette.status(status)) : Color.primary.opacity(0.08),
                                lineWidth: 1)))
                    }.buttonStyle(RowButtonStyle(radius: 12))
                }
            } }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        // ⌘F. The counter is the request and this is the only thing that
        // answers it: for a while the shortcut incremented `focusFilter` and
        // nothing read it, so the key was swallowed — no focus, and no beep
        // to say the app had declined. A shortcut that silently does nothing
        // is worse than one that does not exist.
        .onChange(of: store.focusFilter) { _ in focused = true }
    }
}
