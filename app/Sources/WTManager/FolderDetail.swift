import SwiftUI
import WTManagerKit

/// What a folder holds, opened under its row. Deleting is the row's job; this
/// is the evidence behind its verdict, and the way out to Finder or Terminal.
struct WorktreeDetail: View {
    @ObservedObject var store: Store
    let worktree: Worktree
    @State private var confirmingPush = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.fixed(104), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 5) {
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

            if let folder = worktree.folder, folder.verdict == "agent" || folder.reason.contains("git worktree unlock") {
                lockPanel(stale: folder.verdict != "agent", reason: folder.reason)
            }

            if !worktree.soloLog.isEmpty { soloCommits }

            if let pr = worktree.linkedPR { prProof(pr) }

            HStack(spacing: 7) {
                if worktree.path.contains("/.claude/worktrees/") {
                    small("Resume in Claude", "play.circle", tint: Palette.brand) { store.resumeInClaude(worktree) }
                }
                if let editor = store.editorChoice {
                    small(editor.name, "chevron.left.forwardslash.chevron.right") { store.openInEditor(worktree) }
                }
                if worktree.atRisk > 0, worktree.branch != nil {
                    small("Push branch", "arrow.up.circle", tint: Palette.risk) { confirmingPush = true }
                }
                small("Reveal", "folder") { store.reveal(worktree) }
                small("Terminal", "terminal") { store.openInTerminal(worktree) }
                if worktree.linkedPR?.url.isEmpty == false {
                    small("Pull request", "arrow.up.forward.square") { store.openPR(worktree) }
                }
                Spacer(minLength: 8)
                if worktree.reclaimKb > 0 {
                    small("Clean caches · \(Store.human(worktree.reclaimKb))", "sparkles", tint: Palette.reclaim) {
                        store.preview(Store.Action(kind: .clean, paths: [worktree.path]))
                    }
                }
            }
        }
        .confirmationDialog("Push \(worktree.branch ?? "this branch") to its remote?",
                            isPresented: $confirmingPush, titleVisibility: .visible) {
            Button("Push") { store.runCommand(["push", "--path", worktree.path, "--yes"]) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends the commits that exist only on this Mac. Uncommitted edits stay here.")
        }
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
                .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if worktree.dirty > 0 {
                // Said next to the commits, because "push" reads as "safe" and
                // this is the part it does not cover — and on this machine the
                // uncommitted half is the larger one.
                Text("\(worktree.dirty) uncommitted file\(worktree.dirty == 1 ? "" : "s") "
                     + "would stay here even after a push")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(Palette.inkRisk)))
    }

    /// A locked folder: held by a running agent, or by one that has gone.
    /// The first is left alone; the second gets the command that frees it.
    private func lockPanel(stale: Bool, reason: String) -> some View {
        let tint: Color = stale ? Palette.risk : Palette.brand
        let command: String = "git worktree unlock '" + worktree.path + "'"
        return VStack(alignment: .leading, spacing: 6) {
            Text(stale ? "The session that locked this has ended" : "An agent session is working here")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink(tint))
            Text(stale ? "Nothing is deleted by unlocking. It runs this for you:"
                       : "Deleting and cleaning are off while it runs. The lock is released when the session ends.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if stale {
                HStack(spacing: 8) {
                    Text(command).font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button(store.commandRunning ? "Unlocking…" : "Unlock") {
                        store.runCommand(["unlock", "--path", worktree.path])
                    }
                    .controlSize(.small).disabled(store.commandRunning)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.wash(tint)))
    }

    /// "Merged" is a claim. This is the evidence behind it, with a link to check.
    private func prProof(_ pr: PRInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: pr.state == "MERGED" ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(pr.state == "MERGED" ? Palette.status("merged") : .secondary)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "#\(pr.number) \(pr.state.lowercased())"
                     + (pr.draft ? " · draft" : ""))
                    .font(.system(size: 11, weight: .medium))
                Text(proofLine(pr)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if !pr.url.isEmpty {
                Button("Open PR") { store.openPR(worktree) }
                    .buttonStyle(.link).font(.system(size: 11))
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
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    private func small(_ title: String, _ icon: String, tint: Color? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .foregroundStyle(tint.map(Palette.ink) ?? .primary)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(tint.map(Palette.wash) ?? Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.map(Palette.edge) ?? Color.primary.opacity(0.10), lineWidth: 1)))
        }
        .buttonStyle(RowButtonStyle(radius: 8))
    }
}

/// The page's one filter: a folder, branch or repo name.
struct FilterBar: View {
    @ObservedObject var store: Store
    /// In the header: no margins of its own.
    var compact = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            TextField("Folder, branch or repo", text: $store.query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .focused($focused)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                .accessibilityLabel("Clear the filter")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.06)))
        .padding(.horizontal, compact ? 0 : 20).padding(.vertical, compact ? 0 : 10)
        // ⌘F. The counter is the request and this is the only thing that
        // answers it: a shortcut that silently does nothing is worse than one
        // that does not exist.
        .onChange(of: store.focusFilter) { _ in focused = true }
    }
}
