import XCTest
@testable import CleanerKit

/// Проверки строятся на временном каталоге, а не на настоящем ~ пользователя:
/// тест, который ходит в реальный дом, однажды в нём что-нибудь и сломает.
final class PathGuardTests: XCTestCase {
    private var home: URL!
    private var sut: PathGuard!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PathGuardTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()

        for sub in ["Library/Caches", "Library/Developer/Xcode/DerivedData",
                    "Library/Developer/Xcode/Archives", "Documents", ".ssh"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(sub), withIntermediateDirectories: true)
        }

        sut = PathGuard(
            allowedRoots: [
                home.appendingPathComponent("Library/Caches"),
                home.appendingPathComponent("Library/Developer"),
            ],
            deniedPaths: [
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent(".ssh"),
                home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            ]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        try super.tearDownWithError()
    }

    private func makeDir(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func reject(_ url: URL, _ expected: GuardRejection,
                        _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        switch sut.validate(url) {
        case .success:
            XCTFail("должен быть запрещён (\(message)): \(url.path)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, message, file: file, line: line)
        }
    }

    // MARK: - Отказы

    func testRejectsRelativePath() {
        reject(URL(string: "relative/path")!, .notAbsolute, "относительный путь")
    }

    func testRejectsTraversal() {
        let url = home.appendingPathComponent("Library/Caches/../../Documents")
        reject(url, .traversal, "путь с ..")
    }

    func testRejectsAllowedRootItself() {
        reject(home.appendingPathComponent("Library/Caches"), .isRootItself, "сам разрешённый корень")
        reject(home.appendingPathComponent("Library/Developer"), .isRootItself, "сам разрешённый корень")
    }

    func testRejectsDeniedPaths() {
        reject(home.appendingPathComponent("Documents"), .inDenyList, "Documents")
        reject(home.appendingPathComponent(".ssh"), .inDenyList, ".ssh")
    }

    func testRejectsInsideDeniedPath() {
        reject(home.appendingPathComponent("Documents/важное.txt"), .inDenyList, "файл внутри Documents")
    }

    /// Archives лежит внутри разрешённого корня Developer — стоп-лист должен победить.
    func testDenyListBeatsAllowedRoot() {
        reject(home.appendingPathComponent("Library/Developer/Xcode/Archives"),
               .inDenyList, "Archives внутри разрешённого корня")
        reject(home.appendingPathComponent("Library/Developer/Xcode/Archives/App.xcarchive"),
               .inDenyList, "содержимое Archives")
    }

    /// Путь, который сам содержит запрещённый каталог, удалять нельзя:
    /// снеся Xcode/, мы унесли бы вместе с ним Archives.
    func testRejectsPathContainingDeniedPath() {
        reject(home.appendingPathComponent("Library/Developer/Xcode"),
               .inDenyList, "Xcode содержит Archives")
    }

    func testRejectsFilesystemRoot() {
        reject(URL(fileURLWithPath: "/"), .inDenyList, "корень файловой системы")
    }

    func testRejectsOutsideAllowedRoots() {
        reject(URL(fileURLWithPath: "/etc/passwd"), .outsideAllowedRoots, "системный файл")
        reject(URL(fileURLWithPath: "/System"), .outsideAllowedRoots, "системный каталог")
    }

    /// Library не входит в разрешённые корни и вдобавок содержит Archives —
    /// достаточно любой из причин, но стоп-лист проверяется первым.
    func testRejectsLibraryBecauseItContainsDeniedPath() {
        reject(home.appendingPathComponent("Library"), .inDenyList, "Library содержит Archives")
    }

    /// Строковое сравнение префиксов сочло бы CachesOther продолжением Caches.
    func testRejectsSiblingWithSharedPrefix() throws {
        let sibling = try makeDir("Library/CachesOther/thing")
        reject(sibling, .outsideAllowedRoots, "каталог с общим префиксом имени")
    }

    func testRejectsNonexistentPath() {
        reject(home.appendingPathComponent("Library/Caches/нет-такого"),
               .doesNotExist, "несуществующий путь")
    }

    func testRejectsSymlink() throws {
        let target = try makeDir("Documents/секрет")
        let link = home.appendingPathComponent("Library/Caches/ссылка")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        reject(link, .symlink, "симлинк наружу")
    }

    // MARK: - Пропуски

    func testAllowsDirectChildOfAllowedRoot() throws {
        let url = try makeDir("Library/Caches/npm")
        XCTAssertEqual(try sut.validate(url).get(), url)
    }

    func testAllowsDeeplyNestedPath() throws {
        let url = try makeDir("Library/Developer/Xcode/DerivedData/App-abc123")
        XCTAssertEqual(try sut.validate(url).get(), url)
    }

    func testAllowsRegularFile() throws {
        let url = home.appendingPathComponent("Library/Caches/файл.db")
        try Data("x".utf8).write(to: url)
        XCTAssertEqual(try sut.validate(url).get(), url)
    }
}
