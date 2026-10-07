import SwiftUI

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sheetWidth: CGFloat {
        min(740, max(600, (NSApp.mainWindow?.contentView?.bounds.width ?? 780) - 32))
    }
    private var height: CGFloat {
        let ceiling = min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 100)
        switch plan.stage {
        case .previewing, .committing: return 300
        case .reviewing:
            let rows = (preview?.paths.count ?? 0) + (preview?.skipped.count ?? 0)
                + (preview?.precious.count ?? 0) + (preview?.unknown.count ?? 0)
            return min(ceiling, max(440, 300 + CGFloat(rows) * 65))
        case .done: return min(ceiling, max(450, 340 + CGFloat(doneRows.count) * 45))
        case .failed, .changed: return min(ceiling, 500)
        }
    }

    private var kind: Store.ActionKind { plan.action.kind }
    private var preview: Store.PlanResult? { plan.preview }
    private var destructive: Bool { plan.stage == .reviewing && !(preview?.paths.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Hairline()
            scopeBar
            Hairline()
            outcome
            Hairline()
            buttons
        }
        // Narrower than the window's minimum, so it never overhangs. The
        // height belongs to the stage, not to the sheet: a 500pt box around
        // "65G returned" is 400pt of nothing, and the list is the only stage
        // that has any use for the room.
        .frame(width: sheetWidth, height: height)
        .background(.background)
        .overlay { if plan.stage == .done, let id = store.celebration {
            PixelCelebration().id(id).allowsHitTesting(false)
        } }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: plan.stage)
    }

    // MARK: heading

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            if plan.stage == .done {
                OutcomeGlyph(symbol: headingSymbol, tint: headingTint)
            } else {
                Image(systemName: headingSymbol)
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(headingTint)
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(headingTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(headingBlurb)
                    .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }

    private var headingSymbol: String {
        switch plan.stage {
        case .done:    return (plan.result?.failed ?? 0) > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed:  return "xmark.octagon.fill"
        case .changed: return "arrow.triangle.2.circlepath.circle.fill"
        default:       return kind.icon
        }
    }

    private var headingTint: Color {
        switch plan.stage {
        case .done:    return (plan.result?.failed ?? 0) > 0
            ? Palette.ink(status: (plan.result?.completedPaths.isEmpty ?? true) ? "blocked" : "stale") : Palette.inkReclaim
        case .failed:  return Palette.status("blocked")
        case .changed: return Palette.status("stale")
        default:       return Palette.muted
        }
    }

    /// The verb in the past tense, for the sentences that report what did or
    /// did not happen.
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

    private var headingTitle: String {
        switch plan.stage {
        case .done:
            if let r = plan.result, r.failed > 0 { return r.completedPaths.isEmpty ? "Could not finish" : "Partially completed" }
            switch kind {
            case .reap:  return "Removed"
            case .clean: return "Cleaned"
            }
        case .failed:  return "That did not work"
        case .changed: return "This changed since you looked"
        default:       return plan.action.title
        }
    }

    private var headingBlurb: String {
        switch plan.stage {
        case .done:
            if let r = plan.result, r.failed > 0 {
                return "Only confirmed completions are listed. \(r.failed) item\(r.failed == 1 ? "" : "s") could not finish; details are below."
            }
            if store.busy { return "The operation finished. Updating the rest of the window…" }
            // What it means, not what the app did next. The figures below
            // already say how much; this is the line that says it was safe,
            // and it is the claim the whole design of the verb rests on.
            // The clean line leads with what was *not* done. The sheet ends
            // with a list of worktrees under green ticks, which for `reap`
            // means "these are gone" and for `clean` means very nearly the
            // opposite — and nothing on the screen said which. Someone who
            // reclaims 250G and then reads a list of their branches has
            // every reason to think they just deleted them.
            switch kind {
            case .reap:
                return "Only eligible worktrees were removed. Uncommitted, unpushed, "
                    + "and unclassified local files were kept."
            case .clean:
                return "The worktrees are untouched — only build output went. "
                    + "All of it comes back with a build or an install, and "
                    + "environment files and keys were never read."
            }
        case .failed:
            return "The operation could not finish. Read the engine’s message below."
        case .changed:
            return "What this would touch is no longer what the preview showed, so nothing was "
                + verbPast + ". Review it again to see the current set."
        default:
            return plan.action.blurb
        }
    }

    // MARK: scope

    /// Exactly what is in range, said before you read the list.
    private var scopeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: plan.action.single ? "scope" : "square.stack.3d.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(plan.action.single ? Palette.muted : Palette.ink(status: "stale"))
            Text(scopeText).font(.system(size: 11)).foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let p = preview, plan.stage == .reviewing, !p.paths.isEmpty {
                Text(summaryText(p))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(plan.action.single ? Color.clear : Palette.status("stale").opacity(0.10))
    }

    private var scopeText: String {
        if plan.action.single {
            return "One worktree: " + (plan.action.paths.first.map {
                URL(fileURLWithPath: $0).lastPathComponent } ?? "")
        }
        if !plan.action.paths.isEmpty { return "\(plan.action.paths.count) selected worktrees" }
        if kind == .reap { return "Every finished worktree under your roots" }
        return plan.action.staleOnly
            ? "Every forgotten or finished worktree under your roots"
            : "Every worktree under your roots, including work in flight"
    }

    private func summaryText(_ p: Store.PlanResult) -> String {
        let n = p.paths.count
        let amount = p.kb > 0 ? " · " + Store.human(p.kb) : ""
        return "\(n) worktree\(n == 1 ? "" : "s")" + amount
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
            case .reap:
                working("Removing", "Through git, one worktree at a time.")
            case .clean:
                working("Deleting", "Build output only, one worktree at a time.")
            }
        case .failed:
            ScrollView {
                Text(plan.failed ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink(status: "blocked")).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
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
        let current = plan.progress ?? (store.busy ? store.scanProgress : nil)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(store.busy && plan.progress == nil ? title : current.map { phaseNames($0)[min($0.step - 1, phaseNames($0).count - 1)] } ?? title).font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                TimerText(since: plan.since)
            }
            if let p = current, let f = p.fraction {
                Bar(fraction: f, step: p.step, steps: p.steps,
                    tint: barTint)
                HStack(spacing: 6) {
                    Text("\(p.done) of \(p.total)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(p.label.isEmpty ? sub : p.label)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    // On the same line as the count, because it is the thing
                    // that explains the count going back to nearly nothing.
                    // Without it the bar fills, empties and fills again under
                    // one unchanged heading, which reads as a bug rather than
                    // as the second of three passes.
                    if let caption = p.stepCaption {
                        Text(caption)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Palette.muted)
                    }
                }
            } else {
                Bar(fraction: nil, step: current?.step ?? 1, steps: current?.steps ?? 1,
                    tint: barTint)
                Text(current?.label.isEmpty == false ? current!.label : sub)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let p = current, p.steps > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(phaseNames(p).enumerated()), id: \.offset) { i, name in
                        HStack(spacing: 4) {
                            Image(systemName: i + 1 < p.step ? "checkmark.circle.fill" : i + 1 == p.step ? "circle.inset.filled" : "circle")
                                .font(.system(size: 9))
                            Text(name).font(.system(size: 10, weight: i + 1 == p.step ? .semibold : .regular))
                        }
                        .foregroundStyle(i + 1 <= p.step ? Palette.ink(barTint) : Palette.muted)
                        if i < phaseNames(p).count - 1 { Spacer(minLength: 0) }
                    }
                }.padding(.top, 5)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func phaseNames(_ p: Engine.Progress) -> [String] {
        if p.steps == 4 && kind == .reap { return ["Read repos", "Measure", "Check safety", "Preserve & remove"] }
        if p.steps == 3 && kind == .reap { return ["Read repos", "Measure", "Check safety"] }
        if p.steps == 3 { return ["Read repos", "Measure", "Clean"] }
        if p.steps == 2 { return ["Read repos", "Measure"] }
        return ["Working"]
    }

    @ViewBuilder
    private func review(_ p: Store.PlanResult) -> some View {
        if p.paths.isEmpty {
            // Two different empty results, and they used to look the same.
            // A tick over "nothing to do here" reads as all-clear; when the
            // engine *refused* what you pointed at, all-clear is the wrong
            // answer and the reason is the only thing worth showing.
            let refused = !p.skipped.isEmpty
            ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Image(systemName: refused ? "lock" : "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(refused ? Palette.ink(status: "stale") : Palette.muted)
                    Text(refused
                         ? (p.skipped.count == 1
                            ? "That one cannot be \(verbPast)."
                            : "None of these can be \(verbPast).")
                         : "Nothing to do here.")
                        .font(.system(size: 12.5, weight: refused ? .medium : .regular))
                        .foregroundStyle(refused ? .primary : Palette.muted)
                }
                if refused { skippedList(p.skipped).padding(.horizontal, 20) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    itemList(p)
                    if !p.skipped.isEmpty {
                        section("Kept out", ink: Palette.ink(status: "stale")) { skippedList(p.skipped) }
                    }
                    if !p.precious.isEmpty {
                        let lost = kind == .reap && p.keptIn.isEmpty
                        section(lost ? "Goes with them"
                                     : kind == .reap ? "Set aside in \(p.keptIn) first" : "Never touched",
                                ink: lost ? Palette.ink(status: "blocked") : Palette.inkReclaim) {
                            ForEach(p.precious.keys.sorted(), id: \.self) { path in
                                fileList(path, names: p.precious[path] ?? [])
                            }
                        }
                    }
                    if kind == .reap && !p.unknown.isEmpty {
                        section(p.keepsUnknown ? "Set aside too, unrecognised" : "Also removed, unrecognised",
                                ink: Palette.muted) {
                            ForEach(p.unknown.keys.sorted(), id: \.self) { path in
                                fileList(path, names: p.unknown[path] ?? [])
                            }
                        }
                    }
                    rawToggle(p.text)
                }
                .padding(20)
            }
        }
    }

    private func itemList(_ p: Store.PlanResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(p.paths.enumerated()), id: \.element) { i, path in
                if i > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: kind.icon).font(.system(size: 10))
                        .foregroundStyle(kind == .reap ? Palette.status("merged") : Palette.reclaim)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                        Text(kind == .clean
                             ? (p.entries[path] ?? []).joined(separator: "  ")
                             : path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.04)))
    }

    private func skippedList(_ items: [Store.PlanResult.Skipped]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.path) { s in
                line(s.name, s.why + (s.override.isEmpty ? "" : "  ·  \(s.override) in the terminal overrides"))
            }
        }
    }

    /// `ink` is already a text colour. Pulling a system dynamic colour like
    /// `.secondary` through `Palette.ink` resolves it once, in whichever
    /// appearance is current, and the heading vanished in the other.
    private func section<C: View>(_ title: String, ink: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(ink)
            content()
        }
    }

    private func line(_ head: String, _ tail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(head).font(.system(size: 12.5, weight: .medium))
            Text(tail).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    private func fileList(_ path: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            line(URL(fileURLWithPath: path).lastPathComponent, names.prefix(4).joined(separator: "\n"))
            if names.count > 4 {
                DisclosureGroup("Show all \(names.count) paths") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            Text(name).font(.system(size: 12, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.system(size: 12))
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
                    Text("The command's own output").font(.system(size: 10.5))
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

    private var changed: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = plan.result?.text, !text.isEmpty {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.04)))
            }
            Button("Review again") { store.preview(plan.action) }
                .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What actually went, one line each. The engine names them in its own
    /// output as it goes; the preview named the same set before you approved
    /// it, so this is that list with the outcome attached rather than a second
    /// claim about what happened.
    private var doneRows: [String] {
        guard plan.stage == .done, let r = plan.result else { return [] }
        return r.completedPaths
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = plan.result {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    switch kind {
                    case .reap:
                        figure("\(r.removed)",
                               r.removed == 1 ? "worktree removed" : "worktrees removed",
                               tint: Palette.inkReclaim)
                    case .clean:
                        figure(Store.human(r.freedKb), "of build output deleted",
                               tint: Palette.inkReclaim)
                    }
                    if kind == .clean {
                        figure("\(doneRows.count)",
                               doneRows.count == 1 ? "worktree, still there"
                                                   : "worktrees, all still there",
                               tint: Palette.status("active"))
                    }
                    if kind == .reap && r.freedKb > 0 {
                        figure(Store.human(r.freedKb), "returned to the disk",
                               tint: Palette.inkReclaim)
                    }
                    if r.failed > 0 {
                        figure("\(r.failed)", r.failed == 1 ? "failed" : "failed",
                               tint: Palette.ink(status: "blocked"))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

                if !doneRows.isEmpty {
                    Hairline()
                    Group {
                        VStack(alignment: .leading, spacing: 0) {
                            // The list needs a verb on it. Ticks alone are
                            // ambiguous between "gone" and "kept", and the
                            // two verbs here mean opposite things about the
                            // same rows.
                            Text(kind == .reap
                                 ? "REMOVED — THESE WORKTREES ARE GONE"
                                 : "STILL HERE — ONLY THEIR BUILD OUTPUT WENT")
                                .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(kind == .reap
                                                 ? Palette.ink(status: "merged")
                                                 : Palette.inkReclaim)
                                .padding(.bottom, 8)
                            ForEach(Array(doneRows.enumerated()), id: \.element) { i, path in
                                if i > 0 { Hairline() }
                                HStack(spacing: 9) {
                                    Image(systemName: kind == .reap ? "xmark" : "sparkles")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(kind == .reap
                                                         ? Palette.ink(status: "merged")
                                                         : Palette.inkReclaim)
                                        .frame(width: 12)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 11.5))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(URL(fileURLWithPath: path).deletingLastPathComponent()
                                            .lastPathComponent)
                                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    Hairline()
                }
                // Within the same scroll as the result list. It is the least important thing here and
                // it is also the thing you go looking for when something did
                // not add up, so it has to be findable without hunting.
                if r.failed > 0 {
                    Text(r.text).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.inkRisk).textSelection(.enabled).padding(20)
                }
                rawToggle(r.text).padding(.horizontal, 20).padding(.vertical, 10)
                if doneRows.isEmpty { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func figure(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    // MARK: buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            if destructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(Palette.status("stale"))
                Text(kind == .reap
                     ? "Removed through git. This cannot be undone from here."
                     : "Comes back with a build or install, not with undo.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
            Spacer()
            // Nothing to press while a delete is in flight. Closing the sheet
            // does not stop the subprocess, and a button labelled "Cancel"
            // that abandons the window while files keep disappearing behind
            // it is a lie about what it does. The dry run is different — it
            // changes nothing, so walking away from it is free.
            Button(plan.stage == .previewing ? "Close preview" : plan.done || plan.stage == .changed ? "Close" : "Cancel") { store.plan = nil }
                .keyboardShortcut(.cancelAction)
                .disabled(plan.stage == .committing)
            if plan.stage == .failed {
                Button("Review again") { store.preview(plan.action) }
                    .buttonStyle(.borderedProminent)
            }
            if destructive {
                // Labelled with the consequence: a button that names what it
                // destroys gets read, one that says "Confirm" gets clicked.
                // Prominent and red: `.tint` alone changes nothing on a default
                // button, and a destructive action should not look like Cancel.
                // The darkened red keeps white text at 5.5:1 in both appearances.
                Button(confirmLabel) { store.commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.badge)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var confirmLabel: String {
        guard let p = preview else { return kind.verb }
        let n = p.paths.count
        if kind == .reap {
            return n == 1 ? "Remove it" : "Remove \(n) worktrees"
        }
        return p.kb > 0 ? "Delete \(Store.human(p.kb))" : "Delete it"
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
