import SwiftUI
import WTManagerKit

/// The window.
///
/// One surface, laid out by hand. `NavigationSplitView` gives its sidebar and
/// its detail separate materials, and in a transparent window each rounds its
/// own corners — which reads as two windows taped together rather than one app.
/// Everything here is drawn clear on top of the single backdrop the window
/// owns, so the whole thing is continuous by construction.
struct RootView: View {
    @ObservedObject var store: Store
    /// Offscreen only: which worktree row to render expanded.
    var openRow: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store)
                .frame(width: Sidebar.railWidth - 1)
            Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                Header(store: store)
                UpdateBanner(store: store, updates: store.updates)
                if store.mergeNudges, let nudge = store.prLifecycle.pending.first {
                    MergeSpeechBanner(store: store, nudge: nudge)
                }
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                if let completion = store.completion {
                    CompletionBanner(store: store, plan: completion)
                        .transition(.opacity)
                }
                content
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                StatusBar(store: store)
            }
        }
        // The window enforces the minimum via contentMinSize. Declaring it here
        // too makes the hosting view demand a size the window may not have yet,
        // and the overflow is clipped at both edges rather than scrolled.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.completion?.id)
        .overlay { if let id = store.celebration { PixelCelebration().id(id).allowsHitTesting(false) } }
        .preferredColorScheme(store.colorScheme)
        .sheet(item: $store.plan) { PlanSheet(store: store, plan: $0) }
        .sheet(isPresented: $store.showingSettings) { SettingsSheet(store: store) }
        .onChange(of: store.figure) { figure in
            if let coat = ["robot": "graphite", "rooster": "sunrise", "rabbit": "chestnut", "snowman": "frost", "palm": "tropical", "orb": "pearl", "antenna": "cherry"][figure] { store.skin = coat }
        }
        .onChange(of: store.section) { next in
            // Status chips describe the current group. A selection from the
            // previous group would silently empty the next one.
            store.statusFilter = []
            if next != "all" { store.repoFilter = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Before anything else, and whatever section is selected: with no
        // roots there is nothing for any of them to show, and five empty
        // lists do not add up to the one question that is actually in the way.
        if store.unconfigured {
            FirstRun(store: store)
        } else {
            switch store.section {
            case "overview": Overview(store: store)
            case "disk":     DiskDetail(store: store)
            default:         WorktreeList(store: store, section: store.section,
                                          initiallyOpen: openRow)
            }
        }
    }
}

// MARK: - sidebar

struct Sidebar: View {
    /// The rail, hairline included. Named because the window's width ceiling
    /// is measured against it: half the screen is promised to the content, and
    /// the rail is added on top of that rather than taken out of it.
    static let railWidth: CGFloat = 194
    /// One entry, ground included: 12.5pt text on 5.5pt of padding either side,
    /// plus the half-point that separates it from its neighbour.
    static let rowHeight: CGFloat = 28

    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights end 23pt down — measured, not guessed — and
            // only the sidebar owes them anything, since they sit entirely
            // within its width. But clearing them by a hair is not the same as
            // looking clear of them: 24pt puts the first row's tint directly
            // under the green button. A whole row's height of air above the
            // first row reads as deliberate, and the header keeps its own
            // tighter padding because nothing overlaps it.
            Color.clear.frame(height: 34)
            PixelWordmark()
                .padding(.horizontal, 17).padding(.bottom, 18)

            entry("overview", "Overview", "square.grid.2x2", nil)
            entry("disk", "Disk", "internaldrive", store.disk.map { Store.human($0.reclaim) },
                  tint: store.disk == nil ? nil : Palette.reclaim)

            heading("Worktrees")

            ForEach(store.allGroups) { g in
                // A dash before the first envelope, and while nobody has said
                // where to look: "0 forgotten" is a claim, and on a machine
                // that has not been scanned it is one nothing has established.
                entry(g.id, g.title, icon(g.id),
                      store.envelope == nil || store.unconfigured ? "–" : "\(g.items.count)",
                      tint: g.items.isEmpty ? nil : Palette.section(g.id))
            }

