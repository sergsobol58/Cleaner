import Foundation

/// Room on the volume, and the Trash standing between "moved" and "freed".
///
/// The distinction is the whole point of this file: moving 20 GB to the Trash
/// frees nothing until the Trash is emptied, and an app that reports the first
/// number as though it were the second is lying to the person using it.
/// What a volume has, and the gap macOS papers over.
///
/// `free` is what is actually unused; `available` is what the system promises
/// an app that asks for room, because it will evict caches and snapshots to
/// make good on it. The difference is the "purgeable" space that explains why
/// a Mac can report little free room and then find some.
public struct VolumeSpace: Sendable, Equatable {
    public let total: Int64
    public let free: Int64
    public let available: Int64

    public init(total: Int64, free: Int64, available: Int64) {
        self.total = total
        self.free = free
        self.available = available
    }

    public var purgeable: Int64 { max(0, available - free) }
}

public enum DiskSpace {
    /// What the system is willing to give an application that asks for room.
    public static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static func volume(at url: URL) -> VolumeSpace? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity,
           let free = values.volumeAvailableCapacity else { return nil }

        return VolumeSpace(
            total: Int64(total),
            free: Int64(free),
            available: values.volumeAvailableCapacityForImportantUsage ?? Int64(free))
    }
}

public enum TrashFolder {
    public static func url(home: URL) -> URL { home.appending(path: ".Trash") }

    /// Zero when the Trash cannot be read, which reads the same as empty on
    /// screen — acceptable here, because this number only ever adds context
    /// to an action the user already took.
    public static func sizeBytes(home: URL) -> Int64 {
        let trash = url(home: home)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil) else { return 0 }
        return entries.reduce(0) { $0 + allocatedSize(of: $1) }
    }
}
