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
            VStack(alignment: .leading, spacing: 14) {
                // Title and line together, the way the Mascots page has them.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Locations")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        if !places.isEmpty {
                            Text(verbatim: "\(places.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.muted)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                    Text("Where your worktree folders live, biggest first. Open one to see them.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if places.isEmpty {
                    Text(store.envelope == nil ? "Reading your repos…" : "No worktree folders yet.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                            if i > 0 { Hairline().padding(.horizontal, 14) }
                            PlaceRow(store: store, place: place, share: share(of: place))
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                }
                if !store.leftovers.isEmpty { LeftoversCard(store: store, items: store.leftovers) }
                if let note = store.commandNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
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
        let safe: Int = place.count("safe")
        let unsaved: Int = place.count("unsaved")
        if safe > 0 { parts.append("\(safe) safe") }
        if unsaved > 0 { parts.append("\(unsaved) unsaved") }
        if place.cachesKb > 0 { parts.append(Store.human(place.cachesKb) + " caches") }
        return parts.joined(separator: " · ")
    }
    @State private var hovering = false

    private var elsewhere: Bool { place.id == Store.elsewhere }

    var body: some View {
        Button {
            store.locationFilter = place.id
            store.verdictFilter = nil
            store.page = .folders
        } label: {
            HStack(spacing: 12) {
                Image(systemName: elsewhere ? "folder" : "folder.fill")
                    .font(.system(size: 17)).foregroundStyle(Palette.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.locationLabel(place.id))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(elsewhere ? "folders that sit alone in their parent" : place.id)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.head)
                    Text(summary)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    // How big this place is beside the biggest: the list is
                    // sorted by size, and the bar is that order made visible.
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(width: 180, height: 5)
                        Capsule().fill(Palette.status("draft"))
                            .frame(width: max(4, 180 * CGFloat(share)), height: 5)
                    }
                    .padding(.top, 3).accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                Text(place.kb > 0 ? Store.human(place.kb) : "—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
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
