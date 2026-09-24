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
    /// Set when the finding must not be removed right now.
    public let hold: Hold?

    public var isRemovable: Bool { hold == nil }

    public init(url: URL, sizeBytes: Int64, modified: Date, root: URL, hold: Hold? = nil) {
        self.id = url
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.root = root
        self.hold = hold
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
    /// Roots that exist but refused to be read. Reported rather than counted
    /// as empty: to the user "0 B" and "not allowed to look" are opposites,
    /// and only one of them means there is nothing to clean.
    public let unreadableRoots: [URL]

    public init(id: String, category: CleanupCategory, items: [ScanItem],
                unreadableRoots: [URL] = []) {
        self.id = id
        self.category = category
        self.items = items
        self.unreadableRoots = unreadableRoots
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var removableBytes: Int64 {
        items.filter(\.isRemovable).reduce(0) { $0 + $1.sizeBytes }
    }
    public var heldItems: [ScanItem] { items.filter { !$0.isRemovable } }

    /// Split by root, largest groups first.
    public var groups: [ScanGroup] {
        Dictionary(grouping: items, by: \.root)
            .map { ScanGroup(id: $0.key, items: $0.value.sorted { $0.sizeBytes > $1.sizeBytes }) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

/// What the scanner holds back, and the clock it measures against.
///
/// Injected rather than read from the system, so a test never depends on what
/// the developer happens to have open or on today's date.
public struct ScanPolicy: Sendable {
    public let home: URL
    public let runningApps: [RunningApp]
    public let now: Date

    public init(home: URL, runningApps: [RunningApp] = [], now: Date = .now) {
        self.home = home
        self.runningApps = runningApps
        self.now = now
    }
}

/// Inspection of categories. Read-only: changes and deletes nothing.
public struct DiskScanner: Sendable {
    private let pathGuard: PathGuard
    private let policy: ScanPolicy

    public init(pathGuard: PathGuard, policy: ScanPolicy) {
        self.pathGuard = pathGuard
        self.policy = policy
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
        var candidates: [(root: URL, url: URL)] = []
        var unreadable: [URL] = []

        for root in category.roots {
            let reading = children(of: root)
            if reading.unreadable { unreadable.append(root) }
            candidates += reading.urls.map { (root: root, url: $0) }
        }

        let items = await withTaskGroup(of: ScanItem?.self) { group in
            for candidate in candidates {
                group.addTask { measure(candidate.url, root: candidate.root, in: category) }
            }
            var found: [ScanItem] = []
            for await item in group { if let item { found.append(item) } }
            return found
        }

        return CategoryScan(id: category.id, category: category,
                            items: items.sorted { $0.sizeBytes > $1.sizeBytes },
                            unreadableRoots: unreadable)
    }

    /// Direct children only: the root itself is never removed, and nested
    /// content counts towards the size without getting its own row.
    ///
    /// A directory that is simply absent is not a permission problem, so the
    /// two failures are told apart rather than both reported as empty.
    private func children(of root: URL) -> (urls: [URL], unreadable: Bool) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
            return (urls, false)
        } catch {
            return ([], FileManager.default.fileExists(atPath: root.path))
        }
    }

    private func measure(_ url: URL, root: URL, in category: CleanupCategory) -> ScanItem? {
        // What the guard refuses is not worth showing: otherwise the user
        // ticks a box and gets an unexplained refusal at deletion time.
        guard case .success = pathGuard.validate(url) else { return nil }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        return ScanItem(url: url, sizeBytes: CleanerKit.allocatedSize(of: url),
                        modified: modified, root: root,
                        hold: hold(for: url, modified: modified, in: category))
    }

    /// A running application outranks the age rule: it is the more specific
    /// reason, and the more useful one to read.
    private func hold(for url: URL, modified: Date, in category: CleanupCategory) -> Hold? {
        if let app = AppAttribution.owner(of: url, among: policy.runningApps, home: policy.home) {
            return .appRunning(app.name)
        }
        guard category.minimumIdleDays > 0 else { return nil }
        let idle = policy.now.timeIntervalSince(modified)
        return idle < Double(category.minimumIdleDays) * 86_400 ? .changedRecently : nil
    }
}
