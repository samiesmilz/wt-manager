import Foundation
import WTManagerKit

@MainActor
final class UpdateChecker: ObservableObject {
    static let repository = URL(string: "https://github.com/samiesmilz/wt-manager")!
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
    @Published private(set) var release: PublishedRelease?
    @Published private(set) var checking = false
    @Published var showStatus = false
    @Published private(set) var status = "Check for updates"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "wtmanager.latestRelease") {
            release = try? JSONDecoder().decode(PublishedRelease.self, from: data)
        }
    }
    /// Read-only render fixture; it never changes persisted update state.
    func loadSnapshotRelease(_ data: Data) {
        release = try? JSONDecoder().decode(PublishedRelease.self, from: data)
    }
    var availableURL: URL? { release?.updateURL(current: Self.currentVersion) }
    func check(manual: Bool = false) {
        if manual { showStatus = true }
        guard !checking else { return }
        let last = defaults.object(forKey: "wtmanager.updateCheckedAt") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= (manual ? 30 : 86400) else {
            if manual { status = availableURL == nil ? "Checked recently · try again shortly" : "Update available" }
            return
        }
        checking = true
        status = "Checking for updates…"
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/samiesmilz/wt-manager/releases/latest")!)
                request.timeoutInterval = 12
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("wt-manager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 {
                    release = nil
                    defaults.removeObject(forKey: "wtmanager.latestRelease")
                    defaults.set(Date(), forKey: "wtmanager.updateCheckedAt")
                    status = "No published releases yet"
                    return
                }
                guard response.statusCode == 200, data.count < 1_000_000 else { throw URLError(.badServerResponse) }
                let candidate = try JSONDecoder().decode(PublishedRelease.self, from: data)
                guard ReleaseVersion(candidate.tagName) != nil, !candidate.draft, !candidate.prerelease else {
                    throw URLError(.cannotParseResponse)
                }
                release = candidate
                defaults.set(data, forKey: "wtmanager.latestRelease")
                defaults.set(Date(), forKey: "wtmanager.updateCheckedAt")
                status = availableURL == nil ? "You’re up to date · v\(Self.currentVersion)" : "\(candidate.tagName) is available"
            } catch {
                // An offline check does not erase a previously discovered update.
                status = "Couldn’t check updates · try again"
            }
        }
    }
}
