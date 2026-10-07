import AppKit
import SwiftUI

/// Revisit setup without editing a JSON file. Roots are the only setting a
/// person needs to understand before the app can tell them anything useful.
struct SettingsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var roots: [String]
    private var sheetHeight: CGFloat { min(620, 360 + CGFloat(min(roots.count, 5)) * 50) }

    init(store: Store) {
        self.store = store
        _roots = State(initialValue: store.envelope?.roots ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 23)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Watched folders")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Find repositories inside these folders, up to three levels deep.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(22)
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
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
                    .frame(minHeight: 130, maxHeight: 300)
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
                Spacer(minLength: 0)
            }
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
