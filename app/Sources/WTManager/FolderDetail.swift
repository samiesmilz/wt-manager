import SwiftUI
import WTManagerKit

/// A folder's row, opened: one tinted panel, as the design draws it. What is
/// only here, said in the folder's own commit subjects, then what you can do
/// about it.
struct WorktreeDetail: View {
    @ObservedObject var store: Store
    let worktree: Worktree
    @State private var confirmingPush = false

    private enum Tone { case agent, stale, risk, plain }

    private var tone: Tone {
        if let folder = worktree.folder {
            if folder.verdict == "agent" { return .agent }
            if folder.reason.contains("git worktree unlock") { return .stale }
        }
        if worktree.atRisk > 0 || worktree.dirty > 0 { return .risk }
        return .plain
    }

    private var title: String {
        switch tone {
        case .agent: return "An agent session is working here"
        case .stale: return "The session that locked this has ended"
        case .risk:  return "Only on this Mac"
        case .plain: return "Nothing here is at risk"
        }
    }

    private var ink: Color {
        switch tone {
        case .agent: return Palette.agentInk
        case .stale, .risk: return Palette.riskInk
        case .plain: return Palette.muted
        }
    }

    private var fill: Color {
        switch tone {
        case .agent: return Palette.quiet
        case .stale, .risk: return Palette.warnFill
        case .plain: return Palette.quiet
        }
    }

    private var stroke: Color {
        switch tone {
        case .agent: return Palette.line
        case .stale, .risk: return Palette.warnLine
        case .plain: return Palette.line
        }
    }

    /// The muted sentence under the list: what a push or an unlock would and
    /// would not do.
    private var note: String? {
        switch tone {
        case .agent:
            return "Deleting and cleaning are off while it runs. The lock is released when the session ends."
        case .stale:
            return "Claude Code clears stale locks itself on a later run. You can also release it now; nothing is deleted by unlocking."
        case .risk:
            if worktree.dirty > 0 && worktree.atRisk > 0 {
                return "Plus " + Store.count(worktree.dirty, "uncommitted file")
                    + ". Pushing the branch would cover the commits, not the edits."
            }
            if worktree.dirty > 0 {
                return Store.count(worktree.dirty, "uncommitted file") + ", in no commit yet."
            }
            if worktree.unpushed > worktree.soloLog.count {
                return "And \(worktree.unpushed - worktree.soloLog.count) more commits on no remote."
            }
            return nil
        case .plain:
            return nil
        }
    }

    private var facts: String {
        var parts: [String] = ["Based on " + worktree.base]
        parts.append("\(worktree.ahead) ahead, \(worktree.behind) behind")
        if worktree.lastCommit > 0 { parts.append("last commit " + Store.ago(worktree.ageDays)) }
        if worktree.reclaimKb > 0 { parts.append(Store.human(worktree.reclaimKb) + " rebuildable") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                ForEach(Array(worktree.soloLog.enumerated()), id: \.offset) { _, subject in
                    Text(subject).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                }
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(worktree.path).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Text(facts).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.tail)
                if let pr = worktree.linkedPR {
                    Text(verbatim: "PR #\(pr.number) " + pr.state.lowercased() + (pr.draft ? " · draft" : "")
                         + " · " + proofLine(pr))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions(0..<8) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { actions(0..<3) }
                    HStack(spacing: 8) { actions(3..<8) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1))
        .confirmationDialog("Push \(worktree.branch ?? "this branch") to its remote?",
                            isPresented: $confirmingPush, titleVisibility: .visible) {
            Button("Push") { store.runCommand(["push", "--path", worktree.path, "--yes"]) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends the commits that exist only on this Mac. Uncommitted edits stay here.")
        }
    }

    private struct Act {
        let title: String
        let primary: Bool
        let run: () -> Void
    }

    private var acts: [Act] {
        var out: [Act] = []
        let claude: Bool = worktree.path.contains("/.claude/worktrees/")
        if tone == .stale {
            out.append(Act(title: store.commandRunning ? "Unlocking…" : "Unlock", primary: true) {
                store.runCommand(["unlock", "--path", worktree.path])
            })
        } else if claude {
            out.append(Act(title: tone == .agent ? "Open session" : "Resume in Claude", primary: true) {
                store.resumeInClaude(worktree)
            })
        }
        if store.editorChoice != nil {
            out.append(Act(title: "Open in editor", primary: false) { store.openInEditor(worktree) })
        }
        out.append(Act(title: "Terminal", primary: false) { store.openInTerminal(worktree) })
        out.append(Act(title: "Reveal in Finder", primary: false) { store.reveal(worktree) })
        if tone != .agent, worktree.atRisk > 0, worktree.branch != nil {
            out.append(Act(title: "Push branch", primary: false) { confirmingPush = true })
        }
        if worktree.linkedPR?.url.isEmpty == false {
            out.append(Act(title: "Pull request", primary: false) { store.openPR(worktree) })
        }
        if tone != .agent, worktree.reclaimKb > 0 {
            out.append(Act(title: "Clean caches · " + Store.human(worktree.reclaimKb), primary: false) {
                store.preview(Store.Action(kind: .clean, paths: [worktree.path]))
            })
        }
        return out
    }

    private func actions(_ range: Range<Int>) -> some View {
        let all: [Act] = acts
        let slice: [Act] = Array(all[min(range.lowerBound, all.count)..<min(range.upperBound, all.count)])
        return ForEach(Array(slice.enumerated()), id: \.offset) { _, act in
            Button(act.title, action: act.run)
                .buttonStyle(.wt(act.primary ? .primary : .quiet))
                .disabled(store.commandRunning && act.title.hasPrefix("Unlock"))
        }
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
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
        .padding(.horizontal, compact ? 0 : 20).padding(.vertical, compact ? 0 : 10)
        // ⌘F. The counter is the request and this is the only thing that
        // answers it: a shortcut that silently does nothing is worse than one
        // that does not exist.
        .onChange(of: store.focusFilter) { _ in focused = true }
    }
}
