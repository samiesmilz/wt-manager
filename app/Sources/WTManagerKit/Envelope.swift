import Foundation

// What the engine says, as plain data.
//
// Here rather than beside the process that spawns it because an executable
// target cannot be imported by a test. That is not a technicality: the rule
// that keeps `counts` consistent with `worktrees` after a local edit lived in
// the executable, could not be tested, and was wrong — the list emptied while
// the number beside it went on claiming the rows were there.

public struct PRInfo: Decodable {
    public let number: Int
    public let state: String
    public let draft: Bool
    public let checks: String
    public let review: String
    public let distinctFailing: [String]
    public let endemic: [String]
    public let url: String
    public let mergedAt: String
    public let author: String
    public enum CodingKeys: String, CodingKey {
        case number, state, draft, checks, review, url, author
        case mergedAt = "merged_at"
        case distinctFailing = "distinct_failing"
        case endemic
    }
}

public struct RemovalInfo: Decodable {
    public let state: String
    public let reason: String
}

public struct Worktree: Decodable {
    public let repo: String
    /// Stable repository identity. Two unrelated repos may share a folder name.
    public let repoId: String?
    public let branch: String?
    public let status: String
    public let meaning: String
    public let path: String
    public let ahead: Int
    public let behind: Int
    public let dirty: Int
    /// Of `dirty`, deletions of tracked files. Git still has every one, so
    /// they are changes and not a risk. Absent from an older engine.
    public let deleted: Int?
    /// Uncommitted changes that removing this worktree would actually lose.
    public var wouldLose: Int { dirty - (deleted ?? 0) }
    /// Commits on no remote this machine knows of, whoever wrote them.
    public let unpushed: Int
    /// Of those, the ones written under this repo's own `user.email`. Absent
    /// from an older engine, which could not tell them apart.
    public let unpushedMine: Int?
    /// Your work that would not come back if this disk died. A review
    /// checkout's commits are a colleague's, and their copy is elsewhere.
    public var atRisk: Int { unpushedMine ?? unpushed }
    public let ageDays: Int
    /// Mutable so a counts-only refresh can keep the last measured figures:
    /// the engine reports -1 when it did not measure, and -1 is "unknown",
    /// not "gone".
    public var sizeKb: Int
    public var reclaimKb: Int
    public let lastCommit: Int
    public let base: String
    public let baseSource: String
    /// The repo's main working tree. `git worktree remove` refuses it, always.
    public let primary: Bool
    public var removal: RemovalInfo?
    /// The checkout of the base branch itself, which git refuses for the same
    /// reason. Defaulted rather than required: an older engine on disk beside
    /// a newer app must not fail to decode over one field.
    public var isBase: Bool = false
    public let pr: PRInfo?
    /// The subjects of the commits that exist only here, newest first, up to
    /// five. The count alone says something is at stake and not what, which
    /// left the only way of finding out being to open a terminal — the tool
    /// handing back the question it had just raised.
    public var soloLog: [String] = []
    public enum CodingKeys: String, CodingKey {
        case repo, branch, status, meaning, path, ahead, behind, dirty, deleted, unpushed, pr, base, primary, removal
        case repoId = "repo_id"
        case soloLog = "solo_log"
        case isBase = "is_base"
        case ageDays = "age_days"
        case sizeKb = "size_kb"
        case reclaimKb = "reclaim_kb"
        case lastCommit = "last_commit"
        case baseSource = "base_source"
        case unpushedMine = "unpushed_mine"
    }
    public var name: String { branch ?? "Detached · " + URL(fileURLWithPath: path).lastPathComponent }
    public var removalReady: Bool { removal?.state == "ready" }
    public var removalBlocked: Bool { removal?.state == "blocked" }
    public var removalFingerprint: String {
        "\(status)/\(base)/\(baseSource)/\(primary)/\(isBase)/\(dirty)/\(deleted ?? 0)/\(unpushed)/\(pr?.state ?? "")"
    }
}

