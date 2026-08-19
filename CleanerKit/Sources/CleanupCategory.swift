import Foundation

/// Категория мусора: что чистим и чем это обернётся.
public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// Что произойдёт после удаления. Пользователь вправе знать это до, а не после.
    public let consequence: String
    public let roots: [URL]

    public init(id: String, title: String, consequence: String, roots: [URL]) {
        self.id = id
        self.title = title
        self.consequence = consequence
        self.roots = roots
    }
}

/// Что чистим и что защищаем.
///
/// `home` приходит параметром, а не берётся из `FileManager`: иначе тесты
/// пришлось бы гонять по настоящему каталогу пользователя.
public enum Catalog {
    /// `listing` подменяется в тестах: часть корней вычисляется по факту
    /// содержимого каталога, а тест не должен зависеть от чужой машины.
    public static func standard(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> [CleanupCategory] {
        [
            CleanupCategory(
                id: "derivedData",
                title: "Xcode DerivedData",
                consequence: "Первая сборка будет дольше, проекты переиндексируются",
                roots: [home.appending(path: "Library/Developer/Xcode/DerivedData")]
            ),
            CleanupCategory(
                id: "deviceSupport",
                title: "Символы подключённых устройств",
                consequence: "Перекачается при следующем подключении устройства",
                roots: [
                    home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"),
                    home.appending(path: "Library/Developer/Xcode/watchOS DeviceSupport"),
                    home.appending(path: "Library/Developer/Xcode/tvOS DeviceSupport"),
                ]
            ),
            CleanupCategory(
                id: "packageCaches",
                title: "Кэши пакетных менеджеров",
                consequence: "Первая установка пакетов будет дольше",
                roots: [
                    home.appending(path: ".npm/_cacache"),
                    home.appending(path: "Library/Caches/Yarn"),
                    home.appending(path: "Library/pnpm/store"),
                    home.appending(path: "Library/Caches/pip"),
                    home.appending(path: "Library/Caches/CocoaPods"),
                    home.appending(path: ".gradle/caches"),
                ]
            ),
            CleanupCategory(
                id: "xcodeBuildMCP",
                title: "XcodeBuildMCP workspaces",
                consequence: "Пересоздастся при следующей сборке через MCP",
                roots: [home.appending(path: "Library/Developer/XcodeBuildMCP/workspaces")]
            ),
            CleanupCategory(
                id: "swiftPM",
                title: "Кэш SwiftPM и документации",
                consequence: "Пакеты и документация перекачаются",
                roots: [
                    home.appending(path: "Library/Caches/org.swift.swiftpm"),
                    home.appending(path: "Library/Developer/Xcode/DocumentationCache"),
                ]
            ),
            CleanupCategory(
                id: "appCaches",
                title: "Кэши приложений",
                consequence: "Приложения перестроят кэш при следующем запуске",
                roots: [
                    "com.apple.dt.Xcode", "JetBrains", "com.microsoft.VSCode",
                    "Google", "Homebrew", "ms-playwright", "ms-playwright-go",
                    "typescript", "node-gyp", "electron", "Cypress",
                    "com.openai.codex", "antigravity-updater",
                ].map { home.appending(path: "Library/Caches/\($0)") }
            ),
            CleanupCategory(
                id: "appUpdaters",
                title: "Загруженные обновления приложений",
                consequence: "Установщики уже применённых обновлений, скачаются заново при нужде",
                roots: listing(home.appending(path: "Library/Caches"))
                    .filter { $0.lastPathComponent.hasSuffix(".ShipIt") }
            ),
        ]
    }

    public static func contentsOfDirectory(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) ?? []
    }

    /// Разрешены только корни категорий. Сам корень удалить нельзя —
    /// `PathGuard` отклонит его как `isRootItself`, — но содержимое можно.
    public static func allowedRoots(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> [URL] {
        standard(home: home, listing: listing).flatMap(\.roots)
    }

    /// Не трогаем никогда, даже если путь попал в разрешённый корень.
    public static func deniedPaths(home: URL) -> [URL] {
        [
            "Documents", "Desktop", "Downloads",
            "Library/Mobile Documents",     // iCloud Drive
            "Library/Photos", "Library/Mail", "Library/Messages",
            "Library/Keychains",
            "Library/Application Support/MobileSync",  // бэкапы устройств
            "Library/Developer/Xcode/Archives",        // собранные релизы
            "Library/Developer/Xcode/UserData",        // схемы, сниппеты, брейкпоинты
            ".ssh",
        ].map { home.appending(path: $0) }
    }

    public static func pathGuard(
        home: URL,
        listing: (URL) -> [URL] = Catalog.contentsOfDirectory
    ) -> PathGuard {
        PathGuard(allowedRoots: allowedRoots(home: home, listing: listing),
                  deniedPaths: deniedPaths(home: home))
    }
}

