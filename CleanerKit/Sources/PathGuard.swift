import Foundation

/// Причина, по которой путь не допущен к удалению.
public enum GuardRejection: Error, Equatable, Sendable {
    case notAbsolute
    case traversal
    case isRootItself
    case inDenyList
    case outsideAllowedRoots
    case doesNotExist
    case symlink
}

/// Единственные ворота, через которые проходит всё удаляемое.
///
/// Корни и стоп-лист передаются снаружи, а не зашиты константами: так проверки
/// можно гонять на временном каталоге, не трогая настоящий дом пользователя.
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
        // Проверяем до нормализации: standardized молча схлопнул бы ".." и
        // превратил обход каталогов в безобидный путь.
        guard !url.pathComponents.contains("..") else { return .failure(.traversal) }

        let parts = Self.components(of: url)

        if allowedRoots.contains(parts) { return .failure(.isRootItself) }

        // Сравнение в обе стороны: нельзя ни удалить запрещённое,
        // ни удалить каталог, внутри которого запрещённое лежит.
        for denied in deniedPaths
            where denied == parts
            || Self.isPrefix(denied, of: parts)
            || Self.isPrefix(parts, of: denied) {
            return .failure(.inDenyList)
        }

        guard allowedRoots.contains(where: { Self.isPrefix($0, of: parts) }) else {
            return .failure(.outsideAllowedRoots)
        }

        // attributesOfItem не идёт по ссылке — именно это нам и нужно,
        // иначе симлинк выдал бы себя за свою цель.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: raw) else {
            return .failure(.doesNotExist)
        }
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            return .failure(.symlink)
        }

        return .success(url)
    }

    /// Сравнение по компонентам, а не по строкам: строковый префикс счёл бы
    /// "/a/CachesOther" продолжением "/a/Caches".
    private static func isPrefix(_ prefix: [String], of parts: [String]) -> Bool {
        guard prefix.count < parts.count else { return false }
        return Array(parts.prefix(prefix.count)) == prefix
    }

    private static func components(of url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }
}
