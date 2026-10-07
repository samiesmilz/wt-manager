import Foundation

/// Saved coordinates belong to an old display layout. Recover onto a current
/// display when a monitor disappears, and keep the whole drag target reachable.
public enum FloatingPlacement {
    public static func frame(origin: CGPoint?, size: CGSize, screens: [CGRect]) -> CGRect {
        let screens = screens.filter { !$0.isEmpty && !$0.isNull }
        let fallback = screens.first ?? CGRect(x: 0, y: 0, width: 1440, height: 850)
        let initial = CGPoint(x: fallback.maxX - size.width - 32, y: fallback.minY + 64)
        let point = origin.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil } ?? initial
        let candidate = CGRect(origin: point, size: size)
        let screen = screens.max { a, b in
            area(a.intersection(candidate)) < area(b.intersection(candidate))
        }.flatMap { area($0.intersection(candidate)) > 0 ? $0 : nil } ?? fallback
        let p = area(screen.intersection(candidate)) > 0 ? point : initial
        return CGRect(x: min(max(p.x, screen.minX), max(screen.minX, screen.maxX - size.width)),
                      y: min(max(p.y, screen.minY), max(screen.minY, screen.maxY - size.height)),
                      width: size.width, height: size.height)
    }
    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
