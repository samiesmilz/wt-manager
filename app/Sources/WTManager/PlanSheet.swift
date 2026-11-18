import SwiftUI
import WTManagerKit

/// The confirmation.
///
/// Three things make this safe rather than merely polite:
///
/// * **What you approve is a set, not a filter.** The preview is the engine's
///   own dry run as data - every path it would touch, and a hash of that set.
///   The commit hands the paths and the hash back, and the engine refuses to
///   act if the set has moved. A `dist/` a build wrote after you looked is never
///   deleted unseen.
/// * **The button says the consequence**, not "OK". A button labelled with the
///   thing it will destroy is read; a button labelled "Confirm" is clicked.
/// * **Scope is spelled out at the top**, because "clean" meaning one worktree
///   and "clean" meaning ninety are one keystroke apart everywhere else.
struct PlanSheet: View {
    @ObservedObject var store: Store
    let plan: Store.Plan
    @State private var showRaw = false
    @State private var typed: String = ""
    /// Sizes as they were when the sheet opened: a deleted folder leaves the
    /// envelope on the next refresh, and the result still has to say how big
    /// it was.
    @State private var sizes: [String: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pad: CGFloat = 28

    private var sheetWidth: CGFloat {
        min(720, max(600, (NSApp.mainWindow?.contentView?.bounds.width ?? 780) - 32))
    }
    private var height: CGFloat {
        let ceiling = min(720, (NSScreen.main?.visibleFrame.height ?? 800) - 100)
        switch plan.stage {
        case .previewing: return 300
        case .committing:
            let n = min(preview?.paths.count ?? 0, 8)
            return min(ceiling, 330 + CGFloat(n > 1 ? n : 0) * 22)
        case .reviewing:
            guard let p = preview, !p.paths.isEmpty else { return 380 }
            var rows: CGFloat = 0
            for path in p.paths { rows += 40 + CGFloat(notes(path, p).count) * 23 }
            rows += CGFloat(p.skipped.count) * 40 + (p.skipped.isEmpty ? 0 : 36)
            if mustType != nil { rows += 170 }
            return min(ceiling, max(460, 330 + rows))
        case .done:
            let failed = failedPaths.count
            return min(ceiling, max(440, 330 + CGFloat(doneRows.count) * 66 + CGFloat(failed) * 80))
        case .failed: return min(ceiling, 460)
        case .changed: return min(ceiling, 380)
        }
    }

    /// "Delete anyway" on one folder asks for its name: the one delete that
    /// can lose something should not be a reflex.
    private var mustType: String? {
        guard plan.action.discardWork, let p = preview, p.paths.count == 1 else { return nil }
        return URL(fileURLWithPath: p.paths[0]).lastPathComponent
    }
    private var kind: Store.ActionKind { plan.action.kind }
    private var preview: Store.PlanResult? { plan.preview }
    private var destructive: Bool { plan.stage == .reviewing && !(preview?.paths.isEmpty ?? true) }
    private var failedCount: Int { plan.result?.failed ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Hairline()
            if destructive, mustType == nil, let p = preview {
                reviewStats(p)
                Hairline()
            }
            if plan.stage == .done, let r = plan.result {
                doneStats(r)
                Hairline()
            }
            outcome.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Hairline()
            footer
        }
        .frame(width: sheetWidth, height: height)
        .background(Palette.ground)
        .overlay { if plan.stage == .done, let id = store.celebration {
            PixelCelebration().id(id).allowsHitTesting(false)
        } }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: plan.stage)
        .onAppear { remember() }
        .onChange(of: plan.stage) { _ in remember() }
    }

    private func remember() {
        for w in store.envelope?.worktrees ?? [] {
            let kb: Int = kind == .clean ? w.reclaimKb : w.sizeKb
            if kb > 0 { sizes[w.path] = kb }
        }
    }

    private func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    private func worktree(_ path: String) -> Worktree? {
        store.envelope?.worktrees.first { $0.path == path }
    }

    private func size(_ path: String) -> String? {
        if let kb = sizes[path] { return Store.human(kb) }
        guard let w = worktree(path) else { return nil }
        let kb: Int = kind == .clean ? w.reclaimKb : w.sizeKb
        return kb > 0 ? Store.human(kb) : nil
    }

    private func listed(_ names: [String]) -> String {
        let head: String = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? head + " and \(names.count - 3) more" : head
    }

    // MARK: heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headingTitle).font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(headingBlurb).font(.system(size: 13)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, pad).padding(.top, 26).padding(.bottom, 20)
    }

    /// The colour the action owns.
    private var barTint: Color {
        switch kind {
        case .reap:  return Palette.status("merged")
        case .clean: return Palette.reclaim
        }
    }

    private var verbPast: String {
        switch kind {
        case .reap:  return "removed"
        case .clean: return "deleted"
        }
    }

    /// The one repo every folder in the plan belongs to, when there is one.
    private func sharedRepo(_ paths: [String]) -> String? {
        let repos = Set(paths.compactMap { worktree($0)?.repo })
        return repos.count == 1 ? repos.first : nil
    }

    private var headingTitle: String {
        switch plan.stage {
        case .done:
            guard let r = plan.result else { return "Done" }
            let total: Int = r.completedPaths.count + r.failed
            if r.failed > 0 {
                if r.completedPaths.isEmpty { return "Could not finish" }
                return kind == .reap ? "Deleted \(r.completedPaths.count) of \(total) folders"
                                     : "Cleaned \(r.completedPaths.count) of \(total) folders"
            }
            let n: Int = max(r.completedPaths.count, r.removed)
            return (kind == .reap ? "Deleted " : "Cleaned ") + Store.count(n, "folder")
        case .failed:  return "That did not work"
        case .changed: return "The plan changed"
        case .committing:
            let n: Int = preview?.paths.count ?? 0
            return (kind == .reap ? "Deleting " : "Cleaning ") + Store.count(n, "folder") + "…"
        case .reviewing:
            guard let p = preview, !p.paths.isEmpty, kind == .reap else { return plan.action.title }
            let n: Int = p.paths.count
            if plan.action.discardWork {
                return n == 1 ? "Delete \(name(p.paths[0])) anyway?" : "Delete \(n) folders anyway?"
            }
            if n == 1 { return "Delete \(name(p.paths[0]))?" }
            if let repo = sharedRepo(p.paths) { return "Delete \(n) folders in \(repo)?" }
            return "Delete \(n) folders?"
        case .previewing: return plan.action.title
        }
    }

    private var headingBlurb: String {
        switch plan.stage {
        case .done:
            guard let r = plan.result else { return "" }
            if r.failed > 0 {
                let left: String = r.failed == 1 ? "One folder was left in place." : "\(r.failed) folders were left in place."
                return left + " Nothing was lost."
            }
            if store.busy { return "Everything in the plan completed. Updating the rest of the window…" }
            switch kind {
            case .reap:  return "Everything in the plan completed."
            case .clean: return "The folders are untouched; only build output went. It comes back with a build or an install."
            }
        case .failed:
            return "The operation could not finish. The engine’s message is below."
        case .changed:
            return "A confirmation only covers exactly what you reviewed."
        case .committing:
            return kind == .reap ? "Through git, one folder at a time."
                                 : "Build output only, one folder at a time."
        case .reviewing:
            guard let p = preview, !p.paths.isEmpty else { return plan.action.blurb }
            if let _ = mustType {
                var parts: [String] = []
                if let repo = worktree(p.paths[0])?.repo { parts.append(repo) }
                if let s = size(p.paths[0]) { parts.append(s) }
                parts.append("unsaved work")
                return parts.joined(separator: " · ")
            }
            if kind == .reap {
                return plan.action.discardWork
                    ? "Work is saved first, then each folder is removed. Each folder is checked again first."
                    : "Nothing is deleted until you confirm. Each folder is checked again first."
            }
            return plan.action.blurb
        case .previewing:
            return plan.action.blurb
        }
    }

    // MARK: figures

    private func figure(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold)).monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private func reviewStats(_ p: Store.PlanResult) -> some View {
        let n: Int = p.paths.count
        let base: String = kind == .reap ? (n == 1 ? "folder" : "folders") : (n == 1 ? "checkout cleaned" : "checkouts cleaned")
        let extra: String = (kind == .reap && !p.branches.isEmpty)
            ? (n == 1 ? " and its finished branch" : " and their finished branches") : ""
        let noun: String = base + extra
        return HStack(alignment: .top, spacing: 36) {
            if p.kb > 0 {
                figure(Store.human(p.kb), "returned to the disk", tint: Palette.safeInk)
            }
            figure("\(n)", noun, tint: Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad).padding(.vertical, 18)
    }

    private func doneStats(_ r: Store.PlanResult) -> some View {
        let n: Int = max(r.completedPaths.count, r.removed)
        return HStack(alignment: .top, spacing: 36) {
            if r.freedKb > 0 {
                figure(Store.human(r.freedKb), kind == .reap ? "returned to the disk" : "of build output deleted",
                       tint: Palette.safeInk)
            }
            if r.failed > 0 {
                figure("\(r.failed)", r.failed == 1 ? "folder left in place" : "folders left in place",
                       tint: Palette.riskInk)
            } else {
                figure("\(n)", kind == .reap ? (n == 1 ? "folder removed" : "folders removed")
                                             : (n == 1 ? "folder, still there" : "folders, all still there"),
                       tint: Color.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad).padding(.vertical, 18)
    }

    // MARK: body

    /// Named `outcome` rather than `body`: a View already has one.
    @ViewBuilder
    private var outcome: some View {
        switch plan.stage {
        case .previewing:
            if store.busy && plan.progress == nil {
                working("Waiting for the current scan", "The preview starts when the background scan finishes. Nothing has changed.")
            } else {
                working("Working out exactly what this would do", "Nothing has changed yet.")
            }
        case .committing:
            switch kind {
            case .reap:  working("Deleting", "Through git, one folder at a time.")
            case .clean: working("Cleaning", "Build output only, one folder at a time.")
            }
        case .failed:
            ScrollView {
                Text(plan.failed ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.riskInk).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(pad)
            }
        case .changed:
            ScrollView { changed }
        case .reviewing:
            if let p = preview { review(p) }
        case .done:
            ScrollView { done }
        }
    }

    /// The wait, with something in it.
    ///
    /// This used to be a bare indeterminate spinner, and the scan behind it
    /// takes up to ninety seconds — over that long a wait a spinner and a hang
    /// look exactly alike. The engine now says how far along it is on stderr,
    /// so when it knows, this is a real bar; when it does not, the elapsed
    /// clock still distinguishes working from stuck.
    private func working(_ title: String, _ sub: String) -> some View {
        let current: Engine.Progress? = plan.progress ?? (store.busy ? store.scanProgress : nil)
        let paths: [String] = plan.stage == .committing ? (preview?.paths ?? []) : []
        // The last pass is the one that removes; everything before it is the
        // engine checking each folder again.
        let acting: Bool = current.map { $0.step == $0.steps } ?? false
        let done: Int = acting ? min(current?.done ?? 0, paths.count) : 0
        let verb: String = kind == .reap ? "Removing" : "Cleaning"
        let head: String
        if !paths.isEmpty {
            head = acting && done < paths.count ? verb + " " + name(paths[done])
                                                : "Checking " + (paths.count == 1 ? "the folder" : "all \(paths.count) folders") + " again"
        } else if store.busy && plan.progress == nil {
            head = title
        } else {
            head = current.map { phaseNames($0)[min($0.step - 1, phaseNames($0).count - 1)] } ?? title
        }
        let fraction: Double?
        if !paths.isEmpty {
            fraction = acting ? min(1, (Double(done) + 0.5) / Double(paths.count)) : 0.04
        } else {
            fraction = current?.fraction
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(head).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if !paths.isEmpty && acting {
                    Text("\(min(done + 1, paths.count)) of \(paths.count)")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.muted)
                }
                TimerText(since: plan.since)
            }
            Bar(fraction: fraction, tint: Palette.safeInk)
            if paths.isEmpty {
                Text(current?.label.isEmpty == false ? current!.label : sub)
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    stepRow(acting ? 0 : 1,
                            (acting ? "Checked " : "Checking ")
                            + (paths.count == 1 ? "the folder" : "all \(paths.count) folders") + " again")
                    ForEach(Array(paths.prefix(8).enumerated()), id: \.offset) { i, path in
                        stepRow(!acting ? 2 : i < done ? 0 : i == done ? 1 : 2, stepText(path, at: i, done: acting ? done : -1))
                    }
                    if paths.count > 8 {
                        Text("and \(paths.count - 8) more").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, pad).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What one folder's line says: done, in hand, or still to come.
    private func stepText(_ path: String, at i: Int, done: Int) -> String {
        let folder: String = name(path)
        let branch: Bool = !(preview?.branches[path] ?? "").isEmpty
        if kind == .clean {
            return i < done ? "Cleaned " + folder : i == done ? "Cleaning " + folder : "Clean " + folder
        }
        if i < done {
            return "Removed " + folder + (size(path).map { " · " + $0 } ?? "")
        }
        if i == done { return "Removing " + folder + (branch ? " and its branch" : "") }
        if let p = preview, !p.keptIn.isEmpty, let kept = p.precious[path], !kept.isEmpty {
            return "Set aside " + listed(kept) + ", then remove " + folder
        }
        return "Remove " + folder + (branch ? " and its branch" : "")
    }

    /// 0 done, 1 in hand, 2 still to come.
    private func stepRow(_ state: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: state == 0 ? "checkmark" : "circle")
                .font(.system(size: state == 0 ? 10 : 11, weight: state == 2 ? .regular : .bold))
                .foregroundStyle(state == 0 ? Palette.safeInk : state == 1 ? Color.primary : Palette.faint)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 13, weight: state == 1 ? .semibold : .regular))
                .foregroundStyle(state == 0 ? Palette.safeInk : state == 1 ? Color.primary : Palette.muted)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func folderSteps(_ paths: [String], at done: Int, more: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(paths.enumerated()), id: \.offset) { i, path in
                HStack(spacing: 8) {
                    Image(systemName: i < done ? "checkmark.circle.fill" : i == done ? "circle.inset.filled" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(i < done ? Palette.inkReclaim : i == done ? Color.primary : Palette.faint)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 12, weight: i == done ? .semibold : .regular))
                        .foregroundStyle(i <= done ? Color.primary : Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if more > 0 {
                Text("and \(more) more").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseNames(_ p: Engine.Progress) -> [String] {
        if p.steps == 4 && kind == .reap { return ["Read repos", "Measure", "Check safety", "Preserve & remove"] }
        if p.steps == 3 && kind == .reap { return ["Read repos", "Measure", "Check safety"] }
        if p.steps == 3 { return ["Read repos", "Measure", "Clean"] }
        if p.steps == 2 { return ["Read repos", "Measure"] }
        return ["Working"]
    }

    // MARK: review

    /// One line under a folder: what happens to something in it. A tick is
    /// kept or harmless; a cross is gone for good.
    private struct Note { let ok: Bool; let text: String }

    private func notes(_ path: String, _ p: Store.PlanResult) -> [Note] {
        var out: [Note] = []
        if kind == .clean {
            let e: [String] = p.entries[path] ?? []
            if !e.isEmpty { out.append(Note(ok: true, text: listed(e) + " deleted; comes back with a build")) }
            return out
        }
        if !plan.action.discardWork, let reason = worktree(path)?.folder?.reason, !reason.isEmpty {
            out.append(Note(ok: true, text: reason.prefix(1).uppercased() + reason.dropFirst()))
        }
        if let c = p.commits[path], !c.isEmpty {
            out.append(Note(ok: true, text: c.prefix(1).uppercased() + c.dropFirst()))
        }
        if let ch = p.changes[path], !ch.isEmpty {
            out.append(Note(ok: true, text: Store.count(ch.count, "edit") + " saved as a patch in Kept files"))
        }
        if let b = p.branches[path], !b.isEmpty {
            out.append(Note(ok: true, text: "Branch \(b) deleted too"))
        }
        if let d = p.duplicates[path], !d.isEmpty {
            out.append(Note(ok: true, text: listed(d) + (d.count == 1 ? " is" : " are")
                            + " identical to the main checkout’s, nothing to save"))
        }
        if let pr = p.precious[path], !pr.isEmpty {
            if p.keptIn.isEmpty {
                out.append(Note(ok: false, text: listed(pr) + (pr.count == 1 ? " goes" : " go") + " with the folder"))
            } else {
                out.append(Note(ok: true, text: listed(pr) + " copied to Kept files and verified first"))
            }
        }
        if let u = p.unknown[path], !u.isEmpty {
            out.append(Note(ok: p.keepsUnknown, text: listed(u)
                            + (p.keepsUnknown ? " set aside too, unrecognised" : " removed too, unrecognised")))
        }
        if let dr = p.droppedUnknown[path], !dr.isEmpty {
            out.append(Note(ok: false, text: listed(dr) + " · unrecognised files, too large to set aside"))
        }
        return out
    }

    private func noteRow(_ n: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: n.ok ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(n.ok ? Palette.safeInk : Palette.danger)
                .frame(width: 13)
            Text(n.text).font(.system(size: 13)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func folderHead(_ path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name(path)).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.middle).help(path)
            Spacer(minLength: 8)
            if let s = size(path) {
                Text(s).font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.muted)
            }
        }
    }

    /// Every folder in the plan, each with what happens to what is in it.
    private func itemList(_ p: Store.PlanResult) -> some View {
        CardBox {
            ForEach(Array(p.paths.enumerated()), id: \.element) { i, path in
                if i > 0 { Hairline().padding(.horizontal, 18) }
                VStack(alignment: .leading, spacing: 7) {
                    folderHead(path)
                    ForEach(Array(notes(path, p).enumerated()), id: \.offset) { _, n in noteRow(n) }
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
            }
        }
    }

    private func leftAlone(_ items: [Store.PlanResult.Skipped]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Left alone").padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.element.path) { i, s in
                if i > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(s.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(s.why).font(.system(size: 12))
                        .foregroundStyle(s.why.lowercased().contains("session") || s.why.lowercased().contains("agent")
                                         ? Palette.agentInk : Palette.riskInk)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 10)
            }
        }
    }

    /// The one delete that can lose something, laid out as what is saved and
    /// what is not.
    private func anyway(_ p: Store.PlanResult, name folder: String) -> some View {
        let all: [Note] = notes(p.paths[0], p)
        let saved: [Note] = all.filter { $0.ok }
        let lost: [Note] = all.filter { !$0.ok }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.riskInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This folder holds work that exists nowhere else")
                        .font(.system(size: 13, weight: .semibold))
                    Text("It is saved first, then the folder is removed. The copy is not a full backup of the checkout.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.warnFill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.warnLine, lineWidth: 1))

            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved before deleting").font(.system(size: 13, weight: .semibold))
                    if saved.isEmpty {
                        Text("Nothing here needs saving.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(saved.enumerated()), id: \.offset) { _, n in noteRow(n) }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                if !lost.isEmpty {
                    Hairline().padding(.horizontal, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deleted and not coming back").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(lost.enumerated()), id: \.offset) { _, n in noteRow(n) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Type the folder name to confirm").font(.system(size: 12)).foregroundStyle(Palette.muted)
                TextField(folder, text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.controlLine, lineWidth: 1))
                    .accessibilityLabel("Type the folder name to confirm")
            }
        }
    }

    @ViewBuilder
    private func review(_ p: Store.PlanResult) -> some View {
        if p.paths.isEmpty {
            // Two different empty results. "Nothing to do" is all-clear; a
            // refusal is not, and its reason is the only thing worth showing.
            let refused: Bool = !p.skipped.isEmpty
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(refused
                         ? (p.skipped.count == 1 ? "That one cannot be \(verbPast)." : "None of these can be \(verbPast).")
                         : "Nothing to do here.")
                        .font(.system(size: 13, weight: refused ? .semibold : .regular))
                        .foregroundStyle(refused ? Color.primary : Palette.muted)
                    if refused { leftAlone(p.skipped) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, pad).padding(.vertical, 22)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let folder = mustType {
                        anyway(p, name: folder)
                    } else {
                        itemList(p)
                    }
                    if !p.skipped.isEmpty { leftAlone(p.skipped) }
                    rawToggle(p.text)
                }
                .padding(.horizontal, pad).padding(.vertical, 22)
            }
        }
    }

    private func rawToggle(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { showRaw.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(showRaw ? 90 : 0))
                    Text("Details").font(.system(size: 11))
                }
                .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            if showRaw {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.04)))
            }
        }
    }

    // MARK: changed

    private var changed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.agentInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Something changed after you reviewed it")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Nothing was \(verbPast). Review the updated plan to continue.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.quiet))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1))
            if let text = plan.result?.text, !text.isEmpty {
                rawToggle(text)
            }
        }
        .padding(.horizontal, pad).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: done

    private var doneRows: [String] {
        guard plan.stage == .done, let r = plan.result else { return [] }
        return r.completedPaths
    }

    /// What the plan held that did not complete.
    private var failedPaths: [String] {
        guard plan.stage == .done, let r = plan.result, r.failed > 0 else { return [] }
        return (preview?.paths ?? []).filter { !r.completedPaths.contains($0) }
    }

    private func doneNote(_ path: String) -> String {
        if kind == .clean { return "Build output removed; the folder is still there" }
        var text: String = "Folder removed"
        if let b = preview?.branches[path], !b.isEmpty { text = "Folder and branch removed" }
        if let p = preview, !p.keptIn.isEmpty || !p.changesKeptIn.isEmpty {
            var kept: [String] = p.keptIn.isEmpty ? [] : (p.precious[path] ?? [])
            if p.keepsUnknown { kept += p.unknown[path] ?? [] }
            if !kept.isEmpty {
                text += " · " + listed(kept) + (kept.count == 1 ? " is" : " are") + " in Kept files"
            } else if let ch = p.changes[path], !ch.isEmpty {
                text += " · " + Store.count(ch.count, "edit") + " saved in Kept files"
            }
        }
        return text
    }

    /// The engine's own sentence about a folder that did not finish.
    private func failureNote(_ path: String) -> String {
        let folder: String = name(path)
        for raw in (plan.result?.text ?? "").split(separator: "\n") {
            let line = String(raw)
            guard line.lowercased().hasPrefix("failed"), line.contains(folder) else { continue }
            if let r = line.range(of: ": ") {
                let why = String(line[r.upperBound...])
                return why
            }
        }
        return "Could not be finished, so the folder was left exactly as it was"
    }

    private var anythingKept: Bool {
        guard kind == .reap, let p = preview else { return false }
        let done = Set(doneRows)
        if !p.keptIn.isEmpty, p.precious.keys.contains(where: { done.contains($0) }) { return true }
        if p.keepsUnknown, p.unknown.keys.contains(where: { done.contains($0) }) { return true }
        return p.changes.keys.contains(where: { done.contains($0) })
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !doneRows.isEmpty {
                CardBox {
                    ForEach(Array(doneRows.enumerated()), id: \.element) { i, path in
                        if i > 0 { Hairline().padding(.horizontal, 18) }
                        VStack(alignment: .leading, spacing: 7) {
                            folderHead(path)
                            noteRow(Note(ok: true, text: doneNote(path)))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 13)
                    }
                }
            }
            if !failedPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GroupLabel("Not removed")
                    CardBox {
                        ForEach(Array(failedPaths.enumerated()), id: \.element) { i, path in
                            if i > 0 { Hairline().padding(.horizontal, 18) }
                            VStack(alignment: .leading, spacing: 7) {
                                folderHead(path)
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Palette.riskInk).frame(width: 13)
                                    Text(failureNote(path)).font(.system(size: 13))
                                        .foregroundStyle(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 13)
                        }
                    }
                }
            } else if failedCount > 0, let text = plan.result?.text {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.riskInk).textSelection(.enabled)
            }
            if let r = plan.result, !r.text.isEmpty, showRaw || failedCount == 0 {
                rawToggle(r.text)
            }
        }
        .padding(.horizontal, pad).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: footer

    private var footerNote: String {
        switch plan.stage {
        case .reviewing:
            guard destructive else { return "" }
            if mustType != nil { return "Shown once more because this is the one delete that can lose something." }
            return kind == .reap
                ? "Folders are removed through git and cannot be restored from here."
                : "Comes back with a build or install, not with undo."
        case .committing: return "Quit is off until this finishes."
        case .done: return failedCount > 0 ? "Only completed removals count toward space freed." : ""
        default: return ""
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerNote).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            switch plan.stage {
            case .previewing:
                Button("Close preview") { store.plan = nil }
                    .buttonStyle(.wt(.secondary)).keyboardShortcut(.cancelAction)
            case .committing:
                // Nothing to press while a delete is in flight: closing the
                // sheet would not stop it, and a Cancel that does not cancel
                // is a lie about what it does.
                Button("Working…") { }.buttonStyle(.wt(.secondary)).disabled(true)
            case .reviewing:
                Button(destructive ? "Cancel" : "Close") { store.plan = nil }
                    .buttonStyle(.wt(.secondary)).keyboardShortcut(.cancelAction)
                if destructive {
                    // Labelled with the consequence: a button that names what
                    // it destroys gets read, one that says "Confirm" gets clicked.
                    Button(confirmLabel) { store.commit() }
                        .buttonStyle(.wt(kind == .reap ? .danger : .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(mustType != nil && typed != mustType)
                }
            case .failed, .changed:
                Button(plan.stage == .changed ? "Cancel" : "Close") { store.plan = nil }
                    .buttonStyle(.wt(.secondary)).keyboardShortcut(.cancelAction)
                Button("Review again") { store.preview(plan.action) }
                    .buttonStyle(.wt(.primary)).keyboardShortcut(.defaultAction)
            case .done:
                if failedCount > 0 {
                    Button(showRaw ? "Hide details" : "Details") { showRaw.toggle() }
                        .buttonStyle(.wt(.secondary))
                    Button("Close") { store.plan = nil }
                        .buttonStyle(.wt(.secondary)).keyboardShortcut(.cancelAction)
                    // What failed was left exactly as it was, so the same
                    // request reviewed again is the rest of the job.
                    Button(failedCount == 1 ? "Try that one again" : "Try the rest again") {
                        store.preview(plan.action)
                    }
                    .buttonStyle(.wt(.primary)).keyboardShortcut(.defaultAction)
                } else {
                    if anythingKept {
                        Button("Show kept files") { store.page = .kept; store.plan = nil }
                            .buttonStyle(.wt(.secondary))
                    }
                    Button("Done") { store.plan = nil }
                        .buttonStyle(.wt(.primary)).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, pad).padding(.vertical, 16)
    }

    private var confirmLabel: String {
        guard let p = preview else { return kind.verb }
        let n: Int = p.paths.count
        if kind == .reap {
            if plan.action.discardWork {
                return n == 1 ? "Save work, then delete" : "Save work, then delete \(n)"
            }
            return n == 1 ? "Delete folder" : "Delete \(n) folders"
        }
        return p.kb > 0 ? "Clean \(Store.human(p.kb))" : "Clean it"
    }
}


/// Seconds since a wait began, ticking once a second.
///
/// Its own clock, not the mascot's: this one only exists while a sheet is up,
/// and the mascot's runs at four and a half hertz for a blink nobody needs
/// behind a modal.
struct TimerText: View {
    let since: Date
    @State private var now = Date()
    private let beat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(label)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Palette.muted)
            .monospacedDigit()
            .onReceive(beat) { now = $0 }
    }

    private var label: String {
        let s = Int(now.timeIntervalSince(since))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}


/// The progress bar, drawn rather than borrowed, and segmented because a run
/// is not one measurement.
///
/// `ProgressView(value:)` on macOS is an `NSProgressIndicator` underneath and
/// does not take the palette's tint, so the one colour in the app that means
/// "this is reclaiming space" came out system grey. That is why it is drawn.
///
/// **Why it is segmented.** A run makes several passes — read the repos,
/// measure them, remove what you approved — and the second cannot even be
/// counted until the first has finished, so they cannot share a scale. Drawn
/// on one continuous bar, the fill reached the end, *slid back* to a fifth and
/// climbed again, twice. A caption naming the pass made that legible and did
/// not make it feel right: a progress fill that retreats reads as failure, and
/// you feel it a beat before you read anything.
///
/// One segment per pass fixes the feeling rather than explaining it. Finished
/// segments stay full, so the ink on screen only ever increases across the
/// whole run, while each segment keeps its own honest scale. The alternative —
/// one bar weighted across all three — is a worse lie: reading is about four
/// seconds against eighty for measuring, so any weighting by item count
/// sprints to a third and then appears to hang.
///
/// A ring was the other candidate and solves none of this. A ring that fills
/// to 360° and snaps back to 20° is the same retreat, curled; the scale is the
/// problem, not the geometry. It would also cost the line underneath — "23 of
/// 57 · removing ec-website/feat/cards" — which is carrying more of the
/// information than the bar is.
struct Bar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far through the current pass, or `nil` when the engine has not said.
    let fraction: Double?
    /// Which pass, 1-based, and how many. One pass draws one segment, which is
    /// an ordinary bar.
    var step: Int = 1
    var steps: Int = 1
    let tint: Color

    private static let height: CGFloat = 7
    private static let gap: CGFloat = 3

    var body: some View {
        let n = max(1, steps)
        HStack(spacing: Self.gap) {
            ForEach(1...n, id: \.self) { i in
                Segment(fill: filled(i), tint: tint, indeterminate: i == step && fraction == nil)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress, phase \(step) of \(max(steps, 1))")
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent of this phase" } ?? "In progress")
    }

    /// Behind is done, ahead is empty, and only the current one moves. A pass
    /// that has been left behind stays full even if it ended early — it *is*
    /// finished, and emptying it to show the next one starting is the exact
    /// retreat this shape exists to avoid.
    private func filled(_ i: Int) -> Double {
        if i < step { return 1 }
        if i > step { return 0 }
        return fraction ?? 0
    }
}

private struct Segment: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fill: Double
    let tint: Color
    let indeterminate: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                if indeterminate {
                    // A quarter of the segment, sliding. The engine does not
                    // always know a total, and a bar resting at zero says
                    // "stuck" where a moving one says "working".
                    Capsule().fill(tint.opacity(0.7))
                        .frame(width: geo.size.width * 0.25)
                        .offset(x: sweep ? geo.size.width * 0.75 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                   value: sweep)
                        .onAppear { sweep = !reduceMotion }
                } else if fill > 0 {
                    // No floor under the width. A `max(6, …)` minimum put a
                    // 6pt lozenge of solid tint on a segment holding nothing,
                    // and at 6pt tall that is a dot — which is a claim, at the
                    // one moment there is nothing to claim.
                    Capsule().fill(tint)
                        .frame(width: min(geo.size.width, geo.size.width * fill))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fill)
                }
            }
        }
    }
}


private struct OutcomeGlyph: View {
    let symbol: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 28, weight: .medium))
            .foregroundStyle(tint).frame(width: 46, height: 46)
            .background(Circle().fill(tint.opacity(0.10)))
            .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: appeared)
            .onAppear { appeared = true }
            .accessibilityHidden(true)
    }
}
