import Foundation

/// Space taken on disk, nested content included. Matches `du`: we count
/// allocated blocks rather than the logical file length.
public func allocatedSize(of url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]

    let values = try? url.resourceValues(forKeys: keys)
    if values?.isDirectory != true {
        return Int64(values?.totalFileAllocatedSize ?? 0)
    }

    guard let walker = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }

    var total: Int64 = 0
    for case let child as URL in walker {
        // Walking DerivedData can take a while, and a cancelled scan the user
        // is still waiting on is not a cancelled scan.
        if Task.isCancelled { return total }
        total += Int64((try? child.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
    }
    return total
}
