import AppKit
import QuartzCore
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
    private var wanderGeneration = 0
    private var walking = false
    private var walkFrame = 0
    private var firstWander = true
    private var facesLeft = false
    private var returningHome = false
    private var legsLeft = 0
    private var homeOrigin = NSPoint.zero
    private let openWindow: () -> Void
    private let positionKey = "wtmanager.floatingPosition.v1"
    private let size = NSSize(width: 84, height: 84)

    init(store: Store, openWindow: @escaping () -> Void, menu: @escaping () -> NSMenu) {
        self.openWindow = openWindow
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
        let pulse = Pulse.shared
        syncWander()
        let frame = walking ? walkFrame : pulse.wag
        let key = "\(store.figure)/\(store.skin)/\(store.face?.gauge ?? 0)/\(store.face?.eyes ?? "shut")/\(store.face?.tint ?? "")/\(store.face?.mood ?? "working")/\(frame)/\(pulse.blinking)/\(walking)/\(facesLeft)"
        if key != drawn {
            drawn = key
            view.image = store.image(height: 69, frame: frame, blinking: pulse.blinking,
                                     detailed: true, walking: walking, facesLeft: facesLeft)
            let roamTip = store.mascotWanders ? " · occasional strolls; click or drag to interrupt" : ""
            view.toolTip = "\(store.face?.meaning ?? "Reading your repos") · click to open wt-manager; drag to move\(roamTip); right-click for more actions"
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        syncSpeech()
    }

    private func syncSpeech() {
        let mainVisible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
        guard store.mergeNudges, !mainVisible, store.plan?.stage != .committing,
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
            let host = NSHostingView(rootView: MergeSpeechBanner(store: store, nudge: nudge,
                compact: true, onReview: openWindow).background(Color(nsColor: .windowBackgroundColor)))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: speech.frame.size)
            host.autoresizingMask = [.width, .height]
            speech.contentView = host
        }
        let origin = NSPoint(x: panel.frame.maxX + 8, y: panel.frame.minY)
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
        guard store.mascotWanders, store.floatingMascot,
              store.prLifecycle.pending.isEmpty, store.plan?.stage != .committing,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        let mainVisible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
        return !mainVisible
    }

    /// The existing clock advances character poses. One delayed action starts
    /// each trip; AppKit animates the window between endpoints without polling.
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
        scheduleGaitFrame()
        drawn = nil
        let generation = wanderGeneration
        let duration = MascotWander.travelTime(from: current.origin, to: destination)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.wanderGeneration == generation, self.walking else { return }
                self.walking = false
                self.gaitWork?.cancel(); self.gaitWork = nil
                self.drawn = nil
                if goingHome { self.legsLeft = 0; self.returningHome = false }
                else {
                    self.legsLeft -= 1
                    if self.legsLeft == 0 { self.returningHome = true }
                }
                self.scheduleWander(after: goingHome
                    ? self.wanderPlanner.restAfterTrip()
                    : self.wanderPlanner.pauseAtWaypoint())
            }
        }
    }

    /// Run the 8-frame pixel gait only during a trip. The shared 220 ms
    /// expression clock is intentionally slower for blinks and idles.
    private func scheduleGaitFrame() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.walking else { return }
            self.walkFrame = (self.walkFrame + 1) % 8
            self.drawn = nil
            self.gaitWork = nil
            self.sync()
            self.scheduleGaitFrame()
        }
        gaitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func stopWander(at origin: NSPoint?) {
        guard walking || wanderWork != nil || returningHome || legsLeft != 0 else { return }
        wanderGeneration &+= 1
        wanderWork?.cancel()
        wanderWork = nil
        if walking { panel.setFrameOrigin(origin ?? panel.frame.origin) }
        gaitWork?.cancel(); gaitWork = nil
        walking = false
        returningHome = false
        legsLeft = 0
        drawn = nil
    }

    private func interruptForUser(globalPoint: NSPoint, localPoint: NSPoint) {
        let origin = NSPoint(x: globalPoint.x-localPoint.x, y: globalPoint.y-localPoint.y)
        stopWander(at: origin)
    }
}

@MainActor
private final class FloatingMascotView: NSView {
    var image: NSImage?
    var makeMenu: (() -> NSMenu)?
    var openWindow: (() -> Void)?
    var didMove: (() -> Void)?
    var interactionBegan: ((NSPoint, NSPoint) -> Void)?
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
    }
    override func rightMouseDown(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        interactionBegan?(current, event.locationInWindow)
        showMenu(event)
    }
    override func accessibilityPerformPress() -> Bool {
        guard let openWindow else { return false }
        interactionBegan?(window?.frame.origin ?? .zero, .zero)
        openWindow()
        return true
    }
    private func showMenu(_ event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
