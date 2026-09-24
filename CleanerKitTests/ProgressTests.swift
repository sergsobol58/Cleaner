import XCTest
@testable import CleanerKit

final class ScanProgressTests: XCTestCase {
    func testFractionRunsFromNothingToWhole() {
        XCTAssertEqual(ScanProgress(completed: 0, total: 4, finished: "a").fraction, 0)
        XCTAssertEqual(ScanProgress(completed: 2, total: 4, finished: "b").fraction, 0.5)
        XCTAssertEqual(ScanProgress(completed: 4, total: 4, finished: "c").fraction, 1)
    }

    /// Nothing to do is done, not stuck at zero.
    func testNoCategoriesReadsAsFinished() {
        XCTAssertEqual(ScanProgress(completed: 0, total: 0, finished: "").fraction, 1)
    }
}

final class ScannerProgressTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func category(_ name: String) throws -> CleanupCategory {
        let directory = root.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appending(path: "child"))
        return CleanupCategory(id: name, title: name, consequence: "—", roots: [directory])
    }

    func testEveryCategoryIsReportedOnceAndTheLastOneCompletesTheBar() async throws {
        let categories = try ["one", "two", "three"].map(category)
        let scanner = DiskScanner(pathGuard: PathGuard(allowedRoots: [root], deniedPaths: []),
                                  policy: ScanPolicy(home: root))

        let box = Box()
        _ = await scanner.scan(categories) { box.append($0) }
        let seen = box.values

        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen.map(\.completed), [1, 2, 3], "progress only moves forward")
        XCTAssertEqual(seen.last?.fraction, 1)
        XCTAssertEqual(Set(seen.map(\.finished)), ["one", "two", "three"],
                       "each report names the category that landed")
    }

    /// Categories are measured in parallel, so the order reports arrive in is
    /// not the catalog order — but the results still come back in it.
    func testResultsKeepCatalogOrderRegardlessOfWhoFinishesFirst() async throws {
        let categories = try ["one", "two", "three"].map(category)
        let scanner = DiskScanner(pathGuard: PathGuard(allowedRoots: [root], deniedPaths: []),
                                  policy: ScanPolicy(home: root))

        let scans = await scanner.scan(categories)
        XCTAssertEqual(scans.map(\.id), ["one", "two", "three"])
    }
}

/// Progress arrives from parallel tasks; collecting it needs somewhere safe.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []

    func append(_ progress: ScanProgress) {
        lock.lock(); defer { lock.unlock() }
        storage.append(progress)
    }

    var values: [ScanProgress] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

final class VolumeSpaceTests: XCTestCase {
    func testPurgeableIsWhatTheSystemPromisesBeyondWhatIsFree() {
        let space = VolumeSpace(total: 500, free: 10, available: 40)
        XCTAssertEqual(space.purgeable, 30)
    }

    /// Some volumes report less available than free; a negative gap is noise.
    func testPurgeableNeverGoesNegative() {
        XCTAssertEqual(VolumeSpace(total: 500, free: 40, available: 10).purgeable, 0)
    }
}
