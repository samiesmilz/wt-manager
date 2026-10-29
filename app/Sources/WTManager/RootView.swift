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
        // One page. The app does two things, delete folders and clean their
        // caches, and both live on the folder list; a sidebar of four places
        // was navigation for summaries of that one list.
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
                Button("Watched folders…") { store.showingSettings = true }
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
