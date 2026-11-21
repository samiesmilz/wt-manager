import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import WTManagerKit

// MARK: - capture

/// Loads a page from this machine in a web view nobody sees and photographs
/// the whole of it at a chosen width.
///
/// A web view of its own, not a picture of the screen: Screen Recording is a
/// permission tied to the app's signature, this app is signed ad hoc, and so
/// the grant would be asked for again after every rebuild. A view the app
/// owns needs no permission at all, and can be 390 points wide on a display
/// that is not.
@MainActor
final class WebCapture: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var window: NSWindow?
    private var completion: ((Result<NSImage, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var width: CGFloat = 390
    /// Long pages are cut here: a snapshot is one bitmap, and an endless feed
    /// would ask for one the size of the machine's memory.
    static let tallest: CGFloat = 12_000

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func capture(_ url: URL, width: Int, completion: @escaping (Result<NSImage, Error>) -> Void) {
        cancel()
        self.completion = completion
        self.width = CGFloat(width)
        let frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 900)
        // The default store, shared with the sign-in sheet: a page behind a
        // login is captured as whoever signed in there, and never otherwise.
        let web = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        web.navigationDelegate = self
        // In a window, so the page lays out and paints as it would on screen;
        // never ordered in, so it is not on anyone's screen.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        self.web = web
        self.window = window
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(Failure(message: "The page did not finish loading in 25 seconds.")))
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        completion = nil
        web?.navigationDelegate = nil
        web?.stopLoading()
        window?.close()
        web = nil
        window = nil
    }

    private func finish(_ result: Result<NSImage, Error>) {
        let done = completion
        cancel()
        done?(result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A beat for fonts, images and the first client-side render: "loaded"
        // is when the document arrived, not when the page looks like itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.measure() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(Failure(message: error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(Failure(message: error.localizedDescription)))
    }

    private func measure() {
        guard let web else { return }
        let script = "Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)"
        web.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self, let web = self.web else { return }
            let full: CGFloat = CGFloat((value as? NSNumber)?.doubleValue ?? 900)
            let height: CGFloat = min(max(full, 300), Self.tallest)
            let size = NSSize(width: self.width, height: height)
            self.window?.setContentSize(size)
            web.frame = NSRect(origin: .zero, size: size)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.snap(size) }
        }
    }

    private func snap(_ size: NSSize) {
        guard let web else { return }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.snapshotWidth = NSNumber(value: Double(size.width))
        web.takeSnapshot(with: config) { [weak self] image, error in
            if let image {
                self?.finish(.success(image))
            } else {
                self?.finish(.failure(Failure(message: error?.localizedDescription ?? "The page could not be captured.")))
            }
        }
    }
}

/// Photographs a simulator or an Android device by asking its own tools.
/// No Screen Recording here either: `simctl` and `adb` hand back the device's
/// framebuffer, whatever is or is not on this Mac's display.
enum DeviceCapture {
    static var adbPath: String? {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", home + "/Library/Android/sdk/platform-tools/adb"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private static func run(_ command: [String], timeout: TimeInterval = 15) -> (status: Int32, out: Data) {
        guard let tool = command.first else { return (127, Data()) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = Array(command.dropFirst())
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return (127, Data()) }
        let killer = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        killer.cancel()
        return (task.terminationStatus, data)
    }

    /// Booted simulators and connected devices. Blocking: call off the main thread.
    static func list() -> [CaptureDevice] {
        var found: [CaptureDevice] = []
        let sims = run(["/usr/bin/xcrun", "simctl", "list", "devices", "booted", "-j"])
        if sims.status == 0 { found += CaptureDevice.simulators(fromJSON: sims.out) }
        if let adb = adbPath {
            let phones = run([adb, "devices", "-l"], timeout: 6)
            if phones.status == 0 { found += CaptureDevice.androids(fromList: String(decoding: phones.out, as: UTF8.self)) }
        }
        return found
    }

    /// The device's screen as PNG data, or nil. Blocking.
    static func screenshot(_ device: CaptureDevice) -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wt-manager-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard device.kind == .simulator || adbPath != nil else { return nil }
        let result = run(device.screenshotCommand(adb: adbPath ?? "", file: file.path), timeout: 20)
        guard result.status == 0 else { return nil }
        let data: Data? = device.kind == .simulator ? try? Data(contentsOf: file) : result.out
        return data.flatMap { NSImage(data: $0) == nil ? nil : $0 }
    }
}

