import XCTest
@testable import CleanerKit

final class CatalogTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/testuser", isDirectory: true)

    /// An empty listing: the test must not depend on someone else's Caches.
    private func categories() -> [CleanupCategory] {
        Catalog.standard(home: home, listing: { _ in [] })
    }

    func testHasExpectedCategories() {
        XCTAssertEqual(categories().map(\.id),
                       ["derivedData", "deviceSupport", "packageCaches",
                        "xcodeBuildMCP", "swiftPM", "appCaches",
                        "agentBuilds", "agentVM", "desktopAppCaches",
                        "sandboxedAppCaches", "modelCaches", "logs",
                        "leftovers", "appUpdaters"])
    }

    /// The whole workspace must not be a root: wiping it during a build in
    /// flight breaks that build, so only finished products and logs are named.
    func testMCPCategoryTargetsProductsAndLogsRatherThanWholeWorkspaces() {
        let workspaces = home.appending(path: "Library/Developer/XcodeBuildMCP/workspaces")
        let found = Catalog.standard(home: home, listing: { directory in
            directory == workspaces ? [workspaces.appending(path: "proj-abc")] : []
        }).first { $0.id == "xcodeBuildMCP" }

        XCTAssertEqual(found?.roots.map { $0.pathComponents.suffix(2).joined(separator: "/") },
                       ["proj-abc/test-products", "proj-abc/logs"])
        XCTAssertFalse(found?.roots.contains(workspaces) ?? true,
                       "the workspaces directory itself must never be a root")
    }

    /// Measured, not assumed: a cache directory's timestamp moves whenever
    /// anything inside it is touched, so a blanket age rule held back every
    /// finding in these categories and quietly turned them off.
    func testCacheCategoriesCarryNoAgeRule() {
        let byID = Dictionary(uniqueKeysWithValues: categories().map { ($0.id, $0) })
        for id in ["packageCaches", "swiftPM", "appCaches", "desktopAppCaches", "logs"] {
            XCTAssertEqual(byID[id]?.minimumIdleDays, 0,
                           "\(id) must rely on the running-app check, not on a timestamp")
        }
    }

    /// Where a fresh timestamp means the user just paid for a large download,
    /// throwing it away the same day is rarely what they meant.
    func testExpensiveCategoriesWaitBeforeOffering() {
        let byID = Dictionary(uniqueKeysWithValues: categories().map { ($0.id, $0) })
        XCTAssertEqual(byID["modelCaches"]?.minimumIdleDays, 7)
        XCTAssertEqual(byID["agentVM"]?.minimumIdleDays, 7)
    }

    /// One place must belong to one category. Two categories sharing a root
    /// would count the same bytes twice and let the user tick the same files
    /// in two places.
    func testNoRootBelongsToTwoCategories() {
        var owner: [URL: String] = [:]
        for category in categories() {
            for root in category.roots {
                if let taken = owner[root] {
                    XCTFail("\(root.path) is claimed by both \(taken) and \(category.id)")
                }
                owner[root] = category.id
            }
        }
    }

    func testUpdaterCategoryTakesOnlyShipItDirectories() {
        let caches = home.appendingPathComponent("Library/Caches")
        let found = Catalog.standard(home: home, listing: { _ in [
            caches.appendingPathComponent("com.microsoft.VSCode.ShipIt"),
            caches.appendingPathComponent("SomethingElse"),
            caches.appendingPathComponent("Slack.ShipIt"),
        ]}).first { $0.id == "appUpdaters" }

        XCTAssertEqual(found?.roots.map(\.lastPathComponent),
                       ["com.microsoft.VSCode.ShipIt", "Slack.ShipIt"])
    }

    /// A watchdog: CleanerKit once declared its own "/" operator, which made
    /// ordinary division ambiguous for everyone importing the module. This
    /// test catches its return.
    func testModuleDoesNotBreakArithmetic() {
        let bytes: Int64 = 8_388_608
        XCTAssertEqual(bytes / 1_048_576, 8)
        XCTAssertEqual(Double(3) / Double(2), 1.5)
    }

    func testEveryRootLivesInsideGivenHome() {
        for category in categories() {
            for root in category.roots {
                XCTAssertTrue(root.path.hasPrefix(home.path),
                              "\(category.id): root \(root.path) lies outside the given home")
            }
        }
    }

    /// A category with several roots — the reason packageCaches is in the
    /// first version at all: it proves the model copes with that.
    func testPackageCachesHasSeveralRoots() {
        let category = categories().first { $0.id == "packageCaches" }
        XCTAssertGreaterThan(category?.roots.count ?? 0, 3)
    }

    func testEveryCategoryExplainsConsequence() {
        for category in categories() {
            XCTAssertFalse(category.title.isEmpty, "\(category.id): empty title")
            XCTAssertFalse(category.consequence.isEmpty, "\(category.id): consequence not stated")
        }
    }

    /// A category root must never be removed, only its contents.
    func testGuardRejectsRootsButAllowsTheirChildren() {
        let sut = Catalog.pathGuard(home: home, listing: { _ in [] })
        for category in categories() {
            for root in category.roots {
                XCTAssertEqual(sut.validate(root), .failure(.isRootItself),
                               "\(category.id): root \(root.lastPathComponent) must be protected")

                // The child does not exist, so validation must reach exactly
                // the existence check — meaning it cleared every prohibition.
                let child = root.appendingPathComponent("something")
                XCTAssertEqual(sut.validate(child), .failure(.doesNotExist),
                               "\(category.id): contents of \(root.lastPathComponent) must be allowed")
            }
        }
    }

    func testGuardProtectsUserData() {
        let sut = Catalog.pathGuard(home: home, listing: { _ in [] })
        for unsafe in ["Documents", "Desktop", "Downloads", "Projects",
                       "Library/Mobile Documents",
                       "Library/Keychains", ".ssh", "Library/Developer/Xcode/Archives",
                       "Library/Developer/Xcode/UserData"] {
            XCTAssertEqual(sut.validate(home.appendingPathComponent(unsafe)), .failure(.inDenyList),
                           "\(unsafe) must be on the never-touch list")
        }
    }
}

