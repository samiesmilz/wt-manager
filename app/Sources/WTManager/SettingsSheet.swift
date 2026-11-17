import AppKit
import SwiftUI

/// Revisit setup without editing a JSON file. Roots are the only setting a
/// person needs to understand before the app can tell them anything useful.
struct SettingsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var roots: [String]
    private var sheetHeight: CGFloat { min(840, 720 + CGFloat(min(roots.count, 3)) * 44) }

    init(store: Store) {
        self.store = store
        _roots = State(initialValue: store.envelope?.roots ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20)).foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Watched folders, what opens your work, and what the app tells you.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(22)
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                groupLabel("Watched folders · searched up to three levels deep")
                if roots.isEmpty {
                    Label("No folders selected. Add one to start watching your work.",
                          systemImage: "folder.badge.plus")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ScrollView {
                        VStack(spacing: 7) {
                        ForEach(roots, id: \.self) { root in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                            Text(display(root)).font(.system(size: 12, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                                .help(root)
                            Spacer()
                            Button { roots.removeAll { $0 == root } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain).help("Stop watching this folder")
                            .accessibilityLabel("Remove \(display(root))")
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05)))
                        }
                        }
                    }
                    .frame(minHeight: 60, maxHeight: 180)
                }
                Button {
                    chooseFolders()
                } label: {
                    Label("Add a folder", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                Text("Scanning reads your repositories. Removing a folder from this list does not delete its files or worktrees.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = store.settingsError, !error.isEmpty {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.inkRisk)
                }
                Hairline()
                groupLabel("Open with")
                Picker("Terminal", selection: $store.terminalApp) {
                    ForEach(OpenWith.installed(OpenWith.terminals)) { app in Text(app.name).tag(app.id) }
                }
                Picker("Editor", selection: $store.editorApp) {
                    Text("First one installed").tag("")
                    ForEach(OpenWith.installed(OpenWith.editors)) { app in Text(app.name).tag(app.id) }
                }
                Hairline()
                groupLabel("Before deleting a folder")
                Toggle("Check the remote first, so “merged” is current (a few seconds)", isOn: $store.fetchBeforeReview)
                Toggle("Delete its branch too, when it merged or has nothing of its own", isOn: $store.deleteFinishedBranch)
                Hairline()
                groupLabel("Tell me")
                Toggle("When a pull request merges and its folder can go", isOn: $store.mergeNudges)
                Toggle("Also in Notification Center, when the window is closed", isOn: $store.systemNotifications)
                    .onChange(of: store.systemNotifications) { on in if on { Notifier.requestPermission() } }
                    .disabled(!store.mergeNudges)
                Toggle("Celebrate a cleanup", isOn: $store.celebrationsEnabled)
                Toggle("Check for updates automatically", isOn: $store.automaticUpdates)
                Picker("Theme", selection: $store.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(22)
            Hairline()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(store.adopting ? "Saving…" : "Save folders") {
                    store.setRoots(roots)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.adopting || store.busy || roots == (store.envelope?.roots ?? []))
            }
            .padding(.horizontal, 22).padding(.vertical, 15)
        }
        .frame(width: 525, height: sheetHeight)
        .background(.background)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.5)
            .foregroundStyle(Palette.muted)
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
