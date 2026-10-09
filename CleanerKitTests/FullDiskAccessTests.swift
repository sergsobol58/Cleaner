import XCTest
@testable import CleanerKit

final class FullDiskAccessTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testUnreadableProbesMeanThePermissionIsMissing() {
        XCTAssertFalse(FullDiskAccess.isGranted(home: home,
                                                exists: { _ in true },
                                                canRead: { _ in false }))
    }

    func testOneReadableProbeIsEnough() {
        let safari = home.appending(path: "Library/Safari")
        XCTAssertTrue(FullDiskAccess.isGranted(home: home,
                                               exists: { _ in true },
                                               canRead: { $0 == safari }))
    }

    /// Nagging on no evidence is worse than staying quiet: a Mac that has
    /// never opened Mail has nothing to say about permissions.
    func testAbsentProbesCountAsGranted() {
        XCTAssertTrue(FullDiskAccess.isGranted(home: home,
                                               exists: { _ in false },
                                               canRead: { _ in false }))
    }
}

final class TrashTests: XCTestCase {
    func testTrashIsOnTheNeverTouchList() {
        let home = URL(fileURLWithPath: "/Users/test")
        let guardian = Catalog.pathGuard(home: home, listing: { _ in [] })
        let inTrash = TrashFolder.url(home: home).appending(path: "something")

        XCTAssertEqual(guardian.validate(inTrash), .failure(.inDenyList),
                       "the app must never reach back into what it already moved")
    }
}

final class TrashSizeTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// macOS keeps the Trash behind the same permission as the rest of the
    /// Library, so this is the common case — and reporting zero would have
    /// the app announce an empty Trash right after filling it.
    func testAnUnreadableTrashIsUnknownRatherThanEmpty() {
        XCTAssertNil(TrashFolder.sizeBytes(home: home), "no Trash directory at all")
    }

    func testAReadableEmptyTrashIsZero() throws {
        try FileManager.default.createDirectory(at: TrashFolder.url(home: home),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(TrashFolder.sizeBytes(home: home), 0)
    }

    func testCountsWhatTheTrashHolds() throws {
        let trash = TrashFolder.url(home: home)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2_048).write(to: trash.appending(path: "dropped.bin"))

        XCTAssertGreaterThan(TrashFolder.sizeBytes(home: home) ?? 0, 0)
    }
}
