import CryptoKit
import Foundation

/// A design image and a capture of the running page, kept as a pair.
///
/// "Check the design again" is a comparison nobody can make from memory, and
/// the two halves of it live in different apps at different sizes. A pair is
/// one worktree, one path and one width: the three things that have to match
/// before two pictures are about the same screen.
public struct ComparePair: Hashable {
    public static let widths: [Int] = [390, 600, 900, 1440]

    public let worktree: String
    public let path: String
    public let width: Int

    public init(worktree: String, path: String, width: Int) {
        self.worktree = worktree
        self.path = ComparePair.normalised(path)
        self.width = width
    }

    /// `checkout`, ` /checkout ` and `/checkout` are one page. A full URL is
    /// reduced to its path and query: the host is always this machine.
    public static func normalised(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = s.range(of: "://") {
            let rest = s[scheme.upperBound...]
            s = rest.firstIndex(of: "/").map { String(rest[$0...]) } ?? "/"
        }
        if !s.hasPrefix("/") { s = "/" + s }
        return s
    }

    /// Stable across launches and safe as a folder name.
    public var key: String {
        let digest = SHA256.hash(data: Data("\(worktree)\n\(path)\n\(width)".utf8))
        return digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// The page to load. Always localhost: this never leaves the machine.
    public func url(port: Int) -> URL? {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)) ?? path
        return URL(string: "http://localhost:\(port)\(escaped)")
    }
}

/// Where pairs are kept: Application Support, beside the chosen mascot image.
/// Copied in, for the same reason that one is: a design dragged out of
/// Downloads must survive Downloads being tidied.
public enum CompareLibrary {
    static var storageDirectoryOverride: URL?

    public static var root: URL {
        if let storageDirectoryOverride { return storageDirectoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("wt-manager/compare")
    }

    public enum Side: String { case design, capture }

    public static func url(_ side: Side, for pair: ComparePair) -> URL {
        root.appendingPathComponent(pair.key).appendingPathComponent(side.rawValue + ".png")
    }

    public static func has(_ side: Side, for pair: ComparePair) -> Bool {
        FileManager.default.isReadableFile(atPath: url(side, for: pair).path)
    }

    /// Stores PNG data for one side, replacing what was there.
    @discardableResult
    public static func store(_ png: Data, as side: Side, for pair: ComparePair) -> Bool {
        let target = url(side, for: pair)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func remove(_ side: Side, for pair: ComparePair) {
        try? FileManager.default.removeItem(at: url(side, for: pair))
    }
}

/// The arithmetic of laying two images of different sizes over each other.
///
/// Both are scaled to one width, because the width is the thing the pair
/// agreed on; the heights then say whether the page is longer or shorter
/// than the design, which is itself a finding and is said rather than hidden
/// by stretching either one.
public struct CompareGeometry: Equatable {
    public let design: CGSize
    public let capture: CGSize

    public init(design: CGSize, capture: CGSize) {
        self.design = design; self.capture = capture
    }

    /// The height of each once both are `width` wide.
    public func heights(atWidth width: CGFloat) -> (design: CGFloat, capture: CGFloat) {
        (design.width > 0 ? design.height * width / design.width : 0,
         capture.width > 0 ? capture.height * width / capture.width : 0)
    }

    /// One line for under the comparison, or nil when the two already agree
    /// to within a point at the pair's width.
    public func note(atWidth width: Int) -> String? {
        let h = heights(atWidth: CGFloat(width))
        let gap = Int((h.capture - h.design).rounded())
        guard h.design > 0, h.capture > 0, abs(gap) > 1 else { return nil }
        return gap > 0
            ? "Both are scaled to \(width)pt wide. The running page is \(gap)pt taller than the design."
            : "Both are scaled to \(width)pt wide. The design is \(-gap)pt taller than the running page."
    }
}

/// A booted simulator or a connected Android device: something with a screen
/// that can be photographed by asking its own tools, not by recording ours.
public struct CaptureDevice: Hashable, Identifiable {
    public enum Kind: String { case simulator, android }
    public let kind: Kind
    public let id: String
    public let name: String

    public init(kind: Kind, id: String, name: String) {
        self.kind = kind; self.id = id; self.name = name
    }

    /// What a pair made on this device is filed under, in place of a worktree.
    public var pairOwner: String { "device:\(kind.rawValue):\(id)" }

    /// `xcrun simctl list devices booted -j`: every booted simulator.
    public static func simulators(fromJSON data: Data) -> [CaptureDevice] {
        struct Listing: Decodable {
            struct Device: Decodable { let udid: String; let name: String; let state: String? }
            let devices: [String: [Device]]
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return [] }
        return listing.devices.values.flatMap { $0 }
            .filter { ($0.state ?? "Booted") == "Booted" }
            .map { CaptureDevice(kind: .simulator, id: $0.udid, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    /// `adb devices -l`: only the ones in the `device` state. `unauthorized`
    /// and `offline` are attached and cannot be asked for a screen.
    public static func androids(fromList text: String) -> [CaptureDevice] {
        text.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts[1] == "device" else { return nil }
            let model = parts.first { $0.hasPrefix("model:") }.map { $0.dropFirst(6).replacingOccurrences(of: "_", with: " ") }
            return CaptureDevice(kind: .android, id: parts[0], name: model ?? parts[0])
        }
    }

    /// The command that writes this device's screen as a PNG: to `file` for a
    /// simulator, to standard output for Android.
    public func screenshotCommand(adb: String, file: String) -> [String] {
        switch kind {
        case .simulator: return ["/usr/bin/xcrun", "simctl", "io", id, "screenshot", "--type=png", file]
        case .android: return [adb, "-s", id, "exec-out", "screencap", "-p"]
        }
    }
}
