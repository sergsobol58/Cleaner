import Foundation

/// Куда девается удаляемое. Отдельный протокол — чтобы тесты не трогали
/// настоящую Корзину.
public protocol FileTrashing: Sendable {
    func trash(_ url: URL) throws
}

/// Штатная Корзина macOS: перемещение обратимо кнопкой «Положить обратно».
public struct SystemTrash: FileTrashing {
    public init() {}

    public func trash(_ url: URL) throws {
        var restored: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &restored)
    }
}

public struct RemovalOutcome: Sendable {
    public let item: ScanItem
    public let error: String?
}

public struct RemovalReport: Sendable {
    public let moved: [RemovalOutcome]
    public let failed: [RemovalOutcome]

    public var movedBytes: Int64 { moved.reduce(0) { $0 + $1.item.sizeBytes } }
    public var isClean: Bool { failed.isEmpty }
}

/// Перемещение выбранного в Корзину.
public struct Remover: Sendable {
    private let pathGuard: PathGuard
    private let trash: FileTrashing

    public init(pathGuard: PathGuard, trash: FileTrashing) {
        self.pathGuard = pathGuard
        self.trash = trash
    }

    /// Последовательно, а не параллельно: скорость тут не выигрыш, а
    /// предсказуемость отчёта — выигрыш.
    public func remove(_ items: [ScanItem]) async -> RemovalReport {
        var moved: [RemovalOutcome] = []
        var failed: [RemovalOutcome] = []

        for item in items {
            // Результатам скана не доверяем: проверяем заново прямо сейчас.
            if case .failure(let rejection) = pathGuard.validate(item.url) {
                failed.append(RemovalOutcome(item: item, error: Self.describe(rejection)))
                continue
            }

            do {
                try trash.trash(item.url)
                moved.append(RemovalOutcome(item: item, error: nil))
            } catch {
                failed.append(RemovalOutcome(item: item, error: error.localizedDescription))
            }
        }

        return RemovalReport(moved: moved, failed: failed)
    }

    private static func describe(_ rejection: GuardRejection) -> String {
        switch rejection {
        case .notAbsolute:         "путь не абсолютный"
        case .traversal:           "путь содержит .."
        case .isRootItself:        "это корень категории, удаляется только содержимое"
        case .inDenyList:          "путь в стоп-листе"
        case .outsideAllowedRoots: "путь вне разрешённых каталогов"
        case .doesNotExist:        "путь исчез после сканирования"
        case .symlink:             "это символическая ссылка"
        }
    }
}
