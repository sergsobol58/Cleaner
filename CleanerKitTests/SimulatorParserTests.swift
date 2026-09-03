import XCTest
@testable import CleanerKit

final class SimulatorParserTests: XCTestCase {
    private let devicesOutput = """
    == Devices ==
    -- iOS 18.5 --
        iPhone 16 (DC2FE43F-E8F6-47A4-938E-1815A25B2156) (Shutdown)\u{20}
    -- iOS 26.3 --
        iPhone 17 Pro (FCFE9A4C-A3BA-4AD4-B160-2679BFE19258) (Booted)\u{20}
        iPad Pro 13-inch (M5) (17683048-DF6F-4AE9-B16D-757C1B6C4AE5) (Shutdown)\u{20}
        iPad (A16) (21D822CC-6844-4115-8426-8CE7F0D5F3F6) (Shutdown)\u{20}
    -- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --
        iPhone 17 (7B3C4928-9E4F-4872-B950-3BFE54CEDB4B) (Shutdown) (unavailable, runtime profile not found using "System" match policy)\u{20}
    """

    private let runtimesOutput = """
    == Disk Images ==
    -- iOS --
    iOS 26.3.1 (23D8133) - EBB5CF07-10A5-427D-B240-C0377D5FD868
        State: Ready
        Deletable: YES
        Last Used At: 2026-08-01 21:21:22 +0000
        Size: 7.8G
    iOS 26.1 (23B86) - 9C2A98BC-E5A9-4CE3-A091-B2485113F08D
        State: Ready
        Deletable: YES
        Size: 7.8G
    iOS 18.4 (22E238) - B48F8A51-F2D3-46CD-94D1-E81935FBA1CD
        State: Ready
        Deletable: NO
        Size: 8.2G
    """

    // MARK: - Devices

    func testParsesAllDevices() {
        XCTAssertEqual(SimulatorParser.devices(from: devicesOutput).count, 5)
    }

    /// The predecessor stumbled here: splitting on parentheses read "M5" as the UDID.
    func testParsesNamesContainingParentheses() {
        let devices = SimulatorParser.devices(from: devicesOutput)

        let ipadPro = devices.first { $0.id == "17683048-DF6F-4AE9-B16D-757C1B6C4AE5" }
        XCTAssertEqual(ipadPro?.name, "iPad Pro 13-inch (M5)")

        let ipad = devices.first { $0.id == "21D822CC-6844-4115-8426-8CE7F0D5F3F6" }
        XCTAssertEqual(ipad?.name, "iPad (A16)")
    }

    func testDetectsBootedDevice() {
        let devices = SimulatorParser.devices(from: devicesOutput)
        XCTAssertEqual(devices.filter(\.isBooted).map(\.name), ["iPhone 17 Pro"])
    }

    func testDetectsUnavailableDeviceAndRecoversRuntimeName() {
        let unavailable = SimulatorParser.devices(from: devicesOutput).filter(\.isUnavailable)

        XCTAssertEqual(unavailable.map(\.name), ["iPhone 17"])
        XCTAssertEqual(unavailable.first?.runtime, "iOS 26.2",
                       "the runtime name is recovered from the SimRuntime identifier")
    }

    func testAssignsRuntimeFromPrecedingHeader() {
        let devices = SimulatorParser.devices(from: devicesOutput)
        XCTAssertEqual(devices.first { $0.name == "iPhone 16" }?.runtime, "iOS 18.5")
        XCTAssertEqual(devices.first { $0.name == "iPad (A16)" }?.runtime, "iOS 26.3")
    }

    // MARK: - Runtimes

    func testParsesRuntimes() {
        let runtimes = SimulatorParser.runtimes(from: runtimesOutput)
        XCTAssertEqual(runtimes.map(\.name), ["iOS 26.3.1 (23D8133)", "iOS 26.1 (23B86)", "iOS 18.4 (22E238)"])
        XCTAssertEqual(runtimes.first?.id, "EBB5CF07-10A5-427D-B240-C0377D5FD868")
    }

    func testParsesRuntimeSize() {
        let runtimes = SimulatorParser.runtimes(from: runtimesOutput)
        XCTAssertEqual(runtimes[0].sizeBytes, Int64(7.8 * 1024 * 1024 * 1024))
    }

    func testParsesDeletableFlag() {
        let runtimes = SimulatorParser.runtimes(from: runtimesOutput)
        XCTAssertTrue(runtimes[0].isDeletable)
        XCTAssertFalse(runtimes[2].isDeletable, "Deletable: NO must forbid removal")
    }

    func testNeverUsedRuntimeHasNoDate() {
        let runtimes = SimulatorParser.runtimes(from: runtimesOutput)
        XCTAssertNotNil(runtimes[0].lastUsed)
        XCTAssertNil(runtimes[1].lastUsed, "an unused runtime carries no date")
    }

    /// This number is the whole point: a runtime with no devices can go.
    func testCountsDevicesPerRuntime() {
        let counted = SimulatorParser.countDevices(
            runtimes: SimulatorParser.runtimes(from: runtimesOutput),
            devices: SimulatorParser.devices(from: devicesOutput)
        )

        XCTAssertEqual(counted.first { $0.name.hasPrefix("iOS 26.3") }?.deviceCount, 3)
        XCTAssertEqual(counted.first { $0.name.hasPrefix("iOS 26.1") }?.deviceCount, 0)
    }

    func testHandlesEmptyOutput() {
        XCTAssertTrue(SimulatorParser.devices(from: "").isEmpty)
        XCTAssertTrue(SimulatorParser.runtimes(from: "").isEmpty)
    }
}
