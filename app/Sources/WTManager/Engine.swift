import Foundation
import WTManagerKit

/// Runs the wt-manager CLI and decodes one envelope.
///
/// The app owns no opinion about what any of it means: the mood, the ordering
/// and the wording all arrive already decided. That keeps the menu bar and the
/// terminal incapable of disagreeing, which they would otherwise do the first
/// time either learned a new status.
final class Engine {
    /// Measuring disk walks hundreds of gigabytes, so it runs rarely. Counts
    /// are cheap and run often, carrying the last known reclaim total forward
    /// so the gauge does not falsely empty between measurements.
    static let fastInterval: TimeInterval = 5 * 60
    static let diskInterval: TimeInterval = 60 * 60

    private let queue = DispatchQueue(label: "wtmanager.engine", qos: .utility)
    private(set) var lastReclaimKb: Int = 0

    /// Login items have a small PATH. Pick an absolute interpreter shared by
    /// both the refresh and action paths, including Apple Silicon and Intel
    /// Homebrew installs. The source checkout does not contain a Python runtime.
    private var pythonURL: URL? {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                          "/usr/bin/python3"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }

    /// Tell the engine what a delete just changed, so the next counts-only
    /// pass carries the new figure forward instead of the one from before it.
    /// Without this, freeing 65G leaves "250G rebuildable" on the header until
    /// the hourly measure, and the app looks like it did not do the thing it
    /// just reported doing.
    func noteReclaim(_ kb: Int) { lastReclaimKb = max(kb, 0) }

    var scriptURL: URL? {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("engine/wtmanager.py")
            if FileManager.default.isReadableFile(atPath: bundled.path) { return bundled }
        }
        // Running from a checkout rather than an installed bundle.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("wtmanager.py")
        return FileManager.default.isReadableFile(atPath: dev.path) ? dev : nil
    }

    func refresh(measureDisk: Bool, progress: ((Progress) -> Void)? = nil, completion: @escaping (Result<Envelope, Error>) -> Void) {
        queue.async {
            let result = self.run(measureDisk: measureDisk, progress: progress)
            if case .success(let env) = result, env.reclaimKb > 0 {
                self.lastReclaimKb = env.reclaimKb
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func run(measureDisk: Bool, progress: ((Progress) -> Void)?) -> Result<Envelope, Error> {
        guard let script = scriptURL else {
            return .failure(Err("wtmanager.py not found in the bundle"))
        }
        guard let python = pythonURL else {
            return .failure(Err("Python 3 is required. Install it and reopen wt-manager."))
        }
        var args = [script.path, "--progress", "agent"]
        if !measureDisk {
            args += ["--no-size"]
            if lastReclaimKb > 0 { args += ["--reclaim-kb", String(lastReclaimKb)] }
        }
        let task = Process()
        task.executableURL = python
        task.arguments = args
        // A login-item process inherits a minimal PATH, and the engine shells
        // out to git and gh. Without this it reports an empty machine and looks
        // like nothing is in flight, which is the most misleading answer it has.
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        task.environment = env
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do { try task.run() } catch { return .failure(error) }
        let (data, errData) = Self.drain(out, err, progress: progress)
        task.waitUntilExit()
        guard task.terminationStatus == 0, !data.isEmpty else {
            let msg = String(data: errData, encoding: .utf8) ?? "no output"
            return .failure(Err("wt-manager exited \(task.terminationStatus): \(msg.prefix(200))"))
        }
        do { return .success(try JSONDecoder().decode(Envelope.self, from: data)) }
        catch { return .failure(error) }
    }

    /// Runs any subcommand and hands back what it printed.
    ///
    /// Used for the destructive verbs, which are dry runs unless `--yes` is in
    /// the arguments. The UI always runs the dry form first and shows you its
    /// output; nothing here decides on your behalf what a plan means.
    /// Named here for the call sites; defined in the shared module, where a
    /// test can reach it.
    typealias Progress = EngineProgress

    func run(_ args: [String], progress: ((Progress) -> Void)? = nil,
             completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard let script = self.scriptURL else {
                DispatchQueue.main.async { completion(.failure(Err("wtmanager.py not found"))) }
                return
            }
            guard let python = self.pythonURL else {
                DispatchQueue.main.async { completion(.failure(Err("Python 3 is required. Install it and reopen wt-manager."))) }
                return
            }
            let task = Process()
            task.executableURL = python
            // Global flags go before the subcommand; argparse rejects them
            // after it. Appending looks harmless and fails every action.
            // `--progress` is asked for rather than assumed: the engine stays
            // silent for every other caller, so nobody's pipeline gains sixty
            // lines of progress it never wanted.
            task.arguments = [script.path, "--color=never"]
                + (progress == nil ? [] : ["--progress"]) + args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
                + [env["PATH"] ?? ""]).joined(separator: ":")
            task.environment = env
            let out = Pipe(), err = Pipe()
            task.standardOutput = out
            task.standardError = err
            do { try task.run() } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let (data, errData) = Self.drain(out, err, progress: progress)
            task.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let errText = String(data: errData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if task.terminationStatus == 0 {
                    completion(.success(text.isEmpty ? errText : text))
                } else {
                    // Both streams: a refused plan prints its JSON to stdout
                    // and exits 3, and a warning on stderr must not hide it.
                    let both = [text, errText].filter { !$0.isEmpty }.joined(separator: "\n")
                    completion(.failure(Err(both.isEmpty ? "exited \(task.terminationStatus)" : both)))
                }
            }
        }
    }


    /// Drains both pipes at once. Reading stdout to its end and only then
    /// stderr deadlocks the moment stderr fills its 64K buffer: the child blocks
    /// writing stderr, we block reading stdout, and neither moves. A spinner
    /// never gets that far, a traceback does.
    private static func drain(_ out: Pipe, _ err: Pipe,
                              progress: ((Progress) -> Void)? = nil) -> (Data, Data) {
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            // Chunk at a time rather than to the end, so progress arrives
            // while it is still progress. Everything still accumulates: a
            // traceback on this stream is the whole of the error message.
            let handle = err.fileHandleForReading
            var pending = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                errData.append(chunk)
                guard let progress else { continue }
                pending.append(chunk)
                while let nl = pending.firstIndex(of: 0x0a) {
                    let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...nl)
                    if let p = Progress(line: line[...]) {
                        DispatchQueue.main.async { progress(p) }
                    }
                }
            }
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        return (outData, errData)
    }

    struct Err: LocalizedError {
        let msg: String
        init(_ m: String) { msg = m }
        var errorDescription: String? { msg }
    }
}
