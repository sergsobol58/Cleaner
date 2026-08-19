import XCTest
@testable import CleanerKit

final class CatalogTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/тест", isDirectory: true)

    /// Пустой listing: тест не должен зависеть от содержимого чужого Caches.
    private func categories() -> [CleanupCategory] {
        Catalog.standard(home: home, listing: { _ in [] })
    }

    func testHasExpectedCategories() {
        XCTAssertEqual(categories().map(\.id),
                       ["derivedData", "deviceSupport", "packageCaches",
                        "xcodeBuildMCP", "swiftPM", "appCaches", "appUpdaters"])
    }

    func testUpdaterCategoryTakesOnlyShipItDirectories() {
        let caches = home.appendingPathComponent("Library/Caches")
        let found = Catalog.standard(home: home, listing: { _ in [
            caches.appendingPathComponent("com.microsoft.VSCode.ShipIt"),
            caches.appendingPathComponent("СовсемДругое"),
            caches.appendingPathComponent("Slack.ShipIt"),
        ]}).first { $0.id == "appUpdaters" }

        XCTAssertEqual(found?.roots.map(\.lastPathComponent),
                       ["com.microsoft.VSCode.ShipIt", "Slack.ShipIt"])
    }

    /// Сторож: в CleanerKit был объявлен собственный оператор "/", из-за
    /// которого обычное деление становилось неоднозначным у всех, кто
    /// импортирует модуль. Этот тест ловит его возвращение.
    func testModuleDoesNotBreakArithmetic() {
        let bytes: Int64 = 8_388_608
        XCTAssertEqual(bytes / 1_048_576, 8)
        XCTAssertEqual(Double(3) / Double(2), 1.5)
    }

    func testEveryRootLivesInsideGivenHome() {
        for category in categories() {
            for root in category.roots {
                XCTAssertTrue(root.path.hasPrefix(home.path),
                              "\(category.id): корень \(root.path) вне переданного дома")
            }
        }
    }

    /// Категория с несколькими корнями — ради неё packageCaches и попала
    /// в первую версию: на ней проверяется, что модель это выдерживает.
    func testPackageCachesHasSeveralRoots() {
        let category = categories().first { $0.id == "packageCaches" }
        XCTAssertGreaterThan(category?.roots.count ?? 0, 3)
    }

    func testEveryCategoryExplainsConsequence() {
        for category in categories() {
            XCTAssertFalse(category.title.isEmpty, "\(category.id): пустой заголовок")
            XCTAssertFalse(category.consequence.isEmpty, "\(category.id): не сказано о последствии")
        }
    }

    /// Корень категории удалять нельзя — только его содержимое.
    func testGuardRejectsRootsButAllowsTheirChildren() {
        let sut = Catalog.pathGuard(home: home, listing: { _ in [] })
        for category in categories() {
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
        let sut = Catalog.pathGuard(home: home, listing: { _ in [] })
        for unsafe in ["Documents", "Desktop", "Downloads", "Library/Mobile Documents",
                       "Library/Keychains", ".ssh", "Library/Developer/Xcode/Archives",
                       "Library/Developer/Xcode/UserData"] {
            XCTAssertEqual(sut.validate(home.appendingPathComponent(unsafe)), .failure(.inDenyList),
                           "\(unsafe) обязан быть в стоп-листе")
        }
    }
}
