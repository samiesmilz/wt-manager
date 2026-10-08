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
        let minimumHop = min(150, hypot(maxX - minX, maxY - minY) * 0.22)
        for _ in 0..<10 {
            let candidate = CGPoint(x: random(minX...maxX), y: random(minY...maxY))
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

    /// A relaxed pixel-pet pace, with a ceiling for ultrawide displays.
    public static func travelTime(from start: CGPoint, to end: CGPoint) -> TimeInterval {
        min(8.5, max(1.8, hypot(end.x - start.x, end.y - start.y) / 150))
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