            Spacer(minLength: 12)
            VStack(spacing: 7) {
                Button { store.showingSettings = true } label: {
                    Label("Watched folders", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 7)
            }
            .padding(.horizontal, 12).padding(.bottom, 15)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Sentence case, not shouted. A group label in a rail is a signpost, and
    /// SMALL CAPS WITH TRACKING competes with the rows it is labelling — which
    /// is the wrong way round, since nobody clicks the label.
    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 17).padding(.top, 18).padding(.bottom, 4)
    }

    private func icon(_ id: String) -> String {
        switch id {
        case "all":    return "square.stack"
        case "need":   return "exclamationmark.circle"
        case "forgot": return "clock.badge.exclamationmark"
        case "flight": return "arrow.triangle.branch"
        case "others": return "person.2"
        case "repos":  return "shippingbox"
        default:       return "checkmark.circle"
        }
    }

    /// One row, in the system's own sidebar idiom.
    ///
    /// The selected row used to be a saturated accent slab with white text on
    /// it, which is a *button*, not a selection — it shouted louder than
    /// anything in the content it was pointing at, and it made the rail the
    /// loudest thing on the window. A pale accent ground with accent ink is
    /// what every sidebar on this machine does, and it reads as selected
    /// without competing.
    private func entry(_ id: String, _ title: String, _ symbol: String,
                       _ badge: String?, tint: Color? = nil) -> some View {
        let on = store.section == id
        return Button { store.section = id } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(on ? Color.accentColor : (tint ?? Palette.muted))
                Text(title).font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    // The count is read, so it takes the ink, not the mark.
                    Text(badge).font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(on ? Color.accentColor : (tint.map(Palette.ink) ?? Palette.muted))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(on ? Palette.selection : .clear))
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityRemoveTraits(on ? [] : .isSelected)
        .padding(.horizontal, 9).padding(.vertical, 1)
    }
}

