import XCTest
@testable import CleanerKit

final class UserFolderValidationTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "user-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeDirectory(_ relative: String) throws -> URL {
        let url = home.appending(path: relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func validate(_ path: String, covered: [URL] = [],
                          denied: [URL] = []) -> Result<URL, FolderRejection> {
        UserCatalogStore.validate(path, home: home, covered: covered, denied: denied)
    }

    func testAcceptsAFolderInsideHome() throws {
        let renders = try makeDirectory("Library/Caches/MyTool")
        XCTAssertEqual((try? validate(renders.path).get())?.path, renders.path)
    }

    func testRejectsAnythingOutsideHome() throws {
        XCTAssertEqual(validate("/tmp"), .failure(.outsideHome))
        XCTAssertEqual(validate("/"), .failure(.outsideHome))
    }

    /// The whole home folder would put every document one click away.
    func testRejectsHomeItself() {
        XCTAssertEqual(validate(home.path), .failure(.homeItself))
    }

    func testRejectsTraversalAndRelativePaths() {
        XCTAssertEqual(validate("Library/Caches"), .failure(.notAbsolute))
        XCTAssertEqual(validate(home.path + "/Library/../../etc"), .failure(.traversal))
    }

    /// Compared both ways: neither add something forbidden, nor add a folder
    /// with something forbidden inside it.
    func testRejectsTheNeverTouchList() throws {
        let documents = try makeDirectory("Documents")
        try makeDirectory("Documents/Work")
        let library = try makeDirectory("Library")
        let photos = try makeDirectory("Library/Photos")

        XCTAssertEqual(validate(documents.path, denied: [documents]), .failure(.neverTouched))
        XCTAssertEqual(validate(documents.appending(path: "Work").path, denied: [documents]),
                       .failure(.neverTouched))
        XCTAssertEqual(validate(library.path, denied: [photos]), .failure(.neverTouched),
                       "a folder holding something forbidden cannot be added either")
    }

    func testRejectsWhatABuiltInCategoryAlreadyCovers() throws {
        let derived = try makeDirectory("Library/Developer/Xcode/DerivedData")
        try makeDirectory("Library/Developer/Xcode/DerivedData/Project-abc")
        XCTAssertEqual(validate(derived.path, covered: [derived]), .failure(.alreadyCovered))
        XCTAssertEqual(validate(derived.appending(path: "Project-abc").path, covered: [derived]),
                       .failure(.alreadyCovered))
    }

    func testRejectsFilesAndMissingPaths() throws {
        let file = home.appending(path: "note.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(validate(file.path), .failure(.notADirectory))
        XCTAssertEqual(validate(home.appending(path: "nowhere").path), .failure(.notADirectory))
    }
}

final class UserCatalogStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testNoFileMeansNoEditsAndNoComplaint() {
        let loaded = UserCatalogStore.load(home: home)
        XCTAssertEqual(loaded.catalog, .empty)
        XCTAssertNil(loaded.problem)
    }

    func testSurvivesARoundTrip() throws {
        let catalog = UserCatalog(disabled: ["agentVM"],
                                  folders: [UserFolder(title: "Renders", path: "~/Library/Caches/R")])
        try UserCatalogStore.save(catalog, home: home)
        XCTAssertEqual(UserCatalogStore.load(home: home).catalog, catalog)
    }

    /// A hand-edited file that cannot be parsed must say so: silence would
    /// leave the user believing their edit took effect.
    func testABrokenFileComplainsInsteadOfPretending() throws {
        let file = UserCatalogStore.url(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: file)

        let loaded = UserCatalogStore.load(home: home)
        XCTAssertEqual(loaded.catalog, .empty)
        XCTAssertNotNil(loaded.problem)
    }
}

final class CatalogWithUserEditsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func categories(_ user: UserCatalog) -> [CleanupCategory] {
        Catalog.standard(home: home, listing: { _ in [] }, user: user)
    }

    func testASwitchedOffCategoryDisappears() {
        let ids = categories(UserCatalog(disabled: ["agentVM", "logs"])).map(\.id)
        XCTAssertFalse(ids.contains("agentVM"))
        XCTAssertFalse(ids.contains("logs"))
        XCTAssertTrue(ids.contains("derivedData"))
    }

    /// A category nobody scans must not keep widening what may be deleted.
    func testASwitchedOffCategoryStopsWideningTheGuard() {
        let logs = home.appending(path: "Library/Logs")
        let item = logs.appending(path: "SomeApp")

        XCTAssertEqual(Catalog.pathGuard(home: home, listing: { _ in [] })
            .validate(item), .failure(.doesNotExist),
                       "with the category on, only existence stands in the way")

        XCTAssertEqual(Catalog.pathGuard(home: home, listing: { _ in [] },
                                         user: UserCatalog(disabled: ["logs"]))
            .validate(item), .failure(.outsideAllowedRoots))
    }

    /// The file can be hand-edited, so a path is checked every time it is
    /// read, not only when it was added.
    func testAnInvalidFolderInTheFileIsIgnored() {
        let bad = UserCatalog(folders: [
            UserFolder(title: "Everything", path: "/"),
            UserFolder(title: "Documents", path: "/Users/test/Documents"),
        ])
        XCTAssertTrue(categories(bad).allSatisfy { !$0.isUserDefined })
    }
}
