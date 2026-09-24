import Foundation

/// Why a path was refused for deletion.
public enum GuardRejection: Error, Equatable, Sendable {
    case notAbsolute
    case traversal
    case isRootItself
    case inDenyList
    case outsideAllowedRoots
    case doesNotExist
    case symlink
}

/// The single gate every deletable path passes through.
///
/// Roots and the deny list are injected rather than hardcoded, so the checks
/// can run against a temporary directory instead of the user's real home.
public struct PathGuard: Sendable {
    private let allowedRoots: [[String]]
    private let deniedPaths: [[String]]

    public init(allowedRoots: [URL], deniedPaths: [URL]) {
        self.allowedRoots = allowedRoots.map { Self.components(of: $0) }
        self.deniedPaths = deniedPaths.map { Self.components(of: $0) }
    }

    public func validate(_ url: URL) -> Result<URL, GuardRejection> {
        let raw = url.path

        guard raw.hasPrefix("/") else { return .failure(.notAbsolute) }
        // Checked before normalisation: `standardized` would quietly collapse
        // ".." and turn directory traversal into an innocent-looking path.
        guard !url.pathComponents.contains("..") else { return .failure(.traversal) }

        let parts = Self.components(of: url)

        if allowedRoots.contains(parts) { return .failure(.isRootItself) }

        // Compared both ways: neither delete something forbidden, nor delete a
        // directory that has something forbidden inside it.
        for denied in deniedPaths
            where denied == parts
            || Self.isPrefix(denied, of: parts)
            || Self.isPrefix(parts, of: denied) {
            return .failure(.inDenyList)
        }

        // A direct child of a root, and nothing deeper. Every finding the
        // scanner produces is a direct child by construction, so this costs
        // nothing — and it stops a broad root like Application Support, which
        // the leftovers category needs, from quietly admitting everything
        // nested below it.
        guard allowedRoots.contains(where: { $0.count + 1 == parts.count
                                             && Self.isPrefix($0, of: parts) }) else {
            return .failure(.outsideAllowedRoots)
        }

        // attributesOfItem does not follow links, which is exactly what we
        // need here: otherwise a symlink would pass itself off as its target.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: raw) else {
            return .failure(.doesNotExist)
        }
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            return .failure(.symlink)
        }

        return .success(url)
    }

    /// Compared by path component rather than by string: a string prefix would
    /// treat "/a/CachesOther" as living inside "/a/Caches".
    private static func isPrefix(_ prefix: [String], of parts: [String]) -> Bool {
        guard prefix.count < parts.count else { return false }
        return Array(parts.prefix(prefix.count)) == prefix
    }

    private static func components(of url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }
}
