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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Title and line together, the way the Mascots page has them.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Locations")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text(verbatim: "\(places.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink(Palette.status("trunk")))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.wash(Palette.status("trunk"))))
                    }
                    Text("Where your worktree folders live, biggest first. Open one to see them.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                }
                if places.isEmpty {
                    Text(store.envelope == nil ? "Reading your repos…" : "No worktree folders yet.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                            if i > 0 { Hairline().padding(.horizontal, 14) }
                            PlaceRow(store: store, place: place)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
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
                    .font(.system(size: 18)).foregroundStyle(Palette.status("trunk"))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.locationLabel(place.id))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(elsewhere ? "folders that sit alone in their parent" : place.id)
                        .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.head)
                    HStack(spacing: 6) {
                        tag(Store.count(place.folders.count, "folder"), Palette.status("trunk"))
                        if place.count("safe") > 0 { tag("\(place.count("safe")) safe", Palette.reclaim) }
                        if place.count("unsaved") > 0 { tag("\(place.count("unsaved")) unsaved", Palette.risk) }
                        if place.cachesKb > 0 { tag(Store.human(place.cachesKb) + " caches", Palette.reclaim) }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Text(place.kb > 0 ? Store.human(place.kb) : "—")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
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
        Text(text).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.ink(tint))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(Palette.wash(tint)))
    }
}
