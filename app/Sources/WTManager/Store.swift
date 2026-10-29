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
    /// The last folder verdict that saw each folder's local files.
    private var lastFolders: [String: FolderInfo] = [:]
    /// New worktrees already sent for a one-off measure, so one that cannot
    /// be measured is not asked about again on every refresh.
    private var measureAttempted: Set<String> = []
    @Published var plan: Plan?
    @Published var completion: Plan?
    @Published private(set) var scanProgress: Engine.Progress?
    @Published var history = CleanupHistory()
    @Published var celebration: UUID?
    @Published var prLifecycle = PRLifecycle()
    @AppStorage("wtmanager.mergeNudges") var mergeNudges = true
    private let prLifecycleKey = "wtmanager.prLifecycle.v1"
    func savePRLifecycle() {
        if let data = try? JSONEncoder().encode(prLifecycle) { UserDefaults.standard.set(data, forKey: prLifecycleKey) }
    }
    func dismissMerge(_ id: String) { prLifecycle.dismiss(id); savePRLifecycle() }
    let updates = UpdateChecker()
    @AppStorage("wtmanager.automaticUpdates") var automaticUpdates = false
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
    @AppStorage("wtmanager.mascotWanders") var mascotWanders = false

    @AppStorage("wtmanager.skin") var skin: String = "acorn"
    /// Which character, or `Store.ownFigure` for a picture the person chose.
    @AppStorage("wtmanager.figure") var figure: String = "cat"
    @AppStorage("wtmanager.theme") var theme: String = "system"     // system | light | dark
    /// Free text, applied to the rows. Kept out of the engine on purpose:
    /// filtering is a question about what you want to look at, not about what
    /// is true, and the counts and the mood must not move when you narrow it.
    @Published var query: String = ""
    /// A worktree another page asked the list to show: it opens expanded and
    /// scrolled into view, and is cleared once it has been.
    @Published var focusPath: String?
    @Published var showingSettings = false
    /// Bumped to move focus into the filter field. A counter rather than a Bool
    /// because focusing twice in a row is a real request, and a Bool that is
    /// already true is silently ignored.
    @Published private(set) var focusFilter = 0

    /// ⌘F. The filter lives on the folder list, so asking for it there.
    func focusTheFilter() { page = .folders; focusFilter += 1 }

    enum Page { case folders, mascots }
    @Published var page: Page = .folders
    /// The sidebar's filters: one verdict (`safe`, `busy`, `unsaved`, `kept`)
    /// and one location, each nil for all.
    @Published var verdictFilter: String?
    @Published var locationFilter: String?

    /// Every worktree folder the engine judged, main checkouts excluded.
    var folderRows: [Worktree] { (envelope?.worktrees ?? []).filter { $0.folder != nil } }

    static let elsewhere = "Elsewhere"

    /// Where a folder sits, as the list groups it: its parent, home as `~`,
    /// or "Elsewhere" for a folder alone in its parent, so a long tail of
    /// one-folder places does not bury the full ones.
    func location(of w: Worktree) -> String {
        let parent = Self.parent(w)
        return folderRows.filter { Self.parent($0) == parent }.count > 1 ? parent : Self.elsewhere
    }

    static func parent(_ w: Worktree) -> String {
        let home = NSHomeDirectory()
        let p = (w.path as NSString).deletingLastPathComponent
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// The places folders live, fullest first, "Elsewhere" last.
    var locations: [(id: String, count: Int)] {
        var counts: [String: Int] = [:]
        let byParent = Dictionary(grouping: folderRows, by: Self.parent)
        for (parent, ws) in byParent { counts[ws.count > 1 ? parent : Self.elsewhere, default: 0] += ws.count }
        return counts.map { (id: $0.key, count: $0.value) }
            .sorted { a, b in
                if (a.id == Self.elsewhere) != (b.id == Self.elsewhere) { return b.id == Self.elsewhere }
                return a.count != b.count ? a.count > b.count : a.id < b.id
            }
    }

    /// A location's short name: its folder, with as much of the way to it as
    /// it takes to tell it apart from another of the same name.
    func locationLabel(_ id: String) -> String {
        guard id != Self.elsewhere else { return id }
        let parts = id.split(separator: "/").map(String.init)
        let others = locations.map(\.id).filter { $0 != id && $0 != Self.elsewhere }
            .map { $0.split(separator: "/").map(String.init) }
        var n = 1
        while n < parts.count, others.contains(where: { Array($0.suffix(n)) == Array(parts.suffix(n)) }) { n += 1 }
        return parts.suffix(n).joined(separator: "/")
    }

    /// Folders that held worktrees and are empty now, as the last scan saw
    /// them, less any removed since.
    var emptyLocations: [String] { envelope?.emptyLocations ?? [] }

    /// Remove empty folders. Nothing can be lost: each is checked again here,
    /// and one with anything but Finder's `.DS_Store` in it is left alone.
    func removeEmptyLocations(_ paths: [String]) {
        let fm = FileManager.default
        var gone: Set<String> = []
        for p in paths {
            guard let inside = try? fm.contentsOfDirectory(atPath: p),
                  inside.allSatisfy({ $0 == ".DS_Store" }) else { continue }
            if inside.contains(".DS_Store") { try? fm.removeItem(atPath: p + "/.DS_Store") }
            // rmdir, not removeItem: it refuses a folder that is not empty,
            // so a file arriving between the check and here is never lost.
            if rmdir(p) == 0 { gone.insert(p) }
        }
        envelope?.emptyLocations.removeAll { gone.contains($0) }
    }

    /// Search and location: what a verdict count in the sidebar counts over.
    func inScope(_ w: Worktree) -> Bool {
        passes(w) && (locationFilter == nil || location(of: w) == locationFilter)
    }

    let mascot: Mascot?
    private let engine = Engine()
    private var timers: [Timer] = []

    init(mascot: Mascot?) {
        self.mascot = mascot
        if let data = UserDefaults.standard.data(forKey: prLifecycleKey),
           let saved = try? JSONDecoder().decode(PRLifecycle.self, from: data) { prLifecycle = saved }
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
    /// A cleanup just landed: the character wears the proud face for a few
    /// seconds, in the window, the menu bar and on the desktop alike.
    @Published private(set) var cheer: Face?
    var face: Face? { cheer ?? envelope?.face }

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

    func refresh(measureDisk: Bool, measure paths: [String] = [], then next: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        phase = measureDisk || !paths.isEmpty ? "measuring disk" : "reading repos"
        scanProgress = nil
        engine.refresh(measureDisk: measureDisk, measure: paths, progress: { [weak self] p in
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
                    self.lastFolders = Dictionary(env.worktrees.compactMap { w in
                        w.folder?.checked == true ? (w.path, w.folder!) : nil }, uniquingKeysWith: { a, _ in a })
                } else {
                    // A partial pass measured a few new worktrees; keep theirs
                    // and carry every other size, which it left unmeasured.
                    let fresh = Set(env.measuredPaths ?? [])
                    for i in env.worktrees.indices {
                        let w = env.worktrees[i]
                        if fresh.contains(w.path), w.sizeKb >= 0 {
                            self.lastSizes[w.path] = (w.sizeKb, max(w.reclaimKb, 0))
                        } else if let s = self.lastSizes[w.path] {
                            env.worktrees[i].sizeKb = s.size
                            env.worktrees[i].reclaimKb = s.reclaim
                        }
                        if w.folder?.checked == true {
                            self.lastFolders[w.path] = w.folder
                        } else {
                            env.worktrees[i].folder = FolderInfo.carried(w.folder, over: self.lastFolders[w.path])
                        }
                    }
                }
                self.prLifecycle.observe(env.worktrees, complete: env.notices.isEmpty)
                self.savePRLifecycle()
                self.envelope = env
                self.error = nil
                self.countedAt = Date()
            case .failure(let e):
                self.error = e.localizedDescription
            }
            next?()
            if let d = self.pendingDisk {
                self.pendingDisk = nil
                self.refresh(measureDisk: d)
            } else if !self.lastSizes.isEmpty, let env = self.envelope {
                // A worktree that appeared since the last full measure: size it
                // now, so the balloon grows when it lands, not at the hour.
                let unseen = env.worktrees.map(\.path)
                    .filter { self.lastSizes[$0] == nil && !self.measureAttempted.contains($0) }
                if !unseen.isEmpty {
                    self.measureAttempted.formUnion(unseen)
                    self.refresh(measureDisk: false, measure: unseen)
                }
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
    func image(height: CGFloat, frame: Int = 0, blinking: Bool = false, glancing: Bool = false,
               detailed: Bool = false,
               showSignal: Bool = true, walking: Bool = false, facesLeft: Bool = false) -> NSImage? {
        if usingOwnImage {
            // Custom pictures get the same status badge as every character.
            // Before the first envelope, the badge says the scan is working.
            guard let image = OwnFace.image(fitting: height, tint: nil) else { return nil }
            guard showSignal else { return image }
            return MascotSignal.adding(to: image, mood: face?.mood ?? "working", tint: face?.tint,
                                       facesLeft: facesLeft)
        }
        return mascot?.image(figure: figure,
                             gauge: face?.gauge ?? 0,
                             eyes: blinking ? "shut" : glancing ? "glance" : (face?.eyes ?? "shut"),
                             frame: frame,
                             skin: skin,
                             tint: face?.tint ?? "#8b93a1",
                             fitting: height, mood: face?.mood ?? "working", detailed: detailed,
                             showSignal: showSignal, walking: walking, facesLeft: facesLeft)
    }

    /// The next coat along, wrapping.
    ///
    /// Bound to clicking the character rather than buried in a menu: a
    /// mascot that does something when you poke it is the one control in
    /// this window anybody discovers without being told, and a coat is the
    /// safest thing a stray click can change — it means nothing, it is
    /// visible immediately, and one more click undoes it.
    func nextCharacter() {
        guard let figures = mascot?.figures, !figures.isEmpty else { return }
        let next = figures.firstIndex(where: { $0.id == figure }).map { ($0 + 1) % figures.count } ?? 0
        figure = figures[next].id
    }

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

    /// Land on one folder: every filter off, so it is on the page, opened and
    /// scrolled into view.
    func show(_ w: Worktree) {
        query = ""
        verdictFilter = nil
        locationFilter = nil
        page = .folders
        focusPath = w.path
    }

    var filtering: Bool { !query.isEmpty || verdictFilter != nil || locationFilter != nil }

    /// The search field: one rule for the page and the status bar's "N shown".
    func passes(_ w: Worktree) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return w.repo.lowercased().contains(q)
            || (w.branch ?? "").lowercased().contains(q)
            || URL(fileURLWithPath: w.path).lastPathComponent.lowercased().contains(q)
    }

    /// "1 commit", "2 commits": a count, where the sentence supplies the verb.
    static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    /// A size, with the unit spelled far enough to be a unit. `348M` sitting in
    /// a row of plain counts — 3 needing you, 17 forgotten, 56 commits only
    /// here — reads as "348 million", which is what that column shape usually
    /// means. `MB` cannot be read as anything else, and costs one character.
    /// Kept in step with `human()` in the engine, which formats the same
    /// numbers for the table.
    static func human(_ kb: Int) -> String { DiskSize.human(kb) }
}

// MARK: - reclaim

extension Store {
    /// What cleaning up could free — the header line and the balloon's number,
    /// from one calculation.
    var freeable: DiskBalloon.Freeable? { DiskBalloon.freeable(envelope?.worktrees ?? []) }

    /// Every checkout with rebuildable output, main checkouts included: most
    /// of the caches live in the repos themselves, which no delete reaches.
    var cacheCandidates: [Worktree] { (envelope?.worktrees ?? []).filter { $0.reclaimKb > 0 } }
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
        /// For merged PRs held back only by uncommitted edits: save the
        /// edits, then remove. A different plan from a plain removal, and the
        /// engine refuses it for anything else.
        var discardChanges = false
        /// Worktrees as folders: also removes unfinished ones whose commits
        /// are all on a remote, since the branch outlives the folder.
        var folders = false
        /// You are done with the work in these folders: delete them even with
        /// unsaved work, which the engine saves or names first.
        var discardWork = false
        var id: String { "\(kind.rawValue)/\(paths.joined(separator: ","))/\(staleOnly)/\(discardChanges)/\(folders)/\(discardWork)" }

        var single: Bool { paths.count == 1 }

        var title: String {
            if discardWork {
                return single ? "Delete this folder, unsaved work included"
                              : "Delete \(paths.count) folders, unsaved work included"
            }
            if folders {
                return single ? "Delete this folder" : "Delete \(paths.count) folders"
            }
            if discardChanges {
                return single ? "Save changes and remove this worktree"
                              : "Save changes and remove merged worktrees"
            }
            switch (kind, single, staleOnly) {
            case (.reap, true, _):      return "Review removal of this worktree"
            case (.reap, false, _):     return "Review worktree removal"
            case (.clean, true, _):     return "Reclaim this worktree's build output"
            case (.clean, false, true): return "Reclaim build output from idle folders"
            case (.clean, false, false):return "Reclaim build output everywhere"
            }
        }

        var blurb: String {
            if discardWork {
                return "You are done with this work, so it goes, but not without a copy. Edits are saved as a patch, commits stay on their branch or are saved as a bundle when they are on none, and only unrecognised files too large to set aside are deleted outright."
            }
            if folders {
                return "Each folder is deleted through git, which keeps its branch. Nothing that exists only on this Mac goes: .env files and keys are set aside, and a merged PR's stray edits are saved first."
            }
            if discardChanges {
                return "For pull requests that merged with every commit inside them. Uncommitted edits are saved as a patch and untracked files copied and verified, then the worktree is removed."
            }
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
            if kind == .reap && discardChanges { a += ["--discard-changes"] }
            if kind == .reap && folders { a += ["--folders"] }
            if kind == .reap && discardWork { a += ["--discard-work"] }
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
            if kind == .reap && discardChanges { a += ["--discard-changes"] }
            if kind == .reap && folders { a += ["--folders"] }
            if kind == .reap && discardWork { a += ["--discard-work"] }
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
        /// Uncommitted edits each removal saves, then discards.
        var changes: [String: [String]] = [:]
        var changesKeptIn: String = ""
        /// Commits on no remote, and where each set ends up.
        var commits: [String: String] = [:]
        /// Unrecognised files too large to set aside, deleted with the folder.
        var droppedUnknown: [String: [String]] = [:]
        var done: Bool = false
        var removed: Int = 0
        var completedPaths: [String] = []
        var freedKb: Int = 0
        var failed: Int = 0
        var rc: Int = 0
        enum CodingKeys: String, CodingKey {
            case kind, text, paths, plan, count, kb, skipped, precious, unknown, entries, changes, commits
            case done, removed, failed, rc
            case changesKeptIn = "changes_kept_in"
            case droppedUnknown = "dropped_unknown"
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
            changes = try c.decodeIfPresent([String: [String]].self, forKey: .changes) ?? [:]
            changesKeptIn = try c.decodeIfPresent(String.self, forKey: .changesKeptIn) ?? ""
            commits = try c.decodeIfPresent([String: String].self, forKey: .commits) ?? [:]
            droppedUnknown = try c.decodeIfPresent([String: [String]].self, forKey: .droppedUnknown) ?? [:]
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
                        let cheer = r.freedKb > 0 ? Face.cheer(freedKb: r.freedKb) : nil
                        self.cheer = cheer
                        let rewardID = p.id
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 2_800_000_000)
                            if self?.celebration == rewardID { self?.celebration = nil }
                            try? await Task.sleep(nanoseconds: 5_200_000_000)
                            if let cheer, self?.cheer?.meaning == cheer.meaning { self?.cheer = nil }
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
            // What failed may have lost some of its files on the way, so its
            // size is measured again, alone; everything else is known.
            let failed = Set(preview.paths).subtracting(p.result?.completedPaths ?? [])
            if absorbed, !failed.isEmpty, !self.busy {
                self.refresh(measureDisk: false, measure: Array(failed))
            } else {
                self.refreshWhenIdle(measureDisk: !absorbed)
            }
        }
    }

    /// Apply an outcome the engine has already measured, rather than asking
    /// for the whole machine to be walked again.
    ///
    /// A partial run too. The engine names every path it completed, and its
    /// freed figure counts only those, so what went can be taken off the page
    /// at once. Waiting for a full re-measure instead left deleted folders on
    /// screen for minutes, as if the delete had not happened. The paths that
    /// failed are measured again on their own, in `commit`.
    @discardableResult
    private func absorb(_ r: PlanResult, from preview: PlanResult) -> Bool {
        guard r.done, !r.completedPaths.isEmpty || r.failed == 0, var env = envelope else { return false }
        let touched = Set(r.completedPaths)
        switch plan?.action.kind {
        case .reap:
            // The rebuildable total only ever counted these worktrees' caches,
            // so that is all it loses. Subtracting everything freed took the
            // whole worktrees out of it: 36 GB removed turned 68 GB of caches
            // into "32 GB rebuildable" when 57 GB were still there, and the
            // engine carried the wrong figure forward until the hourly measure.
            let removedCaches = env.worktrees.filter { touched.contains($0.path) }
                .reduce(0) { $0 + max($1.reclaimKb, 0) }
            env.worktrees.removeAll { touched.contains($0.path) }
            let freed = r.freedKb
            disk = disk.map { (total: max($0.total - freed, 0), reclaim: max($0.reclaim - removedCaches, 0)) }
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
        let answered = plan?.action.kind == .reap ? "folders" : "reclaim"
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
        guard let url = w.linkedPR?.url, let u = URL(string: url), u.scheme == "https", u.host != nil else { return }
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
