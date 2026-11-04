import Foundation

/// How hard the system is working to find memory.
public enum MemoryPressure: Int, Sendable, Equatable, Comparable {
    case normal = 1, warning = 2, critical = 4

    public static func < (a: MemoryPressure, b: MemoryPressure) -> Bool {
        a.rawValue < b.rawValue
    }

    public init(level: Int32) {
        self = switch level {
        case 4...: .critical
        case 2...: .warning
        default:   .normal
        }
    }
}

/// What the kernel reports about memory, in the shape Activity Monitor uses.
///
/// The raw page counters are kept out of this type on purpose: the derivation
/// from them is where the mistakes live, so it happens once, here, under test.
public struct MemorySnapshot: Sendable, Equatable {
    public let total: Int64
    /// Memory applications hold and cannot be taken back without asking them.
    public let app: Int64
    /// Memory the kernel cannot page out at all.
    public let wired: Int64
    /// Memory squeezed to make room. Growth here is the first sign of trouble.
    public let compressed: Int64
    /// File contents kept around in case they are wanted again. Counted as
    /// used by `df`-style thinking, but the system gives it up on demand.
    public let cached: Int64
    public let free: Int64
    public let swapUsed: Int64
    public let pressure: MemoryPressure

    public init(total: Int64, app: Int64, wired: Int64, compressed: Int64,
                cached: Int64, free: Int64, swapUsed: Int64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    /// What Activity Monitor calls "Memory Used": everything that is not
    /// cache and not free.
    public var used: Int64 { app + wired + compressed }

    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    public var cachedFraction: Double {
        total > 0 ? Double(cached) / Double(total) : 0
    }

    /// Swap in use says more than the pressure level does. The kernel reports
    /// normal pressure while writing gigabytes to disk, because it is coping
    /// — but coping by making everything slower.
    public var isStrained: Bool {
        pressure > .normal || swapUsed > 1_073_741_824
    }
}

/// Raw kernel counters, in pages. Separated from the snapshot so the
/// arithmetic that turns one into the other can be tested without a kernel.
public struct MemoryCounters: Sendable, Equatable {
    public let pageSize: Int64
    public let totalBytes: Int64
    public let free: Int64
    public let speculative: Int64
    public let wired: Int64
    public let compressed: Int64
    public let internalPages: Int64
    public let externalPages: Int64
    public let purgeable: Int64
    public let swapUsedBytes: Int64
    public let pressureLevel: Int32

    public init(pageSize: Int64, totalBytes: Int64, free: Int64, speculative: Int64,
                wired: Int64, compressed: Int64, internalPages: Int64,
                externalPages: Int64, purgeable: Int64, swapUsedBytes: Int64,
                pressureLevel: Int32) {
        self.pageSize = pageSize
        self.totalBytes = totalBytes
        self.free = free
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.internalPages = internalPages
        self.externalPages = externalPages
        self.purgeable = purgeable
        self.swapUsedBytes = swapUsedBytes
        self.pressureLevel = pressureLevel
    }

    public var snapshot: MemorySnapshot {
        func bytes(_ pages: Int64) -> Int64 { max(0, pages) * pageSize }

        return MemorySnapshot(
            total: totalBytes,
            // Purgeable pages are counted as internal by the kernel but the
            // system can drop them, so they belong with the cache.
            app: bytes(internalPages - purgeable),
            wired: bytes(wired),
            compressed: bytes(compressed),
            cached: bytes(externalPages + purgeable),
            free: bytes(free - speculative),
            swapUsed: swapUsedBytes,
            pressure: MemoryPressure(level: pressureLevel))
    }
}
