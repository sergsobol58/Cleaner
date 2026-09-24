import Foundation

/// Room on the volume, and the Trash standing between "moved" and "freed".
///
/// The distinction is the whole point of this file: moving 20 GB to the Trash
/// frees nothing until the Trash is emptied, and an app that reports the first
/// number as though it were the second is lying to the person using it.
public enum DiskSpace {
    /// What the system is willing to give an application that asks for room.
    public static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
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
