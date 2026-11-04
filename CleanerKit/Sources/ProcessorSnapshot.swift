import Foundation

/// Cumulative processor ticks since boot, as the kernel counts them.
public struct ProcessorTicks: Sendable, Equatable {
    public let user: Int64
    public let system: Int64
    public let idle: Int64
    public let nice: Int64

    public init(user: Int64, system: Int64, idle: Int64, nice: Int64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var total: Int64 { user + system + idle + nice }
}

/// How busy the machine is.
public struct ProcessorSnapshot: Sendable, Equatable {
    public let userPercent: Double
    public let systemPercent: Double
    public let coreCount: Int
    /// One, five and fifteen minute averages, in runnable processes.
    public let loadAverage: [Double]

    public init(userPercent: Double, systemPercent: Double, coreCount: Int,
                loadAverage: [Double]) {
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.coreCount = coreCount
        self.loadAverage = loadAverage
    }

    public var busyPercent: Double { userPercent + systemPercent }
    public var idlePercent: Double { max(0, 100 - busyPercent) }

    /// A load average above the core count means work is queueing: there are
    /// more processes wanting a core than there are cores to give.
    public var isQueueing: Bool {
        guard let oneMinute = loadAverage.first, coreCount > 0 else { return false }
        return oneMinute > Double(coreCount)
    }

    /// Ticks only mean something as a difference, so the first reading of a
    /// session reports an idle machine rather than inventing a number from
    /// everything that has happened since boot.
    public static func between(previous: ProcessorTicks?, current: ProcessorTicks,
                               coreCount: Int, loadAverage: [Double]) -> ProcessorSnapshot {
        guard let previous else {
            return ProcessorSnapshot(userPercent: 0, systemPercent: 0,
                                     coreCount: coreCount, loadAverage: loadAverage)
        }

        let elapsed = current.total - previous.total
        guard elapsed > 0 else {
            return ProcessorSnapshot(userPercent: 0, systemPercent: 0,
                                     coreCount: coreCount, loadAverage: loadAverage)
        }

        func share(_ now: Int64, _ before: Int64) -> Double {
            Double(max(0, now - before)) / Double(elapsed) * 100
        }

        return ProcessorSnapshot(
            // Niced work is still work someone asked for; hiding it would
            // leave a busy machine looking idle.
            userPercent: share(current.user + current.nice, previous.user + previous.nice),
            systemPercent: share(current.system, previous.system),
            coreCount: coreCount,
            loadAverage: loadAverage)
    }
}