public struct Face: Decodable {
    public let mood: String
    public let meaning: String
    public let eyes: String
    public let tint: String
    public let bob: [Int]
    public let gauge: Int
}

public struct Envelope: Decodable {
    /// Mutable so a locally applied outcome can keep it consistent with
    /// `worktrees`. Grouping rows by status is arithmetic, not judgement —
    /// unlike the headline and the mood, which stay exactly as the engine
    /// decided them until the engine decides again.
    public var counts: [String: Int]
    public let reclaimKb: Int
    public let totalKb: Int
    public let measuredDisk: Bool
    public let notices: [String]
    /// The one sentence, derived from the mood by the engine. The header shows
    /// it verbatim rather than ranking the counts again: two rankings of one
    /// set of facts drift, and this one used to say "nothing wasted" under a
    /// face that said it was carrying dead weight.
    public let headline: String
    /// One fact each, coloured by what it means, aimed at the section that
    /// answers it. Never repeated in the headline or the inventory strip.
    public var insights: [Insight] = []
    public let face: Face
    public var worktrees: [Worktree]
    /// Nobody has said where the repositories are yet.
    ///
    /// A state, not a failure. The engine used to exit 2 here and the window
    /// rendered `wt-manager exited 2: not inside a git repository` in a card
    /// headed "error" — a first run reported as a fault, over the one question
    /// the tool can answer for itself.
    public var unconfigured: Bool = false
    /// Where the engine found repositories while it was answering it.
    public var candidates: [RootCandidate] = []
    /// Folders currently watched. Included so setup remains editable later.
    public var roots: [String] = []
    public var configPath: String = ""
    public enum CodingKeys: String, CodingKey {
        case counts, notices, face, worktrees, headline, insights
        case unconfigured, candidates, roots
        case configPath = "config_path"
        case reclaimKb = "reclaim_kb"
        case totalKb = "total_kb"
        case measuredDisk = "measured_disk"
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        counts = try c.decode([String: Int].self, forKey: .counts)
        reclaimKb = try c.decode(Int.self, forKey: .reclaimKb)
        totalKb = try c.decode(Int.self, forKey: .totalKb)
        measuredDisk = try c.decode(Bool.self, forKey: .measuredDisk)
        notices = try c.decode([String].self, forKey: .notices)
        headline = try c.decode(String.self, forKey: .headline)
        insights = try c.decodeIfPresent([Insight].self, forKey: .insights) ?? []
        face = try c.decode(Face.self, forKey: .face)
        worktrees = try c.decode([Worktree].self, forKey: .worktrees)
        unconfigured = try c.decodeIfPresent(Bool.self, forKey: .unconfigured) ?? false
        candidates = try c.decodeIfPresent([RootCandidate].self, forKey: .candidates) ?? []
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        configPath = try c.decodeIfPresent(String.self, forKey: .configPath) ?? ""
    }
}

/// A folder the engine found repositories in, and how many.
public struct RootCandidate: Decodable, Identifiable, Equatable {
    public let root: String
    public let repos: Int
    public var id: String { root }
    /// `~/dev`, because the absolute path is the machine's business and the
    /// person reading it already knows where home is.
    public var display: String {
        let home = NSHomeDirectory()
        return root.hasPrefix(home) ? "~" + root.dropFirst(home.count) : root
    }
}

public struct Insight: Decodable, Identifiable {
    public let id: String
    public let label: String
    public let tint: String
    public let target: String
    public let value: Int
    /// True when this window has nowhere else that carries the same number.
    /// The window has a sidebar, so most of these are already on screen as a
    /// count beside their section; the header shows only the ones that are not.
    public var solo: Bool = false
    public enum CodingKeys: String, CodingKey { case id, label, tint, target, value, solo }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        tint = try c.decode(String.self, forKey: .tint)
        target = try c.decode(String.self, forKey: .target)
        value = try c.decode(Int.self, forKey: .value)
        solo = try c.decodeIfPresent(Bool.self, forKey: .solo) ?? false
    }
}
