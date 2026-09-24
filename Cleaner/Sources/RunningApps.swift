import AppKit
import CleanerKit

/// What macOS reports as running right now.
///
/// Background agents are included on purpose: a helper nobody sees in the
/// Dock still holds its cache open.
enum SystemRunningApps {
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
    }
}