/// A small bitmap alphabet, drawn on whole cells like the app's mascot.
struct PixelWordmark: View {
    private let glyphs: [Character: [String]] = [
        "w": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
        "t": ["00100", "00100", "11111", "00100", "00100", "00100", "00011"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "m": ["00000", "00000", "11011", "10101", "10101", "10101", "10101"],
        "a": ["00000", "00000", "01110", "00001", "01111", "10001", "01111"],
        "n": ["00000", "00000", "11110", "10001", "10001", "10001", "10001"],
        "g": ["00000", "01111", "10001", "10001", "01111", "00001", "01110"],
        "e": ["00000", "00000", "01110", "10001", "11111", "10000", "01111"],
        "r": ["00000", "00000", "10110", "11001", "10000", "10000", "10000"],
    ]
    var body: some View {
        Canvas { context, _ in
            for (i, character) in "wt-manager".enumerated() {
                for (y, row) in (glyphs[character] ?? []).enumerated() {
                    for (x, pixel) in row.enumerated() where pixel == "1" {
                        let rect = CGRect(x: (i * 6 + x) * 2, y: y * 2, width: 2, height: 2)
                        context.fill(Path(rect), with: .color(i < 3 ? Color(red: 0.72, green: 0.36, blue: 0.17) : .primary))
                    }
                }
            }
        }
        .frame(width: 118, height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("wt-manager")
    }
}

// MARK: - header

struct Header: View {
    @ObservedObject var store: Store

    /// Two rows, and only two.
    ///
    /// The first is the state: Wity, a headline that never wraps, the
    /// controls. The second is the facts that live nowhere else on this
    /// window — at most three, on one line, never wrapping either.
    ///
    /// It used to be four rows: a headline, eight tags across two rows, and an
    /// inventory strip. Five of the eight tags repeated a count already
    /// showing in the sidebar, one repeated the headline word for word ("One
    /// thing needs you" over a tag reading "1 needs you"), and the strip
    /// repeated the status bar at the bottom of the same window. Everything
    /// was on screen twice and nothing was emphasised, which is the definition
    /// of noise. What is left is the two or three things that are only here.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 13) {
                Menu {
                    Button("Change coat") { store.nextSkin() }.disabled(store.usingOwnImage)
                    Button("Check for updates…") { store.updates.check(manual: true) }
                    Divider()
                    Button("Quit wt-manager") { store.quit() }
                        .disabled(store.plan?.stage == .committing)
                } label: {
                    WityView(store: store, height: 44).frame(width: 44)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Mascot menu · change coat, check updates, or quit")
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1).truncationMode(.tail)
                        .help(store.face?.meaning ?? "")
                    if let phase = store.phase {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).scaleEffect(0.55)
                            Text(phase)
                            if let p = store.scanProgress {
                                Bar(fraction: p.fraction, step: p.step, steps: p.steps, tint: Palette.brand)
                                    .frame(width: 92)
                                    .accessibilityLabel(p.label)
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 8)
                controls
            }
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags) { tag in InsightTag(tag: tag) { store.section = tag.target } }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 11)
    }

    /// Only the facts with no other home, and never more than three of them.
    /// The cap is not decoration: a row that can wrap will wrap on the day
    /// everything is wrong at once, which is the day the header most needs to
    /// stay the size it was.
    private var tags: [Insight] {
        Array((store.envelope?.insights ?? []).filter(\.solo).prefix(3))
    }

    /// The engine's sentence, verbatim. Before an envelope exists there is
    /// nothing to derive it from, so the only honest lines are about the wait.
    private var headline: String {
        if store.error != nil { return "Something could not be read" }
        guard let env = store.envelope else {
            return store.phase == "measuring disk" ? "Measuring disk…" : "Reading your repos…"
        }
        return env.headline
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { store.refresh(measureDisk: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh, measuring disk").disabled(store.busy)

            Menu {
                Button("Check for updates…") { store.updates.check(manual: true) }
                Toggle("Check updates automatically", isOn: $store.automaticUpdates)
                Toggle("Mascot merge messages", isOn: $store.mergeNudges)
                Toggle("Cleanup celebrations", isOn: $store.celebrationsEnabled)
                Toggle("Show floating mascot", isOn: $store.floatingMascot)
                Divider()
                Picker("Theme", selection: $store.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                if let mascot = store.mascot {
                    // Two axes, and they are not the same axis. The character
                    // is *who* is on the perch; the coat is what colour they
                    // are. Folding them into one list of twenty entries was
                    // the first draft and nobody could find anything in it.
                    Picker("Character", selection: $store.figure) {
                        ForEach(mascot.figures) { f in
                            Label {
                                Text("\(f.name) — \(f.tell)")
                            } icon: {
                                if let image = mascot.image(figure: f.id, gauge: 0, eyes: "open", frame: 0,
                                    skin: ["robot": "graphite", "rooster": "sunrise", "rabbit": "chestnut", "snowman": "frost", "palm": "tropical", "orb": "pearl", "antenna": "cherry"][f.id] ?? store.skin,
                                    tint: "#3fb27f", fitting: 22) {
                                    Image(nsImage: image).interpolation(.none)
                                }
                            }.tag(f.id)
                        }
                        if OwnFace.exists {
                            Divider()
                            Text("Your own picture").tag(Store.ownFigure)
                        }
                    }
                    Picker("Coat", selection: $store.skin) {
                        ForEach(mascot.skins.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(store.usingOwnImage)
                    Button(OwnFace.exists ? "Choose another picture…" : "Use your own picture…") {
                        store.chooseOwnImage()
                    }
                    if OwnFace.exists {
                        Button("Forget that picture") {
                            OwnFace.forget()
                            store.figure = mascot.defaultFigure
                        }
                    }
                }
            } label: { Image(systemName: "slider.horizontal.3") }
            .menuStyle(.borderlessButton).fixedSize().help("Appearance")
        }
        .buttonStyle(.borderless).font(.system(size: 12))
    }
}

/// One clickable fact. The hue is on the mark, the wash and the edge; the words
/// are ink, so it reads in both appearances (white on the stale orange is 2.1:1).
struct InsightTag: View {
    let tag: Insight
    let action: () -> Void
    private var mark: Color { Palette.tint(named: tag.tint) }
    private var symbol: String {
        switch tag.id {
        case "need":       return "exclamationmark.circle.fill"
        case "stale":      return "clock.badge.exclamationmark"
        case "unpushed":   return "arrow.up.circle"
        case "reclaim":    return "sparkles"
        case "waiting":    return "person.2"
        case "draft":      return "pencil.line"
        case "finished":   return "checkmark.circle"
        default:           return "eye.slash"
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(mark)
                Text(tag.label).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink(mark)).lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Palette.wash(mark))
                .overlay(Capsule().strokeBorder(Palette.edge(mark), lineWidth: 1)))
        }
        .buttonStyle(RowButtonStyle(radius: 12))
        .help("Show " + tag.label)
    }
}

/// Inventory: what there is, not what to do about it. It lives down here and
/// not in the header because it is the least urgent thing on the window, and
/// it was in both places at once — "57 worktrees" twice, "330G" twice.
struct StatusBar: View {
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 6) {
            if store.unconfigured {
                // Not "0 worktrees · 0 repos". Nothing has been counted, and
                // an inventory of zero reads as a finding.
                Text("no folders being watched yet")
            } else if let env = store.envelope {
                Text("\(env.worktrees.count) worktrees")
                Text("· \(Set(env.worktrees.map(\.repo)).count) repos")
                if store.filtering {
                    let shown = store.groups.first(where: { $0.id == store.section })?.items.count
                        ?? Set(store.groups.flatMap { $0.items.map(\.path) }).count
                    Text("· \(shown) shown")
                }
            }
            Spacer()
            if let d = store.disk {
                Text("measured \(Store.human(d.total))")
            }
        }
        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 20).padding(.vertical, 7)
    }
}
