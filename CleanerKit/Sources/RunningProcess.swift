import Darwin
import Foundation

/// Why a process must not be asked to quit.
public enum ProcessRejection: Error, Equatable, Sendable {
    case notYours
    case essential
    case isCleanerItself

    public var reason: String {
        switch self {
        case .notYours:        kitString("belongs to another user")
        case .essential:       kitString("the session depends on it")
        case .isCleanerItself: kitString("this is Cleaner")
        }
    }
}

public struct RunningProcess: Identifiable, Sendable, Equatable {
    public let id: pid_t
    public var pid: pid_t { id }
    public let name: String
    /// Physical memory the process holds right now.
    public let residentBytes: Int64
    public let cpuPercent: Double
    public let uid: uid_t
    /// Set when the process must not be signalled.
    public let protection: ProcessRejection?

    public var canQuit: Bool { protection == nil }

    public init(pid: pid_t, name: String, residentBytes: Int64, cpuPercent: Double,
                uid: uid_t, protection: ProcessRejection? = nil) {
        self.id = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.uid = uid
        self.protection = protection
    }
}

/// The single gate every process passes through before it can be signalled.
///
/// The same shape as `PathGuard`, for the same reason: quitting the wrong
/// process ends the login session, and that decision belongs in one tested
/// place rather than spread through a view.
public struct ProcessGuard: Sendable {
    /// Quitting any of these ends or breaks the session rather than merely
    /// closing something. Named rather than matched by pattern: the list is
    /// short, and a pattern would eventually catch something innocent.
    ///
    /// Dock and Finder are deliberately absent — macOS relaunches them, so
    /// quitting one is disruptive but not destructive.
    static let essential: Set<String> = [
        "launchd", "kernel_task", "loginwindow", "WindowServer",
        "logind", "securityd", "opendirectoryd", "distnoted",
    ]

    private let currentUser: uid_t
    private let ownPID: pid_t

    public init(currentUser: uid_t, ownPID: pid_t) {
        self.currentUser = currentUser
        self.ownPID = ownPID
    }

    public func validate(name: String, uid: uid_t, pid: pid_t) -> ProcessRejection? {
        if pid == ownPID { return .isCleanerItself }
        // Signalling another user's process needs privileges this app does
        // not have and should not want.
        if uid != currentUser { return .notYours }
        if pid <= 1 { return .essential }
        if Self.essential.contains(name) { return .essential }
        return nil
    }
}

/// Processor time a process has used, as the kernel counts it: cumulative
/// nanoseconds since it started.
public enum ProcessorTime {
    /// Share of one core, as a percentage, between two readings.
    ///
    /// Cumulative counters only mean something as a difference, and a first
    /// reading has nothing to subtract from — which is why a fresh process
    /// reports zero rather than a number invented from its whole lifetime.
    public static func percent(previous: Int64?, current: Int64,
                               elapsed: TimeInterval) -> Double {
        guard let previous, elapsed > 0, current >= previous else { return 0 }
        let nanoseconds = Double(current - previous)
        return nanoseconds / (elapsed * 1_000_000_000) * 100
    }
}

/// Where a quit request goes. A protocol so tests never signal a real process.
public protocol ProcessSignalling: Sendable {
    func terminate(_ pid: pid_t) throws
}

/// Asks politely: `SIGTERM` lets an application save and close, which is the
/// difference between quitting it and losing what was open in it.
public struct SystemSignal: ProcessSignalling {
    public init() {}

    public func terminate(_ pid: pid_t) throws {
        if kill(pid, SIGTERM) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

public struct QuitOutcome: Sendable {
    public let process: RunningProcess
    public let error: String?
}

public struct QuitReport: Sendable {
    public let asked: [QuitOutcome]
    public let refused: [QuitOutcome]

    public var askedBytes: Int64 { asked.reduce(0) { $0 + $1.process.residentBytes } }
}

/// Asks the selected processes to quit.
public struct ProcessTerminator: Sendable {
    private let processGuard: ProcessGuard
    private let signal: ProcessSignalling

    public init(processGuard: ProcessGuard, signal: ProcessSignalling) {
        self.processGuard = processGuard
        self.signal = signal
    }

    public func quit(_ processes: [RunningProcess]) async -> QuitReport {
        var asked: [QuitOutcome] = []
        var refused: [QuitOutcome] = []

        for process in processes {
            // The list is seconds old and a pid is reused the moment its
            // process dies, so the guard runs again on the way out.
            if let rejection = processGuard.validate(name: process.name,
                                                     uid: process.uid, pid: process.pid) {
                refused.append(QuitOutcome(process: process, error: rejection.reason))
                continue
            }
            do {
                try signal.terminate(process.pid)
                asked.append(QuitOutcome(process: process, error: nil))
            } catch {
                refused.append(QuitOutcome(process: process,
                                           error: error.localizedDescription))
            }
        }

        return QuitReport(asked: asked, refused: refused)
    }
}
