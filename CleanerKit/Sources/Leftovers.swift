import Foundation

/// What the system can still find.
///
/// Injected rather than read from the system, so a test never depends on what
/// happens to be installed on the machine running it. The default claims
/// everything: if the wiring is ever missing, nothing is called a leftover.
public struct InstalledApplications: Sendable {
    private let bundleIDs: Set<String>
    private let lookup: @Sendable (String) -> Bool

    public static let everything = InstalledApplications(bundleIDs: [], lookup: { _ in true })

    public init(bundleIDs: Set<String>, lookup: @escaping @Sendable (String) -> Bool) {
        self.bundleIDs = Set(bundleIDs.map { $0.lowercased() })
        self.lookup = lookup
    }

    /// Whether anything installed answers to this identifier.
    ///
    /// Matching runs both ways on purpose. A group container named `dev.warp`
    /// belongs to an application whose identifier is `dev.warp.Warp-Stable`,
    /// and an extension named `notion.id.NotionSafariExtension` belongs to
    /// `notion.id`. Checking only for an exact identifier calls both of them
    /// abandoned while their application sits in the Dock.
    public func claims(_ id: String) -> Bool {
        if id.hasPrefix("com.apple.") { return true }
        if lookup(id) { return true }
        return bundleIDs.contains { $0 == id || $0.hasPrefix(id + ".") || id.hasPrefix($0 + ".") }
    }
}

/// Data an application left behind when it was removed.
public enum Leftovers {
    /// How long something must sit untouched before absence of the
    /// application is taken as proof rather than suspicion. Measured: below
    /// this, the list fills with live command line tools and helpers that
    /// simply have no `.app` for the system to find.
    public static let idleDays = 180

    /// The bundle identifier a directory name carries, or nil when the name
    /// is not shaped like one.
    ///
    /// Only these names are ever considered. A folder called `Notion` cannot
    /// be checked against anything, and guessing from an application's name
    /// is how a cleaner deletes the data of software you still use.
    public static func identifier(in name: String) -> String? {
        var text = name
        for suffix in [".savedState", ".binarycookies", ".plist"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        text = stripTeamPrefix(text)
        if text.hasPrefix("group.") { text.removeFirst("group.".count) }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return text.lowercased()
    }

    public static func isOrphan(name: String, modified: Date, now: Date,
                                installed: InstalledApplications) -> Bool {
        guard let id = identifier(in: name), !installed.claims(id) else { return false }
        return now.timeIntervalSince(modified) >= Double(idleDays) * 86_400
    }

    /// Group containers are prefixed with the developer's team identifier,
    /// which is ten upper-case characters and no part of the application's
    /// own name.
    private static func stripTeamPrefix(_ text: String) -> String {
        guard let dot = text.firstIndex(of: "."),
              text.distance(from: text.startIndex, to: dot) == 10,
              text[text.startIndex..<dot].allSatisfy({ $0.isUppercase || $0.isNumber })
        else { return text }
        return String(text[text.index(after: dot)...])
    }
}
