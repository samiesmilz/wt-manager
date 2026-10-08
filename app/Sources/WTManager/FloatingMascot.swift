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
    private let size = NSSize(width: 84, height: 84)

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

    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) } }

    func sync() {
        guard store.floatingMascot else { stopWander(at: nil); panel.orderOut(nil); speech?.orderOut(nil); return }
        if let movingFigure, movingFigure != store.figure { stopWander(at: nil); firstWander = true }
        let pulse = Pulse.shared
        syncWander()
        let frame = walking ? walkFrame : pulse.wag
        let key = "\(store.figure)/\(store.skin)/\(store.face?.gauge ?? 0)/\(store.face?.eyes ?? "shut")/\(store.face?.tint ?? "")/\(store.face?.mood ?? "working")/\(frame)/\(pulse.blinking)/\(walking)/\(facesLeft)"
        if key != drawn {
            drawn = key
            view.image = store.image(height: 69, frame: frame, blinking: pulse.blinking,
                                     detailed: true, showSignal: !walking, walking: walking, facesLeft: facesLeft)
            let roamTip = store.mascotWanders ? " · occasional strolls; click or drag to interrupt" : ""
            view.toolTip = "\(store.face?.meaning ?? "Reading your repos") · click to open wt-manager; drag to move\(roamTip); right-click for more actions"
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        syncSpeech()
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
                let progress = (ProcessInfo.processInfo.systemUptime - start) / 3.6
                self.view.rotation = MascotWander.rootedAngle(progress: progress)
                self.view.needsDisplay = true
                if progress >= 1 {
                    if self.traceMovement { NSLog("wt-manager wander: rooted recovery at %@", NSStringFromPoint(self.panel.frame.origin)) }
                    self.walking = false
                    self.rootedStartedAt = nil
                    self.view.rotation = 0
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
                    elapsed: ProcessInfo.processInfo.systemUptime - self.legStartedAt)
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
        let interval = MascotWander.poseInterval
        let delay = rootedStartedAt != nil ? 0.06
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
        view.rotation = 0
        view.needsDisplay = true
        returningHome = false
        legsLeft = 0
        drawn = nil
    }

    private func interruptForUser(globalPoint: NSPoint, localPoint: NSPoint) {
        userInteracting = true
        let origin = NSPoint(x: globalPoint.x-localPoint.x, y: globalPoint.y-localPoint.y)
        stopWander(at: origin)
    }
}

@MainActor
private final class FloatingMascotView: NSView {
    var image: NSImage?
    var rotation: Double = 0
    var makeMenu: (() -> NSMenu)?
    var openWindow: (() -> Void)?
    var didMove: (() -> Void)?
    var interactionBegan: ((NSPoint, NSPoint) -> Void)?
    var interactionEnded: (() -> Void)?
    private var pressPoint: NSPoint?
    private var pressOrigin: NSPoint?
    private var moved = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        let rect = NSRect(x: floor((bounds.width - image.size.width) / 2),
                          y: floor((bounds.height - image.size.height) / 2),
                          width: image.size.width, height: image.size.height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if rotation != 0 {
            let pivot = NSPoint(x: rect.midX, y: rect.minY)
            let turn = AffineTransform(rotationByDegrees: CGFloat(-rotation))
            let corners = [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                           NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
                .map { turn.transform(NSPoint(x: $0.x - pivot.x, y: $0.y - pivot.y)) }
            let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
            let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
            let scale = min(1, min((bounds.width - 4) / (maxX - minX), (bounds.height - 4) / (maxY - minY)))
            let x = min(max(pivot.x, 2 - minX * scale), bounds.width - 2 - maxX * scale)
            let y = min(max(pivot.y, 2 - minY * scale), bounds.height - 2 - maxY * scale)
            let transform = NSAffineTransform()
            transform.translateX(by: x, yBy: y)
            transform.rotate(byDegrees: CGFloat(-rotation))
            transform.scale(by: scale)
            transform.translateX(by: -pivot.x, yBy: -pivot.y)
            transform.concat()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        pressPoint = current
        let local = event.locationInWindow
        let origin = NSPoint(x: current.x-local.x, y: current.y-local.y)
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
        if moved { didMove?() } else { openWindow?() }
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
