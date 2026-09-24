import XCTest
@testable import CleanerKit

/// The checks run against a temporary directory rather than the user's real
/// home: a test that walks into a real home will eventually break something.
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
            XCTFail("must be refused (\(message)): \(url.path)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, message, file: file, line: line)
        }
    }

    // MARK: - Refusals

    func testRejectsRelativePath() {
        reject(URL(string: "relative/path")!, .notAbsolute, "a relative path")
    }

    func testRejectsTraversal() {
        let url = home.appendingPathComponent("Library/Caches/../../Documents")
        reject(url, .traversal, "a path containing ..")
    }

    func testRejectsAllowedRootItself() {
        reject(home.appendingPathComponent("Library/Caches"), .isRootItself, "the allowed root itself")
        reject(home.appendingPathComponent("Library/Developer"), .isRootItself, "the allowed root itself")
    }

    func testRejectsDeniedPaths() {
        reject(home.appendingPathComponent("Documents"), .inDenyList, "Documents")
        reject(home.appendingPathComponent(".ssh"), .inDenyList, ".ssh")
    }

    func testRejectsInsideDeniedPath() {
        reject(home.appendingPathComponent("Documents/important.txt"), .inDenyList, "a file inside Documents")
    }

    /// Archives sits inside the allowed Developer root — the deny list must win.
    func testDenyListBeatsAllowedRoot() {
        reject(home.appendingPathComponent("Library/Developer/Xcode/Archives"),
               .inDenyList, "Archives inside an allowed root")
        reject(home.appendingPathComponent("Library/Developer/Xcode/Archives/App.xcarchive"),
               .inDenyList, "contents of Archives")
    }

    /// A path that itself contains a forbidden directory cannot be removed:
    /// deleting Xcode/ would carry Archives away with it.
    func testRejectsPathContainingDeniedPath() {
        reject(home.appendingPathComponent("Library/Developer/Xcode"),
               .inDenyList, "Xcode contains Archives")
    }

    func testRejectsFilesystemRoot() {
        reject(URL(fileURLWithPath: "/"), .inDenyList, "the filesystem root")
    }

    func testRejectsOutsideAllowedRoots() {
        reject(URL(fileURLWithPath: "/etc/passwd"), .outsideAllowedRoots, "a system file")
        reject(URL(fileURLWithPath: "/System"), .outsideAllowedRoots, "a system directory")
    }

    /// Library is not an allowed root and additionally contains Archives —
    /// either reason suffices, but the deny list is checked first.
    func testRejectsLibraryBecauseItContainsDeniedPath() {
        reject(home.appendingPathComponent("Library"), .inDenyList, "Library contains Archives")
    }

    /// A string prefix comparison would read CachesOther as part of Caches.
    func testRejectsSiblingWithSharedPrefix() throws {
        let sibling = try makeDir("Library/CachesOther/thing")
        reject(sibling, .outsideAllowedRoots, "a sibling sharing a name prefix")
    }

    func testRejectsNonexistentPath() {
        reject(home.appendingPathComponent("Library/Caches/no-such-thing"),
               .doesNotExist, "a path that does not exist")
    }

    func testRejectsSymlink() throws {
        let target = try makeDir("Documents/secret")
        let link = home.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        reject(link, .symlink, "a symlink pointing outside")
    }

    // MARK: - Allowed

    func testAllowsDirectChildOfAllowedRoot() throws {
        let url = try makeDir("Library/Caches/npm")
        XCTAssertEqual(try sut.validate(url).get(), url)
    }

    /// Deliberately refused. Everything the scanner offers is a direct child
    /// of a root, so nothing legitimate is lost — and without this, one broad
    /// root such as Application Support would stand in for the whole tree
    /// below it, which is most of the Library.
    func testRefusesAnythingDeeperThanADirectChild() throws {
        let url = try makeDir("Library/Developer/Xcode/DerivedData/App-abc123")
        XCTAssertEqual(sut.validate(url), .failure(.outsideAllowedRoots))
    }

    func testAllowsRegularFile() throws {
        let url = home.appendingPathComponent("Library/Caches/file.db")
        try Data("x".utf8).write(to: url)
        XCTAssertEqual(try sut.validate(url).get(), url)
    }
}

final class PathGuardDepthTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/test/Library/Application Support")

    /// Everything the scanner offers is a direct child of a root. Admitting
    /// deeper paths would let one broad root stand in for the whole tree
    /// beneath it.
    func testOnlyDirectChildrenOfARootAreAllowed() {
        let guardian = PathGuard(allowedRoots: [root], deniedPaths: [])

        XCTAssertEqual(guardian.validate(root.appending(path: "a/b")),
                       .failure(.outsideAllowedRoots))
        XCTAssertEqual(guardian.validate(root.appending(path: "a/b/c")),
                       .failure(.outsideAllowedRoots))
        XCTAssertEqual(guardian.validate(root), .failure(.isRootItself))
    }
}
