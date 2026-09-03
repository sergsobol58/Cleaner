import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `WindowGroup` opens a window at launch regardless of our preferences.
    /// In background mode that contradicts the whole point, so the launch
    /// window is closed and the Dock icon dropped before it can settle in.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: AppSettings.Key.runsInBackground) else { return }

        NSApp.setActivationPolicy(.accessory)
        for window in NSApp.windows where window.canBecomeMain {
            window.close()
        }
    }

    /// Closing the window must not quit the app: the menu bar item stays,
    /// and quitting is an explicit choice in the panel.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
