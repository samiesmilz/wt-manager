import Foundation

/// One way to write a size, everywhere: the same rule as the engine's
/// `human()`, so the terminal, the window and the balloon can never show one
/// figure two ways. The window used to truncate (56.6 GB as "56GB") while the
/// balloon rounded it to "57", and two numbers that are the same measurement
/// read as a disagreement.
public enum DiskSize {
    public static func parts(_ kb: Int) -> (number: String, unit: String) {
        for (unit, factor) in [("TB", 1 << 30), ("GB", 1 << 20), ("MB", 1 << 10)] where kb >= factor {
            let v = Double(kb) / Double(factor)
            return (String(format: v < 10 ? "%.1f" : "%.0f", v), unit)
        }
        return (String(max(kb, 0)), "KB")
    }
    /// "56GB", or a dash for nothing measured.
    public static func human(_ kb: Int) -> String {
        guard kb > 0 else { return "—" }
        let p = parts(kb)
        return p.number + p.unit
    }
}

/// The disk balloon: what wt-manager could free, as a number the floating
/// character holds on a string.
///
/// A magnitude rather than a status. The badge it replaces said one of eight
/// moods, most of which the menu bar already says; this says how much room the
/// tool could give back, which is the thing worth a glance. It counts only what
/// wt-manager can actually free — a balloon that cleaning up could not shrink
/// would be wallpaper.
public enum DiskBalloon {
    public static let gb = 1_048_576.0                 // KB in a GB

    /// What cleaning up would free, in the two parts the Disk page offers to
    /// free them by: whole finished worktrees, and rebuildable caches inside
    /// everything else.
    public struct Freeable: Equatable {
        public var finishedKb = 0
        public var finishedCount = 0
        public var cachesKb = 0
        public var totalKb: Int { finishedKb + cachesKb }
    }

    /// The whole of a worktree that is free to go, and the caches inside
    /// everything else — main checkouts and blocked removals can never be one
    /// click away, so they count only their caches. `nil` until anything has
    /// been measured at all.
    public static func freeable(_ worktrees: [Worktree]) -> Freeable? {
        var f = Freeable(), known = false
        for w in worktrees {
            if w.removable, w.sizeKb > 0 {
                f.finishedKb += w.sizeKb; f.finishedCount += 1; known = true
            } else if w.reclaimKb >= 0 {
                f.cachesKb += w.reclaimKb; known = true
            }
        }
        return known ? f : nil
    }

    public static func freeableKb(_ worktrees: [Worktree]) -> Int? { freeable(worktrees)?.totalKb }

    // MARK: colour

    public enum Colour: String { case grey, green, yellow, orange }

    /// Where the colour bands start, in GB.
    public static let bands: [Double] = [5, 20]
    /// How far below a band's start the value has to fall before the colour
    /// goes back down. Without it a figure hovering at 5.0 flickers between
    /// green and yellow on every measurement.
    public static let margin = 0.5
    /// A nearly full disk steps the colour up one band: 6 GB is nothing with a
    /// terabyte free and urgent with fifteen gigabytes free.
    public static let lowDisk = 0.10, lowDiskRelease = 0.12

    public struct Level: Equatable {
        public var band: Int          // 0, 1, 2: below 5 GB, 5-20 GB, above 20 GB
        public var lowDisk: Bool
        public var colour: Colour { [.green, .yellow, .orange][min(2, band + (lowDisk ? 1 : 0))] }
        /// Size follows the amount, not the urgency: a nearly full disk makes
        /// a small balloon orange, not bigger.
        public var size: Size { [.small, .medium, .large][band] }
        public init(band: Int, lowDisk: Bool) { self.band = band; self.lowDisk = lowDisk }
    }

    public static func level(gb value: Double, freeFraction: Double?, previous: Level?) -> Level {
        let raw = bands.filter { value >= $0 }.count
        var band = raw
        if let p = previous, raw < p.band {
            band = min(p.band, bands.filter { value >= $0 - margin }.count)
        }
        var low = false
        if let f = freeFraction {
            low = (previous?.lowDisk == true) ? f < lowDiskRelease : f < lowDisk
        }
        return Level(band: band, lowDisk: low)
    }

    // MARK: size and label

    public enum Size { case small, medium, large
        /// In art pixels, two points each.
        public var pixels: (w: Int, h: Int) {
            switch self { case .small: return (19, 17); case .medium: return (23, 21); case .large: return (27, 24) }
        }
    }

