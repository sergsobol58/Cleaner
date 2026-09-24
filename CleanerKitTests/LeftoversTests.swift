import XCTest
@testable import CleanerKit

final class LeftoverIdentifierTests: XCTestCase {
    func testPlainBundleIdentifier() {
        XCTAssertEqual(Leftovers.identifier(in: "com.microsoft.teams"), "com.microsoft.teams")
    }

    func testDropsTheTeamPrefixOfAGroupContainer() {
        XCTAssertEqual(Leftovers.identifier(in: "UBF8T346G9.com.microsoft.teams"),
                       "com.microsoft.teams")
        XCTAssertEqual(Leftovers.identifier(in: "group.com.microsoft.teams"),
                       "com.microsoft.teams")
    }

    func testDropsTheSuffixesMacOSAppends() {
        XCTAssertEqual(Leftovers.identifier(in: "com.microsoft.teams.savedState"),
                       "com.microsoft.teams")
        XCTAssertEqual(Leftovers.identifier(in: "com.epson.InstallNavi.binarycookies"),
                       "com.epson.installnavi")
    }

    /// The whole feature rests on this: a folder that is not named after a
    /// bundle identifier is never judged, because there is nothing to judge
    /// it against.
    func testNamesThatAreNotIdentifiersAreNeverConsidered() {
        for name in ["Notion", "Figma", "My Stuff", "com.foo", "a..b", ""] {
            XCTAssertNil(Leftovers.identifier(in: name), name)
        }
    }
}

final class InstalledApplicationsTests: XCTestCase {
    private func installed(_ ids: [String]) -> InstalledApplications {
        InstalledApplications(bundleIDs: Set(ids), lookup: { _ in false })
    }

    func testExactMatchIsClaimed() {
        XCTAssertTrue(installed(["dev.warp.warp-stable"]).claims("dev.warp.warp-stable"))
    }

    /// Warp's group container is `dev.warp`; the application answers to
    /// `dev.warp.Warp-Stable`. Matching one way calls a live app abandoned.
    func testAnInstalledIdentifierThatExtendsTheFolderNameClaimsIt() {
        XCTAssertTrue(installed(["dev.warp.warp-stable"]).claims("dev.warp"))
    }

    /// The other direction: a Safari extension's folder extends its host.
    func testAnInstalledHostClaimsItsExtension() {
        XCTAssertTrue(installed(["notion.id"]).claims("notion.id.notionsafariextension"))
    }

    func testAppleIdentifiersAreAlwaysClaimed() {
        XCTAssertTrue(installed([]).claims("com.apple.somethingorother"))
    }

    func testSomethingNobodyAnswersToIsNotClaimed() {
        XCTAssertFalse(installed(["dev.warp.warp-stable"]).claims("com.microsoft.teams"))
    }

    /// If the wiring is ever missing, nothing may be called a leftover.
    func testTheDefaultClaimsEverything() {
        XCTAssertTrue(InstalledApplications.everything.claims("com.long.gone"))
    }
}

final class OrphanTests: XCTestCase {
    private let now = Date()
    private let none = InstalledApplications(bundleIDs: [], lookup: { _ in false })

    private func isOrphan(_ name: String, daysIdle: Int,
                          installed: InstalledApplications? = nil) -> Bool {
        Leftovers.isOrphan(name: name,
                           modified: now.addingTimeInterval(-Double(daysIdle) * 86_400),
                           now: now, installed: installed ?? none)
    }

    func testLongAbandonedDataOfAMissingApplicationIsALeftover() {
        XCTAssertTrue(isOrphan("com.microsoft.teams", daysIdle: 400))
    }

    /// Below the threshold the list fills with live command line tools and
    /// helpers that simply have no application bundle to find.
    func testRecentlyTouchedDataIsLeftAlone() {
        XCTAssertFalse(isOrphan("com.vercel.cli", daysIdle: 60))
        XCTAssertFalse(isOrphan("com.vercel.cli", daysIdle: Leftovers.idleDays - 1))
        XCTAssertTrue(isOrphan("com.vercel.cli", daysIdle: Leftovers.idleDays))
    }

