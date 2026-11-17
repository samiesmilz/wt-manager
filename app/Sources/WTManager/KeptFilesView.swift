import SwiftUI
import WTManagerKit

/// What was set aside before a folder was deleted: the files git could not
/// give back. Read straight from the folder the engine copies them into, so
/// the page is true even for sets kept by a version that listed nothing.
struct KeptFilesView: View {
    struct KeptSet: Identifiable, Hashable {
        let url: URL
        let repo: String
        let name: String
        let date: Date
        let kb: Int
        var id: String { url.path }
    }

    @State private var sets: [KeptSet] = []
    @State private var loaded = false
    @State private var pending: KeptSet? = nil
    @State private var note: String? = nil
    /// 0 keeps everything. Expired sets go to the Trash, never straight out.
    @AppStorage("wtmanager.keptDays") private var keptDays = 0

    static var root: URL {
        if let data = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !data.isEmpty {
            return URL(fileURLWithPath: data).appendingPathComponent("wt-manager/kept")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/wt-manager/kept")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kept files")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Files git could not give back, copied and verified before a folder was deleted. They stay until you remove them.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Keep them for", selection: $keptDays) {
                    Text("Forever").tag(0); Text("90 days").tag(90); Text("30 days").tag(30)
                }
                .pickerStyle(.menu).fixedSize().font(.system(size: 12))
                .onChange(of: keptDays) { _ in load() }
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if !loaded {
                    Text("Reading…").font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else if sets.isEmpty {
                    Text("Nothing has been set aside yet.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    ForEach(repos, id: \.self) { repo in card(repo) }
                }
                Button("Open the kept folder in Finder") {
                    NSWorkspace.shared.open(Self.root)
                }
                .buttonStyle(.link).font(.system(size: 11)).disabled(!loaded || sets.isEmpty)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .confirmationDialog("Move these kept files to the Trash?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let set = pending { trash(set) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("They may be the only copy. You can put them back from the Trash.")
        }
    }

    private var repos: [String] {
        var seen: [String] = []
        for s in sets where !seen.contains(s.repo) { seen.append(s.repo) }
        return seen
    }

    private func card(_ repo: String) -> some View {
        let mine: [KeptSet] = sets.filter { $0.repo == repo }
        let total: Int = mine.reduce(0) { $0 + $1.kb }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo).font(.system(size: 15, weight: .semibold))
                Text(Store.count(mine.count, "set") + " · " + Store.human(total))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            ForEach(mine) { set in
                Hairline().padding(.horizontal, 14)
                row(set)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row(_ set: KeptSet) -> some View {
        let when: String = RelativeDateTimeFormatter().localizedString(for: set.date, relativeTo: Date())
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text("Kept " + when).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Text(Store.human(set.kb))
                .font(.system(size: 13, design: .rounded)).monospacedDigit()
            Button("Restore…") { restore(set) }
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([set.url]) }
            Button { pending = set } label: { Image(systemName: "trash") }
                .accessibilityLabel("Move \(set.name) to the Trash")
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func load() {
        let root: URL = Self.root
        let days: Int = keptDays
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [KeptSet] = Self.scan(root)
            var expired: Int = 0
            if days > 0 {
                let cutoff: Date = Date().addingTimeInterval(-Double(days) * 86400)
                for set in found where set.date < cutoff && set.date != Date.distantPast {
                    if (try? FileManager.default.trashItem(at: set.url, resultingItemURL: nil)) != nil { expired += 1 }
                }
                if expired > 0 { found = Self.scan(root) }
            }
            DispatchQueue.main.async {
                sets = found
                loaded = true
                if expired > 0 { note = "Moved \(expired) expired set\(expired == 1 ? "" : "s") to the Trash." }
            }
        }
    }

    /// Copies a set into a folder you choose. The kept copy stays where it is.
    private func restore(_ set: KeptSet) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Restore here"
        panel.message = "Choose where to put a copy of “\(set.name)”."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let target: URL = folder.appendingPathComponent(set.name)
        do {
            try FileManager.default.copyItem(at: set.url, to: target)
            note = "Copied to " + target.path
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            note = "Could not restore: " + error.localizedDescription
        }
    }

    private func trash(_ set: KeptSet) {
        do {
            try FileManager.default.trashItem(at: set.url, resultingItemURL: nil)
            sets.removeAll { $0.id == set.id }
        } catch {
            NSSound.beep()
        }
    }

    /// `kept/<repo>/<set>/…`: one row per set, newest first.
    static func scan(_ root: URL) -> [KeptSet] {
        let fm = FileManager.default
        var out: [KeptSet] = []
        let repos: [URL] = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])) ?? []
        for repo in repos {
            let children: [URL] = (try? fm.contentsOfDirectory(at: repo, includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: [.skipsHiddenFiles])) ?? []
            for child in children {
                let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                let date: Date = values?.contentModificationDate ?? Date.distantPast
                out.append(KeptSet(url: child, repo: repo.lastPathComponent, name: child.lastPathComponent,
                                   date: date, kb: sizeKb(child)))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    private static func sizeKb(_ url: URL) -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let size: Int = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return max(1, size / 1024)
        }
        var bytes: Int = 0
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in walker {
                bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        }
        return max(1, bytes / 1024)
    }
}
