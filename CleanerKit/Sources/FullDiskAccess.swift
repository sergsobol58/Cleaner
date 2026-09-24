import Foundation

/// Whether macOS is letting this app look inside the directories it keeps
/// behind a permission prompt.
///
/// Without the permission a scan quietly under-reports: unreadable folders
/// look exactly like empty ones, and the user is told the Mac is clean when
/// nobody actually looked.
public enum FullDiskAccess {
    /// Folders every Mac has and nothing but Full Disk Access opens.
    public static func probes(home: URL) -> [URL] {
        ["Library/Safari", "Library/Mail", "Library/Messages"]
            .map { home.appending(path: $0) }
    }

    /// Unknown counts as granted. A probe that is simply absent proves
    /// nothing, and nagging on no evidence is worse than staying quiet.
    public static func isGranted(
        home: URL,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        canRead: (URL) -> Bool = Self.canRead
    ) -> Bool {
        let present = probes(home: home).filter(exists)
        guard !present.isEmpty else { return true }
        return present.contains(where: canRead)
    }

    public static func canRead(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) != nil
    }

    /// The Privacy pane that grants it.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
