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
