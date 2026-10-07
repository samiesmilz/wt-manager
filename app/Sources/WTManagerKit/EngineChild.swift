import Foundation

/// One owner for every engine child, including refreshes and operation previews.
/// The caller must refuse shutdown while a destructive operation is committing.
public final class EngineChild {
    private let lock = NSLock()
    private var running: Process?
    private var stopping = false
    public init() {}
    public func launch(_ task: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !stopping else { throw CancellationError() }
        try task.run()
        running = task
    }
    public func finished() {
        lock.lock(); defer { lock.unlock() }
        running = nil
    }
    public func shutdown() {
        lock.lock(); defer { lock.unlock() }
        stopping = true
        if running?.isRunning == true { running?.terminate() }
    }
}
