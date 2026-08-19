import Foundation

/// Занимаемый объём с учётом вложенного. Совпадает с `du`: считаем
/// выделенное на диске, а не логический размер файла.
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
        total += Int64((try? child.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
    }
    return total
}
