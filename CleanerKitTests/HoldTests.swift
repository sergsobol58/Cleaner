import XCTest
@testable import CleanerKit

final class AppAttributionTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let safari = RunningApp(bundleID: "com.apple.Safari", name: "Safari")
    private let notion = RunningApp(bundleID: "notion.id", name: "Notion")

    private func owner(_ path: String, _ running: [RunningApp]) -> RunningApp? {
        AppAttribution.owner(of: home.appending(path: path), among: running, home: home)
    }

    func testContainerPathNamesItsOwnerOutright() {
        XCTAssertEqual(owner("Library/Containers/com.apple.Safari/Data/Library/Caches",
                             [safari]), safari)
    }

    func testApplicationSupportFolderMatchesTheApplicationName() {
        XCTAssertEqual(owner("Library/Application Support/Notion/Partitions/notion/Cache",
                             [notion]), notion)
    }

    /// Folder names are not typed the way the app is named.
    func testMatchingIgnoresCase() {
        let discord = RunningApp(bundleID: "com.hnc.Discord", name: "Discord")
        XCTAssertEqual(owner("Library/Application Support/discord/Cache", [discord]), discord)
    }

    func testGroupContainerDropsTheGroupAndTeamPrefixes() {
        let notes = RunningApp(bundleID: "com.apple.Notes", name: "Notes")
        XCTAssertEqual(owner("Library/Group Containers/group.com.apple.Notes", [notes]), notes)
        XCTAssertEqual(owner("Library/Group Containers/A1B2C3D4E5.com.apple.Notes", [notes]), notes)
    }

    /// The dangerous direction: claiming an owner a path never named would
    /// hold back far more than it protects.
    func testPathThatNamesNobodyHasNoOwner() {
        XCTAssertNil(owner("Library/Developer/Xcode/DerivedData/Safari-abc", [safari]))
        XCTAssertNil(owner(".npm/_cacache/content-v2", [safari, notion]))
    }

    func testAnApplicationThatIsNotRunningIsNotAnOwner() {
        XCTAssertNil(owner("Library/Containers/com.apple.Safari/Data", [notion]))
    }
}

final class ScannerHoldTests: XCTestCase {
    private var home: URL!
    private var root: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "hold-\(UUID().uuidString)")
        root = home.appending(path: "Library/Caches/probe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeChild(_ name: String, modified: Date) throws -> URL {
        let url = root.appending(path: name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: url.path)
        return url
    }

    private func scan(_ category: CleanupCategory, policy: ScanPolicy) async -> CategoryScan {
        let guardian = PathGuard(allowedRoots: [root], deniedPaths: [])
        return await DiskScanner(pathGuard: guardian, policy: policy).scan([category])[0]
    }

    private func category(idleDays: Int) -> CleanupCategory {
        CleanupCategory(id: "probe", title: "Probe", consequence: "None",
                        roots: [root], minimumIdleDays: idleDays)
    }

    func testSomethingChangedInsideTheIdleWindowIsHeld() async throws {
        let now = Date()
        _ = try makeChild("fresh", modified: now.addingTimeInterval(-3_600))
        let scan = await scan(category(idleDays: 1), policy: ScanPolicy(home: home, now: now))

        XCTAssertEqual(scan.items.first?.hold, .changedRecently)
        XCTAssertEqual(scan.removableBytes, 0)
        XCTAssertGreaterThan(scan.totalBytes, 0, "a held finding still counts as found")
    }

    func testSomethingOlderThanTheWindowIsOffered() async throws {
        let now = Date()
        _ = try makeChild("stale", modified: now.addingTimeInterval(-3 * 86_400))
        let scan = await scan(category(idleDays: 1), policy: ScanPolicy(home: home, now: now))

        XCTAssertNil(scan.items.first?.hold)
    }

    /// Build output exists to be thrown away; a fresh timestamp is normal.
    func testZeroIdleDaysNeverHoldsOnAge() async throws {
        let now = Date()
        _ = try makeChild("fresh", modified: now)
        let scan = await scan(category(idleDays: 0), policy: ScanPolicy(home: home, now: now))

        XCTAssertNil(scan.items.first?.hold)
    }

    func testARunningApplicationOutranksTheAgeRule() async throws {
        let appRoot = home.appending(path: "Library/Application Support/Notion")
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: appRoot.appending(path: "Cache"))

        let category = CleanupCategory(id: "notion", title: "Notion", consequence: "None",
                                       roots: [appRoot], minimumIdleDays: 1)
        let guardian = PathGuard(allowedRoots: [appRoot], deniedPaths: [])
        let policy = ScanPolicy(home: home,
                                runningApps: [RunningApp(bundleID: "notion.id", name: "Notion")])
        let scan = await DiskScanner(pathGuard: guardian, policy: policy).scan([category])[0]

        XCTAssertEqual(scan.items.first?.hold, .appRunning("Notion"))
    }

    /// "Nothing here" and "not allowed to look" must not read the same.
    func testAnUnreadableRootIsReportedRatherThanCountedAsEmpty() async throws {
        let locked = home.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: locked.path) }

        let missing = home.appending(path: "never-existed")
        let category = CleanupCategory(id: "probe", title: "Probe", consequence: "None",
                                       roots: [locked, missing])
        let guardian = PathGuard(allowedRoots: [locked, missing], deniedPaths: [])
        let scan = await DiskScanner(pathGuard: guardian,
                                     policy: ScanPolicy(home: home)).scan([category])[0]

        XCTAssertEqual(scan.unreadableRoots, [locked],
                       "a missing directory is not a permission problem")
    }
}

final class HoldEnforcementTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/probe")

    private func item(_ name: String, hold: Hold? = nil) -> ScanItem {
        ScanItem(url: root.appending(path: name), sizeBytes: 10,
                 modified: .now, root: root, hold: hold)
    }

    func testSelectionRefusesToSelectAHeldFinding() {
        var selection = SelectionState()
        let held = item("held", hold: .changedRecently)

        selection.set(held, selected: true)
        XCTAssertFalse(selection.contains(held))

        selection.set([held], selected: true)
        XCTAssertTrue(selection.isEmpty, "select all must not sweep held findings in")
    }

    func testCoverageIgnoresHeldFindings() {
        var selection = SelectionState()
        let free = item("free")
        let items = [free, item("held", hold: .appRunning("Notion"))]

        selection.set(free, selected: true)
        XCTAssertEqual(selection.coverage(of: items), .all,
                       "a group must not be stuck at partial by a finding nobody can select")
    }

    func testEverythingHeldReadsAsNothingSelected() {
        let items = [item("a", hold: .changedRecently), item("b", hold: .changedRecently)]
        XCTAssertEqual(SelectionState().coverage(of: items), .none)
    }

    func testRemoverRefusesAHeldFindingHandedToItDirectly() async {
        let held = item("held", hold: .appRunning("Notion"))
        let remover = Remover(pathGuard: PathGuard(allowedRoots: [root], deniedPaths: []),
                              trash: RecordingTrash())
        let report = await remover.remove([held])

        XCTAssertTrue(report.moved.isEmpty)
        XCTAssertEqual(report.failed.count, 1)
    }
}

private struct RecordingTrash: FileTrashing {
    func trash(_ url: URL) throws {}
}
