import SwiftUI
import WTManagerKit

/// Folders and registrations git and the disk disagree about. Shown, with the
/// way to look at each; nothing here is deleted by the app, because an orphan
/// is exactly the thing it has no evidence about.
struct LeftoversCard: View {
    let items: [Leftover]
    @State private var copied: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Leftovers git no longer tracks")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(items.count) found · not counted as worktrees")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            ForEach(items) { item in
                Hairline().padding(.horizontal, 14)
                row(item)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row(_ item: Leftover) -> some View {
        let orphan: Bool = item.kind == "orphan"
        let name: String = URL(fileURLWithPath: item.path).lastPathComponent
        let size: String = item.kb > 0 ? " · " + Store.human(item.kb) : ""
        let command: String = "git -C '" + item.main + "' worktree prune"
        return HStack(spacing: 12) {
            Image(systemName: orphan ? "questionmark.folder" : "link.badge.plus")
                .font(.system(size: 17)).foregroundStyle(Palette.inkRisk).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name + " · " + item.repo)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.reason + size)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                Text(item.path)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.head).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if orphan {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                }
            } else {
                Button(copied == item.id ? "Copied" : "Copy prune command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = item.id
                }
                .help(command)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
