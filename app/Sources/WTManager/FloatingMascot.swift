import AppKit
import SwiftUI
import WTManagerKit

/// An optional companion, with a direct window shortcut and a secondary context menu.
/// The window stays nonactivating so moving it never steals keyboard focus.
@MainActor
final class FloatingMascot {
    private let store: Store
    private let panel: NSPanel
    private let view: FloatingMascotView
    private var screenObserver: NSObjectProtocol?
    private var drawn: String?
    private var renderedWalking = false
    private var speech: NSPanel?
    private var spoken: String?
    private var wanderPlanner = MascotWander()
    private var wanderWork: DispatchWorkItem?
    private var gaitWork: DispatchWorkItem?
    private var walking = false
    private var walkFrame = 0
    private var firstWander = true
    private var facesLeft = false
    private var returningHome = false
    private var legsLeft = 0
    private var homeOrigin = NSPoint.zero
    private var rootedStartedAt: TimeInterval?
    private var movingFigure: String?
    private var speechOrigin: NSPoint?
    private var legStartedAt: TimeInterval = 0
    private var legOrigin = NSPoint.zero
    private var legDestination = NSPoint.zero
    private var legGoingHome = false
    private var legDistance: Double = 0
    private var userInteracting = false
    private let traceMovement = ProcessInfo.processInfo.environment["WT_MANAGER_TRACE_WANDER"] == "1"
    private let openWindow: () -> Void
    private let mainWindowIsVisible: () -> Bool
    private let positionKey = "wtmanager.floatingPosition.v1"
    /// Wider and taller than the character, for the balloon it holds. The
    /// character keeps its old 10-point inset from the bottom-left corner, so
    /// a position saved for the 84-point window still puts it on the same spot.
    private let size = NSSize(width: 112, height: 184)

    // The disk balloon. See `DiskBalloon` and `BalloonSwing`.
    private enum Content: Equatable { case none, measuring, unknown, value(Int) }
    private var content: Content = .none
    private var level: DiskBalloon.Level?
    private var swing = BalloonSwing(seed: UInt64(Date().timeIntervalSince1970))
    private var mirrored = false
    private var balloonTimer: Timer?
    private var lastTick: TimeInterval = 0
    private var lastOrigin: NSPoint?
    private var lastSpeed: CGFloat = 0
    private var tag: (text: String, colour: DiskBalloon.Colour, until: TimeInterval)?
    private var inflateUntil: TimeInterval = 0
    private var release: (start: TimeInterval, scene: BalloonScene)?
    private var freeFraction: Double?
    private var freeCheckedAt: TimeInterval = -.infinity
    private var pose = (frame: 0, walking: false, facesLeft: false)

