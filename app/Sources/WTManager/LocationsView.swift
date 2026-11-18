import SwiftUI
import WTManagerKit

/// Every place worktrees live, one row each, biggest first. Opening one shows
/// its folders.
///
/// These were a list in the sidebar, which worked for eight and would not for
/// forty: a navigation rail that scrolls is a rail nobody reads, and the names
/// it had room for were `privat…rktrees`. Here each place has the width for
/// its whole path and what it holds.
struct LocationsView: View {
    @ObservedObject var store: Store

    struct Place: Identifiable {
        let id: String
        let folders: [Worktree]
        var kb: Int { folders.reduce(0) { $0 + max($1.sizeKb, 0) } }
        var cachesKb: Int { folders.reduce(0) { $0 + max($1.reclaimKb, 0) } }
        func count(_ verdict: String) -> Int { folders.filter { $0.folder?.verdict == verdict }.count }
    }

    private var places: [Place] {
        let byPlace = Dictionary(grouping: store.folderRows, by: store.location(of:))
        return byPlace.map { Place(id: $0.key, folders: $0.value) }
            .sorted { a, b in
                if (a.id == Store.elsewhere) != (b.id == Store.elsewhere) { return b.id == Store.elsewhere }
                return a.kb != b.kb ? a.kb > b.kb : a.id < b.id
            }
    }

    private func share(of place: Place) -> Double {
        let top: Int = places.map { max($0.kb, 0) }.max() ?? 0
        return top > 0 ? Double(max(place.kb, 0)) / Double(top) : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardBox {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Where worktree folders live").font(.system(size: 15, weight: .semibold))
                        Text(Store.count(places.count, "location") + " · biggest first")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                    if places.isEmpty {
                        Hairline().padding(.horizontal, 20)
                        Text(store.envelope == nil ? "Reading your repos…" : "No worktree folders yet.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                    }
                    ForEach(places) { place in
                        Hairline().padding(.horizontal, 20)
                        PlaceRow(store: store, place: place, share: share(of: place))
                    }
                }
                if !store.leftovers.isEmpty { LeftoversCard(store: store, items: store.leftovers) }
                if let note = store.commandNote {
                    Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PlaceRow: View {
    @ObservedObject var store: Store
    let place: LocationsView.Place
    /// This place's size against the biggest one, 0...1, for the bar.
    var share: Double = 0

    /// "5 folders · 3 safe · 2 unsaved · 4.1GB caches", only the parts there are.
    private var summary: String {
        var parts: [String] = [Store.count(place.folders.count, "folder")]
        if place.kb > 0 { parts.append(Store.human(place.kb)) }
        let safe: Int = place.count("safe")
        let unsaved: Int = place.count("unsaved")
        if safe > 0 { parts.append("\(safe) safe") }
        if unsaved > 0 { parts.append("\(unsaved) unsaved") }
        if place.cachesKb > 0 { parts.append(Store.human(place.cachesKb) + " caches") }
        return parts.joined(separator: " · ")
    }
    @State private var hovering = false

    private var elsewhere: Bool { place.id == Store.elsewhere }
    /// `.claude/worktrees` for an agent's home, the tilde path otherwise.
    private var shownPath: String {
        place.id.hasSuffix("/.claude/worktrees") ? ".claude/worktrees"
            : (place.id as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Button {
            store.locationFilter = place.id
            store.verdictFilter = nil
            store.page = .folders
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.locationLabel(place.id))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(elsewhere ? "folders that sit alone in their parent" : shownPath)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // How big this place is beside the biggest: the list is
                // sorted by size, and the bar is that order made visible.
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.line)
                            Capsule().fill(Palette.status("draft"))
                                .frame(width: max(4, geo.size.width * CGFloat(share)))
                        }
                    }
                    .frame(height: 5).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Open").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.quiet)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1)))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(elsewhere ? "Folders that sit alone in their parent" : place.id)
        .accessibilityLabel("\(store.locationLabel(place.id)), \(Store.count(place.folders.count, "folder")), \(Store.human(place.kb))")
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.ink(tint))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(Palette.wash(tint)))
    }
}
