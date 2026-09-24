import Foundation

/// Where removed items go. A separate protocol so tests never touch the
/// real Trash.
public protocol FileTrashing: Sendable {
    func trash(_ url: URL) throws
}

/// The system Trash: the move is undone by Finder's "Put Back".
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

/// Moves the selection to the Trash.
public struct Remover: Sendable {
    private let pathGuard: PathGuard
    private let trash: FileTrashing

    public init(pathGuard: PathGuard, trash: FileTrashing) {
        self.pathGuard = pathGuard
        self.trash = trash
    }

    /// Sequential rather than parallel: speed is not the prize here,
    /// a predictable report is.
    public func remove(_ items: [ScanItem]) async -> RemovalReport {
        var moved: [RemovalOutcome] = []
        var failed: [RemovalOutcome] = []

        for item in items {
            // Second line of defence. The selection already refuses held
            // findings; a caller assembling a list by hand does not.
            if let hold = item.hold {
                failed.append(RemovalOutcome(item: item, error: hold.reason))
                continue
            }

            // Scan results are not trusted: the path is checked again, now.
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
        case .notAbsolute:         kitString("the path is not absolute")
        case .traversal:           kitString("the path contains ..")
        case .isRootItself:        kitString("this is a category root; only its contents are removed")
        case .inDenyList:          kitString("the path is on the never-touch list")
        case .outsideAllowedRoots: kitString("the path is outside the allowed directories")
        case .doesNotExist:        kitString("the path disappeared after the scan")
        case .symlink:             kitString("this is a symbolic link")
        }
    }
}
