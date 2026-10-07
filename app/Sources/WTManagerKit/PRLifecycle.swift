import Foundation

public struct LinkedPRStats {
    public let open: Int
    public let merged: Int
    public let closed: Int
    public let unconfirmed: Int
    public init(worktrees: [Worktree]) {
        let groups = Dictionary(grouping: worktrees.filter { $0.linkedPR != nil }, by: PRLifecycle.key)
        var o=0, m=0, c=0, unknown=0
        for rows in groups.values {
            let states = Set(rows.compactMap { $0.linkedPR?.state })
            if states.count != 1 { unknown += rows.count; continue }
            switch states.first { case "OPEN": o += 1; case "MERGED": m += 1; case "CLOSED": c += 1; default: unknown += rows.count }
        }
        open=o; merged=m; closed=c
        unconfirmed=unknown + worktrees.filter { !$0.primary && !$0.isBase && $0.linkedPR == nil }.count
    }
}

public struct MergeNudge: Codable, Identifiable, Equatable {
    public let id: String
    public let number: Int
    public let repo: String
    public var paths: [String]
    public let occupiedKb: Int?
    public let blocked: Bool
}

/// Persist transitions locally. Unknown/absent results never overwrite known
/// state; duplicate checkouts never create duplicate messages. First scan seeds
/// a baseline, so installing the app doesn't announce years of old merges.
public struct PRLifecycle: Codable {
    private var states: [String: String] = [:]
    private var initialized = false
    public private(set) var pending: [MergeNudge] = []
    public init() {}
    public static func key(_ w: Worktree) -> String {
        if let url = w.linkedPR?.url, !url.isEmpty { return url }
        return "\(w.repoId ?? w.repo)/\(w.linkedPR?.number ?? 0)"
    }
    public mutating func observe(_ worktrees: [Worktree], complete: Bool = true) {
        let live = Set(worktrees.map(\.path))
        // Prune only after a complete scan; a failed repo read isn't removal.
        if complete {
            pending = pending.compactMap { n in
                var n = n; n.paths = n.paths.filter { live.contains($0) }
                return n.paths.isEmpty ? nil : n
            }
        }
        let groups = Dictionary(grouping: worktrees.filter { $0.linkedPR != nil }, by: Self.key)
        for key in groups.keys.sorted() {
            guard let rows = groups[key], let first = rows.first, let pr = first.linkedPR else { continue }
            let current = Set(rows.compactMap { $0.linkedPR?.state })
            guard current.count == 1 else { continue }
            if initialized && states[key] == "OPEN" && pr.state == "MERGED" && !pending.contains(where: { $0.id == key }) {
                let checkouts = rows.filter { !$0.primary && !$0.isBase }
                let paths = Array(Set(checkouts.map(\.path))).sorted()
                if !paths.isEmpty {
                    let measured = checkouts.allSatisfy { $0.sizeKb >= 0 }
                    // Count a path only once even if duplicated in an envelope.
                    let unique = Dictionary(grouping: checkouts, by: \.path).values.compactMap { $0.first }
                    pending.append(MergeNudge(id: key, number: pr.number, repo: first.repo, paths: paths,
                        occupiedKb: measured ? unique.reduce(0) { $0 + $1.sizeKb } : nil,
                        blocked: checkouts.contains { $0.removalBlocked || $0.status != "merged" }))
                }
            }
            if pr.state == "MERGED", let index = pending.firstIndex(where: { $0.id == key }) {
                let checkouts = rows.filter { !$0.primary && !$0.isBase }
                let currentPaths = Set(checkouts.map(\.path))
                let paths = (complete ? currentPaths : currentPaths.union(pending[index].paths)).sorted()
                let unique = Dictionary(grouping: checkouts, by: \.path).values.compactMap { $0.first }
                let measured = paths.count == unique.count && unique.allSatisfy { $0.sizeKb >= 0 }
                pending[index] = MergeNudge(id: key, number: pr.number, repo: first.repo, paths: paths,
                    occupiedKb: measured ? unique.reduce(0) { $0 + $1.sizeKb } : nil,
                    blocked: paths.count != unique.count || checkouts.contains { $0.removalBlocked || $0.status != "merged" })
                if paths.isEmpty { pending.remove(at: index) }
            }
            if pr.state != "MERGED" { pending.removeAll { $0.id == key } }
            states[key] = pr.state
        }
        initialized = true
    }
    public mutating func dismiss(_ id: String) { pending.removeAll { $0.id == id } }
}