final class CacheSweepTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/test/Library/Application Support")

    /// A tree shaped like the real one: an Electron app keeps caches two
    /// levels down inside a partition, not only beside its data.
    private func tree(_ url: URL) -> [URL] {
        let map: [String: [String]] = [
            "Application Support": ["Notion", "Figma", "Boring"],
            "Notion": ["Partitions", "Cache"],
            "Partitions": ["notion"],
            "notion": ["Cache", "Code Cache", "IndexedDB"],
            "Figma": ["DesktopProfile"],
            "DesktopProfile": ["v42"],
            "v42": ["GPUCache"],
            "Boring": ["Documents"],
        ]
        return (map[url.lastPathComponent] ?? []).map { url.appending(path: $0) }
    }

    private func sweep(depth: Int) -> [String] {
        Catalog.find(named: Catalog.chromiumCacheNames, under: root,
                     depth: depth, listing: tree)
            .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
    }

    func testFindsCachesAtEveryDepthAndLeavesDataAlone() {
        XCTAssertEqual(Set(sweep(depth: 4)), [
            "Notion/Cache",
            "Notion/Partitions/notion/Cache",
            "Notion/Partitions/notion/Code Cache",
            "Figma/DesktopProfile/v42/GPUCache",
        ])
    }

    /// Chromium nests a "Code Cache" inside "Cache". Reporting both would
    /// count the same files twice, through the parent and again on their own.
    func testAMatchEndsTheDescent() {
        let nested = Catalog.find(named: Catalog.chromiumCacheNames, under: root, depth: 4) { url in
            switch url.lastPathComponent {
            case "Application Support": [url.appending(path: "App")]
            case "App":                 [url.appending(path: "Cache")]
            case "Cache":               [url.appending(path: "Code Cache")]
            default:                    []
            }
        }
        XCTAssertEqual(nested.map(\.lastPathComponent), ["Cache"])
    }

    func testDepthIsRespected() {
        XCTAssertEqual(Set(sweep(depth: 2)), ["Notion/Cache"])
    }
}