// MARK: - model

/// The page's state: which pair is on screen, its two images, and how they
/// are being compared.
@MainActor
final class CompareModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide, slider, overlay, difference
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sideBySide: return "Side by side"
            case .slider: return "Slider"
            case .overlay: return "Overlay"
            case .difference: return "Difference"
            }
        }
    }

    enum Source: String, CaseIterable, Identifiable {
        case web, device
        var id: String { rawValue }
        var label: String { self == .web ? "Web page" : "Simulator or device" }
    }

    private static let defaults = UserDefaults.standard
    /// A page a dev server serves, or the screen of a simulator or phone.
    @Published var source: Source = Source(rawValue: defaults.string(forKey: "wtmanager.compare.source") ?? "") ?? .web {
        didSet { Self.defaults.set(source.rawValue, forKey: "wtmanager.compare.source"); reload() }
    }
    @Published private(set) var devices: [CaptureDevice] = []
    @Published private(set) var listingDevices = false
    @Published var deviceID: String = defaults.string(forKey: "wtmanager.compare.device") ?? "" {
        didSet { Self.defaults.set(deviceID, forKey: "wtmanager.compare.device"); reload() }
    }
    /// A device has no path to tell its screens apart, so the person names
    /// the one in front of them: "checkout", "settings".
    @Published var screenDraft: String = defaults.string(forKey: "wtmanager.compare.screen") ?? "home"
    @Published private(set) var screen: String = defaults.string(forKey: "wtmanager.compare.screen") ?? "home"
    var device: CaptureDevice? { devices.first { $0.id == deviceID } }
    /// The width a device pair is drawn and compared at: a phone's, in points.
    static let deviceWidth = 390
    @Published var worktree: String = defaults.string(forKey: "wtmanager.compare.worktree") ?? "" {
        didSet { Self.defaults.set(worktree, forKey: "wtmanager.compare.worktree"); reload() }
    }
    @Published var port: Int = defaults.integer(forKey: "wtmanager.compare.port") {
        didSet { Self.defaults.set(port, forKey: "wtmanager.compare.port") }
    }
    /// What is typed. The pair follows it only when it is committed, so a
    /// half-typed path does not flash through six empty pairs.
    @Published var pathDraft: String = defaults.string(forKey: "wtmanager.compare.path") ?? "/"
    @Published private(set) var path: String = defaults.string(forKey: "wtmanager.compare.path") ?? "/"
    @Published var width: Int = {
        let saved = defaults.integer(forKey: "wtmanager.compare.width")
        return ComparePair.widths.contains(saved) ? saved : 390
    }() {
        didSet { Self.defaults.set(width, forKey: "wtmanager.compare.width"); reload() }
    }
    @Published var mode: Mode = Mode(rawValue: defaults.string(forKey: "wtmanager.compare.mode") ?? "") ?? .sideBySide {
        didSet { Self.defaults.set(mode.rawValue, forKey: "wtmanager.compare.mode") }
    }
    @Published var opacity: Double = 0.5
    /// Where the slider's divide sits, 0...1 from the left.
    @Published var split: Double = 0.5

    @Published private(set) var design: NSImage?
    @Published private(set) var capture: NSImage?
    @Published private(set) var difference: NSImage?
    @Published private(set) var capturing = false
    @Published var note: String?

    private let camera = WebCapture()
    /// Set by the snapshot harness: images are handed in and nothing is read
    /// from or written to disk.
    private var fixture = false

    init() { reload() }

    var pair: ComparePair {
        source == .web ? ComparePair(worktree: worktree, path: path, width: width)
            : ComparePair(worktree: "device:" + deviceID, path: screen, width: Self.deviceWidth)
    }
    /// Whether there is something for a design to sit beside.
    var hasTarget: Bool { source == .web ? !worktree.isEmpty : !deviceID.isEmpty }
    var geometry: CompareGeometry? {
        guard let design, let capture else { return nil }
        return CompareGeometry(design: Self.pixels(design), capture: Self.pixels(capture))
    }

    func commitPath() {
        if source == .device {
            let name = screenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            screenDraft = name.isEmpty ? "home" : name
            guard screenDraft != screen else { return }
            screen = screenDraft
            Self.defaults.set(screen, forKey: "wtmanager.compare.screen")
            reload()
            return
        }
        let clean = ComparePair.normalised(pathDraft)
        pathDraft = clean
        guard clean != path else { return }
        path = clean
        Self.defaults.set(clean, forKey: "wtmanager.compare.path")
        reload()
    }

    func select(worktree: String, port: Int) {
        self.port = port
        if worktree != self.worktree { self.worktree = worktree }
    }

    /// Read this pair's two images back from disk.
    func reload() {
        guard !fixture else { return }
        note = nil
        let pair = self.pair
        design = hasTarget ? NSImage(contentsOf: CompareLibrary.url(.design, for: pair)) : nil
        capture = hasTarget ? NSImage(contentsOf: CompareLibrary.url(.capture, for: pair)) : nil
        rediff()
    }

    func loadFixture(design: NSImage?, capture: NSImage?, worktree: String, port: Int, path: String, width: Int, mode: Mode) {
        fixture = true
        self.source = .web
        self.worktree = worktree; self.port = port; self.path = path; self.pathDraft = path
        self.width = width; self.mode = mode
        self.design = design; self.capture = capture
        difference = design.flatMap { d in capture.flatMap { Self.difference(design: d, capture: $0, width: width) } }
    }

    /// Ask the simulator and adb what has a screen right now.
    func listDevices() {
        guard !fixture, !listingDevices else { return }
        listingDevices = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = DeviceCapture.list()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.listingDevices = false
                self.devices = found
                if self.device == nil, self.capture == nil, self.design == nil, let first = found.first {
                    self.deviceID = first.id
                }
            }
        }
    }

    private func captureDevice() {
        guard !capturing, let device else { return }
        commitPath()
        let pair = self.pair
        capturing = true
        note = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let png = DeviceCapture.screenshot(device)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.capturing = false
                guard let png, let image = NSImage(data: png) else {
                    self.note = "\(device.name) did not hand back its screen. Check it is still booted and unlocked."
                    return
                }
                CompareLibrary.store(png, as: .capture, for: pair)
                if pair == self.pair {
                    self.capture = image
                    self.rediff()
                }
            }
        }
    }

    func loadFixture(device: CaptureDevice, design: NSImage?, capture: NSImage?) {
        fixture = true
        devices = [device]
        source = .device
        deviceID = device.id
        screen = "checkout"; screenDraft = "checkout"
        mode = .sideBySide
        self.design = design; self.capture = capture
        difference = nil
    }

    func captureNow() {
        if source == .device { captureDevice(); return }
        guard !capturing, !worktree.isEmpty, port > 0, let url = pair.url(port: port) else { return }
        commitPath()
        let pair = self.pair
        capturing = true
        note = nil
        camera.capture(url, width: width) { [weak self] result in
            guard let self else { return }
            self.capturing = false
            switch result {
            case .success(let image):
                guard let png = Self.png(image) else {
                    self.note = "The capture could not be saved."
                    return
                }
                CompareLibrary.store(png, as: .capture, for: pair)
                if pair == self.pair {
                    self.capture = image
                    self.rediff()
                }
            case .failure(let error):
                self.note = "Could not capture \(url.absoluteString): \(error.localizedDescription)"
            }
        }
    }

    /// Take an image as this pair's design. It is copied in; the original is
    /// not referenced again.
    @discardableResult
    func adopt(design image: NSImage) -> Bool {
        guard hasTarget, let png = Self.png(image) else {
            note = !hasTarget ? "Pick a server or a device first, so the design has a screen to sit beside."
                : "That could not be read as an image."
            return false
        }
        CompareLibrary.store(png, as: .design, for: pair)
        design = image
        note = nil
        rediff()
        return true
    }

    func chooseDesign() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as design"
        panel.message = "Pick the design for this screen. It is copied into wt-manager and stays on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let image = NSImage(contentsOf: url) { adopt(design: image) }
        else { note = "That file could not be read as an image." }
    }

    func pasteDesign() {
        let board = NSPasteboard.general
        if let image = NSImage(pasteboard: board) {
            adopt(design: image)
        } else if let url = (board.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
                  let image = NSImage(contentsOf: url) {
            adopt(design: image)
        } else {
            note = "There is no image on the clipboard."
        }
    }

    func removeDesign() {
        CompareLibrary.remove(.design, for: pair)
        design = nil
        difference = nil
    }

    private func rediff() {
        guard let design, let capture else { difference = nil; return }
        let pair = self.pair
        let width = pair.width
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Self.difference(design: design, capture: capture, width: width)
            DispatchQueue.main.async { [weak self] in
                if self?.pair == pair { self?.difference = image }
            }
        }
    }

    // MARK: images

    static func pixels(_ image: NSImage) -> CGSize {
        if let rep = image.representations.first, rep.pixelsWide > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    static func png(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Both images at one width, tops aligned, subtracted. Black is where
    /// they agree; anything lit is a difference, and the taller one's extra
    /// length shows as itself.
    nonisolated static func difference(design: NSImage, capture: NSImage, width: Int) -> NSImage? {
        guard let d = design.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let c = capture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let target = CGFloat(min(width * 2, 2880))
        func scaled(_ cg: CGImage) -> CIImage {
            let k = target / CGFloat(cg.width)
            return CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        let a = scaled(d), b = scaled(c)
        let height = max(a.extent.height, b.extent.height)
        let canvas = CGRect(x: 0, y: 0, width: target, height: height)
        let black = CIImage(color: .black).cropped(to: canvas)
        // Core Image counts up from the bottom; pages are read from the top.
        func placed(_ image: CIImage) -> CIImage {
            image.transformed(by: CGAffineTransform(translationX: 0, y: height - image.extent.height))
                .composited(over: black)
        }
        guard let filter = CIFilter(name: "CIDifferenceBlendMode") else { return nil }
        filter.setValue(placed(a), forKey: kCIInputImageKey)
        filter.setValue(placed(b), forKey: kCIInputBackgroundImageKey)
        guard let out = filter.outputImage?.cropped(to: canvas),
              let cg = CIContext().createCGImage(out, from: canvas) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: target / 2, height: height / 2))
    }
}

