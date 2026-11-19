import AppKit
import UserNotifications
import WTManagerKit

/// Notification Center, for the one thing worth interrupting for: a pull
/// request merged, so a folder can go. Asked for only when the switch is
/// turned on, posted only while the window is not in front, and each merge
/// once. Clicking it opens the app; it never deletes anything.
enum Notifier {
    private static let seenKey = "wtmanager.notifiedMerges"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func merged(_ nudge: MergeNudge) {
        var seen: [String] = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        guard !seen.contains(nudge.id) else { return }
        seen.append(nudge.id)
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: seenKey)

        let content = UNMutableNotificationContent()
        content.title = "PR #\(nudge.number) merged"
        content.body = nudge.repo + ": its folder can be reviewed for deletion."
        let request = UNNotificationRequest(identifier: "merge-" + nudge.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension Notifier {
    private static let diskKey = "wtmanager.diskWarnedAt"

    /// How full the startup disk is, 0 to 1, by what macOS says is available
    /// for things a person keeps.
    static func diskUsed() -> Double? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, total > 0,
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return 1 - Double(free) / Double(total)
    }

    /// At most once a day, and only when there is something to do about it.
    static func diskNearlyFull(used: Double, freeable: String?) {
        let last: Double = UserDefaults.standard.double(forKey: diskKey)
        guard Date().timeIntervalSince1970 - last > 86400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: diskKey)
        let content = UNMutableNotificationContent()
        content.title = "Your disk is \(Int((used * 100).rounded()))% full"
        content.body = freeable.map { "wt-manager could free " + $0 + " from worktree folders and caches." }
            ?? "Open wt-manager to see what your worktree folders hold."
        let request = UNNotificationRequest(identifier: "disk-full", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension Store {
    /// Called after each scan, beside the merge announcements.
    func announceDisk() {
        guard systemNotifications, diskNotifications, let used = Notifier.diskUsed(), used >= 0.9 else { return }
        let free: String? = freeable.flatMap { $0.totalKb > 0 ? Store.human($0.totalKb) : nil }
        Notifier.diskNearlyFull(used: used, freeable: free)
    }

    /// Called after each scan. The in-app banner covers the window being
    /// open, so this speaks only when it is not the active app.
    func announceMerges() {
        guard systemNotifications, mergeNudges, !NSApp.isActive else { return }
        for nudge in prLifecycle.pending { Notifier.merged(nudge) }
    }
}
