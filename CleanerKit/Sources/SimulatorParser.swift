import Foundation

public struct SimulatorDevice: Identifiable, Sendable, Equatable {
    public let id: String          // UDID
    public let name: String
    public let runtime: String
    public let isBooted: Bool
    public let isUnavailable: Bool
    public var sizeBytes: Int64 = 0
    /// When the device directory last changed. The best available signal
    /// for "nobody has used this in ages": simctl reports no date of its own.
    public var lastUsed: Date?
}

public struct SimulatorRuntime: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sizeBytes: Int64
    public let lastUsed: Date?
    public let isDeletable: Bool
    public var deviceCount: Int = 0
}

/// Parsing of `simctl` output. Pure functions, verified against recorded
/// fixtures without a single simulator present.
public enum SimulatorParser {
    private static let udid = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/

    public static func devices(from output: String) -> [SimulatorDevice] {
        var runtime = ""
        var result: [SimulatorDevice] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)

            if text.hasPrefix("-- "), text.hasSuffix(" --") {
                runtime = header(text)
                continue
            }

            // The UDID is found by regex rather than by splitting on
            // parentheses: names like "iPad Pro 13-inch (M5)" contain their own.
            guard let match = text.firstMatch(of: udid) else { continue }

            let name = String(text[text.startIndex..<match.range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "($", with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ("))

            let tail = String(text[match.range.upperBound...])
            result.append(SimulatorDevice(
                id: String(text[match.range]),
                name: name,
                runtime: runtime,
                isBooted: tail.contains("(Booted)"),
                isUnavailable: tail.contains("unavailable")
            ))
        }
        return result
    }

    /// "-- iOS 26.3 --" becomes "iOS 26.3".
    /// "-- Unavailable: com.apple...SimRuntime.iOS-26-2 --" becomes "iOS 26.2".
    private static func header(_ line: String) -> String {
        var value = String(line.dropFirst(3).dropLast(3))
        guard value.hasPrefix("Unavailable:") else { return value }

        guard let range = value.range(of: "SimRuntime.") else { return kitString("unknown runtime") }
        value = String(value[range.upperBound...]).replacingOccurrences(of: "-", with: ".")
        if let dot = value.firstIndex(of: ".") {
            value.replaceSubrange(dot...dot, with: " ")
        }
        return value
    }

    public static func runtimes(from output: String) -> [SimulatorRuntime] {
        var result: [SimulatorRuntime] = []
        var name: String?
        var id = ""
        var size: Int64 = 0
        var lastUsed: Date?
        var deletable = false

        func flush() {
            guard let name else { return }
            result.append(SimulatorRuntime(id: id, name: name, sizeBytes: size,
                                           lastUsed: lastUsed, isDeletable: deletable))
        }

        for line in output.split(separator: "\n") {
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            if !text.hasPrefix(" "), let separator = text.range(of: " - "),
               text[separator.upperBound...].firstMatch(of: udid) != nil {
                flush()
                name = String(text[text.startIndex..<separator.lowerBound])
                id = String(text[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                size = 0; lastUsed = nil; deletable = false
            } else if trimmed.hasPrefix("Size:") {
                size = bytes(from: value(of: trimmed))
            } else if trimmed.hasPrefix("Deletable:") {
                deletable = value(of: trimmed) == "YES"
            } else if trimmed.hasPrefix("Last Used At:") {
                lastUsed = date(from: value(of: trimmed))
            }
        }
        flush()
        return result
    }

    /// A runtime with no devices is the first candidate for removal.
    public static func countDevices(runtimes: [SimulatorRuntime],
                                    devices: [SimulatorDevice]) -> [SimulatorRuntime] {
        runtimes.map { runtime in
            var counted = runtime
            counted.deviceCount = devices.filter {
                !$0.runtime.isEmpty && runtime.name.hasPrefix($0.runtime)
            }.count
            return counted
        }
    }

    private static func value(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Turns "7.8G" into bytes.
    private static func bytes(from text: String) -> Int64 {
        let units: [(Character, Double)] = [("K", 1024), ("M", 1_048_576),
                                            ("G", 1_073_741_824), ("T", 1_099_511_627_776)]
        guard let unit = text.last else { return 0 }
        guard let factor = units.first(where: { $0.0 == unit })?.1 else {
            return Int64(Double(text) ?? 0)
        }
        return Int64((Double(text.dropLast()) ?? 0) * factor)
    }

    private static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
    }
}
