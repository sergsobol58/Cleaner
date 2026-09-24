import AppKit
import CleanerKit

/// What the system says is installed.
enum SystemApplications {
    /// Places an application bundle normally lives. Anything installed
    /// elsewhere is still found through LaunchServices.
    private static let searched = [
        "/Applications", "/System/Applications", "/System/Library/CoreServices",
        NSHomeDirectory() + "/Applications",
    ]

    static func installed() -> InstalledApplications {
        // If the system cannot find Finder, the answer to every other lookup
        // is worthless too — and acting on it would call the whole Library
        // abandoned. Claim everything and report nothing.
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.finder") != nil else { return .everything }

        return InstalledApplications(bundleIDs: bundleIDs(), lookup: Cache().claims)
    }

    private static func bundleIDs() -> Set<String> {
        var found: Set<String> = []
        for directory in searched {
            guard let walker = FileManager.default.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }

            for case let url as URL in walker where url.pathExtension == "app" {
                walker.skipDescendants()
                if let id = Bundle(url: url)?.bundleIdentifier { found.insert(id) }
            }
        }
        return found
    }
}

/// LaunchServices is asked about the same identifiers repeatedly — once per
/// candidate and again for each of its prefixes.
private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Bool] = [:]

    func claims(_ id: String) -> Bool {
        lock.lock()
        if let known = answers[id] {
            lock.unlock()
            return known
        }
        lock.unlock()

        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil

        lock.lock()
        answers[id] = found
        lock.unlock()
        return found
    }
}
