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

    static let compactBelow: CGFloat = 780
    @State private var width: CGFloat = 1000
    /// Offscreen only: render the narrow layout whatever the width.
    var forceCompact: Bool? = nil

    var body: some View {
        // Below `compactBelow` the rail folds into a strip of chips under the
        // header. The width is read from behind, not with a reader around the
        // window's content: a reader has no height of its own, and the window
        // sizes itself from what its content asks for.
        let compact: Bool = forceCompact ?? (width < RootView.compactBelow)
        return HStack(spacing: 0) {
            if !compact {
                Sidebar(store: store)
                    .frame(width: Sidebar.railWidth - 1)
                    .background(Palette.rail)
                Rectangle().fill(Palette.line).frame(width: 1)
            }
            page(compact: compact).background(Palette.ground)
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { width = $0 }
        })
        // The window enforces the minimum via contentMinSize. Declaring it here
        // too makes the hosting view demand a size the window may not have yet,
        // and the overflow is clipped at both edges rather than scrolled.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.completion?.id)
        .overlay { if let id = store.celebration { PixelCelebration().id(id).allowsHitTesting(false) } }
        .tint(Palette.action)
        .preferredColorScheme(store.colorScheme)
        .sheet(item: $store.plan) { PlanSheet(store: store, plan: $0).tint(Palette.action) }
        .sheet(isPresented: $store.showingSettings) { SettingsSheet(store: store).tint(Palette.action) }
        .onChange(of: store.figure) { figure in
            if let coat = Mascot.drawnCoats[figure] { store.skin = coat }
        }
    }

    /// The header, banners, the folder list and the inventory strip.
    private func page(compact: Bool) -> some View {
        VStack(spacing: 0) {
            // With no rail, the header sits under the window's own buttons.
            if compact { Color.clear.frame(height: 24) }
            Header(store: store)
            if compact {
                Rectangle().fill(Palette.line).frame(height: 1)
                ChipBar(store: store)
            }
            UpdateBanner(store: store, updates: store.updates)
            if store.mergeNudges, let nudge = store.prLifecycle.pending.first {
                MergeSpeechBanner(store: store, nudge: nudge)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            if let completion = store.completion {
                CompletionBanner(store: store, plan: completion)
                    .transition(.opacity)
            }
            content
            Rectangle().fill(Palette.line).frame(height: 1)
            StatusBar(store: store)
        }
    }

    @ViewBuilder
    private var content: some View {
        // With no roots there is nothing to list, and the one question in
        // the way is where the repositories are.
        if store.unconfigured {
            FirstRun(store: store)
        } else {
            switch store.page {
            case .folders: FoldersView(store: store, open: openRow ?? store.focusPath)
            case .locations: LocationsView(store: store)
            case .kept: KeptFilesView()
            case .mascots: MascotsView(store: store)
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
            (Text("wt-").foregroundColor(Palette.rust) + Text("manager"))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .accessibilityLabel("wt-manager")
                .padding(.horizontal, 19).padding(.bottom, 18)

            let ready = store.envelope != nil && !store.unconfigured
            entry("Folders", "folder", ready && !store.folderRows.isEmpty ? "\(store.folderRows.count)" : nil,
                  tint: Palette.reclaim, on: store.page == .folders && store.verdictFilter == nil && store.locationFilter == nil) {
                store.page = .folders
                store.verdictFilter = nil
                store.locationFilter = nil
            }
            entry("Locations", "folder.fill.badge.gearshape", ready && !store.locations.isEmpty ? "\(store.locations.count)" : nil,
                  tint: Palette.status("trunk"),
                  on: store.page == .locations || (store.page == .folders && store.locationFilter != nil)) {
                store.locationFilter = nil
                store.page = .locations
            }
            entry("Kept files", "archivebox", nil, tint: Palette.muted, on: store.page == .kept) {
                store.page = .kept
            }
            entry("Mascots", "pawprint.fill", nil, tint: Palette.mascot, on: store.page == .mascots) {
                store.page = .mascots
            }

            if ready && !(store.folderRows.isEmpty && store.emptyLocations.isEmpty) {
                // The list's filters, here rather than as pills over it: a
                // filter is where you are, and where you are is the sidebar's.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heading("Show")
                        let scoped = store.folderRows.filter(store.inScope)
                        ForEach(FoldersView.Verdict.allCases, id: \.self) { v in
                            // Empty leftover folders are safe by definition.
                            let n = scoped.filter { $0.folder?.verdict == v.rawValue }.count
                                + (v == .safe && store.locationFilter == nil && store.query.isEmpty
                                   ? store.emptyLocations.count : 0)
                            let on = store.page == .folders && store.verdictFilter == v.rawValue
                            if v != .kept || n > 0 || on {
                                entry(v.label, nil, n == 0 ? nil : "\(n)", dot: v.tint, tint: v.tint, on: on, dim: n == 0 && !on) {
                                    store.page = .folders
                                    store.verdictFilter = on ? nil : v.rawValue
                                }
                            }
                        }
                        heading("Made by")
                        ForEach(Store.makers, id: \.self) { maker in
                            let n: Int = store.folderRows.filter { Store.madeBy($0.path) == maker }.count
                            let on: Bool = store.page == .folders && store.madeByFilter == maker
                            entry(maker, nil, n == 0 ? nil : "\(n)", tint: Palette.muted, on: on, dim: n == 0 && !on) {
                                store.page = .folders
                                store.madeByFilter = on ? nil : maker
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 12)
            VStack(spacing: 7) {
                Button { store.showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
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

    /// One row, in the system's own sidebar idiom.
    ///
    /// The selected row used to be a saturated accent slab with white text on
    /// it, which is a *button*, not a selection — it shouted louder than
    /// anything in the content it was pointing at, and it made the rail the
    /// loudest thing on the window. A pale accent ground with accent ink is
    /// what every sidebar on this machine does, and it reads as selected
    /// without competing.
    private func heading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 17).padding(.top, 16).padding(.bottom, 4)
    }

    /// `symbol` or `dot`: an icon for a place, the verdict's colour for a
    /// filter. Each entry carries its own colour on the mark, the count and,
    /// when selected, the ground; the words stay ink so they read in both
    /// appearances.
    private func entry(_ title: String, _ symbol: String?, _ badge: String?, dot: Color? = nil,
                       tint: Color, on: Bool, dim: Bool = false, alert: Bool = false,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Words only, as designed; a dot where the entry is a verdict.
                if let dot {
                    Circle().fill(dim ? Palette.faint : dot).frame(width: 8, height: 8)
                }
                Text(title).font(.system(size: 13, weight: on ? .semibold : .regular))
                    .foregroundStyle(dim ? Palette.muted : Color.primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .semibold, design: .rounded))
                        // Filled means "needs you"; a plain number means "exists".
                        .foregroundStyle(alert ? Color.white : Palette.muted).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(alert ? Palette.badge : Color.clear))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            // Selected is a raised neutral card, the same for every entry. It
            // was each entry's own colour, which made the rail three accents.
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.cardFill : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(on ? Palette.line : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(dim)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                        context.fill(Path(rect), with: .color(i < 3 ? Palette.mascot : .primary))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keep status and direct character selection available above the scrolling content.
    /// Unique facts remain a compact final row.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 13) {
                Button { store.page = .mascots } label: {
                    WityView(store: store, height: 32).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a character")
                .help("Choose a character")
                .contextMenu {
                    Button("Next character") { store.nextCharacter() }
                    Button("Change coat") { store.nextSkin() }.disabled(store.usingOwnImage)
                    Button("Check for updates…") { store.updates.check(manual: true) }
                    Divider()
                    Button("Quit wt-manager") { store.quit() }
                        .disabled(store.plan?.stage == .committing)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1).truncationMode(.tail)
                        .help(store.face?.meaning ?? "")
                    if let phase = store.phase {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).scaleEffect(0.55)
                            Text(phase).lineLimit(1).fixedSize()
                            if let p = store.scanProgress {
                                Bar(fraction: p.fraction, step: p.step, steps: p.steps, tint: Palette.brand)
                                    .frame(width: 92)
                                    .accessibilityLabel(p.label)
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize()
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if store.page == .folders && !store.unconfigured && store.envelope != nil {
                    FilterBar(store: store, compact: true).frame(minWidth: 120, idealWidth: 220, maxWidth: 220)
                }
                controls
            }
        }
        .padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 9)
    }

    /// The engine's sentence, verbatim. Before an envelope exists there is
    /// nothing to derive it from, so the only honest lines are about the wait.
    private var headline: String {
        if let cheer = store.cheer { return cheer.meaning }
        if store.error != nil { return "Something could not be read" }
        guard let env = store.envelope else {
            return store.phase == "measuring disk" ? "Measuring disk…" : "Reading your repos…"
        }
        if store.page == .locations {
            let places = Set(store.folderRows.map(store.location(of:))).count
            if places > 0 { return Store.count(places, "place") + (places == 1 ? " holds" : " hold") + " your worktrees" }
        }
        return env.headline
    }

    private var controls: some View {
        Button("Refresh") { store.refresh(measureDisk: true) }
            .buttonStyle(.wt(.quiet))
            .help("Refresh, measuring disk").disabled(store.busy)
    }
}

/// Inventory: what there is, not what to do about it. It lives down here and
/// not in the header because it is the least urgent thing on the window, and
/// it was in both places at once — "57 worktrees" twice, "330G" twice.
struct StatusBar: View {
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 4) {
            if store.unconfigured {
                // Not "0 worktrees · 0 repos". Nothing has been counted, and
                // an inventory of zero reads as a finding.
                Text("no folders being watched yet")
            } else if let env = store.envelope {
                Text(Store.count(store.folderRows.count, "folder"))
                Text("· " + Store.count(Set(env.worktrees.map(\.repo)).count, "repo"))
                if store.filtering {
                    Text("· showing \(store.folderRows.filter { store.inScope($0) && (store.verdictFilter == nil || $0.folder?.verdict == store.verdictFilter) }.count)")
                }
            }
            Spacer()
            if let d = store.disk {
                Text("\(Store.human(d.total)) on disk")
            }
        }
        .font(.system(size: 11)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 28).padding(.vertical, 9)
    }
}
