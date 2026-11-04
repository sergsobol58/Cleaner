import XCTest
@testable import CleanerKit

final class MemoryCountersTests: XCTestCase {
    private let page: Int64 = 16_384

    private func counters(free: Int64 = 0, speculative: Int64 = 0, wired: Int64 = 0,
                          compressed: Int64 = 0, internalPages: Int64 = 0,
                          externalPages: Int64 = 0, purgeable: Int64 = 0,
                          total: Int64 = 0, swap: Int64 = 0,
                          pressure: Int32 = 1) -> MemoryCounters {
        MemoryCounters(pageSize: page, totalBytes: total, free: free,
                       speculative: speculative, wired: wired, compressed: compressed,
                       internalPages: internalPages, externalPages: externalPages,
                       purgeable: purgeable, swapUsedBytes: swap, pressureLevel: pressure)
    }

    /// Purgeable pages are counted as internal by the kernel, but the system
    /// drops them on demand — so they are cache, not application memory.
    func testPurgeablePagesCountAsCacheNotAsApplicationMemory() {
        let snapshot = counters(internalPages: 100, externalPages: 50, purgeable: 30).snapshot

        XCTAssertEqual(snapshot.app, 70 * page)
        XCTAssertEqual(snapshot.cached, 80 * page)
    }

    /// Speculative pages are read ahead on a guess and are not really free.
    func testSpeculativePagesAreNotCountedAsFree() {
        XCTAssertEqual(counters(free: 100, speculative: 40).snapshot.free, 60 * page)
    }

    func testUsedIsApplicationPlusWiredPlusCompressed() {
        let snapshot = counters(wired: 10, compressed: 20, internalPages: 30).snapshot
        XCTAssertEqual(snapshot.used, 60 * page)
    }

    /// Taken from a real machine: the parts must add up to the whole.
    func testThePartsAccountForTheWholeOfPhysicalMemory() {
        let total: Int64 = 36 * 1_073_741_824
        let snapshot = counters(free: 91_750, wired: 411_041, compressed: 623_329,
                                internalPages: 770_703, externalPages: 435_896,
                                purgeable: 26_869, total: total).snapshot

        let accounted = snapshot.used + snapshot.cached + snapshot.free
        XCTAssertEqual(Double(accounted) / Double(total), 1, accuracy: 0.02)
    }

    func testNegativeDerivationsAreClampedRatherThanWrappingAround() {
        let snapshot = counters(free: 10, speculative: 50, internalPages: 10,
                                purgeable: 90).snapshot
        XCTAssertEqual(snapshot.free, 0)
        XCTAssertEqual(snapshot.app, 0)
    }
}

final class MemoryPressureTests: XCTestCase {
    func testLevelsMapToTheKernelsOwnNumbering() {
        XCTAssertEqual(MemoryPressure(level: 1), .normal)
        XCTAssertEqual(MemoryPressure(level: 2), .warning)
        XCTAssertEqual(MemoryPressure(level: 4), .critical)
        XCTAssertEqual(MemoryPressure(level: 0), .normal, "an unknown level is not an alarm")
    }

    private func snapshot(swap: Int64, pressure: MemoryPressure) -> MemorySnapshot {
        MemorySnapshot(total: 100, app: 10, wired: 10, compressed: 10,
                       cached: 10, free: 10, swapUsed: swap, pressure: pressure)
    }

    /// The kernel reports normal pressure while writing gigabytes to swap,
    /// because it is coping — by making everything slower.
    func testHeavySwapCountsAsStrainEvenAtNormalPressure() {
        XCTAssertTrue(snapshot(swap: 23 * 1_073_741_824, pressure: .normal).isStrained)
        XCTAssertFalse(snapshot(swap: 0, pressure: .normal).isStrained)
        XCTAssertTrue(snapshot(swap: 0, pressure: .warning).isStrained)
    }
}

final class ProcessorTimeTests: XCTestCase {
    /// A cumulative counter only means something as a difference. Without a
    /// previous reading there is nothing to subtract from, and reporting a
    /// number computed from the whole lifetime would be a lie about now.
    func testAFirstReadingReportsNothing() {
        XCTAssertEqual(ProcessorTime.percent(previous: nil, current: 5_000_000_000,
                                             elapsed: 1), 0)
    }

    func testOneCoreFullyBusyReadsAsOneHundred() {
        XCTAssertEqual(ProcessorTime.percent(previous: 0, current: 2_000_000_000,
                                             elapsed: 2), 100, accuracy: 0.001)
    }

    func testTwoCoresFullyBusyReadAsTwoHundred() {
        XCTAssertEqual(ProcessorTime.percent(previous: 0, current: 4_000_000_000,
                                             elapsed: 2), 200, accuracy: 0.001)
    }

    /// A pid is reused the moment its process dies, so the counter can go
    /// backwards. A negative percentage would be nonsense.
    func testACounterThatWentBackwardsReportsNothing() {
        XCTAssertEqual(ProcessorTime.percent(previous: 9_000, current: 10, elapsed: 1), 0)
    }

    func testNoTimePassedReportsNothing() {
        XCTAssertEqual(ProcessorTime.percent(previous: 0, current: 1_000, elapsed: 0), 0)
    }
}
