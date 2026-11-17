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

extension Store {
    /// Called after each scan. The in-app banner covers the window being
    /// open, so this speaks only when it is not the active app.
    func announceMerges() {
        guard systemNotifications, mergeNudges, !NSApp.isActive else { return }
        for nudge in prLifecycle.pending { Notifier.merged(nudge) }
    }
}
