import XCTest
@testable import CleanerKit

/// A stand-in trash: a test must never delete anything for real.
private final class TrashSpy: FileTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [URL] = []
    private let failOn: Set<URL>

    var calls: [URL] { lock.withLock { _calls } }

    init(failOn: Set<URL> = []) { self.failOn = failOn }

    func trash(_ url: URL) throws {
        lock.withLock { _calls.append(url) }
        if failOn.contains(url) {
            throw NSError(domain: "TrashSpy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "the trash refused"])
        }
    }
}

final class RemoverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RemoverTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeDir(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(_ url: URL, bytes: Int64 = 1_000) -> ScanItem {
        ScanItem(url: url, sizeBytes: bytes, modified: .now, root: root)
    }

    private func makeRemover(_ spy: TrashSpy, denied: [URL] = []) -> Remover {
        Remover(pathGuard: PathGuard(allowedRoots: [root], deniedPaths: denied), trash: spy)
    }

    func testMovesValidItems() async throws {
        let first = try makeDir("first")
        let second = try makeDir("second")
        let spy = TrashSpy()

        let report = await makeRemover(spy).remove([item(first), item(second)])

        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(report.moved.count, 2)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.movedBytes, 2_000)
    }

    /// Minutes pass between the scan and the button press, and the path
    /// could have become anything in the meantime. The guard therefore runs
    /// again instead of trusting the scan results.
    func testRevalidatesBeforeDeleting() async throws {
        let forbidden = try makeDir("became-forbidden")
        let spy = TrashSpy()

        let report = await makeRemover(spy, denied: [forbidden]).remove([item(forbidden)])

        XCTAssertTrue(spy.calls.isEmpty, "forbidden paths must never reach the trash")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.moved.isEmpty)
        XCTAssertEqual(report.movedBytes, 0)
    }

    func testItemDeletedBehindOurBackIsReportedNotCrashed() async throws {
        let vanished = root.appendingPathComponent("vanished")
        let spy = TrashSpy()

        let report = await makeRemover(spy).remove([item(vanished)])

        XCTAssertTrue(spy.calls.isEmpty)
        XCTAssertEqual(report.failed.count, 1)
    }

    func testOneFailureDoesNotStopTheRest() async throws {
        let good = try makeDir("good")
        let bad = try makeDir("bad")
        let spy = TrashSpy(failOn: [bad])

        let report = await makeRemover(spy).remove([item(bad), item(good)])

        XCTAssertEqual(report.moved.map { $0.item.url }, [good])
        XCTAssertEqual(report.failed.map { $0.item.url }, [bad])
        XCTAssertEqual(report.failed.first?.error, "the trash refused")
    }

    func testEmptySelectionDoesNothing() async {
        let spy = TrashSpy()
        let report = await makeRemover(spy).remove([])

        XCTAssertTrue(spy.calls.isEmpty)
        XCTAssertTrue(report.moved.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
    }
}
