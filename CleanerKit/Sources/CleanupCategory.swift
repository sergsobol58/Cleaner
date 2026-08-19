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
    public static func standard(home: URL) -> [CleanupCategory] {
        [
            CleanupCategory(
                id: "derivedData",
                title: "Xcode DerivedData",
                consequence: "Первая сборка будет дольше, проекты переиндексируются",
                roots: [home / "Library/Developer/Xcode/DerivedData"]
            ),
            CleanupCategory(
                id: "deviceSupport",
                title: "Символы подключённых устройств",
                consequence: "Перекачается при следующем подключении устройства",
                roots: [
                    home / "Library/Developer/Xcode/iOS DeviceSupport",
                    home / "Library/Developer/Xcode/watchOS DeviceSupport",
                    home / "Library/Developer/Xcode/tvOS DeviceSupport",
                ]
            ),
            CleanupCategory(
                id: "packageCaches",
                title: "Кэши пакетных менеджеров",
                consequence: "Первая установка пакетов будет дольше",
                roots: [
                    home / ".npm/_cacache",
                    home / "Library/Caches/Yarn",
                    home / "Library/pnpm/store",
                    home / "Library/Caches/pip",
                    home / "Library/Caches/CocoaPods",
                    home / ".gradle/caches",
                ]
            ),
        ]
    }

    /// Разрешены только корни категорий. Сам корень удалить нельзя —
    /// `PathGuard` отклонит его как `isRootItself`, — но содержимое можно.
    public static func allowedRoots(home: URL) -> [URL] {
        standard(home: home).flatMap(\.roots)
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
        ].map { home / $0 }
    }

    public static func pathGuard(home: URL) -> PathGuard {
        PathGuard(allowedRoots: allowedRoots(home: home), deniedPaths: deniedPaths(home: home))
    }
}

infix operator /: AdditionPrecedence

extension URL {
    static func / (base: URL, path: String) -> URL {
        base.appending(path: path, directoryHint: .isDirectory)
    }
}