    /// The number and unit on the balloon, written exactly as the Disk page
    /// writes the same figure.
    public static func label(kb: Int) -> (number: String, unit: String) { DiskSize.parts(max(kb, 0)) }

    /// Below this there is nothing worth carrying: the character lets go.
    public static let emptyKb = Int(0.05 * gb)

    /// Growth is shown in half-gigabyte steps: a "+0.6 GB" tag when the figure
    /// crosses one, so measurements that wobble by megabytes stay quiet.
    public static let stepKb = Int(0.5 * gb)
    public static func crossedStep(from old: Int, to new: Int) -> Bool {
        old / stepKb != new / stepKb && abs(new - old) >= stepKb / 5
    }
    public static func delta(from old: Int, to new: Int) -> String {
        let d = Double(new - old) / gb
        return (d >= 0 ? "+" : "−") + String(format: "%.1f GB", abs(d))
    }
}

extension Worktree {
    /// Finished, not a main checkout, and nothing known to block removing it.
    /// The one definition: the Disk page's remove button and the balloon count
    /// the same worktrees, or the number you click does not match the action
    /// it leads to.
    public var removable: Bool {
        (status == "merged" || status == "empty") && !primary && !isBase && !removalBlocked
    }
}

/// The held balloon as a buoyant pendulum pivoting at the hand.
///
/// Positive angles lean out to the side (the viewer's right in a front pose),
/// negative ones toward and over the head. A breeze of two slow waves of
/// different lengths moves its rest point, so the motion never visibly loops;
/// the window's own acceleration swings it back when the character sets off
/// and forward when it stops. Straining adds a quicker gust and an occasional
/// tug — the motion the orange band gets, so pressure reads without colour.
public struct BalloonSwing {
    public static let rest = 6.0
    public static let range: ClosedRange<Double> = -26...16

    public private(set) var angle = BalloonSwing.rest
    public private(set) var velocity = 0.0
    private var time = 0.0
    private var nextTug: Double
    private var seed: UInt64

    public init(seed: UInt64 = 0x5EED) {
        self.seed = seed
        nextTug = 1.5
    }

    private mutating func random() -> Double {           // SplitMix64, deterministic for tests
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }

    /// The breeze's rest point at this moment, before drift.
    public func breeze(straining: Bool) -> Double {
        let t = time
        var wind = 0.62 * sin(2 * .pi * t / 7.3) + 0.38 * sin(2 * .pi * t / 11.9 + 1.1)
        if straining { wind += 0.3 * sin(2 * .pi * t / 1.9) }
        return 2 + 20 * wind
    }

    /// Advance by `dt` seconds.
    /// - accel: the window's acceleration in points per second squared, signed
    ///   along the direction the balloon leans out (right is positive).
    /// - drift: a lean held while walking, so it trails behind.
    /// - limits: the angles the panel has room for at this balloon's size.
    @discardableResult
    public mutating func step(dt: Double, accel: Double = 0, drift: Double = 0,
                              straining: Bool = false,
                              limits: ClosedRange<Double> = BalloonSwing.range) -> Double {
        let k = straining ? 4.2 : 2.2, c = straining ? 1.1 : 1.5
        let target = min(limits.upperBound, max(limits.lowerBound, breeze(straining: straining) + drift))
        let a = k * (target - angle) - c * velocity - 0.6 * accel
        velocity += a * dt
        if straining {
            nextTug -= dt
            if nextTug <= 0 {
                velocity += (random() < 0.5 ? -1 : 1) * (30 + 20 * random())
                nextTug = 1.2 + 1.6 * random()
            }
        }
        angle += velocity * dt
        if angle < limits.lowerBound { angle = limits.lowerBound; velocity = max(0, velocity) }
        if angle > limits.upperBound { angle = limits.upperBound; velocity = min(0, velocity) }
        time += dt
        return angle
    }

    /// Back to rest, for Reduce Motion or a fresh balloon.
    public mutating func settle() { angle = Self.rest; velocity = 0 }

    /// Flip into the other facing. A character walking left is drawn
    /// mirrored, so the same screen position is the opposite angle; flipping
    /// the state with it keeps the balloon where it is on screen instead of
    /// jumping across the head when the walk changes direction.
    public mutating func mirror() { angle = -angle; velocity = -velocity }
}
