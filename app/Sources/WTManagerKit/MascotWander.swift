import Foundation

/// Small, deterministic decisions for a mascot's occasional screen stroll.
/// Animation and scheduling stay in AppKit; this type owns bounds, direction,
/// travel time and rest intervals so they are testable without a live desktop.
public struct MascotWander {
    private var randomState: UInt64

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        randomState = seed
    }

    /// Pick another point on the display the mascot is already on. A little
    /// inset keeps the whole click target reachable after a display changes.
    public mutating func destination(from current: CGRect, size: CGSize,
                                     displays: [CGRect], inset: CGFloat = 20) -> CGPoint? {
        let usable = displays.filter { $0.width >= size.width + inset * 2
            && $0.height >= size.height + inset * 2 }
        guard let display = usable.max(by: {
            area($0.intersection(current)) < area($1.intersection(current))
        }) else { return nil }

        let minX = display.minX + inset
        let maxX = display.maxX - inset - size.width
        let minY = display.minY + inset
        let maxY = display.maxY - inset - size.height
        let origin = CGPoint(x: min(max(current.minX, minX), maxX),
                             y: min(max(current.minY, minY), maxY))
        // Short, mostly horizontal strolls read as walking rather than flying
        // diagonally across the desktop. Explore the display a little at a time.
        let minimumHop = min(80, (maxX - minX) * 0.4)
        for _ in 0..<10 {
            let direction = random(0...1) < 0.5 ? -1.0 : 1.0
            let candidate = CGPoint(x: min(max(origin.x + direction * random(120...280), minX), maxX),
                                    y: min(max(origin.y + random(-24...24), minY), maxY))
            if hypot(candidate.x - origin.x, candidate.y - origin.y) >= minimumHop {
                return candidate.roundedToPixel
            }
        }
        return origin == current.origin ? nil : origin.roundedToPixel
    }

    /// Make enabling the feature feel responsive after the user closes the
    /// settings window. Longer rests still keep the overall motion occasional.
    public mutating func firstPause() -> TimeInterval { random(1.5...3.5) }
    public mutating func pauseAtWaypoint() -> TimeInterval { random(2.8...6.5) }
    public mutating func restAfterTrip() -> TimeInterval { random(34...68) }
    public mutating func tripLength() -> Int { Int(random(2...4)) }

    /// Only active interaction pauses this optional decoration. Unread PR
    /// notifications and main-window visibility do not gate movement.
    public static func isEnabled(wandering: Bool, floating: Bool,
                                 committing: Bool, reduceMotion: Bool, interacting: Bool = false) -> Bool {
        wandering && floating && !committing && !reduceMotion && !interacting
    }

    public static func staysRooted(figure: String) -> Bool { figure == "palm" }

    /// A palm catches a gust, topples, pauses, then springs upright. The panel
    /// stays at its saved location; only the drawing rotates within it.
    public static func rootedAngle(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        switch p {
        case ..<0.15: return -8 * sin(p / 0.15 * .pi)
        case ..<0.46: return 76 * ease((p - 0.15) / 0.31)
        case ..<0.58: return 76
        case ..<0.87: return 76 * (1 - ease((p - 0.58) / 0.29))
        default: return -6 * sin((p - 0.87) / 0.13 * .pi)
        }
    }

    /// Alternate the eight poses steadily, advancing four points with each
    /// pose change. No extra planted hold interrupts the walking cadence.
    /// Position and pose share one clock at a gentle 12 points/second.
    public static let poseInterval: TimeInterval = 1.0 / 3.0

    public struct StepSample {
        public let frame: Int
        public let travelled: Double
        public let finished: Bool
    }

    public static func stepSample(distance: Double, elapsed: TimeInterval) -> StepSample {
        let distance = max(0, distance)
        let ticks = Int(floor(max(0, elapsed) / poseInterval + 1e-9))
        let travelled = min(distance, Double(ticks) * 4)
        return StepSample(frame: ticks % 8, travelled: travelled, finished: travelled >= distance)
    }

    /// The final push is clipped to the remaining distance, never beyond the
    /// destination. Long trips keep the same roughly 12-point/second pace.
    public static func travelTime(from start: CGPoint, to end: CGPoint) -> TimeInterval {
        let pushes = Int(ceil(hypot(end.x - start.x, end.y - start.y) / 4))
        guard pushes > 0 else { return 0 }
        return Double(pushes) * poseInterval
    }

    public static func facesLeft(from start: CGPoint, to end: CGPoint) -> Bool {
        end.x < start.x - 4
    }

    private mutating func random(_ range: ClosedRange<Double>) -> Double {
        // xorshift64*: repeatable for tests, inexpensive enough for a waypoint.
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        let bits = randomState &* 0x2545F4914F6CDD1D
        let unit = Double(bits >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}

private extension CGPoint {
    var roundedToPixel: CGPoint { CGPoint(x: floor(x), y: floor(y)) }
}
