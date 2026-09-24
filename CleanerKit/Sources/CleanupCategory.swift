import Foundation

/// A junk category: what gets cleaned and what that costs.
public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// What happens after deletion. The user is entitled to know beforehand.
    public let consequence: String
    public let roots: [URL]
    /// How long a finding must sit untouched before it is offered.
    ///
    /// Not a guard against deleting something in use — a running application
    /// is detected directly, which is both more precise and more useful to
    /// read. This is about cost: where a fresh timestamp means the user just
    /// paid to download or build something large, throwing it away the same
    /// day is rarely what they meant.
    ///
    /// Zero everywhere else, and deliberately so. A cache directory's
    /// timestamp moves whenever anything inside it is touched, so a blanket
    /// rule here holds back nearly everything and quietly turns a category
    /// off — measured, not guessed.
    public let minimumIdleDays: Int

    public init(id: String, title: String, consequence: String, roots: [URL],
                minimumIdleDays: Int = 0) {
        self.id = id
        self.title = title
        self.consequence = consequence
        self.roots = roots
        self.minimumIdleDays = minimumIdleDays
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
                ],
                minimumIdleDays: 1
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
            // Deliberately not the whole workspace: wiping it during a build
            // in flight breaks that build. Test bundles and logs are the bulk
            // of the size anyway, and DerivedData and state stay put.
            CleanupCategory(
                id: "xcodeBuildMCP",
                title: kitString("XcodeBuildMCP test products and logs"),
                consequence: kitString("Finished test runs; build state stays in place"),
                roots: listing(home.appending(path: "Library/Developer/XcodeBuildMCP/workspaces"))
                    .flatMap { [$0.appending(path: "test-products"), $0.appending(path: "logs")] }
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
                    "notion-updater", "Jedi", "com.apple.helpd", "GeoServices",
                ].map { home.appending(path: "Library/Caches/\($0)") }
            ),
            CleanupCategory(
                id: "agentBuilds",
                title: kitString("Simulator builds made by Claude"),
                consequence: kitString("Recreated the next time the app is built"),
                roots: [home.appending(path: "Library/Application Support/Claude/simulator-builds")]
            ),
            CleanupCategory(
                id: "agentVM",
                title: kitString("Claude sandbox virtual machine"),
                consequence: kitString("Several gigabytes will be downloaded again on next use"),
                roots: [home.appending(path: "Library/Application Support/Claude/vm_bundles")],
                minimumIdleDays: 7
            ),
            // A search by name rather than a list of applications: the same
            // handful of directory names covers every Chromium and Electron
            // app on the Mac, including ones installed after this was written.
            CleanupCategory(
                id: "desktopAppCaches",
                title: kitString("Caches inside application data"),
                consequence: kitString("Applications rebuild these; settings and documents stay"),
                roots: find(named: chromiumCacheNames,
                            under: home.appending(path: "Library/Application Support"),
                            depth: 4, listing: listing)
                    + ["Code/CachedExtensionVSIXs", "Code/CachedData"]
                        .map { home.appending(path: "Library/Application Support/\($0)") }
            ),
            CleanupCategory(
                id: "sandboxedAppCaches",
                title: kitString("Caches of sandboxed applications"),
                consequence: kitString("Applications rebuild these on next launch"),
                roots: listing(home.appending(path: "Library/Containers"))
                    .map { $0.appending(path: "Data/Library/Caches") }
            ),
            CleanupCategory(
                id: "modelCaches",
                title: kitString("Downloaded models and runtimes"),
                consequence: kitString("Downloaded again on demand, which can take a while"),
                roots: [
                    home.appending(path: ".cache/huggingface"),
                    home.appending(path: ".cache/codex-runtimes"),
                    home.appending(path: ".cache/uv"),
                ],
                minimumIdleDays: 7
            ),
            CleanupCategory(
                id: "logs",
                title: kitString("Application logs"),
                consequence: kitString("Only useful while diagnosing a problem"),
                roots: [home.appending(path: "Library/Logs")]
            ),
            CleanupCategory(
                id: "appUpdaters",
                title: kitString("Downloaded application updates"),
                consequence: kitString("Installers for updates already applied; downloaded again if needed"),
                roots: listing(home.appending(path: "Library/Caches"))
                    .filter { $0.lastPathComponent.hasSuffix(".ShipIt") },
                minimumIdleDays: 1
            ),
        ]
    }

    /// Directory names Chromium and Electron give their caches. Every desktop
    /// application built on them uses the same ones, which is why a search by
    /// name reaches dozens of applications that a list of names never would.
    static let chromiumCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "ShaderCache", "GrShaderCache",
        "DawnGraphiteCache", "DawnWebGPUCache", "CacheStorage", "ScriptCache",
    ]

    /// Directories with one of these names, anywhere down to `depth` below
    /// `root`. A match ends the descent: caches do not nest inside caches, and
    /// walking into one would only find the files we are already going to
    /// count through its parent.
    static func find(named names: Set<String>, under root: URL, depth: Int,
                     listing: (URL) -> [URL]) -> [URL] {
        guard depth > 0 else { return [] }
        var found: [URL] = []
        for child in listing(root) {
            if names.contains(child.lastPathComponent) {
                found.append(child)
            } else {
                found += find(named: names, under: child, depth: depth - 1, listing: listing)
            }
        }
        return found
    }

    /// Subdirectories only. Everything the catalog looks for is a directory,
    /// and descending into files would multiply the work for nothing.
    public static func contentsOfDirectory(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
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
            "Projects",                                // source code, never junk
            "Library/Mobile Documents",                // iCloud Drive
            "Library/Photos", "Library/Mail", "Library/Messages",
            "Library/Keychains",
            "Library/Application Support/MobileSync",  // device backups
            "Library/Developer/Xcode/Archives",        // shipped releases
            "Library/Developer/Xcode/UserData",        // schemes, snippets, breakpoints
            ".ssh",
            ".Trash",                                  // what we already moved
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
