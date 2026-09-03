import XCTest
@testable import CleanerKit

final class SelectionStateTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/root-dir")

    private func item(_ name: String, bytes: Int64 = 100) -> ScanItem {
        ScanItem(url: root.appendingPathComponent(name), sizeBytes: bytes,
                 modified: .now, root: root)
    }

    func testStartsEmpty() {
        XCTAssertTrue(SelectionState().isEmpty)
    }

    func testTogglesSingleItem() {
        var sut = SelectionState()
        let one = item("one")

        sut.toggle(one)
        XCTAssertTrue(sut.contains(one))

        sut.toggle(one)
        XCTAssertFalse(sut.contains(one))
    }

    /// Setting the same value twice changes nothing.
    func testSetIsIdempotent() {
        var sut = SelectionState()
        let one = item("one")

        sut.set(one, selected: true)
        sut.set(one, selected: true)
        XCTAssertEqual(sut.count, 1)

        sut.set(one, selected: false)
        sut.set(one, selected: false)
        XCTAssertTrue(sut.isEmpty)
    }

    func testCoverageReflectsPartialSelection() {
        var sut = SelectionState()
        let items = [item("a"), item("b"), item("c")]

        XCTAssertEqual(sut.coverage(of: items), .none)

        sut.toggle(items[0])
        XCTAssertEqual(sut.coverage(of: items), .partial)

        sut.set(items, selected: true)
        XCTAssertEqual(sut.coverage(of: items), .all)
    }

    func testEmptyGroupIsNotConsideredSelected() {
        XCTAssertEqual(SelectionState().coverage(of: []), .none)
    }

    /// Clicking a partly selected group completes it.
    func testToggleAllCompletesPartialGroup() {
        var sut = SelectionState()
        let items = [item("a"), item("b")]
        sut.toggle(items[0])

        sut.toggleAll(items)

        XCTAssertEqual(sut.coverage(of: items), .all)
    }

    func testToggleAllClearsFullGroup() {
        var sut = SelectionState()
        let items = [item("a"), item("b")]
        sut.set(items, selected: true)

        sut.toggleAll(items)

        XCTAssertEqual(sut.coverage(of: items), .none)
    }

    func testCountsSelectedBytes() {
        var sut = SelectionState()
        let items = [item("a", bytes: 300), item("b", bytes: 700)]
        let scan = CategoryScan(id: "c", category: CleanupCategory(
            id: "c", title: "C", consequence: "—", roots: [root]), items: items)

        sut.toggle(items[1])

        XCTAssertEqual(sut.bytes(in: [scan]), 700)
        XCTAssertEqual(sut.items(from: [scan]).map(\.url), [items[1].url])
    }

    /// Paths disappear once removed, so their marks must go too — otherwise
    /// the counter reports things that no longer exist as selected.
    func testForgetsItemsThatVanished() {
        var sut = SelectionState()
        let gone = item("gone")
        let stays = item("still-there")
        sut.set([gone, stays], selected: true)

        let scan = CategoryScan(id: "c", category: CleanupCategory(
            id: "c", title: "C", consequence: "—", roots: [root]), items: [stays])
        sut.keepOnly([scan])

        XCTAssertFalse(sut.contains(gone))
        XCTAssertTrue(sut.contains(stays))
        XCTAssertEqual(sut.count, 1)
    }
}
