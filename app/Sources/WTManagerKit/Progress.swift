import Foundation

/// How far along the engine says it is.
///
/// Lives in the shared module rather than beside the process that spawns it
/// because it is a *parser*, and a parser of a line format two programs have
/// to agree on is the one piece of this worth a test. The executable target
/// cannot be imported by tests; this can.
public struct EngineProgress: Equatable {
    /// The tag the engine writes. Anything on stderr that does not start with
    /// it is a warning or a traceback and is left alone.
    public static let tag = "wt-progress"

    public let done: Int
    public let total: Int
    /// Which pass of the run this is, 1-based, and how many there are.
    ///
    /// A run is several bars, not one: reading the repos, measuring them, then
    /// doing the thing you approved. The second cannot be counted before the
    /// first has finished, so they cannot honestly share a scale — and a bar
    /// that empties and refills under an unchanged heading is the most
    /// reliable way a working process has of looking broken.
    public let step: Int
    public let steps: Int
    public let label: String

    public init(done: Int, total: Int, step: Int = 1, steps: Int = 1, label: String) {
        self.done = done
        self.total = total
        self.step = step
        self.steps = steps
        self.label = label
    }

    /// `wt-progress <done> <total> <step> <steps> <label…>`. The label may be
    /// empty and may contain spaces, so it takes the whole of the rest of the
    /// line.
    public init?(line: Substring) {
        let f = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: false)
        guard f.count >= 5, f[0] == Self.tag,
              let d = Int(f[1]), let t = Int(f[2]),
              let st = Int(f[3]), let sts = Int(f[4]),
              d >= 0, t >= 0, st >= 1, sts >= 1, st <= sts else { return nil }
        done = d
        total = t
        step = st
        steps = sts
        label = f.count > 5 ? String(f[5]) : ""
    }

    /// Shown only when there is more than one pass. "Step 1 of 1" is noise.
    public var stepCaption: String? { steps > 1 ? "Step \(step) of \(steps)" : nil }

    /// `nil` when the engine does not know a total. That is a real state and
    /// not a zero: a bar sitting at 0% says "stuck", an indeterminate one says
    /// "working", and only one of those is true.
    public var fraction: Double? {
        total > 0 ? Swift.min(1, Double(done) / Double(total)) : nil
    }
}
