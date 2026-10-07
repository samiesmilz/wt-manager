import Foundation

/// Compare numeric release components, never lexicographic strings (0.10 > 0.9).
public struct ReleaseVersion: Comparable, Equatable {
    public let parts: [Int]
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let split = value.split(separator: ".", omittingEmptySubsequences: false)
        guard split.count == 3, split.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              split.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = split.map { Int($0)! }
    }
    public static func < (a: Self, b: Self) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

public struct PublishedRelease: Codable, Equatable {
    public let tagName: String
    public let htmlURL: String
    public let draft: Bool
    public let prerelease: Bool
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease
    }
    public func updateURL(current: String) -> URL? {
        guard !draft, !prerelease, let newest = ReleaseVersion(tagName),
              let installed = ReleaseVersion(current), newest > installed,
              let url = URL(string: htmlURL), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil,
              url.path.hasPrefix("/samiesmilz/wt-manager/releases/tag/") else { return nil }
        return url
    }
}

public struct DiskSample: Codable, Equatable {
    public let at: Date
    public let totalKb: Int
    public let rebuildableKb: Int
}

/// Local measurements and confirmed rewards. Neither is inferred from a preview.
public struct CleanupHistory: Codable {
    public private(set) var scope: [String] = []
    public private(set) var samples: [DiskSample] = []
    public private(set) var reclaimedKb: Int = 0
    public private(set) var cleanups: Int = 0
    private var rewarded: [UUID] = []
    public init() {}
    public mutating func measure(roots: [String], totalKb: Int, rebuildableKb: Int, at: Date = Date()) {
        guard totalKb >= 0, rebuildableKb >= 0 else { return }
        let next = roots.sorted()
        if scope != next { samples = []; scope = next }
        samples.append(DiskSample(at: at, totalKb: totalKb, rebuildableKb: rebuildableKb))
        samples = Array(samples.filter { at.timeIntervalSince($0.at) < 30 * 86400 }.suffix(720))
    }
    /// Last measurement is always retained. No baseline means no invented growth.
    public var previous: DiskSample? { samples.count > 1 ? samples[samples.count - 2] : nil }
    public var latest: DiskSample? { samples.last }
    public var growthKb: Int? {
        guard let a = previous, let b = latest else { return nil }
        return b.totalKb - a.totalKb
    }
    @discardableResult
    public mutating func reward(id: UUID, done: Bool, completed: Int, freedKb: Int) -> Bool {
        guard done, completed > 0, freedKb > 0, !rewarded.contains(id),
              reclaimedKb <= Int.max - freedKb else { return false }
        reclaimedKb += freedKb
        cleanups += 1
        rewarded.append(id)
        rewarded = Array(rewarded.suffix(256))
        return true
    }
    public static let milestonesKb = [1, 5, 25, 100, 500].map { $0 * 1024 * 1024 }
    public var level: Int { Self.milestonesKb.filter { reclaimedKb >= $0 }.count }
    public var rank: String { ["Fresh start", "Space Scout", "Cache Ranger", "Disk Guardian", "Storage Hero", "Space Legend"][level] }
    public var nextMilestoneKb: Int? { Self.milestonesKb.first { $0 > reclaimedKb } }
    public var levelFraction: Double {
        guard let next = nextMilestoneKb else { return 1 }
        let floor = level == 0 ? 0 : Self.milestonesKb[level - 1]
        return Double(reclaimedKb - floor) / Double(next - floor)
    }
}
