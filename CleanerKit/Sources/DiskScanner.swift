import Foundation

/// Находка: один каталог или файл, который можно удалить.
public struct ScanItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: URL
    public var url: URL { id }
    public let sizeBytes: Int64
    public let modified: Date

    public init(url: URL, sizeBytes: Int64, modified: Date) {
        self.id = url
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

/// Результат осмотра одной категории.
public struct CategoryScan: Identifiable, Sendable {
    public let id: String
    public let category: CleanupCategory
    public let items: [ScanItem]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

/// Осмотр категорий. Только чтение: ничего не изменяет и не удаляет.
public struct DiskScanner: Sendable {
    private let pathGuard: PathGuard

    public init(pathGuard: PathGuard) {
        self.pathGuard = pathGuard
    }

    public func scan(_ categories: [CleanupCategory]) async -> [CategoryScan] {
        await withTaskGroup(of: (Int, CategoryScan).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask { (index, await scanOne(category)) }
            }
            var result: [(Int, CategoryScan)] = []
            for await value in group { result.append(value) }
            // Порядок задач в группе не гарантирован — восстанавливаем исходный.
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func scanOne(_ category: CleanupCategory) async -> CategoryScan {
        let candidates = category.roots.flatMap(children(of:))

        let items = await withTaskGroup(of: ScanItem?.self) { group in
            for url in candidates {
                group.addTask { measure(url) }
            }
            var found: [ScanItem] = []
            for await item in group { if let item { found.append(item) } }
            return found
        }

        return CategoryScan(id: category.id, category: category,
                            items: items.sorted { $0.sizeBytes > $1.sizeBytes })
    }

    /// Только прямые потомки корня: сам корень не удаляем, вложенное считаем
    /// в размер, но отдельными строками не показываем.
    private func children(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
    }

    private func measure(_ url: URL) -> ScanItem? {
        // Что не проходит охрану, то и показывать незачем — иначе пользователь
        // отметит галочку, а на удалении получит необъяснимый отказ.
        guard case .success = pathGuard.validate(url) else { return nil }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        return ScanItem(url: url, sizeBytes: CleanerKit.allocatedSize(of: url), modified: modified)
    }

}
