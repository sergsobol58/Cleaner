import XCTest
@testable import CleanerKit

final class CatalogTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/тест", isDirectory: true)

    func testHasExpectedCategories() {
        XCTAssertEqual(Catalog.standard(home: home).map(\.id),
                       ["derivedData", "deviceSupport", "packageCaches"])
    }

    func testEveryRootLivesInsideGivenHome() {
        for category in Catalog.standard(home: home) {
            for root in category.roots {
                XCTAssertTrue(root.path.hasPrefix(home.path),
                              "\(category.id): корень \(root.path) вне переданного дома")
            }
        }
    }

    /// Категория с несколькими корнями — ради неё packageCaches и попала
    /// в первую версию: на ней проверяется, что модель это выдерживает.
    func testPackageCachesHasSeveralRoots() {
        let category = Catalog.standard(home: home).first { $0.id == "packageCaches" }
        XCTAssertGreaterThan(category?.roots.count ?? 0, 3)
    }

    func testEveryCategoryExplainsConsequence() {
        for category in Catalog.standard(home: home) {
            XCTAssertFalse(category.title.isEmpty, "\(category.id): пустой заголовок")
            XCTAssertFalse(category.consequence.isEmpty, "\(category.id): не сказано о последствии")
        }
    }

    /// Корень категории удалять нельзя — только его содержимое.
    func testGuardRejectsRootsButAllowsTheirChildren() {
        let sut = Catalog.pathGuard(home: home)
        for category in Catalog.standard(home: home) {
            for root in category.roots {
                XCTAssertEqual(sut.validate(root), .failure(.isRootItself),
                               "\(category.id): корень \(root.lastPathComponent) должен быть защищён")

                // Дочерний путь не существует, значит дойти обязан ровно до
                // проверки существования — то есть все запреты он миновал.
                let child = root.appendingPathComponent("что-то")
                XCTAssertEqual(sut.validate(child), .failure(.doesNotExist),
                               "\(category.id): содержимое \(root.lastPathComponent) должно быть разрешено")
            }
        }
    }

    func testGuardProtectsUserData() {
        let sut = Catalog.pathGuard(home: home)
        for unsafe in ["Documents", "Desktop", "Downloads", "Library/Mobile Documents",
                       "Library/Keychains", ".ssh", "Library/Developer/Xcode/Archives",
                       "Library/Developer/Xcode/UserData"] {
            XCTAssertEqual(sut.validate(home.appendingPathComponent(unsafe)), .failure(.inDenyList),
                           "\(unsafe) обязан быть в стоп-листе")
        }
    }
}
