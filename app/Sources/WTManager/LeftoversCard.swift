import SwiftUI
import WTManagerKit

/// Folders and registrations git and the disk disagree about. Shown, with the
/// way to look at each; nothing here is deleted by the app, because an orphan
/// is exactly the thing it has no evidence about.
struct LeftoversCard: View {
    @ObservedObject var store: Store
    let items: [Leftover]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Leftovers git no longer tracks")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(items.count) found · not counted as worktrees")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            ForEach(items) { item in
                Hairline().padding(.horizontal, 20)
                row(item)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
    }

    private func row(_ item: Leftover) -> some View {
        let orphan: Bool = item.kind == "orphan"
        let name: String = URL(fileURLWithPath: item.path).lastPathComponent
        let size: String = item.kb > 0 ? " · " + Store.human(item.kb) : ""
        let command: String = "git -C '" + item.main + "' worktree prune"
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text((item.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.head).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.reason.prefix(1).uppercased() + item.reason.dropFirst() + size)
                .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if orphan {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                }
            } else {
                Button(store.commandRunning ? "Pruning…" : "Prune entry") {
                    store.runCommand(["prune", "--path", item.main, "--yes"])
                }
                .disabled(store.commandRunning)
                .help(command)
            }
        }
        .buttonStyle(.wt(.quiet))
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