// MARK: - page

/// A design image beside the real, running page, at the same width.
///
/// "Check the design again" is the correction this page exists to make
/// unnecessary. The comparison was being done by eye, across two apps at two
/// zoom levels; here both halves are one width, on one surface, and can be
/// laid over each other.
struct DesignCompareView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: CompareModel

    @State private var cardWidth: CGFloat = 320
    @State private var dropping = false
    @State private var signingIn = false

    init(store: Store) {
        self.store = store
        self.model = store.compare
    }

    struct Target: Hashable, Identifiable {
        let worktree: String
        let name: String
        let port: Int
        let folder: String
        let running: Bool
        var id: String { "\(worktree):\(port)" }
        var label: String {
            running ? "\(name)  ·  :\(String(port))" + (folder.isEmpty ? "" : "  ·  \(folder)") : "\(name)  ·  not running"
        }
    }

    /// Every server in a worktree that answers on a port, plus the pair
    /// already chosen when its server has since stopped: its saved images
    /// are still worth looking at.
    private var targets: [Target] {
        var out: [Target] = []
        for wt in store.running?.worktrees ?? [] {
            for server in wt.servers where server.stoppable {
                for port in server.ports {
                    out.append(Target(worktree: wt.path, name: wt.name, port: port, folder: server.folder, running: true))
                }
            }
        }
        if !model.worktree.isEmpty, !out.contains(where: { $0.worktree == model.worktree && $0.port == model.port }) {
            out.append(Target(worktree: model.worktree, name: (model.worktree as NSString).lastPathComponent,
                              port: model.port, folder: "", running: false))
        }
        return out
    }

    private var current: Target? { targets.first { $0.worktree == model.worktree && $0.port == model.port } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Design compare").font(.system(size: TypeScale.title, weight: .semibold))
                    Text("A design image beside the page your dev server is really serving, at the same width. Nothing leaves this Mac.")
                        .font(.system(size: TypeScale.body)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = model.note {
                    Banner(tone: .warning, symbol: "exclamationmark.triangle", title: note, detail: "", outer: 0,
                           onDismiss: { model.note = nil }) { EmptyView() }
                }
                controls
                comparison
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            store.refreshRunning()
            adoptFirstTarget()
            if model.source == .device { model.listDevices() }
        }
        .onChange(of: store.running?.serverCount) { _ in adoptFirstTarget() }
        .sheet(isPresented: $signingIn) {
            if let url = model.pair.url(port: model.port) {
                SignInSheet(url: url, width: model.width) { signingIn = false }
            }
        }
    }

    /// With nothing chosen yet, the first running server is the obvious one.
    private func adoptFirstTarget() {
        guard model.worktree.isEmpty, let first = targets.first(where: \.running) else { return }
        model.select(worktree: first.worktree, port: first.port)
    }

    // MARK: what to compare

    private var controls: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(CompareModel.Source.allCases) { s in
                        Segment(title: s.label, on: model.source == s) {
                            model.source = s
                            if s == .device { model.listDevices() }
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { picker; nameField }
                    VStack(alignment: .leading, spacing: 10) { picker; nameField }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { secondRowLead; Spacer(minLength: 8); captureButtons }
                    VStack(alignment: .leading, spacing: 10) { secondRowLead; captureButtons }
                }
                if model.source == .device {
                    if model.devices.isEmpty && !model.listingDevices {
                        Text("No booted simulator or connected Android device was found. Boot one, then Look again.")
                            .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if targets.isEmpty {
                    Text("No dev server is running in a worktree. Start one and it appears here; the Running page lists them.")
                        .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let current, !current.running {
                    Text("Its server has stopped, so this is the last capture. Start it again to take a new one.")
                        .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
    }

    @ViewBuilder private var picker: some View {
        if model.source == .web { serverPicker } else { devicePicker }
    }
    @ViewBuilder private var nameField: some View {
        if model.source == .web { pathField } else { screenField }
    }
    @ViewBuilder private var secondRowLead: some View {
        if model.source == .web { widthChips } else {
            Button(model.listingDevices ? "Looking…" : "Look again") { model.listDevices() }
                .buttonStyle(.wt(.quiet)).disabled(model.listingDevices)
                .help("Ask the simulator and adb what is booted or connected")
        }
    }
    /// Whether Capture has something to photograph.
    private var canCapture: Bool {
        model.source == .web ? current?.running == true : model.device != nil
    }

    private func menuLabel(_ text: String, live: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(live ? Palette.reclaim : Palette.faint).frame(width: 8, height: 8)
            Text(text).font(.system(size: TypeScale.secondary, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var devicePicker: some View {
        Menu {
            ForEach(model.devices) { d in
                Button(d.name + (d.kind == .simulator ? "  ·  simulator" : "  ·  Android")) { model.deviceID = d.id }
            }
        } label: {
            menuLabel(model.device.map { $0.name + ($0.kind == .simulator ? "  ·  simulator" : "  ·  Android") }
                      ?? (model.deviceID.isEmpty ? "Choose a device" : "Not connected  ·  last capture"),
                      live: model.device != nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(model.devices.isEmpty)
        .frame(minWidth: 220, maxWidth: .infinity)
        .accessibilityLabel("Device")
    }

    private var screenField: some View {
        HStack(spacing: 6) {
            Text("screen").font(.system(size: TypeScale.secondary, design: .monospaced)).foregroundStyle(Palette.muted)
                .fixedSize()
            TextField("home", text: $model.screenDraft)
                .textFieldStyle(.plain).font(.system(size: TypeScale.secondary, design: .monospaced))
                .onSubmit { model.commitPath() }
                .accessibilityLabel("Screen name")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
        .frame(minWidth: 200, maxWidth: .infinity)
        .help("A name for the screen the device is showing, so each screen keeps its own design")
    }

    private var serverPicker: some View {
        Menu {
            ForEach(targets) { t in
                Button(t.label) { model.select(worktree: t.worktree, port: t.port) }
            }
        } label: {
            menuLabel(current?.label ?? "Choose a server", live: current?.running == true)
        }
        // A button-style menu with a plain button draws the label as written;
        // the borderless style replaces it with the system's own.
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(targets.isEmpty)
        .frame(minWidth: 220, maxWidth: .infinity)
        .accessibilityLabel("Server")
    }

    private var pathField: some View {
        HStack(spacing: 6) {
            Text("localhost:" + (model.port > 0 ? String(model.port) : "…"))
                .font(.system(size: TypeScale.secondary, design: .monospaced)).foregroundStyle(Palette.muted)
                .fixedSize()
            TextField("/", text: $model.pathDraft)
                .textFieldStyle(.plain).font(.system(size: TypeScale.secondary, design: .monospaced))
                .onSubmit { model.commitPath() }
                .accessibilityLabel("Path")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
        .frame(minWidth: 200, maxWidth: .infinity)
    }

    private var widthChips: some View {
        HStack(spacing: 8) {
            ForEach(ComparePair.widths, id: \.self) { w in
                Segment(title: String(w), on: model.width == w) { model.commitPath(); model.width = w }
                    .accessibilityLabel("\(w) points wide")
            }
        }
    }

    private var captureButtons: some View {
        HStack(spacing: 8) {
            if model.capturing {
                ProgressView().controlSize(.small)
                Text("Capturing…").font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted).fixedSize()
            }
            if model.source == .web {
                Button("Sign in…") { model.commitPath(); signingIn = true }
                    .buttonStyle(.wt(.quiet))
                    .disabled(!canCapture)
                    .help("Open this page in a window to sign in. Captures then see what you see.")
            }
            Button(model.capture == nil ? "Capture" : "Capture again") { model.captureNow() }
                .buttonStyle(.wt(.primary))
                .disabled(!canCapture || model.capturing)
        }
    }

    // MARK: the comparison

    private var both: Bool { model.design != nil && model.capture != nil }

    private var comparison: some View {
        CardBox {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { modeChips; Spacer(minLength: 8); designButtons }
                VStack(alignment: .leading, spacing: 10) { modeChips; designButtons }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            Hairline().padding(.horizontal, 20)
            // Measured by a row with no width of its own. Read off the stage
            // instead, the images would set the width they are then sized
            // from, and a narrow window would never get them back.
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardWidth = geo.size.width - 40 }
                    .onChange(of: geo.size.width) { cardWidth = $0 - 40 }
            }
            .frame(height: 0)
            VStack(alignment: .leading, spacing: 12) {
                if both && model.mode == .overlay { opacityRow }
                stage
                if let caption { Text(caption).font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true) }
            }
            .padding(20)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(dropping ? Palette.brand : Color.clear, lineWidth: 2))
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping, perform: drop)
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            ForEach(CompareModel.Mode.allCases) { m in
                Segment(title: m.label, on: model.mode == m) { model.mode = m }
                    .disabled(!both && m != .sideBySide)
            }
        }
    }

    private var designButtons: some View {
        HStack(spacing: 8) {
            Button(model.design == nil ? "Choose design…" : "Replace design…") { model.chooseDesign() }
            Button("Paste") { model.pasteDesign() }.help("Use the image on the clipboard as the design")
            if model.design != nil {
                Button { model.removeDesign() } label: { Image(systemName: "trash").font(.system(size: 12)) }
                    .buttonStyle(TrashButtonStyle(side: 28))
                    .help("Remove this design").accessibilityLabel("Remove this design")
            }
        }
        .buttonStyle(.wt(.quiet))
    }

    private var opacityRow: some View {
        HStack(spacing: 10) {
            Text("Running page").font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted).fixedSize()
            Slider(value: $model.opacity, in: 0...1).frame(maxWidth: 260)
                .accessibilityLabel("Design opacity")
            Text("Design").font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted).fixedSize()
            Text("\(Int((model.opacity * 100).rounded()))%").font(.system(size: TypeScale.secondary)).monospacedDigit()
                .foregroundStyle(Palette.muted).frame(width: 38, alignment: .trailing)
        }
    }

    private var caption: String? {
        guard both else { return nil }
        let proportions: String? = model.geometry?.note(atWidth: model.pair.width)
        switch model.mode {
        case .difference:
            return "Black is where the two agree; anything lit is a difference. " + (proportions ?? "")
        case .slider:
            return "Drag the divide: design on its left, running page on its right. " + (proportions ?? "")
        default:
            return proportions
        }
    }

    /// The width both images are drawn at: the pair's own, or as much of it
    /// as the window has.
    private func shown(_ available: CGFloat) -> CGFloat { max(120, min(available, CGFloat(model.pair.width))) }

    private func height(of image: NSImage, at width: CGFloat) -> CGFloat {
        let px = CompareModel.pixels(image)
        return px.width > 0 ? width * px.height / px.width : width
    }

    @ViewBuilder
    private var stage: some View {
        if both, let design = model.design, let capture = model.capture {
            switch model.mode {
            case .sideBySide: sideBySide
            case .slider: slider(design, capture)
            case .overlay: overlay(design, capture)
            case .difference:
                if let diff = model.difference {
                    picture(diff, width: shown(cardWidth))
                } else {
                    Text("Comparing…").font(.system(size: TypeScale.body)).foregroundStyle(Palette.muted)
                }
            }
        } else {
            sideBySide
        }
    }

    private func picture(_ image: NSImage, width: CGFloat) -> some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: width, height: height(of: image, at: width))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
    }

    private var sideBySide: some View {
        let each: CGFloat = shown((cardWidth - 16) / 2)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                GroupLabel("Design")
                if let design = model.design { picture(design, width: each) } else {
                    placeholder(width: each, symbol: "photo.on.rectangle.angled", title: "Drop a design image here",
                                detail: "Or paste one, or choose a file. It is copied in and stays on this Mac.")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                GroupLabel(model.source == .web ? "Running page" : "Device screen")
                if let capture = model.capture { picture(capture, width: each) } else {
                    placeholder(width: each, symbol: "camera.viewfinder", title: "No capture yet",
                                detail: model.source == .device
                                    ? (canCapture ? "Capture asks the device for the screen it is showing now."
                                                  : "Pick a booted simulator or a connected device above, then capture.")
                                    : (canCapture
                                        ? "Capture loads this page at \(model.width)pt in a hidden view and photographs all of it."
                                        : "Pick a running server above, then capture."))
                }
            }
        }
    }

    private func placeholder(width: CGFloat, symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Palette.muted).accessibilityHidden(true)
            Text(title).font(.system(size: TypeScale.body, weight: .semibold)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: width).frame(minHeight: 220)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.quiet))
        .overlay(RoundedRectangle(cornerRadius: Radius.control)
            .strokeBorder(Palette.controlLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func overlay(_ design: NSImage, _ capture: NSImage) -> some View {
        let w: CGFloat = shown(cardWidth)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: capture).resizable().interpolation(.high)
                .frame(width: w, height: height(of: capture, at: w))
            Image(nsImage: design).resizable().interpolation(.high)
                .frame(width: w, height: height(of: design, at: w))
                .opacity(model.opacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func slider(_ design: NSImage, _ capture: NSImage) -> some View {
        let w: CGFloat = shown(cardWidth)
        let hd: CGFloat = height(of: design, at: w)
        let hc: CGFloat = height(of: capture, at: w)
        let x: CGFloat = w * CGFloat(model.split)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: capture).resizable().interpolation(.high).frame(width: w, height: hc)
            Image(nsImage: design).resizable().interpolation(.high).frame(width: w, height: hd)
                .mask(alignment: .topLeading) { Rectangle().frame(width: x, height: hd) }
            // The divide: a line the full height, and a grip to take hold of.
            Rectangle().fill(Palette.brand).frame(width: 2, height: max(hd, hc)).offset(x: x - 1)
            Circle().fill(Palette.brand).frame(width: 26, height: 26)
                .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                .offset(x: x - 13, y: 14)
                .accessibilityHidden(true)
        }
        .frame(width: w, height: max(hd, hc), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            model.split = Double(min(max(g.location.x / w, 0), 1))
        })
        .accessibilityElement()
        .accessibilityLabel("Divide between design and running page")
        .accessibilityValue("\(Int(model.split * 100)) percent")
        .accessibilityAdjustableAction { direction in
            model.split = min(max(model.split + (direction == .increment ? 0.1 : -0.1), 0), 1)
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                let image: NSImage? = url.flatMap { NSImage(contentsOf: $0) }
                DispatchQueue.main.async {
                    if let image { model.adopt(design: image) } else { model.note = "That file could not be read as an image." }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                let image: NSImage? = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async {
                    if let image { model.adopt(design: image) } else { model.note = "That could not be read as an image." }
                }
            }
            return true
        }
        return false
    }
}

/// One choice among a few, drawn as the narrow layout's chips are.
private struct Segment: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: TypeScale.secondary, weight: .semibold)).lineLimit(1).fixedSize()
                .monospacedDigit()
                .foregroundStyle(on ? Palette.onAction : Color.primary)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(on ? Palette.action : Palette.cardFill))
                .overlay(RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(on ? Palette.action : Palette.line, lineWidth: 1))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The same page in a window you can type into, sharing the capture's
/// cookies. Signing in is done here, by the person: a capture never fills in
/// a form or steps around a login.
private struct SignInSheet: View {
    let url: URL
    let width: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to this page").font(.system(size: TypeScale.section, weight: .semibold))
                    Text(url.absoluteString).font(.system(size: TypeScale.secondary, design: .monospaced))
                        .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button("Done", action: done).buttonStyle(.wt(.primary)).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Hairline()
            WebPane(url: url)
        }
        .frame(width: CGFloat(min(max(width, 480), 1000)), height: 640)
        .background(Palette.ground)
    }
}

private struct WebPane: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.load(URLRequest(url: url))
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {}
}
