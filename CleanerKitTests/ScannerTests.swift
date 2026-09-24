import XCTest
@testable import CleanerKit

final class ScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    /// Mirrors how the app wires this: what may be deleted is exactly the
    /// roots of the categories being scanned, and nothing deeper than their
    /// direct children.
    private func scan(_ categories: [CleanupCategory]) async -> [CategoryScan] {
        await DiskScanner(
            pathGuard: PathGuard(allowedRoots: categories.flatMap(\.roots), deniedPaths: []),
            policy: ScanPolicy(home: root)
        ).scan(categories)
    }

    private func category(_ roots: [URL]) -> CleanupCategory {
        CleanupCategory(id: "test", title: "Test", consequence: "—", roots: roots)
    }

    func testFindsDirectChildrenWithSizes() async throws {
        try write("big/file.bin", bytes: 40_000)
        try write("small/file.bin", bytes: 1_000)

        let scans = await scan([category([root])])

        XCTAssertEqual(scans.count, 1)
        XCTAssertEqual(scans[0].items.count, 2)
        XCTAssertEqual(scans[0].totalBytes,
                       scans[0].items.reduce(0) { $0 + $1.sizeBytes })
    }

    func testSizeCountsNestedFiles() async throws {
        try write("folder/one.bin", bytes: 10_000)
        try write("folder/deeper/two.bin", bytes: 10_000)

        let scans = await scan([category([root])])
        let item = try XCTUnwrap(scans[0].items.first)

        XCTAssertEqual(scans[0].items.count, 1, "nested content must not get its own row")
        XCTAssertGreaterThanOrEqual(item.sizeBytes, 20_000, "the size must include nested files")
    }

    func testSortsLargestFirst() async throws {
        try write("tiny/a.bin", bytes: 1_000)
        try write("huge/b.bin", bytes: 90_000)
        try write("medium/c.bin", bytes: 40_000)

        let scans = await scan([category([root])])
        let names = scans[0].items.map { $0.url.lastPathComponent }

        XCTAssertEqual(names, ["huge", "medium", "tiny"])
    }

    func testMissingRootIsNotAnError() async throws {
        let scans = await scan([category([root.appendingPathComponent("no-such-thing")])])

        XCTAssertEqual(scans.count, 1)
        XCTAssertTrue(scans[0].items.isEmpty)
        XCTAssertEqual(scans[0].totalBytes, 0)
    }

    func testSkipsWhatGuardRejects() async throws {
        try write("ordinary/file.bin", bytes: 1_000)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: target)

        let scans = await scan([category([root])])
        let names = scans[0].items.map { $0.url.lastPathComponent }

        XCTAssertFalse(names.contains("link"), "a symlink must never be offered for removal")
        XCTAssertTrue(names.contains("ordinary"))
    }

    func testGroupsFindingsByTheirRoot() async throws {
        try write("first/a.bin", bytes: 90_000)
        try write("first/b.bin", bytes: 10_000)
        try write("second/c.bin", bytes: 1_000)

        let scans = await scan([category([
            root.appendingPathComponent("first"),
            root.appendingPathComponent("second"),
        ])])
        let groups = scans[0].groups

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { $0.root.lastPathComponent }, ["first", "second"],
                       "larger groups must come first")
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertTrue(groups[0].items.allSatisfy { $0.root.lastPathComponent == "first" })
    }

    func testMergesSeveralRootsIntoOneCategory() async throws {
        try write("first/a.bin", bytes: 1_000)
        try write("second/b.bin", bytes: 1_000)

        let scans = await scan([category([
            root.appendingPathComponent("first"),
            root.appendingPathComponent("second"),
        ])])

        XCTAssertEqual(scans[0].items.count, 2, "category roots merge into one list")
    }
}
