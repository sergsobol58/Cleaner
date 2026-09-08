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
                        "modelCaches", "logs", "appUpdaters"])
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
