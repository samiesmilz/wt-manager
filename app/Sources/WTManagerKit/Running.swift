import Foundation

// What `wt-manager ports --json` says, as plain data.
//
// Every field the engine might not send is read with a default. The app and
// the engine it shells out to are two files that can be of different ages,
// and "a newer page beside an older engine" must degrade to less detail,
// never to a decode failure over one key.

/// One process, named well enough to be told apart from whatever inherits
/// its pid: the kernel reuses process ids, so the command and the start time
/// travel with it everywhere it goes.
public struct ProcessRef: Decodable, Hashable {
    public let pid: Int
    public let command: String
    public let started: String

    public init(pid: Int, command: String, started: String) {
        self.pid = pid; self.command = command; self.started = started
    }
    enum CodingKeys: String, CodingKey { case pid, command, started }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pid = try c.decode(Int.self, forKey: .pid)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        started = try c.decodeIfPresent(String.self, forKey: .started) ?? ""
    }
}

public struct RunningServer: Decodable, Identifiable, Hashable {
    public let pid: Int
    public let command: String
    public let started: String
    public let ports: [Int]
    public let cwd: String
    /// Where inside the worktree it was started: `apps/web`, or empty at the top.
    public let folder: String
    /// False for a coding agent's own listener, which is shown and never stopped.
    public let stoppable: Bool
    /// The runners that would restart it, and so stop with it.
    public let also: [ProcessRef]

    /// The pid alone would let a reused one keep a dead row's identity.
    public var id: String { "\(pid)/\(started)" }
    public var port: Int? { ports.first }
    /// `:3000`, or `:3000 :3001` for a process holding more than one.
    public var portLabel: String { ports.map { ":\($0)" }.joined(separator: " ") }
    public var url: URL? { port.flatMap { URL(string: "http://localhost:\($0)") } }

    enum CodingKeys: String, CodingKey { case pid, command, started, ports, cwd, folder, stoppable, also }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pid = try c.decode(Int.self, forKey: .pid)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        started = try c.decodeIfPresent(String.self, forKey: .started) ?? ""
        ports = try c.decodeIfPresent([Int].self, forKey: .ports) ?? []
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
        stoppable = try c.decodeIfPresent(Bool.self, forKey: .stoppable) ?? false
        also = try c.decodeIfPresent([ProcessRef].self, forKey: .also) ?? []
    }

    /// The arguments that stop exactly this process and nothing that has
    /// since taken its pid.
    public func stopArguments(force: Bool = false) -> [String] {
        ["--json", "stop", "--pid", String(pid), "--started", started, "--command", command]
            + (force ? ["--force"] : [])
    }

    /// What a confirmation has to say before anything is signalled: every
    /// process that will be, by name.
    public func stopDetail(in worktree: String) -> String {
        let place = folder.isEmpty ? worktree : "\(worktree)/\(folder)"
        var text = "\(command) (pid \(pid)) is running in \(place)."
        if !also.isEmpty {
            let names = also.map { "\($0.command) (pid \($0.pid))" }
            let list = names.count == 1 ? names[0]
                : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
            text += " \(list) started it and would start it again, so \(names.count == 1 ? "it stops" : "they stop") too."
        }
        return text
    }
}

/// Which env files one app folder has. Names only: the engine never opens one.
public struct EnvFolder: Decodable, Identifiable, Hashable {
    public let folder: String
    public let present: [String]
    /// In the main checkout and not here: the usual reason a fresh worktree's
    /// server starts and then fails every request.
    public let missing: [String]
    public var id: String { folder }
    /// `web` for `apps/web`; the worktree's own top level is `root`.
    public var label: String { folder.isEmpty ? "root" : (folder as NSString).lastPathComponent }
    public var complete: Bool { missing.isEmpty }

    enum CodingKeys: String, CodingKey { case folder, present, missing }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
        present = try c.decodeIfPresent([String].self, forKey: .present) ?? []
        missing = try c.decodeIfPresent([String].self, forKey: .missing) ?? []
    }
}

public struct RunningWorktree: Decodable, Identifiable {
    public let path: String
    public let name: String
    public let repo: String
    public let branch: String?
    public let primary: Bool
    /// Commits the base has that this folder does not, as of the last fetch.
    /// Nil when there is no base to measure against.
    public let behind: Int?
    public let base: String
    public let env: [EnvFolder]
    public let servers: [RunningServer]
    public var id: String { path }

    enum CodingKeys: String, CodingKey { case path, name, repo, branch, primary, behind, base, env, servers }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? (path as NSString).lastPathComponent
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        primary = try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false
        behind = try c.decodeIfPresent(Int.self, forKey: .behind)
        base = try c.decodeIfPresent(String.self, forKey: .base) ?? ""
        env = try c.decodeIfPresent([EnvFolder].self, forKey: .env) ?? []
        servers = try c.decodeIfPresent([RunningServer].self, forKey: .servers) ?? []
    }

    /// "3 behind origin/main · as of last fetch". The qualifier is not
    /// decoration: the app never fetches on its own, so the number is a fact
    /// about the last time something did.
    public func behindLabel(_ fresher: Int? = nil) -> String? {
        guard let n = fresher ?? behind else { return nil }
        let against = base.isEmpty ? "its base" : base
        return n == 0 ? "Up to date with \(against) · as of last fetch"
            : "\(n) behind \(against) · as of last fetch"
    }
}

public struct RunningEnvelope: Decodable {
    public let worktrees: [RunningWorktree]
    /// Listeners whose process sits outside every known worktree.
    public let other: [RunningServer]
    public let error: String?

    public var serverCount: Int { worktrees.reduce(0) { $0 + $1.servers.count } }

    enum CodingKeys: String, CodingKey { case worktrees, other, error }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        worktrees = try c.decodeIfPresent([RunningWorktree].self, forKey: .worktrees) ?? []
        other = try c.decodeIfPresent([RunningServer].self, forKey: .other) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    /// The header's sentence for this page.
    public var headline: String {
        let n = serverCount
        if n == 0 { return "Nothing is running in your worktrees" }
        let places = worktrees.count
        return "\(n) server\(n == 1 ? "" : "s") running in \(places) worktree\(places == 1 ? "" : "s")"
    }
}

/// What `stop --json` answered.
public struct StopResult: Decodable {
    public let status: String          // stopped | gone | still_running | refused
    public let reason: String
    public let stopped: [ProcessRef]
    public let remaining: [ProcessRef]

    public var ended: Bool { status == "stopped" || status == "gone" }
    /// Only one that ignored the first ask can be asked again, harder.
    public var canForce: Bool { status == "still_running" }

    enum CodingKeys: String, CodingKey { case status, reason, stopped, remaining }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        stopped = try c.decodeIfPresent([ProcessRef].self, forKey: .stopped) ?? []
        remaining = try c.decodeIfPresent([ProcessRef].self, forKey: .remaining) ?? []
    }

    /// One sentence for the page, in the words the result supports.
    public var sentence: String {
        switch status {
        case "stopped":
            let names = stopped.map(\.command)
            return names.isEmpty ? "Stopped." : "Stopped " + names.joined(separator: ", ") + "."
        case "gone": return "It had already ended."
        case "still_running":
            return (remaining.first?.command ?? "It") + " did not exit when asked."
        default: return reason.isEmpty ? "It was left running." : reason.prefix(1).uppercased() + reason.dropFirst() + "."
        }
    }
}
