import Foundation

/// One finding: a directory or file that can be removed.
public struct ScanItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: URL
    public var url: URL { id }
    public let sizeBytes: Int64
    public let modified: Date
    /// The root this finding came from. Without it a name like "content-v2"
    /// tells the reader nothing in a flat list.
    public let root: URL

    public init(url: URL, sizeBytes: Int64, modified: Date, root: URL) {
        self.id = url
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.root = root
    }
}

/// Findings that share one root inside a category.
public struct ScanGroup: Identifiable, Sendable {
    public let id: URL
    public var root: URL { id }
    public let items: [ScanItem]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

/// The result of inspecting one category.
public struct CategoryScan: Identifiable, Sendable {
    public let id: String
    public let category: CleanupCategory
    public let items: [ScanItem]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    /// Split by root, largest groups first.
    public var groups: [ScanGroup] {
        Dictionary(grouping: items, by: \.root)
            .map { ScanGroup(id: $0.key, items: $0.value.sorted { $0.sizeBytes > $1.sizeBytes }) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

/// Inspection of categories. Read-only: changes and deletes nothing.
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
            // Task completion order is not guaranteed — restore the original.
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func scanOne(_ category: CleanupCategory) async -> CategoryScan {
        let candidates = category.roots.flatMap { root in
            children(of: root).map { (root: root, url: $0) }
        }

        let items = await withTaskGroup(of: ScanItem?.self) { group in
            for candidate in candidates {
                group.addTask { measure(candidate.url, root: candidate.root) }
            }
            var found: [ScanItem] = []
            for await item in group { if let item { found.append(item) } }
            return found
        }

        return CategoryScan(id: category.id, category: category,
                            items: items.sorted { $0.sizeBytes > $1.sizeBytes })
    }

    /// Direct children only: the root itself is never removed, and nested
    /// content counts towards the size without getting its own row.
    private func children(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
    }

    private func measure(_ url: URL, root: URL) -> ScanItem? {
        // What the guard refuses is not worth showing: otherwise the user
        // ticks a box and gets an unexplained refusal at deletion time.
        guard case .success = pathGuard.validate(url) else { return nil }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        return ScanItem(url: url, sizeBytes: CleanerKit.allocatedSize(of: url),
                        modified: modified, root: root)
    }
}
