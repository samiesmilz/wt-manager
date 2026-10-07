import AppKit
import WTManagerKit

/// An optional companion, using the same image and menu as the other surfaces.
/// The window stays nonactivating so moving it never steals keyboard focus.
@MainActor
final class FloatingMascot {
    private let store: Store
    private let panel: NSPanel
    private let view: FloatingMascotView
    private var screenObserver: NSObjectProtocol?
    private var drawn: String?
    private let positionKey = "wtmanager.floatingPosition.v1"
    private let size = NSSize(width: 84, height: 84)

    init(store: Store, menu: @escaping () -> NSMenu) {
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
        view.didMove = { [weak self] in self?.keepReachableAndSave() }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Floating mascot menu")
        view.setAccessibilityHelp("Drag to move. Click for Open window, Show floating mascot, and Quit.")
        restorePosition()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepReachableAndSave() }
            }
    }

    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) } }

    func sync() {
        guard store.floatingMascot else { panel.orderOut(nil); return }
        let pulse = Pulse.shared
        let key = "\(store.figure)/\(store.skin)/\(store.face?.gauge ?? 0)/\(store.face?.eyes ?? "shut")/\(store.face?.tint ?? "")/\(store.face?.mood ?? "working")/\(pulse.wag)/\(pulse.blinking)"
        if key != drawn {
            drawn = key
            view.image = store.image(height: 69, frame: pulse.wag, blinking: pulse.blinking)
            view.toolTip = "\(store.face?.meaning ?? "Reading your repos") · drag to move; click for menu"
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
        restorePosition()
    }

    private func restorePosition() {
        let stored = UserDefaults.standard.array(forKey: positionKey) as? [Double]
        let origin = stored.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        panel.setFrame(FloatingPlacement.frame(origin: origin, size: size,
                       screens: NSScreen.screens.map(\.visibleFrame)), display: true)
    }

    private func keepReachableAndSave() {
        panel.setFrame(FloatingPlacement.frame(origin: panel.frame.origin, size: size,
                       screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        UserDefaults.standard.set([Double(panel.frame.minX), Double(panel.frame.minY)], forKey: positionKey)
    }
}

@MainActor
private final class FloatingMascotView: NSView {
    var image: NSImage?
    var makeMenu: (() -> NSMenu)?
    var didMove: (() -> Void)?
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
        pressPoint = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin
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
        if moved { didMove?() } else { showMenu(event) }
        pressPoint = nil; pressOrigin = nil
    }
    override func rightMouseDown(with event: NSEvent) { showMenu(event) }
    override func accessibilityPerformPress() -> Bool {
        guard let menu = makeMenu?() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        return true
    }
    private func showMenu(_ event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