    init(store: Store, openWindow: @escaping () -> Void,
         mainWindowIsVisible: @escaping () -> Bool, menu: @escaping () -> NSMenu) {
        self.openWindow = openWindow
        self.mainWindowIsVisible = mainWindowIsVisible
        self.store = store
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "wt-manager floating mascot"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view = FloatingMascotView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        view.makeMenu = menu
        view.openWindow = openWindow
        view.didMove = { [weak self] in self?.keepReachableAndSave(userInitiated: true) }
        view.interactionBegan = { [weak self] point, local in
            self?.interruptForUser(globalPoint: point, localPoint: local)
        }
        view.interactionEnded = { [weak self] in self?.userInteracting = false }
        view.balloonClicked = { [weak self] in
            self?.store.section = "disk"
            self?.openWindow()
        }
        // Only the character and its balloon catch the mouse; see
        // `updateClickThrough`.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Open wt-manager")
        view.setAccessibilityHelp("Click to open wt-manager. Drag to move. Optional strolls can be interrupted with a click or drag.")
        restorePosition()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopWander(at: nil)
                    self?.keepReachableAndSave(userInitiated: false)
                }
            }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func sync() {
        guard store.floatingMascot else { stopWander(at: nil); panel.orderOut(nil); speech?.orderOut(nil); return }
        if let movingFigure, movingFigure != store.figure { stopWander(at: nil); firstWander = true }
        let pulse = Pulse.shared
        syncWander()
        let frame = walking ? walkFrame : pulse.wag
        // It looks up when the balloon drifts almost over its head.
        let glancing = !walking && view.balloon?.hand != nil && swing.angle < -15 && !reduceMotion
        let key = "\(store.figure)/\(store.skin)/\(store.face?.gauge ?? 0)/\(store.face?.eyes ?? "shut")/\(store.face?.tint ?? "")/\(store.face?.mood ?? "working")/\(frame)/\(pulse.blinking)/\(glancing)/\(walking)/\(facesLeft)"
        if key != drawn {
            drawn = key
            let transition = renderedWalking != walking && !userInteracting
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            // The balloon replaces the status badge here; the menu bar and the
            // window still carry the mood.
            view.setImage(store.image(height: 69, frame: frame, blinking: pulse.blinking, glancing: glancing,
                detailed: true, showSignal: false, walking: walking, facesLeft: facesLeft),
                transitioning: transition)
            renderedWalking = walking
            view.needsDisplay = true
        }
        pose = (frame, walking, facesLeft)
        syncBalloon()
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateClickThrough()
        syncSpeech()
    }

    // MARK: - the disk balloon

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func readContent() -> Content {
        guard let env = store.envelope, !env.unconfigured else { return store.envelope == nil ? .measuring : .none }
        if let kb = DiskBalloon.freeableKb(env.worktrees) { return kb < DiskBalloon.emptyKb ? .none : .value(kb) }
        return store.disk == nil ? .measuring : .unknown
    }

    /// How full the disk holding the user's files is, checked once a minute.
    private func refreshFreeFraction(_ now: TimeInterval) {
        guard now - freeCheckedAt > 60 else { return }
        freeCheckedAt = now
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        if let free = v?.volumeAvailableCapacityForImportantUsage, let total = v?.volumeTotalCapacity, total > 0 {
            freeFraction = Double(free) / Double(total)
        }
    }

    private func syncBalloon() {
        let now = ProcessInfo.processInfo.systemUptime
        refreshFreeFraction(now)
        let next = readContent()
        if next != content {
            switch (content, next) {
            case (.value(let old), .value(let new)):
                if DiskBalloon.crossedStep(from: old, to: new) {
                    let grew = new > old
                    tag = (DiskBalloon.delta(from: old, to: new), grew ? (level?.colour ?? .green) : .green, now + 2.2)
                    if grew { inflateUntil = now + 0.35 }
                }
            case (.value, .none), (.measuring, .none), (.unknown, .none):
                // Nothing left to free: let go, rather than simply vanishing.
                if let scene = scene(now: now), !reduceMotion { release = (now, scene) }
            case (.none, .value):
                swing.settle(); inflateUntil = now + 0.35; release = nil
            default: break
            }
            content = next
        }
        if case .value(let kb) = content {
            level = DiskBalloon.level(gb: Double(kb) / DiskBalloon.gb, freeFraction: freeFraction, previous: level)
            let l = DiskBalloon.label(kb: kb)
            let f = store.freeable
            let parts = f.map { " (\(Store.human($0.finishedKb)) in folders safe to delete, \(Store.human($0.cachesKb)) rebuildable)" } ?? ""
            setToolTip("\(l.number) \(l.unit) you could free\(parts) · click the balloon to see where · click the character to open wt-manager; drag to move; right-click for more")
        } else {
            setToolTip("\(store.face?.meaning ?? "Reading your repos") · click to open wt-manager; drag to move; right-click for more actions")
        }
        // Walking left draws everything mirrored; keep the balloon where it is.
        let shouldMirror = pose.walking && pose.facesLeft
        if shouldMirror != mirrored { swing.mirror(); mirrored = shouldMirror }
        if reduceMotion { swing.settle() }
        setBalloon(scene(now: now))
        let animating = (view.balloon != nil || release != nil) && !reduceMotion && store.floatingMascot
        if animating, balloonTimer == nil {
            lastTick = now
            balloonTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickBalloon() }
            }
        } else if !animating, let t = balloonTimer {
            t.invalidate(); balloonTimer = nil
        }
    }

    /// One step of the swing, driven by the breeze and by how the window moved.
    private func tickBalloon() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0.001, now - lastTick))
        lastTick = now
        let origin = panel.frame.origin
        let speed = lastOrigin.map { (origin.x - $0.x) / CGFloat(dt) } ?? 0
        let accel = (speed - lastSpeed) / CGFloat(dt)
        lastOrigin = origin; lastSpeed = speed
        if case .value = content {
            let limits = swingLimits()
            swing.step(dt: dt, accel: Double(mirrored ? -accel : accel), drift: pose.walking ? -14 : 0,
                       straining: level?.colour == .orange, limits: limits)
        } else if content != .none {
            swing.step(dt: dt, accel: Double(mirrored ? -accel : accel), drift: pose.walking ? -14 : 0,
                       limits: swingLimits())
        }
        if let r = release, now - r.start > 2.6 { release = nil }
        setBalloon(scene(now: now))
        updateClickThrough()
        if view.balloon == nil && release == nil { balloonTimer?.invalidate(); balloonTimer = nil }
    }

    /// Setting a tooltip rebuilds its tracking, so only when the text changes.
    private func setToolTip(_ text: String) { if view.toolTip != text { view.toolTip = text } }

    /// Redraw only when a pixel would change.
    private func setBalloon(_ next: BalloonScene?) {
        let changed = next?.drawnKey != view.balloon?.drawnKey
        view.balloon = next
        if changed { view.needsDisplay = true }
    }

    /// The hand, in view points.
    private func handPoint() -> NSPoint {
        let rect = view.mascotRect
        let p = store.mascot?.hand(figure: store.figure, frame: pose.frame, walking: pose.walking,
                                   facesLeft: pose.facesLeft, imageSize: rect.size)
            ?? NSPoint(x: rect.width - 4, y: rect.height * 0.4)
        return NSPoint(x: rect.minX + p.x, y: rect.minY + p.y)
    }

    private func pixels() -> (w: Int, h: Int) {
        if case .value = content, let level { return level.size.pixels }
        return DiskBalloon.Size.small.pixels
    }

    /// The angles this window has room for, in the swing's own frame.
    private func swingLimits() -> ClosedRange<Double> {
        let hand = handPoint(), L = BalloonPainter.stringLength
        let half = CGFloat(max(pixels().w, pixels().h)) * BalloonPainter.pixel / 2 + 3
        func deg(_ x: CGFloat) -> Double { Double(asin(max(-1, min(1, x)))) * 180 / .pi }
        let right = deg((view.bounds.width - half - hand.x) / L)
        let left = deg((half - hand.x) / L)
        let screen = max(left, BalloonSwing.range.lowerBound)...min(right, BalloonSwing.range.upperBound)
        let r = mirrored ? (-screen.upperBound)...(-screen.lowerBound) : screen
        return r.lowerBound <= r.upperBound ? r : (r.lowerBound...r.lowerBound)
    }

    private func scene(now: TimeInterval) -> BalloonScene? {
        if let r = release {
            // Let go: it drifts up, sways, and fades before the window's edge.
            let t = now - r.start
            var s = r.scene
            s.center.y += CGFloat(36 * t + 14 * t * t)
            s.center.x += CGFloat(6 * sin(t * 2.4))
            s.angle = 6 * sin(t * 3)
            s.hand = nil
            s.tag = nil
            s.alpha = CGFloat(max(0, 1 - t / 2.6))
            return s
        }
        let number: String, unit: String, colour: DiskBalloon.Colour
        switch content {
        case .none: return nil
        case .measuring: (number, unit, colour) = ("…", "", .grey)
        case .unknown: (number, unit, colour) = ("?", "", .grey)
        case .value(let kb):
            let l = DiskBalloon.label(kb: kb)
            (number, unit, colour) = (l.number, l.unit, level?.colour ?? .green)
        }
        var px = pixels()
        if now < inflateUntil { px = (px.w + 2, px.h + 2) }
        let angle = mirrored ? -swing.angle : swing.angle
        let hand = handPoint(), L = BalloonPainter.stringLength, rad = CGFloat(angle * .pi / 180)
        var s = BalloonScene(center: NSPoint(x: hand.x + L * sin(rad), y: hand.y + L * cos(rad)),
                             angle: angle, pixels: px, colour: colour, number: number, unit: unit,
                             hand: hand)
        s.bow = CGFloat(max(-6, min(6, (mirrored ? swing.velocity : -swing.velocity) * 0.12)))
        if let t = tag {
            if now < t.until {
                s.tag = (t.text, t.colour, CGFloat(min(1, (t.until - now) / 0.5)))
            } else { tag = nil }
        }
        return s
    }

    /// Let clicks through everywhere but the character and its balloon.
    ///
    /// Everything else in this window is empty air over whatever is behind
    /// it, and a 112x184 window that swallowed clicks there would be a hole in
    /// the desktop. Polled from the balloon's clock and the pulse rather than
    /// from a mouse-moved monitor: a global monitor has every pointer movement
    /// on the screen delivered to this app, which cost more than the whole
    /// balloon did.
    private func updateClickThrough() {
        guard panel.isVisible else { return }
        let m = NSEvent.mouseLocation, f = panel.frame
        let inside = view.isInteractive(NSPoint(x: m.x - f.minX, y: m.y - f.minY))
            || NSEvent.pressedMouseButtons != 0 && panel.ignoresMouseEvents == false
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    private func syncSpeech() {
        guard store.mergeNudges, !mainWindowIsVisible(), store.plan?.stage != .committing,
              let nudge = store.prLifecycle.pending.first else { speech?.orderOut(nil); return }
        if speech == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "wt-manager merge message"
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            speech = p
        }
        guard let speech else { return }
        let speechKey = "\(nudge.id)/\(nudge.paths)/\(nudge.occupiedKb ?? -1)/\(nudge.blocked)"
        if spoken != speechKey {
            spoken = speechKey
            speechOrigin = nil
            let host = NSHostingView(rootView: MergeSpeechBanner(store: store, nudge: nudge,
                compact: true, onReview: openWindow).background(Color(nsColor: .windowBackgroundColor)))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: speech.frame.size)
            host.autoresizingMask = [.width, .height]
            speech.contentView = host
        }
        // Keep an unread banner still and readable while the mascot explores.
        if speechOrigin == nil { speechOrigin = NSPoint(x: panel.frame.maxX + 8, y: panel.frame.minY) }
        let origin = speechOrigin!
        speech.setFrame(FloatingPlacement.frame(origin: origin, size: speech.frame.size,
                        screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        if !speech.isVisible { speech.orderFrontRegardless() }
    }

    func resetPosition() {
        stopWander(at: nil)
        UserDefaults.standard.removeObject(forKey: positionKey)
        restorePosition()
        sync()
    }

    private func restorePosition() {
        let stored = UserDefaults.standard.array(forKey: positionKey) as? [Double]
        let origin = stored.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        let frame = FloatingPlacement.frame(origin: origin, size: size,
                           screens: NSScreen.screens.map(\.visibleFrame))
        panel.setFrame(frame, display: true)
        homeOrigin = frame.origin
    }

    private func keepReachableAndSave(userInitiated: Bool) {
        let frame = FloatingPlacement.frame(origin: panel.frame.origin, size: size,
                           screens: NSScreen.screens.map(\.visibleFrame))
        panel.setFrame(frame, display: true)
        guard userInitiated else { return }
        homeOrigin = frame.origin
        UserDefaults.standard.set([Double(homeOrigin.x), Double(homeOrigin.y)], forKey: positionKey)
    }

    private var mayWander: Bool {
        return MascotWander.isEnabled(wandering: store.mascotWanders, floating: store.floatingMascot,
            committing: store.plan?.stage == .committing,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            interacting: userInteracting)
    }

    /// The existing clock advances character poses. One delayed action starts
    /// each trip; each planted push advances the window and pose together.
    private func syncWander() {
        guard mayWander else { stopWander(at: nil); return }
        guard !walking, wanderWork == nil else { return }
        let delay = firstWander ? wanderPlanner.firstPause()
            : (returningHome || legsLeft > 0 ? wanderPlanner.pauseAtWaypoint() : wanderPlanner.restAfterTrip())
        scheduleWander(after: delay)
    }

    private func scheduleWander(after delay: TimeInterval) {
        guard mayWander, wanderWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wanderWork = nil
            self.startNextLeg()
        }
        wanderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startNextLeg() {
        guard mayWander else { return }
        movingFigure = store.figure
        if MascotWander.staysRooted(figure: store.figure) {
            facesLeft = false
            if traceMovement { NSLog("wt-manager wander: rooted gesture started at %@", NSStringFromPoint(panel.frame.origin)) }
            firstWander = false
            walking = true
            walkFrame = 0
            rootedStartedAt = ProcessInfo.processInfo.systemUptime
            scheduleGaitFrame()
            return
        }
        if !returningHome && legsLeft == 0 { legsLeft = wanderPlanner.tripLength() }
        firstWander = false
        let current = panel.frame
        let displays = NSScreen.screens.map(\.visibleFrame)
        let goingHome = returningHome
        let destination: CGPoint?
        if goingHome {
            destination = FloatingPlacement.frame(origin: homeOrigin, size: size, screens: displays).origin
        } else {
            destination = wanderPlanner.destination(from: current, size: size, displays: displays)
        }
        guard let destination else {
            legsLeft = 0; returningHome = false
            scheduleWander(after: wanderPlanner.restAfterTrip())
            return
        }
        let target = NSRect(origin: destination, size: size)
        guard hypot(target.minX-current.minX, target.minY-current.minY) > 6 else {
            if goingHome { legsLeft = 0; returningHome = false } else {
                legsLeft -= 1
                if legsLeft == 0 { returningHome = true }
            }
            scheduleWander(after: goingHome || returningHome
                ? wanderPlanner.restAfterTrip() : wanderPlanner.pauseAtWaypoint())
            return
        }
        facesLeft = MascotWander.facesLeft(from: current.origin, to: destination)
        walking = true
        walkFrame = 0
        drawn = nil
        legStartedAt = ProcessInfo.processInfo.systemUptime
        legOrigin = current.origin
        legDestination = destination
        legGoingHome = goingHome
        legDistance = hypot(destination.x-current.minX, destination.y-current.minY)
        if traceMovement { NSLog("wt-manager wander: stroll from %@ to %@", NSStringFromPoint(current.origin), NSStringFromPoint(destination)) }
        sync()
        scheduleGaitFrame()
    }

    private func finishLeg() {
        if traceMovement { NSLog("wt-manager wander: arrived at %@", NSStringFromPoint(panel.frame.origin)) }
        walking = false
        facesLeft = false
        gaitWork = nil
        drawn = nil
        if legGoingHome { legsLeft = 0; returningHome = false }
        else {
            legsLeft -= 1
            if legsLeft == 0 { returningHome = true }
        }
        scheduleWander(after: legGoingHome
            ? wanderPlanner.restAfterTrip() : wanderPlanner.pauseAtWaypoint())
        sync()
    }

    /// One low-frequency clock owns both the pixel pose and window position.
    /// Each alternating pose advances the body. No background travel animation
    /// can carry the body forward while its feet are waiting.
    private func scheduleGaitFrame() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.walking else { return }
            if let start = self.rootedStartedAt {
                if ProcessInfo.processInfo.systemUptime - start >= MascotWander.gustDuration {
                    if self.traceMovement { NSLog("wt-manager wander: rooted recovery at %@", NSStringFromPoint(self.panel.frame.origin)) }
                    self.walking = false
                    self.rootedStartedAt = nil
                    self.gaitWork = nil
                    self.drawn = nil
                    self.scheduleWander(after: self.wanderPlanner.restAfterTrip())
                    return
                }
            }
            self.gaitWork = nil
            if self.rootedStartedAt != nil {
                self.walkFrame = (self.walkFrame + 1) % 8
            } else {
                let sample = MascotWander.stepSample(distance: self.legDistance,
                    elapsed: ProcessInfo.processInfo.systemUptime - self.legStartedAt, figure: self.store.figure)
                self.walkFrame = sample.frame
                let fraction = self.legDistance > 0 ? sample.travelled / self.legDistance : 1
                self.panel.setFrameOrigin(NSPoint(
                    x: self.legOrigin.x + (self.legDestination.x - self.legOrigin.x) * fraction,
                    y: self.legOrigin.y + (self.legDestination.y - self.legOrigin.y) * fraction))
                if sample.finished { self.finishLeg(); return }
            }
            self.sync()
            if self.walking { self.scheduleGaitFrame() }
        }
        gaitWork = work
        let now = ProcessInfo.processInfo.systemUptime
        let interval = MascotWander.poseInterval(figure: store.figure)
        let delay = rootedStartedAt != nil ? MascotWander.gustFrameInterval
            : max(0.001, interval - (now - legStartedAt).truncatingRemainder(dividingBy: interval))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopWander(at origin: NSPoint?) {
        guard walking || wanderWork != nil || returningHome || legsLeft != 0 else { return }
        wanderWork?.cancel()
        wanderWork = nil
        if walking { panel.setFrameOrigin(origin ?? panel.frame.origin) }
        gaitWork?.cancel(); gaitWork = nil
        walking = false
        firstWander = true
        rootedStartedAt = nil
        movingFigure = nil
        view.cancelTransition()
        view.needsDisplay = true
        returningHome = false
        legsLeft = 0
        drawn = nil
    }

    private func interruptForUser(globalPoint: NSPoint, localPoint: NSPoint) {
        userInteracting = true
        let origin = NSPoint(x: globalPoint.x-localPoint.x, y: globalPoint.y-localPoint.y)
        stopWander(at: origin)
        // Being clicked or put somewhere counts as a rest, not a fresh start:
        // the quick first stroll walked off a few seconds after a drag.
        firstWander = false
    }
}

