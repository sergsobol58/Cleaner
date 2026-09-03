import Foundation

/// A junk category: what gets cleaned and what that costs.
public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// What happens after deletion. The user is entitled to know beforehand.
    public let consequence: String
    public let roots: [URL]

    public init(id: String, title: String, consequence: String, roots: [URL]) {
        self.id = id
        self.title = title
        self.consequence = consequence
        self.roots = roots
    }
}

/// What we clean and what we protect.
///
/// `home` is a parameter rather than being read from `FileManager`: otherwise
/// the tests would have to run against the user's real directory.
public enum Catalog {
    /// `listing` is substituted in tests: some roots are derived from the
    /// actual contents of a directory, and a test must not depend on whatever
    /// happens to be on someone's machine.
    public static func standard(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> [CleanupCategory] {
        [
            CleanupCategory(
                id: "derivedData",
                title: kitString("Xcode DerivedData"),
                consequence: kitString("The next build takes longer; projects get reindexed"),
                roots: [home.appending(path: "Library/Developer/Xcode/DerivedData")]
            ),
            CleanupCategory(
                id: "deviceSupport",
                title: kitString("Symbols of connected devices"),
                consequence: kitString("Downloaded again the next time a device is connected"),
                roots: [
                    home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"),
                    home.appending(path: "Library/Developer/Xcode/watchOS DeviceSupport"),
                    home.appending(path: "Library/Developer/Xcode/tvOS DeviceSupport"),
                ]
            ),
            CleanupCategory(
                id: "packageCaches",
                title: kitString("Package manager caches"),
                consequence: kitString("The next package install takes longer"),
                roots: [
                    home.appending(path: ".npm/_cacache"),
                    home.appending(path: "Library/Caches/Yarn"),
                    home.appending(path: "Library/pnpm/store"),
                    home.appending(path: "Library/Caches/pip"),
                    home.appending(path: "Library/Caches/CocoaPods"),
                    home.appending(path: ".gradle/caches"),
                ]
            ),
            CleanupCategory(
                id: "xcodeBuildMCP",
                title: kitString("XcodeBuildMCP workspaces"),
                consequence: kitString("Recreated on the next build through MCP"),
                roots: [home.appending(path: "Library/Developer/XcodeBuildMCP/workspaces")]
            ),
            CleanupCategory(
                id: "swiftPM",
                title: kitString("SwiftPM and documentation cache"),
                consequence: kitString("Packages and documentation are downloaded again"),
                roots: [
                    home.appending(path: "Library/Caches/org.swift.swiftpm"),
                    home.appending(path: "Library/Developer/Xcode/DocumentationCache"),
                ]
            ),
            CleanupCategory(
                id: "appCaches",
                title: kitString("Application caches"),
                consequence: kitString("Applications rebuild their cache on next launch"),
                roots: [
                    "com.apple.dt.Xcode", "JetBrains", "com.microsoft.VSCode",
                    "Google", "Homebrew", "ms-playwright", "ms-playwright-go",
                    "typescript", "node-gyp", "electron", "Cypress",
                    "com.openai.codex", "antigravity-updater",
                ].map { home.appending(path: "Library/Caches/\($0)") }
            ),
            CleanupCategory(
                id: "appUpdaters",
                title: kitString("Downloaded application updates"),
                consequence: kitString("Installers for updates already applied; downloaded again if needed"),
                roots: listing(home.appending(path: "Library/Caches"))
                    .filter { $0.lastPathComponent.hasSuffix(".ShipIt") }
            ),
        ]
    }

    public static func contentsOfDirectory(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) ?? []
    }

    /// Only category roots are allowed. The root itself cannot be deleted —
    /// `PathGuard` rejects it as `isRootItself` — but its contents can.
    public static func allowedRoots(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> [URL] {
        standard(home: home, listing: listing).flatMap(\.roots)
    }

    /// Never touched, even when the path falls inside an allowed root.
    public static func deniedPaths(home: URL) -> [URL] {
        [
            "Documents", "Desktop", "Downloads",
            "Library/Mobile Documents",                // iCloud Drive
            "Library/Photos", "Library/Mail", "Library/Messages",
            "Library/Keychains",
            "Library/Application Support/MobileSync",  // device backups
            "Library/Developer/Xcode/Archives",        // shipped releases
            "Library/Developer/Xcode/UserData",        // schemes, snippets, breakpoints
            ".ssh",
        ].map { home.appending(path: $0) }
    }

    public static func pathGuard(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> PathGuard {
        PathGuard(allowedRoots: allowedRoots(home: home, listing: listing),
                  deniedPaths: deniedPaths(home: home))
    }
}
