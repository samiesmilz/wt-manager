import AppKit
import SwiftUI

/// Settings, as the design draws them: one sheet, grouped by what the choice
/// affects. Each group is a card, each choice a row with its control on the
/// right and one line under it saying what it does.
struct SettingsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var roots: [String]
    @AppStorage("wtmanager.keptDays") private var keptDays = 0

    init(store: Store) {
        self.store = store
        _roots = State(initialValue: store.envelope?.roots ?? [])
    }

    private var changedRoots: Bool { roots != (store.envelope?.roots ?? []) }
    private var sheetHeight: CGFloat {
        min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings").font(.system(size: 20, weight: .semibold))
                        Text("One sheet, grouped by what the choice affects.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    safety
                    notifications
                    openWith
                    appearance
                    watched
                }
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)
            }
            Hairline()
            HStack(spacing: 10) {
                Button("Add a folder…") { chooseFolders() }.buttonStyle(.wt(.secondary))
                Spacer()
                if changedRoots {
                    Button("Cancel") { dismiss() }.buttonStyle(.wt(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
                Button(store.adopting ? "Saving…" : "Done") {
                    if changedRoots { store.setRoots(roots) } else { dismiss() }
                }
                .buttonStyle(.wt(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(store.adopting || (changedRoots && store.busy))
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 600, height: sheetHeight)
        .background(Palette.ground)
    }

    // MARK: groups

    private var safety: some View {
        group("Safety") {
            switchRow("Check the remote before a delete review",
                      "A quick fetch, capped at a few seconds, so “merged” is current",
                      isOn: $store.fetchBeforeReview)
            Hairline()
            switchRow("Delete a finished branch with its folder",
                      "Only when it merged or has nothing of its own",
                      isOn: $store.deleteFinishedBranch)
            Hairline()
            row("Keep set-aside files for", nil) {
                Picker("Keep set-aside files for", selection: $keptDays) {
                    Text("30 days").tag(30); Text("90 days").tag(90); Text("Forever").tag(0)
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var notifications: some View {
        group("Notifications") {
            switchRow("A pull request merged and its folder is now safe",
                      "In the app", isOn: $store.mergeNudges)
            Hairline()
            switchRow("Also in Notification Center",
                      "For when the window is closed", isOn: $store.systemNotifications)
                .disabled(!store.mergeNudges)
                .onChange(of: store.systemNotifications) { on in if on { Notifier.requestPermission() } }
            Hairline()
            switchRow("Celebrate a cleanup",
                      "Pixel sparks; off with Reduce Motion", isOn: $store.celebrationsEnabled)
            Hairline()
            switchRow("Check for updates automatically",
                      "Updates are announced, never installed for you", isOn: $store.automaticUpdates)
        }
    }

    private var openWith: some View {
        group("Open with") {
            row("Terminal", nil) {
                Picker("Terminal", selection: $store.terminalApp) {
                    ForEach(OpenWith.installed(OpenWith.terminals)) { app in Text(app.name).tag(app.id) }
                }
                .labelsHidden().fixedSize()
            }
            Hairline()
            row("Editor", nil) {
                Picker("Editor", selection: $store.editorApp) {
                    Text("First one installed").tag("")
                    ForEach(OpenWith.installed(OpenWith.editors)) { app in Text(app.name).tag(app.id) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var appearance: some View {
        group("Appearance") {
            row("Theme", nil) {
                Picker("Theme", selection: $store.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var watched: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel("Watched folders")
            if roots.isEmpty {
                CardBox {
                    Text("No folders yet. Add one to start watching your work.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                }
            } else {
                CardBox {
                    ForEach(Array(roots.enumerated()), id: \.element) { i, root in
                        if i > 0 { Hairline().padding(.horizontal, 16) }
                        HStack(spacing: 12) {
                            Text(display(root)).font(.system(size: 12, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle).help(root)
                            Spacer(minLength: 8)
                            if let n = repoCount(root), n > 0 {
                                Text(Store.count(n, "repo")).font(.system(size: 12))
                                    .foregroundStyle(Palette.muted)
                            }
                            Button("Remove") { roots.removeAll { $0 == root } }
                                .buttonStyle(.wt(.quiet))
                                .help("Stop watching this folder. Nothing is deleted.")
                                .accessibilityLabel("Remove \(display(root))")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
            }
            Text("Searched up to three levels deep. Removing a folder from this list does not delete its files or worktrees.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let error = store.settingsError, !error.isEmpty {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.riskInk)
            }
        }
    }

    // MARK: pieces

    private func group<C: View>(_ title: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(title)
            CardBox { content() }
        }
    }

    private func row<C: View>(_ title: String, _ sub: String?, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func switchRow(_ title: String, _ sub: String, isOn: Binding<Bool>) -> some View {
        row(title, sub) {
            Toggle(title, isOn: isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.safeInk)
        }
    }

    private func repoCount(_ root: String) -> Int? {
        guard let env = store.envelope else { return nil }
        let prefix: String = root.hasSuffix("/") ? root : root + "/"
        var repos = Set<String>()
        for w in env.worktrees where w.path.hasPrefix(prefix) { repos.insert(w.repo) }
        return repos.count
    }

    private func display(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch these folders"
        panel.message = "Choose folders containing your Git repositories."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !roots.contains(url.path) { roots.append(url.path) }
    }
}
