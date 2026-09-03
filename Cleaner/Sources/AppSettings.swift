import AppKit
import Observation

/// Preferences that outlive a launch.
@MainActor
@Observable
final class AppSettings {
    enum Key {
        static let runsInBackground = "runsInBackground"
    }

    /// In background mode the app lives in the menu bar only and drops its
    /// Dock icon. The window still opens from the menu; it simply no longer
    /// has a Dock tile or a Cmd-Tab entry behind it.
    var runsInBackground: Bool {
        didSet {
            UserDefaults.standard.set(runsInBackground, forKey: Key.runsInBackground)
            applyActivationPolicy()
        }
    }

    init() {
        runsInBackground = UserDefaults.standard.bool(forKey: Key.runsInBackground)
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(runsInBackground ? .accessory : .regular)
    }
}
