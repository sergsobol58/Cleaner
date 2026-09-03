import Foundation

/// Насколько выбрана группа находок.
public enum Coverage: Sendable, Equatable {
    case none, partial, all
}

/// Что именно отмечено к удалению.
///
/// Живёт в CleanerKit, а не во вьюхе: от этого набора зависит, какие файлы
/// уедут в Корзину, и такое стоит держать под тестами.
public struct SelectionState: Sendable, Equatable {
    private var selected: Set<URL> = []

    public init() {}

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }

    public func contains(_ item: ScanItem) -> Bool { selected.contains(item.url) }

    public mutating func set(_ item: ScanItem, selected isOn: Bool) {
        if isOn { selected.insert(item.url) } else { selected.remove(item.url) }
    }

    public mutating func toggle(_ item: ScanItem) {
        if selected.contains(item.url) { selected.remove(item.url) }
        else { selected.insert(item.url) }
    }

    public mutating func set(_ items: [ScanItem], selected isOn: Bool) {
        for item in items {
            if isOn { selected.insert(item.url) } else { selected.remove(item.url) }
        }
    }

    /// Нажатие по частично выбранной группе добирает остаток, а не сбрасывает
    /// её: снять уже отмеченное пользователь может повторным нажатием.
    public mutating func toggleAll(_ items: [ScanItem]) {
        set(items, selected: coverage(of: items) != .all)
    }

    public func coverage(of items: [ScanItem]) -> Coverage {
        guard !items.isEmpty else { return .none }
        let chosen = items.filter { selected.contains($0.url) }.count
        if chosen == 0 { return .none }
        return chosen == items.count ? .all : .partial
    }

    public func items(from scans: [CategoryScan]) -> [ScanItem] {
        scans.flatMap(\.items).filter { selected.contains($0.url) }
    }

    public func bytes(in scans: [CategoryScan]) -> Int64 {
        items(from: scans).reduce(0) { $0 + $1.sizeBytes }
    }

    /// После удаления отметки на исчезнувшие пути держать незачем.
    public mutating func keepOnly(_ scans: [CategoryScan]) {
        let alive = Set(scans.flatMap(\.items).map(\.url))
        selected.formIntersection(alive)
    }
}
