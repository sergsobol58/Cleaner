import XCTest
@testable import CleanerKit

final class SimulatorTriageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func device(_ name: String, booted: Bool = false, unavailable: Bool = false,
                        daysAgo: Int? = nil) -> SimulatorDevice {
        SimulatorDevice(
            id: name, name: name, runtime: "iOS 26.5",
            isBooted: booted, isUnavailable: unavailable, sizeBytes: 1_000,
            lastUsed: daysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) }
        )
    }

    func testCatchesDeviceWithoutRuntime() {
        let found = SimulatorTriage.unusedDevices([device("dead", unavailable: true, daysAgo: 1)], now: now)
        XCTAssertEqual(found.map(\.reason), [.runtimeMissing])
    }

    func testCatchesForgottenDevice() {
        let found = SimulatorTriage.unusedDevices([device("forgotten", daysAgo: 120)], now: now)
        XCTAssertEqual(found.map(\.reason), [.untouched(days: 120)])
    }

    func testKeepsRecentlyUsedDevice() {
        XCTAssertTrue(SimulatorTriage.unusedDevices([device("fresh", daysAgo: 10)], now: now).isEmpty)
    }

    /// A running device is never suggested, however ancient it is.
    func testNeverSuggestsBootedDevice() {
        let ancient = device("running", booted: true, daysAgo: 999)
        XCTAssertTrue(SimulatorTriage.unusedDevices([ancient], now: now).isEmpty)
    }

    func testBootedDeviceWithoutRuntimeIsStillSpared() {
        let odd = device("odd", booted: true, unavailable: true, daysAgo: 999)
        XCTAssertTrue(SimulatorTriage.unusedDevices([odd], now: now).isEmpty)
    }

    func testDeviceWithUnknownDateIsNotGuessedAbout() {
        XCTAssertTrue(SimulatorTriage.unusedDevices([device("no-date")], now: now).isEmpty)
    }

    func testBoundaryIsInclusive() {
        XCTAssertEqual(SimulatorTriage.unusedDevices([device("exactly", daysAgo: 90)], now: now).count, 1)
        XCTAssertTrue(SimulatorTriage.unusedDevices([device("almost", daysAgo: 89)], now: now).isEmpty)
    }

    func testRuntimeWithoutDevicesIsUnused() {
        let empty = SimulatorRuntime(id: "1", name: "iOS 18.4", sizeBytes: 1, lastUsed: nil,
                                     isDeletable: true, deviceCount: 0)
        let used = SimulatorRuntime(id: "2", name: "iOS 26.5", sizeBytes: 1, lastUsed: nil,
                                    isDeletable: true, deviceCount: 3)
        let locked = SimulatorRuntime(id: "3", name: "iOS 18.5", sizeBytes: 1, lastUsed: nil,
                                      isDeletable: false, deviceCount: 0)

        XCTAssertEqual(SimulatorTriage.unusedRuntimes([empty, used, locked]).map(\.id), ["1"])
    }
}
