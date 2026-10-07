import AppKit
import SwiftUI
import WTManagerKit

/// wt-manager — an ambient reading of what you are in the middle of.
///
/// Two surfaces over one store: a window, and a menu bar item. The menu bar
/// item cannot be dismissed, so there is always a way back to a window you
/// closed.
///
/// There was a third — a floating Wity you could drag anywhere. It was the
/// menu bar item exactly: same character, same count, same click, same
/// right-click menu, and on top of that a saved position, a drag-versus-click
/// distance tracker and a `canBecomeKey` override to make a borderless panel
/// behave. A second copy of one control is not a second way to reach it, it
/// is a second thing to keep in agreement.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var store: Store!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var observer: NSObjectProtocol?
    private var announced = false
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ note: Notification) {
        Self.capLog()
        let mascot = Self.loadMascot()
        NSLog("wt-manager: launching, mascot=\(mascot == nil ? "MISSING" : "loaded")")
        store = Store(mascot: mascot)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        // Redrawing the status item is the one thing SwiftUI does not do for us.
        observer = NotificationCenter.default.addObserver(
            forName: Pulse.tickNote, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.drawStatusItem() }
            }

        installKeyboardShortcuts()
        store.start()
        drawStatusItem()
        openWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.prepareToQuit() ? .terminateNow : .terminateCancel
    }

    /// An accessory app has no menu bar to hang key equivalents on, so the
    /// shortcuts are matched here — and only while our own window has focus, or
    /// they would fire over whatever the person is actually typing in.
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow,
                  event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": self.store.quit(); return nil
            case "r": self.store.refresh(measureDisk: true); return nil
            case "f": self.store.focusTheFilter(); return nil
            case ",": self.store.showingSettings = true; return nil
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let i = Int(event.charactersIgnoringModifiers ?? "1")! - 1
                let order = self.store.sectionOrder
                if i < order.count { self.store.section = order[i] }
                return nil
            default: return event
            }
        }
    }

    static func loadMascotForSnapshot() -> Mascot? { loadMascot() }

    /// launchd appends every launch's output to one file and never rotates
    /// it. Keep the tail. launchd opened the file with O_APPEND, so writes after
    /// the truncate land at the new end rather than at a stale offset.
    static func capLog(limit: UInt64 = 512 * 1024, keep: Int = 128 * 1024) {
        let path = NSString(string: "~/Library/Logs/wt-manager.log").expandingTildeInPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64, size > limit,
              let fh = FileHandle(forUpdatingAtPath: path) else { return }
        defer { try? fh.close() }
        guard let _ = try? fh.seek(toOffset: size - UInt64(keep)),
              let tail = try? fh.readToEnd() else { return }
        // Start on a whole line.
        let cut = tail.firstIndex(of: 0x0a).map { tail.index(after: $0) } ?? tail.startIndex
        try? fh.truncate(atOffset: 0)
        try? fh.seek(toOffset: 0)
        try? fh.write(contentsOf: tail[cut...])
        NSLog("wt-manager: log capped from \(size) bytes")
    }

    private static func loadMascot() -> Mascot? {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "json"),
           let m = Mascot.load(url) { return m }
        NSLog("wt-manager: mascot.json not found in bundle, trying the checkout")
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/mascot.json")
        return Mascot.load(dev)
    }

    // MARK: - menu bar

    /// What the status item last drew. The clock ticks at 0.22s so the blink
    /// has somewhere to happen, but the *picture* only changes on one tick in
    /// three (the wag) and two in twenty-seven (the blink) — rasterising the
    /// same 22x23 sprite the other three times a second is work nobody sees.
    private var drawn: String?

    private func drawStatusItem() {
        guard let button = statusItem.button else { return }
        let n = store.attention
        let wag = Pulse.shared.wag, blinking = Pulse.shared.blinking
        let key = "\(store.face?.gauge ?? -1)/\(blinking ? "shut" : store.face?.eyes ?? "")"
            + "/\(wag)/\(store.skin)/\(store.figure)/\(store.face?.tint ?? "")/\(n)"
        if key == drawn { return }
        drawn = key
        if let image = store.image(height: NSStatusBar.system.thickness,
                                   frame: wag, blinking: blinking) {
            image.isTemplate = false
            button.image = image
            button.title = n > 0 ? " \(n)" : ""
            if !announced {
                announced = true
                NSLog("wt-manager: status item drawn, image \(Int(image.size.width))x\(Int(image.size.height))pt")
            }
        } else {
            // Never leave the button with neither an image nor a title: it then
            // has zero width and is simply not there, which from outside looks
            // exactly like the app having failed to start.
            button.image = nil
            button.title = n > 0 ? "wt-manager \(n)" : "wt-manager"
        }
        button.toolTip = store.error ?? store.face?.meaning
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Open window", #selector(openWindow), key: "o"))
        menu.addItem(.separator())
        if let f = store.face {
            let m = NSMenuItem(title: f.meaning, action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        }
        if store.attention > 0 {
            let m = NSMenuItem(title: "\(store.attention) need you", action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.addItem(item("Refresh now", #selector(refresh), key: "r"))
        menu.addItem(item("Watched folders…", #selector(watchedFolders), key: ","))
        menu.addItem(item("Check for updates…", #selector(checkUpdates), key: ""))
        let updateState = NSMenuItem(title: store.updates.status, action: nil, keyEquivalent: "")
        updateState.isEnabled = false
        menu.addItem(updateState)
        if let url = store.updates.availableURL {
            let release = NSMenuItem(title: "Open update instructions…", action: #selector(openUpdate), keyEquivalent: "")
            release.representedObject = url; release.target = self; menu.addItem(release)
        }
        menu.addItem(.separator())
        let quitItem = item("Quit wt-manager", #selector(quitApp), key: "q")
        quitItem.isEnabled = store.plan?.stage != .committing
        menu.addItem(quitItem)
    }

    @objc private func quitApp() { store.quit() }
    @objc private func checkUpdates() { store.updates.check(manual: true) }
    @objc private func openUpdate() { if let url = store.updates.availableURL { NSWorkspace.shared.open(url) } }

    private func item(_ title: String, _ action: Selector, key: String,
                      target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        return i
    }

    // MARK: - window

    // MARK: sizing
    //
    // The rule: never wider than half the screen, never taller than the screen,
    // and no taller than the content needs. Expressed against the screen the
    // window is on, not as constants, because an external display changes
    // every number. Measured before this existed: the window opened at 980pt
    // (57% of a 1728pt screen), its minimum was 860 (50%, so nothing to
    // spare), and its height ratcheted 660 -> 2215 across restarts - a
    // resize request to 600 tall was ignored outright, because the hosting
    // view's intrinsic height was a required constraint. Once the window is
    // taller than the screen its bottom edge and resize grip are unreachable,
    // and a window the person cannot recover is a bug however it got there.

    struct Limits {
        let min: NSSize
        let max: NSSize
        let ideal: NSSize
    }

    static func limits(for screen: NSScreen?, contentNeeds: CGFloat) -> Limits {
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 850)
        let margin: CGFloat = 48
        // Half the screen for the *content*, plus the sidebar on top of it.
        // The sidebar is chrome — a fixed 177pt of navigation that never holds
        // any of the data — so charging the worktree table for it made the
        // table narrower than half the screen, which is not what "half the
        // screen" was meant to promise.
        let maxW = floor(vf.width / 2) + Sidebar.railWidth
        let maxH = max(480, floor(vf.height - margin))
        let minW: CGFloat = 640
        let minH: CGFloat = 480
        // A ceiling is not a default: comfortably under it, so there is room
        // to drag either way.
        let idealW = Swift.min(Swift.max(minW, 780), maxW)
        let idealH = Swift.min(Swift.max(minH, ceil(contentNeeds)), maxH)
        return Limits(min: NSSize(width: minW, height: minH),
                      max: NSSize(width: maxW, height: maxH),
                      ideal: NSSize(width: idealW, height: idealH))
    }

    /// Whether a person can still grab this frame: enough of its title bar is
    /// on some screen. Lying wholly inside one screen is the wrong test. A
    /// window on its way to a second display straddles both, and one parked
    /// half off an edge was put there on purpose. The frames this exists to
    /// catch - 961pt below the screen - have no title bar on any screen at all.
    private static func reachable(_ frame: NSRect) -> Bool {
        let bar = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        return NSScreen.screens.contains {
            let i = $0.visibleFrame.intersection(bar)
            return !i.isNull && i.width >= 80
        }
    }

    /// Apply the limits of the screen the window is on. A frame too big for it
    /// shrinks in place, top edge kept; only a frame nobody can reach is moved,
    /// back to the middle at the ideal size. A saved frame is honoured whenever
    /// it can be grabbed.
    private func clamp(_ w: NSWindow, contentNeeds: CGFloat) {
        let screen = w.screen ?? NSScreen.main
        let lim = Self.limits(for: screen, contentNeeds: contentNeeds)
        w.contentMinSize = lim.min
        w.contentMaxSize = lim.max
        let vf = screen?.visibleFrame ?? .zero
        let content = w.contentRect(forFrameRect: w.frame)
        let lost = !Self.reachable(w.frame)
        let sized = content.width <= lim.max.width && content.height <= lim.max.height
            && content.width >= lim.min.width && content.height >= lim.min.height
        if sized && !lost { return }
        if lost {
            w.setContentSize(lim.ideal)
            w.center()
        } else {
            let size = NSSize(width: Swift.min(Swift.max(content.width, lim.min.width), lim.max.width),
                              height: Swift.min(Swift.max(content.height, lim.min.height), lim.max.height))
            var f = w.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            f.origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - f.height)
            if vf != .zero {
                f.origin.y = Swift.min(Swift.max(f.origin.y, vf.minY), vf.maxY - f.height)
            }
            w.setFrame(f, display: true)
        }
        NSLog("wt-manager: window frame clamped to \(Int(w.frame.width))x\(Int(w.frame.height)) "
              + "(screen \(Int(vf.width))x\(Int(vf.height)), \(lost ? "recentred" : "kept in place"))")
    }

    /// Waits for the hand to let go before correcting anything.
    ///
    /// `windowDidChangeScreen` fires the moment a dragged window is more on
    /// the other display than on this one, mid-drag. Resizing and centring it
    /// there fought the drag: the window jumped back under the cursor, and
    /// moving it to a second screen did not work at all.
    private var settling: Timer?

    private func clampWhenSettled() {
        settling?.invalidate()
        settling = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] t in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            t.invalidate()
            Task { @MainActor in
                guard let self, let w = self.window else { return }
                self.clamp(w, contentNeeds: w.contentRect(forFrameRect: w.frame).height)
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        store.catchUp()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        clampWhenSettled()
    }

    @objc private func openWindow() {
        if window == nil {
            let lim = Self.limits(for: NSScreen.main, contentNeeds: 0)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: lim.ideal),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                         .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "wt-manager"   // shown in Mission Control and the window list
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            // Required for the translucent surfaces: a visual effect view
            // sampling what is behind the window needs the window itself to
            // stop painting over it first.
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false          // reopened, not rebuilt
            w.delegate = self

            // One material for the whole window, underneath everything.
            //
            // Letting SwiftUI put a background on each pane is what made this
            // look like two windows taped together: NavigationSplitView gives
            // its sidebar and its detail separate materials, and a transparent
            // window lets each one round its own corners. A single effect view
            // as the window's content, with every SwiftUI layer clear on top of
            // it, is one continuous surface by construction.
            let backdrop = NSVisualEffectView()
            backdrop.material = .underWindowBackground
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            let host = NSHostingView(rootView: RootView(store: store))
            // Constraints rather than a frame copied from `backdrop.bounds`:
            // the backdrop has no size until it becomes the content view, so
            // copying its bounds here pins the content at the wrong size and
            // autoresizing then scales the mistake. That is what clipped the
            // sidebar on the left and the counts on the right.
            host.translatesAutoresizingMaskIntoConstraints = false
            // The host must never size the window. Its default sizing options
            // report the SwiftUI content's *ideal* size as an intrinsic size,
            // and a ScrollView's ideal height is the height of everything in
            // it - so with the host pinned to the content view, each card that
            // arrived made the window taller. Measured: 717pt at launch, 2041pt
            // three minutes later, on a 1084pt screen, origin at y = -957. The
            // window owns its size; the content scrolls inside whatever it gets.
            host.sizingOptions = []
            // No safe area. A titled window reports its title bar as a top
            // safe-area inset even with `fullSizeContentView`, and SwiftUI
            // honours it — so the header sat 28pt below a title bar that is
            // not drawn, under traffic lights the sidebar was already making
            // room for. Measured before this: 40pt of nothing above Wity.
            // The sidebar's own 24pt spacer is the whole of the clearance the
            // traffic lights need, and it is where the lights actually are.
            backdrop.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
                host.topAnchor.constraint(equalTo: backdrop.topAnchor),
                host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            ])
            w.contentView = backdrop
            if let close = w.standardWindowButton(.closeButton) {
                let f = close.convert(close.bounds, to: nil)
                NSLog("wt-manager: traffic lights occupy y \(Int(w.frame.height - f.maxY))–\(Int(w.frame.height - f.minY)) from the top, x to \(Int(f.maxX))")
            }
            // Measured on both sides of the fix, because the whole diagnosis
            // of "40pt of nothing above Wity" rests on this number being the
            // title bar rather than a padding somebody typed.
            NSLog("wt-manager: safe area top before \(host.safeAreaInsets.top)")
            // 13.3 is where `safeAreaRegions` arrived. Below it the window
            // keeps the phantom inset; the alternative is a negative padding
            // guessed against a title bar height we would not be reading.
            if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
            host.layoutSubtreeIfNeeded()
            NSLog("wt-manager: safe area top after \(host.safeAreaInsets.top)")
            // What the content asks for right now - the header and the first
            // card, before any envelope - is the honest default height. Once
            // data arrives the content scrolls; the window does not follow it.
            host.layoutSubtreeIfNeeded()
            let needs = host.fittingSize.height
            w.setContentSize(Self.limits(for: NSScreen.main, contentNeeds: needs).ideal)
            w.center()
            // Bumped three times: v2 for a frame narrower than the layout; v3
            // for frames saved by a window that had grown itself off screen;
            // v4 for the screen-relative limits, so no earlier frame is
            // restored unclamped.
            w.setFrameAutosaveName("wtmanager.window.v4")
            clamp(w, contentNeeds: needs)
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func toggleWindow() {
        if let w = window, w.isVisible, w.isKeyWindow { w.orderOut(nil) } else { openWindow() }
    }

    /// Closing hides. An agent app has no Dock icon to reopen from, so a window
    /// that truly closed would leave the menu bar as the only way back.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc private func refresh() { store.refresh(measureDisk: true) }
    @objc private func watchedFolders() {
        openWindow()
        store.showingSettings = true
    }
}

// The delegate is main-actor isolated, so the entry point has to be too.
@MainActor
func start() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // .accessory: a status item and floating panels, no Dock icon and no menu
    // bar of its own.
    app.setActivationPolicy(.accessory)
    // NSApplication does not retain its delegate, and nothing else here holds
    // it, so without this it deallocates and takes the store with it.
    objc_setAssociatedObject(app, "wtmanager.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}

/// `wt-manager --snapshot DIR [envelope.json]` renders the window offscreen in
/// both appearances and exits, without a screen, a session or Screen Recording
/// permission. It exists because the palette was once written without ever being
/// seen rendered; this is how it gets seen, by a person or by `make`.
///
/// The envelope is the engine's own `agent` output, so what is rendered is what
/// the engine would have said - a fixture is one saved run of it.
@MainActor
func snapshot(into dir: String, envelopePath: String?, castOnly: Bool = false, feedbackOnly: Bool = false) {
    _ = NSApplication.shared
    let store = Store(mascot: AppDelegate.loadMascotForSnapshot())
    store.history = CleanupHistory()
    let gb = 1024 * 1024
    for (i, total) in [24, 28, 42].enumerated() {
        store.history.measure(roots: ["/demo/projects"], totalKb: total * gb, rebuildableKb: 18 * gb,
                              at: Date().addingTimeInterval(Double(i - 2) * 86400))
    }
    store.history.reward(id: UUID(), done: true, completed: 2, freedKb: 5 * gb)
    if let p = envelopePath, let data = FileManager.default.contents(atPath: p),
       let env = try? JSONDecoder().decode(Envelope.self, from: data) {
        store.load(env)
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    /// Draws a view the way the window would: hosted in an offscreen NSWindow
    /// and rasterised with cacheDisplay. `ImageRenderer` cannot draw the
    /// AppKit-backed views SwiftUI uses on macOS - ScrollView, TextField, Menu
    /// - and paints a placeholder where each would be, which is exactly the
    /// part of the window worth looking at.
    func draw<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to file: String) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        // AppKit's window appearance alone is not propagated into a new
        // offscreen SwiftUI host on every macOS version. Pin the SwiftUI
        // environment too, or both named snapshots can silently be dark.
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        // Two passes of the run loop: SwiftUI lays out on the next turn, and
        // lazy stacks fill on the one after.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
        }
        window.close()
    }

    // The default and the minimum. A layout that only looks right at its
    // comfortable width is not done.
    let lim = AppDelegate.limits(for: NSScreen.main, contentNeeds: 620)
    let sizes = [("", lim.ideal), ("-min", lim.min)]
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        if castOnly {
            draw(CastSheet(store: store).background(Color(nsColor: .windowBackgroundColor)),
                 size: CGSize(width: 760, height: 170), appearance: appearance,
                 to: "\(name)-cast.png")
            continue
        }
        NSApp.appearance = NSAppearance(named: appearance)
        if feedbackOnly {
            draw(CleanupScoreCard(store: store).padding(20).background(Color(nsColor: .windowBackgroundColor)),
                 size: CGSize(width: 500, height: 400), appearance: appearance, to: "\(name)-rewards.png")
            draw(PixelCelebration(previewElapsed: 0.9).background(Color(nsColor: .windowBackgroundColor)),
                 size: CGSize(width: 500, height: 300), appearance: appearance, to: "\(name)-celebration.png")
            store.updates.loadSnapshotRelease(Data(#"{"tag_name":"v0.4.0","html_url":"https://github.com/samiesmilz/wt-manager/releases/tag/v0.4.0","draft":false,"prerelease":false}"#.utf8))
            store.updates.showStatus = true
            draw(UpdateBanner(store: store, updates: store.updates).background(Color(nsColor: .windowBackgroundColor)),
                 size: CGSize(width: 640, height: 100), appearance: appearance, to: "\(name)-update.png")
            continue
        }
        for (suffix, size) in sizes {
            for section in ["overview", "all", "disk", "need", "forgot", "flight", "others", "done", "repos"] {
                store.section = section
                draw(RootView(store: store).background(Color(nsColor: .windowBackgroundColor)),
                     size: size, appearance: appearance, to: "\(name)-\(section)\(suffix).png")
            }
        }
        // The overview is a scroll view, and a window-sized picture shows only
        // its first two cards. Tall enough to show every card once.
        store.section = "overview"
        draw(RootView(store: store).background(Color(nsColor: .windowBackgroundColor)),
             size: CGSize(width: lim.ideal.width, height: 2000), appearance: appearance,
             to: "\(name)-overview-tall.png")
        draw(CleanupScoreCard(store: store).padding(20).background(Color(nsColor: .windowBackgroundColor)),
             size: CGSize(width: 500, height: 400), appearance: appearance, to: "\(name)-rewards.png")
        draw(PixelCelebration(previewElapsed: 0.9).background(Color(nsColor: .windowBackgroundColor)),
             size: CGSize(width: 500, height: 300), appearance: appearance, to: "\(name)-celebration.png")
        draw(SettingsSheet(store: store).background(Color(nsColor: .windowBackgroundColor)),
             size: CGSize(width: 525, height: 610), appearance: appearance,
             to: "\(name)-settings.png")
        // One row open, because the detail is most of what a row is for and
        // the commit subjects in it are the whole point of the risk work.
        if let risky = store.envelope?.worktrees
            .filter({ $0.atRisk > 0 && !$0.soloLog.isEmpty && $0.status != "trunk" })
            .max(by: { $0.atRisk < $1.atRisk }) {
            let section = Store.spec.first { $0.3.contains(risky.status) }?.0 ?? "flight"
            store.section = section
            // Filtered to it, so the open row is the first one rather than
            // the ninth — a snapshot of a scroll view shows the top of it.
            store.query = risky.branch ?? risky.repo
            defer { store.query = "" }
            draw(RootView(store: store, openRow: risky.path)
                    .background(Color(nsColor: .windowBackgroundColor)),
                 size: lim.ideal, appearance: appearance, to: "\(name)-risk.png")
        }

        // The first run, which is the one screen a new person is guaranteed to
        // see and the one nobody who has used the tool ever sees again.
        if let first = firstRunFixture() {
            let blank = Store(mascot: AppDelegate.loadMascotForSnapshot())
            blank.load(first)
            for (suffix, size) in sizes {
                draw(RootView(store: blank).background(Color(nsColor: .windowBackgroundColor)),
                     size: size, appearance: appearance, to: "\(name)-first-run\(suffix).png")
            }
        }

        // The cast, at the two sizes anything draws it: the header's 44pt and
        // the menu bar's 22. A character that reads at one and smudges at the
        // other is not a character this app can ship, and the only way that
        // was ever checked before was by picking each one and looking.
        draw(CastSheet(store: store).background(Color(nsColor: .windowBackgroundColor)),
             size: CGSize(width: 700, height: 150), appearance: appearance,
             to: "\(name)-cast.png")

        // Every stage of the sheet, at the height that stage asks for. The
        // sheet is where the only irreversible decisions in this app get
        // made, so "I have never seen this state rendered" is not acceptable
        // for any of them.
        var failed = Store.samplePlan(.failed)
        failed?.error = "Could not archive .env.local: permission denied. The worktree was kept. Check the backup folder permissions before reviewing again."
        var changed = Store.samplePlan(.changed)
        changed?.result = Store.decodePlanForSnapshot(#"{"kind":"reap","text":"The reviewed set changed. No worktrees were removed. Review the current files again.","paths":[],"plan":"changed","rc":3}"#)
        var partial = Store.samplePlan(.done)
        partial?.result = Store.decodePlanForSnapshot(#"{"kind":"reap","text":"removed web/feat-campaign-cards\nfailed mobile/fix-badge-bob: backup permission denied; checkout kept\n1 removed, 1 failed","paths":[],"plan":"partial","done":true,"removed":1,"failed":1,"rc":1,"freed_kb":1200000,"completed_paths":["/Users/me/worktrees/web/feat-campaign-cards"]}"#)
        var refused = Store.samplePlan()
        refused?.preview = Store.decodePlanForSnapshot(#"{"kind":"reap","text":"Kept in place: local changes","paths":[],"plan":"blocked","skipped":[{"path":"/Users/me/worktrees/web/feat-campaign-cards","repo":"web","name":"feat/campaign-cards","why":"Contains local changes that exist only in this checkout. Commit or preserve that work before removing it.","override":"--force"}]}"#)
        var clean = Store.Plan(action: Store.Action(kind: .clean, paths: ["/Users/me/worktrees/web/feat-campaign-cards"]))
        clean.stage = .done
        clean.result = Store.decodePlanForSnapshot(#"{"kind":"clean","text":"Cleaned build output. The checkout and protected files were kept.","paths":[],"plan":"clean","done":true,"freed_kb":1200000,"completed_paths":["/Users/me/worktrees/web/feat-campaign-cards"]}"#)
        let stages: [(String, Store.Plan?)] = [
            ("sheet", Store.samplePlan()),
            ("sheet-working", Store.samplePlan(.committing, progress: Engine.Progress(
                line: "wt-progress 4 13 4 4 preserving web/feat-campaign-cards: 20 of 168 paths"[...]))),
            ("sheet-safety", Store.samplePlan(.previewing, progress: Engine.Progress(
                line: "wt-progress 4 13 3 3 checking safety of web/feat-campaign-cards"[...]))),
            ("sheet-scanning", Store.samplePlan(.previewing)),
            ("sheet-done", Store.samplePlan(.done)),
            ("sheet-partial", partial), ("sheet-failed", failed), ("sheet-changed", changed),
            ("sheet-refused", refused), ("sheet-clean-done", clean),
        ]
        for (file, plan) in stages {
            guard let plan else { continue }
            store.plan = plan
            draw(PlanSheet(store: store, plan: plan).background(Color(nsColor: .windowBackgroundColor)),
                 size: CGSize(width: 740, height: 680), appearance: appearance, to: "\(name)-\(file).png")
            store.plan = nil
        }
        store.section = "overview"
        for (file, result) in [("completion", Store.samplePlan(.done)), ("completion-partial", partial)] {
            store.completion = result
            draw(RootView(store: store).background(Color(nsColor: .windowBackgroundColor)),
                 size: lim.min, appearance: appearance, to: "\(name)-\(file)-min.png")
        }
        store.completion = nil

    }
    print("snapshots in \(dir)")
}

// Top-level code already runs on the main thread; Swift 6 just needs telling.
MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot-feedback"), i + 1 < args.count {
        snapshot(into: args[i + 1], envelopePath: nil, feedbackOnly: true)
        exit(0)
    }
    if let i = args.firstIndex(of: "--snapshot-cast"), i + 1 < args.count {
        snapshot(into: args[i + 1], envelopePath: nil, castOnly: true)
        exit(0)
    }
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        _ = NSApplication.shared
        snapshot(into: args[i + 1], envelopePath: i + 2 < args.count ? args[i + 2] : nil)
        exit(0)
    }
    start()
}


/// Every figure side by side, for the snapshot.
/// The unconfigured envelope, as the engine emits it, so the first-run screen
/// can be seen without wiping anybody's config to get there.
private func firstRunFixture() -> Envelope? {
    let home = NSHomeDirectory()
    let json = """
    {"counts":{},"reclaim_kb":0,"total_kb":0,"measured_disk":false,
     "notices":[],"insights":[],"worktrees":[],"unconfigured":true,
     "headline":"Tell me where your repos are",
     "config_path":"~/.config/wt-manager/config.json",
     "candidates":[{"root":"\(home)/dev","repos":27},
                   {"root":"\(home)/Developer","repos":4}],
     "face":{"mood":"calm","meaning":"nothing needs you","eyes":"open",
             "tint":"#3fb27f","tint_name":"good","bob":[0,0,1,1],"gauge":0,"mark":""}}
    """
    do { return try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)) }
    catch { print("first-run fixture: \(error)"); return nil }
}

private struct CastSheet: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([CGFloat(44), CGFloat(22)], id: \.self) { size in
                HStack(alignment: .bottom, spacing: 18) {
                    // Shown when there is one, so the state exists in the
                    // snapshot at all: every other way of seeing it involves
                    // a file picker.
                    if OwnFace.exists, let own = OwnFace.image(
                        fitting: size,
                        tint: store.face.flatMap { Ink.color($0.tint) } ?? .systemGreen) {
                        VStack(spacing: 4) {
                            Image(nsImage: own).interpolation(.none)
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(height: size)
                            if size > 30 {
                                Text("Yours").font(.system(size: 10))
                                Text("outline").font(.system(size: 8.5))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    ForEach(store.mascot?.figures ?? []) { f in
                        VStack(spacing: 4) {
                            if let image = store.mascot?.image(
                                figure: f.id, gauge: 2, eyes: "open", frame: 0,
                                skin: ["robot": "graphite", "rooster": "sunrise", "rabbit": "snow"][f.id] ?? store.skin,
                                tint: store.face?.tint ?? "#3fb27f",
                                fitting: size) {
                                Image(nsImage: image).interpolation(.none)
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .frame(height: size)
                            }
                            if size > 30 {
                                Text(f.name).font(.system(size: 10))
                                Text(f.tell).font(.system(size: 8.5))
                                    .foregroundStyle(Palette.muted)
                            }
                        }.frame(width: 110)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
    }
}