@MainActor
private final class FloatingMascotView: NSView {
    private var image: NSImage?
    private var previousImage: NSImage?
    private var transitionProgress: CGFloat = 1
    private var transitionWork: DispatchWorkItem?

    func setImage(_ next: NSImage?, transitioning: Bool) {
        if transitioning, let image {
            transitionWork?.cancel()
            previousImage = image
            transitionProgress = 0
            advanceTransition()
        }
        image = next
        needsDisplay = true
    }

    func cancelTransition() {
        transitionWork?.cancel(); transitionWork = nil
        previousImage = nil; transitionProgress = 1
    }

    private func advanceTransition() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transitionProgress = min(1, self.transitionProgress + 0.25)
            self.needsDisplay = true
            if self.transitionProgress < 1 { self.advanceTransition() }
            else { self.cancelTransition() }
        }
        transitionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }
    var makeMenu: (() -> NSMenu)?
    var openWindow: (() -> Void)?
    var didMove: (() -> Void)?
    var interactionBegan: ((NSPoint, NSPoint) -> Void)?
    var interactionEnded: (() -> Void)?
    var balloonClicked: (() -> Void)?
    var balloon: BalloonScene?
    private var pressPoint: NSPoint?
    private var pressOrigin: NSPoint?
    private var pressedBalloon = false
    private var moved = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The character's 10-point inset, where it sat in the old 84-point window.
    static let inset = NSPoint(x: 10, y: 10)
    private func rect(for image: NSImage) -> NSRect {
        NSRect(origin: Self.inset, size: image.size)
    }
    var mascotRect: NSRect {
        image.map(rect(for:)) ?? NSRect(origin: Self.inset, size: NSSize(width: 64, height: 64))
    }

    /// Whether this point should take the mouse: the character or its balloon.
    func isInteractive(_ p: NSPoint) -> Bool {
        if mascotRect.insetBy(dx: -2, dy: -2).contains(p) { return true }
        if let b = balloon, b.hand != nil, b.frame.contains(p) { return true }
        return false
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return isInteractive(p) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        // Balloon behind, character over it, string in front of both: the
        // string has to stay visible from the hand to the knot, or a balloon
        // drifting over the head looks like it floats on its own.
        if let b = balloon { BalloonPainter.drawBody(b) }
        if let previousImage {
            previousImage.draw(in: rect(for: previousImage), from: .zero, operation: .sourceOver,
                               fraction: 1-transitionProgress)
        }
        if let image {
            image.draw(in: rect(for: image), from: .zero, operation: .sourceOver, fraction: transitionProgress)
        }
        if let b = balloon {
            let knot = BalloonPainter.knot(b)
            if let hand = b.hand {
                BalloonPainter.drawString(from: knot, to: hand, bow: b.bow, alpha: b.alpha)
            } else {
                // Let go: a short loose end trails from the knot.
                BalloonPainter.drawString(from: knot, to: NSPoint(x: knot.x - 3, y: knot.y - 22),
                                          bow: 4, alpha: b.alpha)
            }
            if let t = b.tag { BalloonPainter.drawTag(t.text, colour: t.colour, alpha: t.alpha, near: b, within: bounds) }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        pressPoint = current
        let local = event.locationInWindow
        let origin = NSPoint(x: current.x-local.x, y: current.y-local.y)
        pressedBalloon = !mascotRect.contains(convert(local, from: nil))
            && balloon.map { $0.frame.contains(convert(local, from: nil)) } == true
        interactionBegan?(current, local)
        pressOrigin = origin
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint, let pressOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - pressPoint.x, dy = current.y - pressPoint.y
        guard moved || hypot(dx, dy) >= 4 else { return }
        moved = true
        window?.setFrameOrigin(NSPoint(x: pressOrigin.x + dx, y: pressOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        if moved { didMove?() } else if pressedBalloon, let balloonClicked { balloonClicked() } else { openWindow?() }
        pressPoint = nil; pressOrigin = nil
        interactionEnded?()
    }
    override func rightMouseDown(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        interactionBegan?(current, event.locationInWindow)
        showMenu(event)
        interactionEnded?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard let openWindow else { return false }
        interactionBegan?(window?.frame.origin ?? .zero, .zero)
        openWindow()
        interactionEnded?()
        return true
    }
    private func showMenu(_ event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

extension FloatingMascot {
    /// The real floating view, offscreen, in each state the balloon can be in:
    /// `--snapshot-balloon DIR`. The balloon is judged on the art it is drawn
    /// with, at the size it is drawn at, on both kinds of desktop.
    static func snapshotBalloons(mascot: Mascot, into dir: String) {
        typealias Case = (figure: String, number: String, unit: String, colour: DiskBalloon.Colour,
                          size: DiskBalloon.Size, angle: Double, walking: Bool, tag: String?)
        let cases: [Case] = [
            ("rex", "…", "", .grey, .small, 6, false, nil),
            ("rex", "860", "MB", .green, .small, 6, false, nil),
            ("rex", "8.5", "GB", .yellow, .medium, -4, false, "+0.6 GB"),
            ("rex", "26", "GB", .orange, .large, 8, false, nil),
            ("rex", "?", "", .grey, .small, -24, false, nil),
            ("rex", "2.1", "GB", .green, .small, -14, true, nil),
            ("robot", "8.5", "GB", .yellow, .medium, 6, false, nil),
            ("pup", "860", "MB", .green, .small, 8, false, nil),
            ("orb", "26", "GB", .orange, .large, 4, false, nil),
            ("cat", "3.2", "GB", .green, .small, 6, false, nil),
            ("crab", "12", "GB", .yellow, .medium, 2, false, nil),
            ("palm", "6", "GB", .orange, .medium, 6, false, nil),
        ]
        let cell = NSSize(width: 112, height: 184), gap: CGFloat = 12
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, bg) in [("light", NSColor(srgbRed: 0.894, green: 0.878, blue: 0.847, alpha: 1)),
                           ("dark", NSColor(srgbRed: 0.122, green: 0.145, blue: 0.192, alpha: 1))] {
            let size = NSSize(width: gap + CGFloat(cases.count) * (cell.width + gap), height: cell.height + 2 * gap)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(origin: .zero, size: size))
            root.wantsLayer = true
            root.layer?.backgroundColor = bg.cgColor
            for (i, c) in cases.enumerated() {
                let v = FloatingMascotView(frame: NSRect(x: gap + CGFloat(i) * (cell.width + gap), y: gap,
                                                         width: cell.width, height: cell.height))
                let coat = Mascot.drawnCoats[c.figure] ?? mascot.defaultSkin
                let image = mascot.image(figure: c.figure, gauge: 0, eyes: "open", frame: 0, skin: coat,
                                         tint: "#3fb27f", fitting: 69, detailed: true, showSignal: false,
                                         walking: c.walking, facesLeft: false)
                v.setImage(image, transitioning: false)
                let r = v.mascotRect
                let p = mascot.hand(figure: c.figure, frame: 0, walking: c.walking, facesLeft: false,
                                    imageSize: r.size) ?? NSPoint(x: r.width - 4, y: r.height * 0.4)
                let hand = NSPoint(x: r.minX + p.x, y: r.minY + p.y)
                let rad = CGFloat(c.angle * .pi / 180), L = BalloonPainter.stringLength
                var s = BalloonScene(center: NSPoint(x: hand.x + L * sin(rad), y: hand.y + L * cos(rad)),
                                     angle: c.angle, pixels: c.size.pixels, colour: c.colour,
                                     number: c.number, unit: c.unit, hand: hand)
                if let t = c.tag { s.tag = (t, c.colour, 1) }
                v.balloon = s
                root.addSubview(v)
            }
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
            root.cacheDisplay(in: root.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-balloon.png"))
            }
            window.close()
        }
        print("snapshots in \(dir)")
    }
}
