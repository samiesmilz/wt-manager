import AppKit

/// The terminal and editor a folder is handed to. Only apps that are
/// installed are offered; Terminal is always there to fall back on.
enum OpenWith {
    struct App: Identifiable, Hashable {
        let id: String      // bundle identifier
        let name: String
    }

    static let terminals: [App] = [
        App(id: "com.apple.Terminal", name: "Terminal"),
        App(id: "com.googlecode.iterm2", name: "iTerm"),
        App(id: "com.mitchellh.ghostty", name: "Ghostty"),
        App(id: "dev.warp.Warp-Stable", name: "Warp"),
        App(id: "net.kovidgoyal.kitty", name: "kitty"),
        App(id: "org.alacritty", name: "Alacritty"),
    ]

    static let editors: [App] = [
        App(id: "com.microsoft.VSCode", name: "Visual Studio Code"),
        App(id: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        App(id: "dev.zed.Zed", name: "Zed"),
        App(id: "com.exafunction.windsurf", name: "Windsurf"),
        App(id: "com.sublimetext.4", name: "Sublime Text"),
        App(id: "com.panic.Nova", name: "Nova"),
        App(id: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    static func installed(_ apps: [App]) -> [App] {
        apps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    /// False when the app is not installed, so the caller can fall back.
    @discardableResult
    static func open(_ path: String, with bundle: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return false }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
