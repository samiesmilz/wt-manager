import SwiftUI
import WTManagerKit

/// Everything the UI reads, in one place.
///
/// Both surfaces — the window and the menu bar item — observe this object, so
/// they cannot show different answers. The same reason the headline is derived
/// from the mood rather than ranked again: two readers of one state are fine,
/// two rankings of it are not.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var envelope: Envelope?
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    /// What it is doing right now, so a slow pass reads as work rather than as
    /// a hang. Counting takes seconds; measuring disk can take minutes on a
    /// cold cache, and "Counting…" for two minutes is indistinguishable from
    /// being stuck.
    @Published private(set) var phase: String?
    /// The last disk figures that were actually measured. A counts-only refresh
    /// carries none, and letting it overwrite these would make the totals appear
    /// after the first disk pass and then vanish five minutes later.
    @Published private(set) var disk: (total: Int, reclaim: Int)?
    /// Per-worktree sizes from the last pass that measured. The totals were
    /// already carried across counts-only refreshes; the rows were not, so the
    /// Disk tab and every row's size vanished for fifty-five minutes of each
    /// hour and reappeared after the next measurement.
    private var lastSizes: [String: (size: Int, reclaim: Int)] = [:]
    @Published var plan: Plan?
    @Published var completion: Plan?
    @Published private(set) var scanProgress: Engine.Progress?
    @Published var history = CleanupHistory()
    @Published var celebration: UUID?
    let updates = UpdateChecker()
    @AppStorage("wtmanager.automaticUpdates") var automaticUpdates = true
    @AppStorage("wtmanager.celebrations") var celebrationsEnabled = true
    @AppStorage("wtmanager.dismissedUpdate") var dismissedUpdate = ""
    private let historyKey = "wtmanager.cleanupHistory.v1"
    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: historyKey) }
    }
    func prepareToQuit() -> Bool {
        guard plan?.stage != .committing else { return false }
        timers.forEach { $0.invalidate() }
        engine.shutdown()
        return true
    }
    func quit() {
        guard plan?.stage != .committing else { return }
        NSApplication.shared.terminate(nil)
    }

    @AppStorage("wtmanager.floatingMascot") var floatingMascot = true

    @AppStorage("wtmanager.skin") var skin: String = "acorn"
    /// Which character, or `Store.ownFigure` for a picture the person chose.
    @AppStorage("wtmanager.figure") var figure: String = "cat"
    @AppStorage("wtmanager.theme") var theme: String = "system"     // system | light | dark
    /// Free text and status chips, applied to the rows. Kept out of the engine
    /// on purpose: filtering is a question about what you want to look at, not
    /// about what is true, and the counts and the mood must not move when you
    /// narrow the view.
    @Published var query: String = ""
    @Published var repoFilter: String?
    @Published var statusFilter: Set<String> = []
    @Published var section: String = "overview"
    @Published var selected: Worktree?
    @Published var showingSettings = false
    /// Bumped to move focus into the filter field. A counter rather than a Bool
    /// because focusing twice in a row is a real request, and a Bool that is
    /// already true is silently ignored.
    @Published private(set) var focusFilter = 0

    /// ⌘F. Only the worktree sections carry a filter bar, so asking for it from
    /// Overview or Disk has to land somewhere that has one — otherwise the
    /// shortcut works on five screens of seven, which is the kind of nearly
    /// that reads as broken. The first populated group is where you were going
    /// to look anyway.
    func focusTheFilter() {
        if section == "overview" || section == "disk" {
            section = groups.first?.id ?? Self.spec[0].0
        }
        focusFilter += 1
    }

    /// The sections in sidebar order, for ⌘1…⌘9.
    var sectionOrder: [String] { ["overview", "disk"] + Self.spec.map { $0.0 } }

    let mascot: Mascot?
    private let engine = Engine()
    private var timers: [Timer] = []

    init(mascot: Mascot?) {
        self.mascot = mascot
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let stored = try? JSONDecoder().decode(CleanupHistory.self, from: data) { history = stored }
        if figure == "owl" { figure = "rooster"; skin = "sunrise" }
        if figure == "dragon" { figure = "rabbit"; skin = "snow" }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var counts: [String: Int] { envelope?.counts ?? [:] }
    var attention: Int { (counts["blocked"] ?? 0) + (counts["review"] ?? 0) }
    var face: Face? { envelope?.face }

    func start() {
        // Counts first, disk second. Reading every repo takes about eight
        // seconds; measuring hundreds of gigabytes takes up to two minutes from
        // cold. Doing the slow one first means the window shows nothing at all
        // until the slow one finishes, which is the whole of the wait spent
        // looking broken. This way the answer appears quickly and the gauge
        // fills in behind it.
        refresh(measureDisk: false) { [weak self] in
            self?.refresh(measureDisk: true)
        }
        Pulse.shared.start()
        if automaticUpdates { updates.check() }
        timers.append(Timer.scheduledTimer(withTimeInterval: Engine.fastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(measureDisk: false)
                if self?.automaticUpdates == true { self?.updates.check() }
            }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: Engine.diskInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(measureDisk: true) }
        })
    }

    /// A refresh that waits its turn. `refresh` drops the request when one is
    /// already running, which is right for a timer and wrong for "I just
    /// deleted something": that one must land, or the window keeps showing
    /// the sizes it just freed until the hourly pass.
    private var pendingDisk: Bool?
    func refreshWhenIdle(measureDisk: Bool) {
        if busy {
            pendingDisk = (pendingDisk ?? false) || measureDisk
        } else {
            refresh(measureDisk: measureDisk)
        }
    }

    /// When the counts last landed. Not for display — for deciding whether a
    /// refresh is worth running at all.
    private(set) var countedAt = Date.distantPast

    /// Catch up with anything that happened outside this app.
    ///
    /// A worktree removed in a terminal — `wt`, `git worktree remove`, the
    /// daily reaper — is invisible here until the five-minute timer, and the
    /// window goes on offering to remove something that is already gone. The
    /// moment someone looks at the window is the moment that matters, and
    /// counts cost about eight seconds, so looking at it is the trigger.
    func catchUp(staleAfter: TimeInterval = 15) {
        guard Date().timeIntervalSince(countedAt) > staleAfter else { return }
        refreshWhenIdle(measureDisk: false)
    }

    func refresh(measureDisk: Bool, then next: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        phase = measureDisk ? "measuring disk" : "reading repos"
        scanProgress = nil
        engine.refresh(measureDisk: measureDisk, progress: { [weak self] p in
            self?.scanProgress = p
        }) { [weak self] result in
            guard let self else { return }
            self.busy = false
            self.phase = nil
            self.scanProgress = nil
            switch result {
            case .success(var env):
                let previous = Dictionary(uniqueKeysWithValues: (self.envelope?.worktrees ?? []).map { ($0.path, $0) })
                if !env.measuredDisk {
                    for i in env.worktrees.indices {
                        let w = env.worktrees[i]
                        if w.removal?.state == "check", let old = previous[w.path],
                           old.removalFingerprint == w.removalFingerprint {
                            env.worktrees[i].removal = old.removal ?? w.removal
                        }
                    }
                }
                if env.measuredDisk {
                    self.disk = (env.totalKb, env.reclaimKb)
                    if env.notices.isEmpty {
                        self.history.measure(roots: env.roots, totalKb: env.totalKb, rebuildableKb: env.reclaimKb)
                        self.saveHistory()
                    }
                    var sizes: [String: (size: Int, reclaim: Int)] = [:]
                    for w in env.worktrees { sizes[w.path] = (w.sizeKb, w.reclaimKb) }
                    self.lastSizes = sizes
                } else {
                    for i in env.worktrees.indices {
                        if let s = self.lastSizes[env.worktrees[i].path] {
                            env.worktrees[i].sizeKb = s.size
                            env.worktrees[i].reclaimKb = s.reclaim
                        }
                    }
                }
                self.envelope = env
                self.error = nil
                self.countedAt = Date()
                // Fresh measurements: whatever was retired was retired against
                // numbers that no longer apply.
                self.retired.removeAll()
            case .failure(let e):
                self.error = e.localizedDescription
            }
            next?()
            if let d = self.pendingDisk {
                self.pendingDisk = nil
                self.refresh(measureDisk: d)
            }
        }
    }


    /// Hand the store an envelope directly, for rendering without an engine.
    func load(_ env: Envelope) {
        envelope = env
        if env.measuredDisk { disk = (env.totalKb, env.reclaimKb) }
    }

    /// A plan for the snapshot: two worktrees in, one .env set aside, one kept out.
    static func samplePlan() -> Plan? {
        // A raw literal: the JSON's own \n escapes must reach the decoder as
        // escapes, and an ordinary multi-line literal turns them into newlines.
        let json = #"""
        {"kind":"reap","text":"skip web/feat/keys (2 unpushed — --force overrides)\n  web   feat/campaign-cards   merged 1.2G\n           keeping .env.local — set aside first\n  mobile   fix/badge-bob   empty 640M\n\n2 worktrees, 1.8G\ndry run — add --yes to remove them\n",
         "paths":["/Users/me/worktrees/web/feat-campaign-cards","/Users/me/worktrees/mobile/fix-badge-bob"],
         "plan":"abc123","count":2,"kb":1887436,
         "skipped":[{"path":"/Users/me/worktrees/web/feat-keys","repo":"web","name":"feat/keys","why":"2 unpushed","override":"--force"}],
         "precious":{"/Users/me/worktrees/web/feat-campaign-cards":[".env.local"]},
         "kept_in":"/Users/me/.local/share/wt-manager/kept","keeps_unknown":true,
         "unknown":{"/Users/me/worktrees/mobile/fix-badge-bob":[".wt-ports","notes.txt"]}}
        """#
        let r: PlanResult
        do { r = try JSONDecoder().decode(PlanResult.self, from: Data(json.utf8)) }
        catch { print("sample plan:", error); print(json); return nil }
        var p = Plan(action: Action(kind: .reap))
        p.preview = r
        p.stage = .reviewing
        return p
    }

    /// The same plan at another stage, so every state of the sheet can be
    /// rendered offscreen. The working and finished states used to be visible
    /// only by actually deleting something, which is why one of them was a
    /// 500pt box with one line in it for as long as it was.
    static func samplePlan(_ stage: Plan.Stage, progress: Engine.Progress? = nil) -> Plan? {
        guard var p = samplePlan() else { return nil }
        p.stage = stage
        p.progress = progress
        p.since = Date().addingTimeInterval(-48)
        if stage == .done {
            p.result = decodePlan(#"{"kind":"reap","text":"removed web/feat/campaign-cards\nremoved mobile/fix/badge-bob\n\n2 removed, 1.8G returned\n","paths":[],"plan":"abc123","done":true,"removed":2,"freed_kb":1887436,"completed_paths":["/demo/web/feat/campaign-cards","/demo/mobile/fix/badge-bob"]}"#)
        }
        return p
    }

    /// The id that means "not one of ours".
    static let ownFigure = "own"

    var usingOwnImage: Bool { figure == Self.ownFigure && OwnFace.exists }

    /// One frame of the character, at the size asked for.
    ///
    /// The blink is applied here rather than in the art, because it belongs to
    /// the clock and not to the mood: every mood that has its eyes open blinks,
    /// and the ones already shut simply keep them shut.
    func image(height: CGFloat, frame: Int = 0, blinking: Bool = false) -> NSImage? {
        if usingOwnImage {
            // A picture cannot blink and cannot change its eyes, so the mood
            // arrives as a ring. Before the first envelope there is no mood,
            // and no ring is drawn — a grey one would read as a state.
            return OwnFace.image(fitting: height,
                                 tint: face.flatMap { Ink.color($0.tint) })
        }
        return mascot?.image(figure: figure,
                             gauge: face?.gauge ?? 0,
                             eyes: blinking ? "shut" : (face?.eyes ?? "shut"),
                             frame: frame,
                             skin: skin,
                             tint: face?.tint ?? "#8b93a1",
                             fitting: height)
    }

    /// The next coat along, wrapping.
    ///
    /// Bound to clicking the character rather than buried in a menu: a
    /// mascot that does something when you poke it is the one control in
    /// this window anybody discovers without being told, and a coat is the
    /// safest thing a stray click can change — it means nothing, it is
    /// visible immediately, and one more click undoes it.
    func nextSkin() {
        guard let names = mascot?.skins.keys.sorted(), !names.isEmpty else { return }
        let i = names.firstIndex(of: skin).map { $0 + 1 } ?? 0
        skin = names[i % names.count]
    }

    /// Ask for a picture and adopt it. Returns false if the person cancelled
    /// or the file was not an image this machine can decode.
    @discardableResult
    func chooseOwnImage() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use this"
        panel.message = "Pick a picture to stand in for the character. It is "
            + "reduced to the same 22 pixels the characters are drawn on, and "
            + "the status colour becomes its outline."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard OwnFace.adopt(url) else {
            error = "That file could not be read as an image."
            return false
        }
        figure = Self.ownFigure
        return true
    }

    // MARK: - first run

    /// Nobody has told the tool where the repositories are.
    var unconfigured: Bool { envelope?.unconfigured ?? false }
    var candidates: [RootCandidate] { envelope?.candidates ?? [] }
    /// True while the roots are being written and the first real scan runs.
    @Published private(set) var adopting = false
    @Published private(set) var settingsError: String?

    /// Offers whose own dry run came back empty.
    ///
    /// A card that says "reclaim 97GB", is asked, finds nothing, and then goes
    /// on saying "reclaim 97GB" has been told it is wrong and kept talking.
    /// The preview is the most authoritative answer in the app — it is the
    /// engine re-measuring right now — so an empty one retires the offer that
    /// produced it until a refresh establishes otherwise.
    @Published private(set) var retired: Set<String> = []

    /// Take these folders as the roots, then read them.
    ///
    /// Written through the engine rather than by encoding JSON here: the
    /// config file has six other keys and a default for each, and a second
    /// writer that knows about one of them is how the other five get dropped
    /// by whichever process saved last.
    func adopt(roots: [String]) { setRoots(roots) }

    func setRoots(_ roots: [String]) {
        guard !adopting else { return }
        adopting = true
        settingsError = nil
        let args = roots.isEmpty ? ["config", "--clear-roots"]
                                 : ["config"] + roots.flatMap { ["--roots", $0] }
        engine.run(args) { [weak self] result in
            guard let self else { return }
            self.adopting = false
            if case .failure(let e) = result {
                self.settingsError = "Could not save folders: \(e.localizedDescription)"
                self.error = self.settingsError
                return
            }
            self.showingSettings = false
            // Counts first and disk behind them, exactly as at launch — the
            // first scan of a machine nobody has measured is the slow one.
            self.refresh(measureDisk: false) { [weak self] in
                self?.refresh(measureDisk: true)
            }
        }
    }

    /// For a machine that keeps its code somewhere the conventions do not name.
    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan this"
        panel.message = "Pick the folder your repositories live in. "
            + "wt-manager looks three levels down, and never writes to them."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        adopt(roots: panel.urls.map(\.path))
    }

    /// Rows grouped by what you would do about them. The order is the advice.
    struct Group: Identifiable {
        let id: String
        let title: String
        let hint: String
        let items: [Worktree]
        /// What an empty section means, in its own words. "Nothing here" is
        /// the same sentence for good news and for a filter that matched nothing.
        var emptyText: String {
            switch id {
            case "all":    return "No worktrees yet."
            case "need":   return "Nothing needs you."
            case "forgot": return "Nothing has been forgotten."
            case "flight": return "Nothing in flight."
            case "others": return "Nothing is with other people."
            case "repos":  return "No repositories in scope."
            default:       return "Nothing finished to remove."
            }
        }
    }

    var filtering: Bool { !query.isEmpty || !statusFilter.isEmpty || repoFilter != nil }

    private func matches(_ w: Worktree) -> Bool {
        if let repoFilter, (w.repoId ?? w.repo) != repoFilter { return false }
        if !statusFilter.isEmpty && !statusFilter.contains(w.status) { return false }
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return w.repo.lowercased().contains(q)
            || (w.branch ?? "").lowercased().contains(q)
            || w.status.contains(q)
    }

    /// Every section, empty ones included. The sidebar must not reshuffle as
    /// counts change — a nav whose items move is a nav you stop trusting.
    var allGroups: [Group] {
        let w = envelope?.worktrees ?? []
        return Self.spec.map { id, title, hint, statuses in
            Group(id: id, title: title, hint: hint,
                  items: w.filter { statuses.contains($0.status) })
        }
    }

    static let spec: [(String, String, String, [String])] = [
        ("all",    "All worktrees",     "every checkout, including the main one",     ["blocked", "review", "stale", "active", "draft", "waiting", "merged", "empty", "trunk"]),
        ("need",   "Needs you",         "specific to your branch",     ["blocked", "review"]),
        ("forgot", "Forgotten",         "without a recent commit",   ["stale"]),
        ("flight", "In flight",         "your recent work",     ["active", "draft"]),
        ("others", "With others",       "nothing for you to do",       ["waiting"]),
        ("done",   "Finished",          "landed or already in the base", ["merged", "empty"]),
        // Your repositories themselves, not worktrees you made. They were
        // filed under "Finished" — so `private/main`, holding 64GB, sat under
        // a heading that means landed and safe to delete. It is neither
        // finished nor yours to finish, and `git worktree remove` refuses it
        // for ever. It is a third of the rows here and most of the disk, so
        // hiding it would be its own lie.
        ("repos",  "Main checkouts",    "the repos themselves, not worktrees", ["trunk"]),
    ]

    var groups: [Group] {
        let w = (envelope?.worktrees ?? []).filter(matches)
        return Self.spec.compactMap { id, title, hint, statuses in
            let items = w.filter { statuses.contains($0.status) }
            return items.isEmpty ? nil : Group(id: id, title: title, hint: hint, items: items)
        }
    }

    /// "1 commit", "2 commits": a count, where the sentence supplies the verb.
    static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    /// "1 commit exists", "2 commits exist". Grammar is part of being read.
    static func commits(_ n: Int, _ verb: (String, String) = ("exists", "exist")) -> String {
        n == 1 ? "1 commit \(verb.0)" : "\(n) commits \(verb.1)"
    }

    /// Why a row is where it is, in the words a person would use.
    func reason(_ w: Worktree) -> String {
        if let pr = w.pr, !pr.distinctFailing.isEmpty {
            return "failing here and not across the repo — " + pr.distinctFailing.joined(separator: ", ")
        }
        switch w.status {
        case "review": return "a reviewer asked for changes"
        case "draft":  return w.pr.map { "#\($0.number) is a draft — yours, not yet offered" } ?? "a draft"
        case "stale":
            var s = "last commit \(w.ageDays) days ago"
            if w.atRisk > 0 { s += " · " + Self.commits(w.atRisk) + " only here" }
            return s
        case "empty":  return "no commits ahead of \(w.base) — review local files before removal"
        case "merged": return w.pr.map { "landed in #\($0.number)" } ?? "landed"
        case "trunk":  return "the base branch itself"
        default: break
        }
        if let pr = w.pr, !pr.endemic.isEmpty {
            return "#\(pr.number) — failing across the repo, so not yours"
        }
        if w.dirty > 0 {
            return "\(w.dirty) uncommitted" + (w.atRisk > 0 ? " · \(w.atRisk) unpushed" : "")
        }
        if w.atRisk > 0 { return Self.commits(w.atRisk) + " only on this machine" }
        return w.meaning
    }

    /// A size, with the unit spelled far enough to be a unit. `348M` sitting in
    /// a row of plain counts — 3 needing you, 17 forgotten, 56 commits only
    /// here — reads as "348 million", which is what that column shape usually
    /// means. `MB` cannot be read as anything else, and costs one character.
    /// Kept in step with `human()` in the engine, which formats the same
    /// numbers for the table.
    static func human(_ kb: Int) -> String {
        guard kb > 0 else { return "—" }
        for (suffix, factor) in [("TB", 1 << 30), ("GB", 1 << 20), ("MB", 1 << 10)] where kb >= factor {
            let v = Double(kb) / Double(factor)
            return v < 10 ? String(format: "%.1f%@", v, suffix) : "\(Int(v))\(suffix)"
        }
        return "\(kb)KB"
    }
}

// MARK: - insight
//
// A list of worktrees is not insight; you already knew you had branches. These
// are the three things the data knows that you do not: what you could lose,
// what it is costing, and how much of it has quietly died.

extension Store {
    /// Work that exists on this machine and nowhere else. The only number here
    /// that describes a *risk* rather than a cost — if the disk failed this
    /// morning, this is what would not come back.
    struct Risk {
        let items: [Worktree]
        /// Commits on no remote that someone else wrote — review checkouts,
        /// mostly. Counted so the card can say they were left out, rather
        /// than the total silently shrinking.
        let others: Int
        let othersIn: Int
        var commits: Int { items.reduce(0) { $0 + $1.atRisk } }
        var dirtyFiles: Int { items.reduce(0) { $0 + $1.wouldLose } }
        var withCommits: Int { items.filter { $0.atRisk > 0 }.count }
        var withChanges: Int { items.filter { $0.wouldLose > 0 }.count }
    }

    var risk: Risk {
        let rows = envelope?.worktrees ?? []
        let foreign = rows.filter { $0.unpushed > $0.atRisk }
        return Risk(items: rows
                        .filter { $0.atRisk > 0 || $0.wouldLose > 0 }
                        .sorted { ($0.atRisk, $0.wouldLose) > ($1.atRisk, $1.wouldLose) },
                    others: foreign.reduce(0) { $0 + $1.unpushed - $1.atRisk },
                    othersIn: foreign.count)
    }

    struct RepoWeight: Identifiable {
        let id: String
        let total: Int
        let reclaim: Int
        var keep: Int { max(total - reclaim, 0) }
    }

    /// Disk by repo, biggest first. Per repo rather than per worktree because
    /// the actionable unit is "this project is eating the disk", and fifteen
    /// worktrees of one monorepo is one decision, not fifteen.
    var weights: [RepoWeight] {
        var totals: [String: (Int, Int)] = [:]
        for w in envelope?.worktrees ?? [] where w.sizeKb > 0 {
            var e = totals[w.repo] ?? (0, 0)
            e.0 += w.sizeKb
            e.1 += max(w.reclaimKb, 0)
            totals[w.repo] = e
        }
        return totals.map { RepoWeight(id: $0.key, total: $0.value.0, reclaim: $0.value.1) }
            .sorted { $0.total > $1.total }
    }

    /// A next move, with its payoff attached.
    struct Move: Identifiable {
        let title: String
        let detail: String
        /// What to do about it, if it is something the app can do. Carrying the
        /// action rather than a string means the recommendation and the button
        /// cannot disagree about what "this" is.
        let action: Action?
        let tint: Color
        /// Where to go to decide, when the decision is not the app's to make.
        var handoff: Worktree? = nil
        var id: String { title }
    }

    /// The moves worth making, most urgent first, and never more than three.
    ///
    /// One was too few: the rule below is an ordered first-match, so a single
    /// blocked PR hid a hundred gigabytes of reclaimable build output behind
    /// it for as long as the PR stayed blocked — and a blocked PR can stay
    /// blocked for a week. Three is the cap because the order *is* the advice,
    /// and a list long enough to skim stops being advice at all.
    var moves: [Move] {
        guard let env = envelope else { return [] }
        var out: [Move] = []
        // Anything whose own dry run came back empty is not offered again
        // until the next refresh.
        func live(_ m: Move) -> Bool { m.action.map { !retired.contains($0.id) } ?? true }
        if let first = env.worktrees.first(where: { $0.status == "blocked" || $0.status == "review" }) {
            out.append(Move(title: "\(first.repo) · \(first.name)",
                            detail: reason(first), action: nil, tint: Palette.status("blocked"), handoff: first))
        }
        let ready = removalCandidates.filter(\.removalReady)
        let pending = removalCandidates.filter { !$0.removalReady }
        if !ready.isEmpty {
            let kb = ready.reduce(0) { $0 + max($1.sizeKb, 0) }
            out.append(Move(title: "Review removal of \(ready.count) eligible worktrees",
                            detail: "up to \(Store.human(kb)); local files were checked and protected files will be archived",
                            action: Action(kind: .reap, paths: ready.map(\.path)), tint: Palette.reclaim))
        } else if !pending.isEmpty {
            out.append(Move(title: "Check \(pending.count) finished worktrees",
                            detail: "local files have not been checked yet; this opens a preview",
                            action: Action(kind: .reap, paths: pending.map(\.path)), tint: Palette.reclaim))
        } else if let kept = env.worktrees.first(where: { ["merged", "empty"].contains($0.status) && $0.removalBlocked }) {
            out.append(Move(title: "Finished work is being kept",
                            detail: kept.removal?.reason ?? "Review local files first",
                            action: nil, tint: Palette.status("stale"), handoff: kept))
        }
        // The number and the button have to come from one query.
        //
        // This offered "Reclaim 97GB of build output" and ran `clean --stale`,
        // which on this machine reclaims *nothing*: a worktree untouched for
        // sixty days was cleaned long ago or never built. The title took the
        // whole-machine figure, the action took the forgotten-only filter, and
        // the gap between them was the worst sentence in the app — a promise
        // of ninety-seven gigabytes answered with "nothing reclaimable under
        // that filter".
        let staleKb = env.worktrees
            .filter { ["stale", "merged", "empty"].contains($0.status) }
            .reduce(0) { $0 + max($1.reclaimKb, 0) }
        let allKb = disk?.reclaim ?? 0
        if staleKb > (2 << 20) {
            out.append(Move(title: "Reclaim \(Store.human(staleKb)) from forgotten work",
                            detail: "build output in finished branches or branches without a recent commit",
                            action: Action(kind: .clean, paths: reclaimCandidates(staleOnly: true).map(\.path), staleOnly: true), tint: Palette.reclaim))
        } else if allKb > (20 << 20) {
            // Where the disk actually is. Most of it sits in the repos
            // themselves, which no amount of reaping reaches.
            out.append(Move(title: "Reclaim \(Store.human(allKb)) of build output",
                            detail: "mostly in the repos themselves, not in worktrees — you will need to reinstall before building again",
                            action: Action(kind: .clean, paths: reclaimCandidates().map(\.path)), tint: Palette.reclaim))
        }
        // What is at stake, and the verb for it. This used to say "nothing is
        // blocking you" over branches holding the only copy of someone's work.
        // One number for one fact. The header's tag counts every unpushed
        // commit; this counted only the pushable ones, so the same card said
        // 51 in one place and 39 in the other. The difference is real — a
        // detached checkout has no branch to push — so it is named rather
        // than silently subtracted.
        let pushable = env.worktrees.filter { $0.atRisk > 0 && $0.branch != nil }
        let stranded = env.worktrees.filter { $0.atRisk > 0 && $0.branch == nil }
        let total = env.worktrees.reduce(0) { $0 + $1.atRisk }
        if let worst = pushable.max(by: { $0.atRisk < $1.atRisk }) {
            var detail = pushable.count == 1
                ? "all of it in \(worst.repo) · \(worst.name)"
                : "across \(pushable.count) branches — \(worst.repo) · \(worst.name) holds the most"
            let strandedCommits = stranded.reduce(0) { $0 + $1.atRisk }
            if strandedCommits > 0 {
                detail += "; \(strandedCommits) more sit on detached checkouts and need a branch first"
            }
            // Pushing is the task's decision, not this window's: the same
            // commits might be a branch to offer, or one to drop. So the move
            // names the worst case and hands you to it.
            out.append(Move(title: Store.commits(total) + " only on this machine",
                            detail: detail, action: nil, tint: Palette.inkRisk,
                            handoff: worst))
        }
        let stale = env.counts["stale"] ?? 0
        if stale > 0 {
            out.append(Move(title: stale == 1 ? "1 branch has gone quiet"
                                             : "\(stale) branches have gone quiet",
                            detail: "no recent commit — review the local work before finishing or dropping it",
                            action: nil, tint: Palette.status("stale")))
        }
        return Array(out.filter(live).prefix(3))
    }

    var removalCandidates: [Worktree] {
        (envelope?.worktrees ?? []).filter {
            ["merged", "empty"].contains($0.status) && !$0.primary && !$0.isBase && !$0.removalBlocked
        }
    }

    func reclaimCandidates(staleOnly: Bool = false) -> [Worktree] {
        (envelope?.worktrees ?? []).filter {
            $0.reclaimKb > 0 && (!staleOnly || ["stale", "merged", "empty"].contains($0.status))
        }
    }

    /// One row per repository: where the work, the waiting and the waste
    /// actually are.
    ///
    /// Nothing else in the window answers this. The sidebar counts by *kind*
    /// across every repo at once, the worktree list is a flat fifty-seven rows,
    /// and Disk counts bytes. But the decision a person makes is per project —
    /// "ec-website has six forgotten branches and forty-four commits that exist
    /// nowhere else" is one afternoon's work, and it is invisible in every
    /// other view here.
    struct RepoRow: Identifiable {
        let id: String
        let name: String
        let path: String
        let worktrees: Int
        let needs: Int
        let stale: Int
        let unpushed: Int
        let oldestDays: Int
        let reclaim: Int
    }

    /// Ranked by what would make you open it: something waiting on you first,
    /// then work that exists only here, then forgotten branches. Disk is
    /// deliberately *not* in the ranking — it has its own section, and letting
    /// bytes sort this list buries a blocked PR under a big `node_modules`.
    var repoRows: [RepoRow] {
        var by: [String: [Worktree]] = [:]
        for w in envelope?.worktrees ?? [] where w.status != "trunk" {
            by[w.repoId ?? w.repo, default: []].append(w)
        }
        return by.map { repoId, ws in
            RepoRow(id: repoId, name: ws[0].repo,
                    path: ws.first(where: \.primary)?.path ?? ws[0].path,
                    worktrees: ws.count,
                    needs: ws.filter { $0.status == "blocked" || $0.status == "review" }.count,
                    stale: ws.filter { $0.status == "stale" }.count,
                    unpushed: ws.reduce(0) { $0 + max($1.atRisk, 0) },
                    oldestDays: ws.filter { $0.ageDays < 9999 }.map(\.ageDays).max() ?? 0,
                    reclaim: ws.reduce(0) { $0 + max($1.reclaimKb, 0) })
        }
        .filter { $0.needs + $0.stale + $0.unpushed > 0 || $0.worktrees > 1 }
        .sorted {
            if $0.needs != $1.needs { return $0.needs > $1.needs }
            if $0.unpushed != $1.unpushed { return $0.unpushed > $1.unpushed }
            if $0.stale != $1.stale { return $0.stale > $1.stale }
            return $0.worktrees > $1.worktrees
        }
    }
}


// MARK: - actions
//
// Two rules hold this together.
//
// **Scope is explicit.** Every action carries the exact paths it will touch, so
// "clean this one worktree" and "clean everything" are the same code with a
// different list rather than two behaviours that can drift apart. A bulk sweep
// is the special case, not the default.
//
// **You approve the dry run's own output.** Not a sentence describing it. A
// description drifts from the thing it describes; its own output cannot.

extension Store {
    enum ActionKind: String, CaseIterable, Identifiable {
        case reap, clean
        var id: String { rawValue }
        var verb: String {
            switch self {
            case .reap:  return "Remove"
            case .clean: return "Delete"
            }
        }
        var icon: String {
            switch self {
            case .reap:  return "scissors"
            case .clean: return "sparkles"
            }
        }
    }

    struct Action: Identifiable, Equatable {
        let kind: ActionKind
        /// Empty means everything in scope — which is why it is never the default
        /// anywhere in the UI.
        var paths: [String] = []
        var staleOnly = false
        var id: String { "\(kind.rawValue)/\(paths.joined(separator: ","))/\(staleOnly)" }

        var single: Bool { paths.count == 1 }

        var title: String {
            switch (kind, single, staleOnly) {
            case (.reap, true, _):      return "Review removal of this worktree"
            case (.reap, false, _):     return "Review worktree removal"
            case (.clean, true, _):     return "Reclaim this worktree's build output"
            case (.clean, false, true): return "Reclaim build output from forgotten work"
            case (.clean, false, false):return "Reclaim build output everywhere"
            }
        }

        var blurb: String {
            switch kind {
            case .reap:
                return "Removes only eligible worktrees. Protected files and small unclassified files are copied and verified first. Work at risk is kept in place."
            case .clean:
                return "Deletes only what a build or install would put back. Environment files, keys and anything unrecognised are left alone."
            }
        }

        /// The dry run, as a machine-readable plan. `--json` is a global flag
        /// and has to precede the subcommand.
        var previewArgs: [String] {
            var a = ["--json", kind.rawValue]
            if kind == .clean && staleOnly && paths.isEmpty { a += ["--stale"] }
            for p in paths { a += ["--path", p] }
            return a
        }

        /// The commit names the *set* the preview showed, not the filter that
        /// produced it: every path explicitly, plus the plan's hash, which the
        /// engine recomputes and refuses to act on if it no longer matches.
        /// Re-running the filter would delete whatever entered scope between
        /// the preview and the click without it ever having been on screen.
        func commitArgs(for preview: PlanResult) -> [String] {
            var a = [kind.rawValue]
            if kind == .clean && staleOnly && paths.isEmpty { a += ["--stale"] }
            for p in preview.paths { a += ["--path", p] }
            return a + ["--plan", preview.plan, "--yes"]
        }
    }

    /// What `reap --json` / `clean --json` print: the dry run's own text, and
    /// the exact set it describes.
    struct PlanResult: Decodable {
        struct Skipped: Decodable {
            let path: String
            let repo: String
            let name: String
            let why: String
            let override: String
        }
        let kind: String
        let text: String
        let paths: [String]
        let plan: String
        var count: Int = 0
        var kb: Int = 0
        var skipped: [Skipped] = []
        var precious: [String: [String]] = [:]
        /// Where reap copies `precious` before removing; empty when they are
        /// discarded instead.
        var keptIn: String = ""
        /// Whether `unknown` is set aside with them rather than deleted.
        var keepsUnknown: Bool = false
        var unknown: [String: [String]] = [:]
        var entries: [String: [String]] = [:]
        var done: Bool = false
        var removed: Int = 0
        var completedPaths: [String] = []
        var freedKb: Int = 0
        var failed: Int = 0
        var rc: Int = 0
        enum CodingKeys: String, CodingKey {
            case kind, text, paths, plan, count, kb, skipped, precious, unknown, entries
            case done, removed, failed, rc
            case freedKb = "freed_kb"
            case completedPaths = "completed_paths"
            case keptIn = "kept_in"
            case keepsUnknown = "keeps_unknown"
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            kind = try c.decode(String.self, forKey: .kind)
            text = try c.decode(String.self, forKey: .text)
            paths = try c.decode([String].self, forKey: .paths)
            plan = try c.decode(String.self, forKey: .plan)
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
            kb = try c.decodeIfPresent(Int.self, forKey: .kb) ?? 0
            skipped = try c.decodeIfPresent([Skipped].self, forKey: .skipped) ?? []
            precious = try c.decodeIfPresent([String: [String]].self, forKey: .precious) ?? [:]
            keptIn = try c.decodeIfPresent(String.self, forKey: .keptIn) ?? ""
            keepsUnknown = try c.decodeIfPresent(Bool.self, forKey: .keepsUnknown) ?? false
            unknown = try c.decodeIfPresent([String: [String]].self, forKey: .unknown) ?? [:]
            entries = try c.decodeIfPresent([String: [String]].self, forKey: .entries) ?? [:]
            done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
            removed = try c.decodeIfPresent(Int.self, forKey: .removed) ?? 0
            completedPaths = try c.decodeIfPresent([String].self, forKey: .completedPaths) ?? []
            freedKb = try c.decodeIfPresent(Int.self, forKey: .freedKb) ?? 0
            failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
            rc = try c.decodeIfPresent(Int.self, forKey: .rc) ?? 0
        }
    }

    struct Plan: Identifiable {
        enum Stage { case previewing, reviewing, committing, done, failed, changed }

        let id = UUID()
        let action: Action
        var stage: Stage = .previewing
        var preview: PlanResult?
        var result: PlanResult?
        var error: String?
        /// The last thing the engine said about how far along it is.
        var progress: Engine.Progress?
        /// When the current stage began, so a wait can say how long it has
        /// been waiting. An indeterminate spinner over ninety seconds is
        /// indistinguishable from a hang; the same spinner over "48s" is not.
        var since = Date()

        var running: Bool { stage == .previewing || stage == .committing }
        var done: Bool { stage == .done }
        var failed: String? { stage == .failed ? (error ?? "failed") : nil }
        var output: String { (stage == .done ? result?.text : preview?.text) ?? "" }
        /// Nothing in the set. The verb said so itself, in its own count.
        var empty: Bool { stage == .reviewing && (preview?.paths.isEmpty ?? true) }
    }

    func preview(_ action: Action) {
        let request = Plan(action: action)
        plan = request
        engine.run(action.previewArgs, progress: { [weak self] p in
            guard let self, var plan = self.plan, plan.id == request.id else { return }
            plan.progress = p
            self.plan = plan
        }) { [weak self] result in
            guard let self, var p = self.plan, p.id == request.id else { return }
            switch result {
            case .success(let text):
                if let parsed = Self.decodePlan(text) {
                    p.preview = parsed
                    for skip in parsed.skipped {
                        if let i = self.envelope?.worktrees.firstIndex(where: { $0.path == skip.path }),
                           let data = try? JSONSerialization.data(withJSONObject: ["state": "blocked", "reason": skip.why]),
                           let info = try? JSONDecoder().decode(RemovalInfo.self, from: data), action.kind == .reap {
                            self.envelope?.worktrees[i].removal = info
                        }
                    }
                    p.stage = .reviewing
                    // Asked and answered "nothing". The offer that led here
                    // stops being made.
                    if parsed.paths.isEmpty { self.retired.insert(action.id) }
                } else {
                    p.error = "could not read the plan:\n" + text
                    p.stage = .failed
                }
            case .failure(let e):
                p.error = e.localizedDescription
                p.stage = .failed
            }
            p.progress = nil
            p.since = Date()
            self.plan = p
        }
    }

    func commit() {
        guard var p = plan, p.stage == .reviewing, let preview = p.preview,
              !preview.paths.isEmpty else { return }
        let action = p.action
        p.stage = .committing
        p.progress = nil
        p.since = Date()
        plan = p
        var absorbed = false
        engine.run(["--json"] + action.commitArgs(for: preview), progress: { [weak self] pr in
            guard let self, var plan = self.plan, plan.action == action else { return }
            plan.progress = pr
            self.plan = plan
        }) { [weak self] result in
            guard let self, var p = self.plan, p.action == action else { return }
            switch result {
            case .success(let text):
                p.result = Self.decodePlan(text)
                if p.result?.done == true { p.stage = .done }
                else { p.stage = .failed; p.error = "The engine returned an unreadable result. Refresh before trying again." }
                absorbed = p.result.map { self.absorb($0, from: preview) } ?? false
            case .failure(let e):
                // Exit 3 is the engine refusing: the set moved under the
                // preview. Not an error to read, a preview to redo.
                if let parsed = Self.decodePlan(e.localizedDescription), parsed.rc == 3 {
                    p.result = parsed
                    p.stage = .changed
                } else if let parsed = Self.decodePlan(e.localizedDescription), parsed.done {
                    p.result = parsed
                    p.stage = .done
                } else {
                    p.error = e.localizedDescription
                    p.stage = .failed
                }
            }
            p.progress = nil
            p.since = Date()
            self.plan = p
            if p.stage == .done, let r = p.result {
                self.completion = p
                if self.history.reward(id: p.id, done: r.done, completed: r.completedPaths.count, freedKb: r.freedKb) {
                    self.saveHistory()
                    if self.celebrationsEnabled && r.failed == 0 {
                        self.celebration = p.id
                        let rewardID = p.id
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 2_800_000_000)
                            if self?.celebration == rewardID { self?.celebration = nil }
                        }
                    }
                }
                let message = r.failed > 0 ? "Operation finished with \(r.failed) issues" : "Operation completed"
                NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                     userInfo: [.announcement: message,
                                                .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
            // Counts, not bytes. Re-measuring the disk here walks every
            // worktree again — a minute and a half of spinner immediately
            // after the one thing on this window that already knows the
            // answer, because the engine reported exactly what it freed and
            // `absorb` has already applied it. The hourly pass trues it up.
            self.refreshWhenIdle(measureDisk: !absorbed)
        }
    }

    /// Apply an outcome the engine has already measured, rather than asking
    /// for the whole machine to be walked again.
    ///
    /// Only when nothing failed: the engine reports *how many* failed and not
    /// *which*, so a partial run leaves us unable to say which paths are still
    /// there — and guessing wrong here means the window claims something is
    /// gone that is not. A partial run pays for the full re-measure.
    @discardableResult
    private func absorb(_ r: PlanResult, from preview: PlanResult) -> Bool {
        guard r.done, r.failed == 0, var env = envelope else { return false }
        let touched = Set(r.completedPaths)
        switch plan?.action.kind {
        case .reap:
            env.worktrees.removeAll { touched.contains($0.path) }
            let freed = r.freedKb
            disk = disk.map { (total: max($0.total - freed, 0), reclaim: max($0.reclaim - freed, 0)) }
        case .clean:
            for i in env.worktrees.indices where touched.contains(env.worktrees[i].path) {
                env.worktrees[i].sizeKb = max(env.worktrees[i].sizeKb - env.worktrees[i].reclaimKb, 0)
                env.worktrees[i].reclaimKb = 0
                // Not cleared: a counts-only refresh reads these back, and an
                // absent entry means "unknown", which would show the row's
                // size as a dash for the next hour.
                lastSizes[env.worktrees[i].path] = (env.worktrees[i].sizeKb, 0)
            }
            disk = disk.map { (total: max($0.total - r.freedKb, 0),
                               reclaim: max($0.reclaim - r.freedKb, 0)) }
        case .none:
            return false
        }
        // Keep the envelope internally consistent, or half the window updates
        // and half does not. `counts` drives the menu bar's number, the
        // sidebar badges and every derived figure — leaving it alone after
        // removing five worktrees from `worktrees` meant the list emptied
        // while the count beside it went on claiming they were there, until
        // the refresh landed eight seconds later. That gap is the whole of
        // "it doesn't feel like it refreshed".
        //
        // Only counts, and only by grouping: that is arithmetic over rows we
        // already have. The headline, the mood and the face are the engine's
        // *judgement*, and re-deriving those here is how two implementations
        // of one rule start disagreeing. They stay as the engine left them
        // until the engine speaks again, which is the refresh below.
        env.counts = Dictionary(grouping: env.worktrees, by: \.status)
            .mapValues(\.count)
        // And drop the tag this action just answered, rather than leaving it
        // asserting a number that is now zero. Subtracting a fact the action
        // resolved is not re-running the rule that produced it.
        let answered = plan?.action.kind == .reap ? "finished" : "reclaim"
        env.insights.removeAll { $0.id == answered }
        envelope = env
        if plan?.action.kind == .reap { for p in touched { lastSizes[p] = nil } }
        engine.noteReclaim(disk?.reclaim ?? 0)
        return true
    }

    static func decodePlanForSnapshot(_ text: String) -> PlanResult? { decodePlan(text) }

    private static func decodePlan(_ text: String) -> PlanResult? {
        // The engine emits one JSON line. Parse that line independently of
        // stderr; a warning mentioning {braces} must not hide a partial result.
        for line in text.split(separator: "\n") {
            if let result = try? JSONDecoder().decode(PlanResult.self, from: Data(line.utf8)) {
                return result
            }
        }
        return nil
    }

    func reveal(_ w: Worktree) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: w.path)
    }

    func openInTerminal(_ w: Worktree) {
        NSWorkspace.shared.open([URL(fileURLWithPath: w.path)],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    func openPR(_ w: Worktree) {
        guard let url = w.pr?.url, let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}

// MARK: - formatting

extension Store {
    static func date(_ epoch: Int) -> String {
        guard epoch > 0 else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    static func ago(_ days: Int) -> String {
        switch days {
        case 9999...: return "no commits yet"       // the engine's "no last commit"
        case ..<1:   return "today"
        case 1:      return "yesterday"
        case ..<31:  return "\(days) days ago"
        case ..<365: return "\(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
        default:     return "over a year ago"
        }
    }

    /// ISO8601 from the forge, as something a person reads.
    static func stamp(_ iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        guard let d = parser.date(from: iso) else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }
}
