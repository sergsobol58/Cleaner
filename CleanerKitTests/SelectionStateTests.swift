import XCTest
@testable import CleanerKit

final class SelectionStateTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/корень")

    private func item(_ name: String, bytes: Int64 = 100) -> ScanItem {
        ScanItem(url: root.appendingPathComponent(name), sizeBytes: bytes,
                 modified: .now, root: root)
    }

    func testStartsEmpty() {
        XCTAssertTrue(SelectionState().isEmpty)
    }

    func testTogglesSingleItem() {
        var sut = SelectionState()
        let one = item("один")

        sut.toggle(one)
        XCTAssertTrue(sut.contains(one))

        sut.toggle(one)
        XCTAssertFalse(sut.contains(one))
    }

    /// Повторная установка того же значения ничего не меняет.
    func testSetIsIdempotent() {
        var sut = SelectionState()
        let one = item("один")

        sut.set(one, selected: true)
        sut.set(one, selected: true)
        XCTAssertEqual(sut.count, 1)

        sut.set(one, selected: false)
        sut.set(one, selected: false)
        XCTAssertTrue(sut.isEmpty)
    }

    func testCoverageReflectsPartialSelection() {
        var sut = SelectionState()
        let items = [item("а"), item("б"), item("в")]

        XCTAssertEqual(sut.coverage(of: items), .none)

        sut.toggle(items[0])
        XCTAssertEqual(sut.coverage(of: items), .partial)

        sut.set(items, selected: true)
        XCTAssertEqual(sut.coverage(of: items), .all)
    }

    func testEmptyGroupIsNotConsideredSelected() {
        XCTAssertEqual(SelectionState().coverage(of: []), .none)
    }

    /// Частично выбранная группа при нажатии добирается до полной.
    func testToggleAllCompletesPartialGroup() {
        var sut = SelectionState()
        let items = [item("а"), item("б")]
        sut.toggle(items[0])

        sut.toggleAll(items)

        XCTAssertEqual(sut.coverage(of: items), .all)
    }

    func testToggleAllClearsFullGroup() {
        var sut = SelectionState()
        let items = [item("а"), item("б")]
        sut.set(items, selected: true)

        sut.toggleAll(items)

        XCTAssertEqual(sut.coverage(of: items), .none)
    }

    func testCountsSelectedBytes() {
        var sut = SelectionState()
        let items = [item("а", bytes: 300), item("б", bytes: 700)]
        let scan = CategoryScan(id: "к", category: CleanupCategory(
            id: "к", title: "К", consequence: "—", roots: [root]), items: items)

        sut.toggle(items[1])

        XCTAssertEqual(sut.bytes(in: [scan]), 700)
        XCTAssertEqual(sut.items(from: [scan]).map(\.url), [items[1].url])
    }

    /// После удаления пути исчезают — отметки на них надо снять,
    /// иначе счётчик показывает выбранным то, чего уже нет.
    func testForgetsItemsThatVanished() {
        var sut = SelectionState()
        let gone = item("исчез")
        let stays = item("остался")
        sut.set([gone, stays], selected: true)

        let scan = CategoryScan(id: "к", category: CleanupCategory(
            id: "к", title: "К", consequence: "—", roots: [root]), items: [stays])
        sut.keepOnly([scan])

        XCTAssertFalse(sut.contains(gone))
        XCTAssertTrue(sut.contains(stays))
        XCTAssertEqual(sut.count, 1)
    }
}