    func testDataOfAnInstalledApplicationIsNeverALeftoverHoweverOld() {
        let warp = InstalledApplications(bundleIDs: ["dev.warp.warp-stable"], lookup: { _ in false })
        XCTAssertFalse(isOrphan("2BBY89MBSN.dev.warp", daysIdle: 3_000, installed: warp))
    }

    func testAFolderNotNamedAfterAnIdentifierIsNeverALeftover() {
        XCTAssertFalse(isOrphan("Notion", daysIdle: 3_000))
    }
}

final class LeftoverScanTests: XCTestCase {
    private var home: URL!
    private var containers: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "leftovers-\(UUID().uuidString)")
        containers = home.appending(path: "Library/Containers")
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func make(_ name: String, daysIdle: Int) throws {
        let url = containers.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(daysIdle) * 86_400)],
            ofItemAtPath: url.path)
    }

    func testOnlyAbandonedIdentifiersAreOffered() async throws {
        try make("com.microsoft.teams", daysIdle: 400)     // видалена
        try make("dev.warp.Warp-Stable", daysIdle: 400)    // встановлена
        try make("com.vercel.cli", daysIdle: 3)            // свіжа
        try make("SomeFolder", daysIdle: 400)              // не bundle id

        let category = CleanupCategory(id: "leftovers", title: "L", consequence: "—",
                                       roots: [containers], selects: .orphanedApplications)
        let policy = ScanPolicy(
            home: home, installed: InstalledApplications(bundleIDs: ["dev.warp.warp-stable"],
                                                         lookup: { _ in false }))
        let scan = await DiskScanner(pathGuard: PathGuard(allowedRoots: [containers],
                                                          deniedPaths: []),
                                     policy: policy).scan([category])[0]

        XCTAssertEqual(scan.items.map { $0.url.lastPathComponent }, ["com.microsoft.teams"])
    }
}

final class LeftoverRemovalTests: XCTestCase {
    private var home: URL!
    private var containers: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "removal-\(UUID().uuidString)")
        containers = home.appending(path: "Library/Containers")
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func leftover(_ name: String, daysIdle: Int) throws -> ScanItem {
        let url = containers.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let modified = Date().addingTimeInterval(-Double(daysIdle) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: url.path)
        return ScanItem(url: url, sizeBytes: 1, modified: modified, root: containers,
                        selects: .orphanedApplications)
    }

    private func remover(_ installed: InstalledApplications) -> Remover {
        Remover(pathGuard: PathGuard(allowedRoots: [containers], deniedPaths: []),
                trash: NoTrash(), policy: ScanPolicy(home: home, installed: installed))
    }

    /// Naming a whole application directory widens what the guard allows, so
    /// the rule that picked it has to hold at the moment of removal too.
    func testRefusesALeftoverWhoseApplicationIsInstalledAgain() async throws {
        let item = try leftover("com.microsoft.teams", daysIdle: 400)
        let back = InstalledApplications(bundleIDs: ["com.microsoft.teams"], lookup: { _ in false })

        let report = await remover(back).remove([item])

        XCTAssertTrue(report.moved.isEmpty)
        XCTAssertEqual(report.failed.count, 1)
    }

    /// The freshness is re-read from disk: an application touched since the
    /// scan is no longer abandoned.
    func testRefusesALeftoverTouchedSinceTheScan() async throws {
        let item = try leftover("com.microsoft.teams", daysIdle: 400)
        try FileManager.default.setAttributes([.modificationDate: Date()],
                                              ofItemAtPath: item.url.path)

        let report = await remover(gone).remove([item])

        XCTAssertEqual(report.failed.count, 1)
    }

    func testMovesALeftoverThatStillQualifies() async throws {
        let item = try leftover("com.microsoft.teams", daysIdle: 400)
        let report = await remover(gone).remove([item])

        XCTAssertEqual(report.moved.count, 1)
        XCTAssertTrue(report.failed.isEmpty)
    }

    private let gone = InstalledApplications(bundleIDs: [], lookup: { _ in false })
}

private struct NoTrash: FileTrashing {
    func trash(_ url: URL) throws {}
}
