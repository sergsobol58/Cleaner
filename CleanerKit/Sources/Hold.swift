import Foundation

/// Why a finding is listed but not offered for removal.
///
/// Two different risks share one mechanism on purpose: the user sees the
/// reason next to the row instead of a checkbox that silently refuses.
public enum Hold: Sendable, Equatable, Hashable {
    /// The application this path belongs to is running. Pulling a cache out
    /// from under a running app can corrupt what it still holds open.
    case appRunning(String)
    /// Changed so recently that calling it leftovers would be a guess.
    case changedRecently

    public var reason: String {
        switch self {
        case .appRunning(let app): kitString("\(app) is running")
        case .changedRecently:     kitString("changed recently")
        }
    }
}

/// An application the system reports as running.
public struct RunningApp: Sendable, Equatable, Hashable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Which running application a path belongs to, when the path itself says so.
///
/// Only the first component below a per-application directory counts. A path
/// like `Library/Containers/com.apple.Safari/…` names its owner outright,
/// while `Library/Developer/Xcode/DerivedData/…` names nobody — and guessing
/// there would hold back far more than it protects.
public enum AppAttribution {
    /// Directories macOS gives every application a folder of its own inside.
    private static let perAppDirectories = [
        "Library/Containers",
        "Library/Group Containers",
        "Library/Application Support",
        "Library/Caches",
        "Library/Logs",
        "Library/HTTPStorages",
        "Library/Saved Application State",
    ]

    public static func owner(of url: URL, among running: [RunningApp], home: URL) -> RunningApp? {
        guard let folder = folderName(of: url, home: home) else { return nil }
        let needle = normalise(folder)
        guard !needle.isEmpty else { return nil }
        return running.first { app in
            needle == app.bundleID.lowercased()
                || needle == app.name.lowercased()
                || needle == app.bundleID.split(separator: ".").last?.lowercased()
        }
    }

    /// The application folder a path sits in, or nil when it sits in none.
    private static func folderName(of url: URL, home: URL) -> String? {
        let path = url.standardizedFileURL.pathComponents
        for directory in perAppDirectories {
            let prefix = home.appending(path: directory).standardizedFileURL.pathComponents
            guard path.count > prefix.count,
                  Array(path.prefix(prefix.count)) == prefix else { continue }
            return path[prefix.count]
        }
        return nil
    }

    /// Group containers carry a team prefix, and some carry "group." as well;
    /// neither belongs to the application's own name.
    private static func normalise(_ folder: String) -> String {
        var name = folder.lowercased()
        if name.hasPrefix("group.") { name.removeFirst("group.".count) }
        let head = name.prefix(while: { $0 != "." })
        if head.count == 10, head.allSatisfy({ $0.isLetter || $0.isNumber }),
           folder.prefix(10).allSatisfy({ !$0.isLowercase }) {
            name.removeFirst(head.count + 1)
            if name.hasPrefix("group.") { name.removeFirst("group.".count) }
        }
        return name
    }
}
