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

    private func makeScanner() -> DiskScanner {
        DiskScanner(pathGuard: PathGuard(allowedRoots: [root], deniedPaths: []))
    }

    private func category(_ roots: [URL]) -> CleanupCategory {
        CleanupCategory(id: "test", title: "Тест", consequence: "—", roots: roots)
    }

    func testFindsDirectChildrenWithSizes() async throws {
        try write("большой/файл.bin", bytes: 40_000)
        try write("маленький/файл.bin", bytes: 1_000)

        let scans = await makeScanner().scan([category([root])])

        XCTAssertEqual(scans.count, 1)
        XCTAssertEqual(scans[0].items.count, 2)
        XCTAssertEqual(scans[0].totalBytes,
                       scans[0].items.reduce(0) { $0 + $1.sizeBytes })
    }

    func testSizeCountsNestedFiles() async throws {
        try write("каталог/один.bin", bytes: 10_000)
        try write("каталог/глубже/два.bin", bytes: 10_000)

        let scans = await makeScanner().scan([category([root])])
        let item = try XCTUnwrap(scans[0].items.first)

        XCTAssertEqual(scans[0].items.count, 1, "вложенное не должно попадать в список отдельно")
        XCTAssertGreaterThanOrEqual(item.sizeBytes, 20_000, "размер должен включать вложенные файлы")
    }

    func testSortsLargestFirst() async throws {
        try write("мелочь/a.bin", bytes: 1_000)
        try write("громадина/b.bin", bytes: 90_000)
        try write("середина/c.bin", bytes: 40_000)

        let scans = await makeScanner().scan([category([root])])
        let names = scans[0].items.map { $0.url.lastPathComponent }

        XCTAssertEqual(names, ["громадина", "середина", "мелочь"])
    }

    func testMissingRootIsNotAnError() async throws {
        let scans = await makeScanner().scan([category([root.appendingPathComponent("нет-такого")])])

        XCTAssertEqual(scans.count, 1)
        XCTAssertTrue(scans[0].items.isEmpty)
        XCTAssertEqual(scans[0].totalBytes, 0)
    }

    func testSkipsWhatGuardRejects() async throws {
        try write("обычный/файл.bin", bytes: 1_000)
        let target = root.appendingPathComponent("цель")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("ссылка"), withDestinationURL: target)

        let scans = await makeScanner().scan([category([root])])
        let names = scans[0].items.map { $0.url.lastPathComponent }

        XCTAssertFalse(names.contains("ссылка"), "симлинк не должен попадать в список на удаление")
        XCTAssertTrue(names.contains("обычный"))
    }

    func testMergesSeveralRootsIntoOneCategory() async throws {
        try write("первый/a.bin", bytes: 1_000)
        try write("второй/b.bin", bytes: 1_000)

        let scans = await makeScanner().scan([category([
            root.appendingPathComponent("первый"),
            root.appendingPathComponent("второй"),
        ])])

        XCTAssertEqual(scans[0].items.count, 2, "корни категории сливаются в один список")
    }
}
