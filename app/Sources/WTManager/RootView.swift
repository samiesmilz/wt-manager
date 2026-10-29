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
            page
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
            if let coat = Mascot.drawnCoats[figure] { store.skin = coat }
        }
    }

    /// The header, banners, the folder list and the inventory strip.
    private var page: some View {
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

    @ViewBuilder
    private var content: some View {
        // With no roots there is nothing to list, and the one question in
        // the way is where the repositories are.
        if store.unconfigured {
            FirstRun(store: store)
        } else {
            FoldersView(store: store, open: openRow ?? store.focusPath)
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

            // The app's one page, with what it holds.
            entry("Folders", "folder",
                  store.envelope == nil || store.unconfigured ? "–" : "\(store.folderRows.count)")

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

    /// One row, in the system's own sidebar idiom.
    ///
    /// The selected row used to be a saturated accent slab with white text on
    /// it, which is a *button*, not a selection — it shouted louder than
    /// anything in the content it was pointing at, and it made the rail the
    /// loudest thing on the window. A pale accent ground with accent ink is
    /// what every sidebar on this machine does, and it reads as selected
    /// without competing.
    private func entry(_ title: String, _ symbol: String, _ badge: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let badge {
                Text(badge).font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.selection))
        .padding(.horizontal, 9).padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
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
    /// The character picker, open only while choosing. All eleven portraits
    /// on every page took a quarter of the window for a setting changed once
    /// in a while.
    @State private var choosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keep status and direct character selection available above the scrolling content.
    /// Unique facts remain a compact final row.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 13) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { choosing.toggle() }
                } label: {
                    WityView(store: store, height: 44).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choosing ? "Close the character picker" : "Choose a character")
                .help(choosing ? "Close the character picker" : "Choose a character")
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
            if choosing {
                MascotSwitcher(store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 11)
    }

    /// The engine's sentence, verbatim. Before an envelope exists there is
    /// nothing to derive it from, so the only honest lines are about the wait.
    private var headline: String {
        if let cheer = store.cheer { return cheer.meaning }
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
                Toggle("Let the mascot wander", isOn: $store.mascotWanders)
                    .help("Occasional screen strolls. Respects Reduce Motion.")
                Toggle("Cleanup celebrations", isOn: $store.celebrationsEnabled)
                Toggle("Show floating mascot", isOn: $store.floatingMascot)
                Divider()
                Picker("Theme", selection: $store.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                if let mascot = store.mascot {
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

/// Always-visible portraits: one press selects the exact character, with no menu or confirmation.
struct MascotSwitcher: View {
    @ObservedObject var store: Store
    private let coats = Mascot.drawnCoats

    var body: some View {
        if let mascot = store.mascot {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 4)], spacing: 4) {
                ForEach(mascot.figures) { figure in
                    portrait(id: figure.id, name: figure.name, help: figure.tell) {
                        if let image = mascot.image(figure: figure.id, gauge: 0, eyes: "open", frame: 0,
                            skin: coats[figure.id] ?? "acorn", tint: "#3fb27f", fitting: 26, showSignal: false) {
                            Image(nsImage: image).interpolation(.none)
                        }
                    }
                }
                if OwnFace.exists {
                    portrait(id: Store.ownFigure, name: "Yours", help: "Your own picture") {
                        if let image = OwnFace.image(fitting: 26, tint: nil) {
                            Image(nsImage: image).interpolation(.none)
                        }
                    }
                }
            }
            .accessibilityLabel("Choose a mascot")
        }
    }

    private func portrait<Content: View>(id: String, name: String, help: String,
                                         @ViewBuilder image: () -> Content) -> some View {
        let selected = store.figure == id
        return Button { store.figure = id } label: {
            VStack(spacing: 2) {
                image().frame(height: 26)
                Text(name).font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(selected ? Palette.brand.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? Palette.brand : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(name) — \(help)")
        .accessibilityLabel("Choose \(name)")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                Text(Store.count(store.folderRows.count, "folder"))
                Text("· " + Store.count(Set(env.worktrees.map(\.repo)).count, "repo"))
                if store.filtering {
                    Text("· \(store.folderRows.filter(store.passes).count) shown")
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
