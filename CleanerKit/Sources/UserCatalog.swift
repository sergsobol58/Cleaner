import Foundation

/// A directory the user asked this app to watch.
public struct UserFolder: Sendable, Equatable, Codable {
    public var title: String
    /// Written the way a person writes a path, `~` included.
    public var path: String
    public var consequence: String?

    public init(title: String, path: String, consequence: String? = nil) {
        self.title = title
        self.path = path
        self.consequence = consequence
    }
}

/// The user's own edits to the catalog, kept in a file so it can change
/// without rebuilding the app.
///
/// Deliberately not a re-encoding of the built-in categories. Five of those
/// are computed — a search for cache directories by name, a rule for
/// identifying abandoned applications, filters over a listing — and putting
/// them in a file would mean inventing a small language for describing what
/// to delete. That is a poor thing to invent. What belongs in a file is the
/// part that is genuinely the user's: which built-in categories to switch
/// off, and which directories of their own to add.
public struct UserCatalog: Sendable, Equatable, Codable {
    /// Identifiers of built-in categories to leave out.
    public var disabled: [String]
    public var folders: [UserFolder]

    public init(disabled: [String] = [], folders: [UserFolder] = []) {
        self.disabled = disabled
        self.folders = folders
    }

    public static let empty = UserCatalog()
}

/// Why a directory cannot be added.
public enum FolderRejection: Error, Equatable, Sendable {
    case notAbsolute
    case traversal
    case outsideHome
    case homeItself
    case neverTouched
    case notADirectory
    case alreadyCovered

    public var reason: String {
        switch self {
        case .notAbsolute:    kitString("that is not a full path")
        case .traversal:      kitString("the path contains ..")
        case .outsideHome:    kitString("only folders inside your home folder can be added")
        case .homeItself:     kitString("that is your home folder")
        case .neverTouched:   kitString("this folder is on the never-touch list")
        case .notADirectory:  kitString("that is not a folder")
        case .alreadyCovered: kitString("a built-in category already covers this folder")
        }
    }
}

public enum UserCatalogStore {
    public static func url(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Cleaner/catalog.json")
    }

    /// A file that cannot be read yields defaults and a complaint. Silently
    /// ignoring a hand-edited file would leave the user believing an edit
    /// took effect when it did nothing.
    public static func load(home: URL) -> (catalog: UserCatalog, problem: String?) {
        let file = url(home: home)
        guard let data = try? Data(contentsOf: file) else { return (.empty, nil) }
        do {
            return (try JSONDecoder().decode(UserCatalog.self, from: data), nil)
        } catch {
            return (.empty, error.localizedDescription)
        }
    }

    public static func save(_ catalog: UserCatalog, home: URL) throws {
        let file = url(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: file, options: .atomic)
    }

    /// The gate every user-supplied path passes before it can widen what the
    /// app is allowed to delete.
    ///
    /// `covered` is the roots of built-in categories that take every child.
    /// Categories that pick their children by a rule are left out: they do
    /// not claim their whole subtree, so a folder inside one is not a
    /// duplicate of anything.
    public static func validate(_ raw: String, home: URL,
                                covered: [URL], denied: [URL]) -> Result<URL, FolderRejection> {
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return .failure(.notAbsolute) }

        let url = URL(fileURLWithPath: expanded)
        guard !url.pathComponents.contains("..") else { return .failure(.traversal) }

        let parts = components(url)
        let homeParts = components(home)
        guard parts != homeParts else { return .failure(.homeItself) }
        guard isPrefix(homeParts, of: parts) else { return .failure(.outsideHome) }

        for path in denied.map(components)
            where path == parts || isPrefix(path, of: parts) || isPrefix(parts, of: path) {
            return .failure(.neverTouched)
        }

        for root in covered.map(components)
            where root == parts || isPrefix(root, of: parts) || isPrefix(parts, of: root) {
            return .failure(.alreadyCovered)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failure(.notADirectory) }

        return .success(url)
    }

    private static func components(_ url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }

    private static func isPrefix(_ prefix: [String], of parts: [String]) -> Bool {
        guard prefix.count < parts.count else { return false }
        return Array(parts.prefix(prefix.count)) == prefix
    }
}
