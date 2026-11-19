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
    /// 0 keeps everything; thirty days unless chosen otherwise. Expired sets go to the Trash, never straight out.
    @AppStorage("wtmanager.keptDays") private var keptDays = 30

    static var root: URL {
        if let data = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !data.isEmpty {
            return URL(fileURLWithPath: data).appendingPathComponent("wt-manager/kept")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/wt-manager/kept")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kept files").font(.system(size: 20, weight: .semibold))
                        Text("Files git could not give back, copied and verified before a folder was deleted. They stay until you remove them or they expire.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Text("Expire after").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .fixedSize()
                        Picker("Expire after", selection: $keptDays) {
                            Text("90 days").tag(90); Text("30 days").tag(30); Text("Never").tag(0)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                        .onChange(of: keptDays) { _ in load() }
                    }
                }
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if !loaded {
                    Text("Reading…").font(.system(size: 13)).foregroundStyle(Palette.muted)
                } else if sets.isEmpty {
                    CardBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing has been set aside yet").font(.system(size: 13, weight: .semibold))
                            Text("When a deleted folder holds files git cannot give back, they are copied here first.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                } else {
                    ForEach(repos, id: \.self) { repo in card(repo) }
                    HStack {
                        Text(Store.count(sets.count, "set") + " · " + Store.human(sets.reduce(0) { $0 + $1.kb }))
                        Spacer()
                        Text("Stored only on this Mac")
                    }
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            .padding(28)
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
        let where_: String = (Self.root.appendingPathComponent(repo).path as NSString).abbreviatingWithTildeInPath
        return CardBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo).font(.system(size: 15, weight: .semibold))
                (Text(where_).font(.system(size: 12, design: .monospaced))
                 + Text(" · " + Store.count(mine.count, "set") + " · " + Store.human(total)).font(.system(size: 12)))
                    .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            ForEach(mine) { set in
                Hairline().padding(.horizontal, 20)
                row(set)
            }
        }
    }

    /// What a set holds, by name: the first few things in it.
    private func contents(_ set: KeptSet) -> String {
        let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: set.url.path)) ?? [])
            .filter { !$0.hasPrefix(".DS_") }.sorted()
        if names.isEmpty { return set.url.hasDirectoryPath ? "Empty" : "One file" }
        // Only the record: the work itself is a rescue branch inside the repo.
        if names == ["RESTORE.txt"] { return "Edits and commits, saved in the repo as a rescue branch" }
        let head: String = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? head + " and \(names.count - 3) more" : head
    }

    private func expiry(_ set: KeptSet) -> String {
        guard keptDays > 0, set.date != Date.distantPast else { return "" }
        let left: Int = keptDays - Int(Date().timeIntervalSince(set.date) / 86400)
        return " · expires in " + Store.count(max(left, 0), "day")
    }

    private func row(_ set: KeptSet) -> some View {
        let when: String = RelativeDateTimeFormatter().localizedString(for: set.date, relativeTo: Date())
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(contents(set)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Kept " + when + expiry(set)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Store.human(set.kb)).font(.system(size: 13)).monospacedDigit().fixedSize()
            Button("Restore…") { restore(set) }.buttonStyle(.wt(.quiet))
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([set.url]) }
                .buttonStyle(.wt(.quiet))
            Button { pending = set } label: { Image(systemName: "trash").font(.system(size: 12)) }
                .buttonStyle(TrashButtonStyle(side: 30))
            .accessibilityLabel("Move \(set.name) to the Trash")
            .help("Move to the Trash")
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
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
        // A rescue is restored with git, and its record says how.
        let record: URL = set.url.appendingPathComponent("RESTORE.txt")
        let inside: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: set.url.path)) ?? [])
            .filter { !$0.hasPrefix(".DS_") }
        if inside == ["RESTORE.txt"] {
            NSWorkspace.shared.open(record)
            return
        }
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
