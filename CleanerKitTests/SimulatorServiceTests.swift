import XCTest
@testable import CleanerKit

private final class SimctlFake: SimctlRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [[String]] = []
    var commands: [[String]] { lock.withLock { _commands } }

    var devicesOutput = ""
    var runtimesOutput = ""

    func run(_ arguments: [String]) throws -> String {
        lock.withLock { _commands.append(arguments) }
        if arguments.contains("runtime") { return runtimesOutput }
        return devicesOutput
    }
}

final class SimulatorServiceTests: XCTestCase {
    private var fake: SimctlFake!
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fake = SimctlFake()
        fake.devicesOutput = """
        -- iOS 26.3 --
            iPhone 17 Pro (FCFE9A4C-A3BA-4AD4-B160-2679BFE19258) (Booted)
            iPad Pro 13-inch (M5) (17683048-DF6F-4AE9-B16D-757C1B6C4AE5) (Shutdown)
        -- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --
            iPhone 17 (7B3C4928-9E4F-4872-B950-3BFE54CEDB4B) (Shutdown) (unavailable, runtime profile not found)
        """
        fake.runtimesOutput = """
        iOS 26.1 (23B86) - 9C2A98BC-E5A9-4CE3-A091-B2485113F08D
            Deletable: YES
            Size: 7.8G
        iOS 18.4 (22E238) - B48F8A51-F2D3-46CD-94D1-E81935FBA1CD
            Deletable: NO
            Size: 8.2G
        """
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SimService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeService() -> SimulatorService {
        SimulatorService(simctl: fake, devicesRoot: root)
    }

    func testReadsDevicesWithSizes() throws {
        let udid = "17683048-DF6F-4AE9-B16D-757C1B6C4AE5"
        let dir = root.appendingPathComponent(udid)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8_000).write(to: dir.appendingPathComponent("data.bin"))

        let devices = try makeService().devices()

        XCTAssertEqual(devices.count, 3)
        XCTAssertGreaterThanOrEqual(devices.first { $0.id == udid }?.sizeBytes ?? 0, 8_000)
    }

    func testFindsUnusableDevices() throws {
        let unusable = try makeService().devices().filter(\.isUnavailable)
        XCTAssertEqual(unusable.map(\.name), ["iPhone 17"])
    }

    /// A running simulator cannot be deleted; it must be shut down first.
    func testRefusesToDeleteBootedDevice() throws {
        let booted = try XCTUnwrap(try makeService().devices().first(where: \.isBooted))
        let before = fake.commands.count

        XCTAssertThrowsError(try makeService().delete(device: booted)) { error in
            XCTAssertEqual(error as? SimulatorError, .deviceIsBooted)
        }
        XCTAssertEqual(fake.commands.count, before, "no delete command must be sent")
    }

    func testDeletesShutdownDevice() throws {
        let device = try XCTUnwrap(try makeService().devices().first { !$0.isBooted })
        try makeService().delete(device: device)

        XCTAssertEqual(fake.commands.last, ["delete", device.id])
    }

    func testRefusesToDeleteUndeletableRuntime() throws {
        let locked = try XCTUnwrap(try makeService().runtimes().first { !$0.isDeletable })
        let before = fake.commands.count

        XCTAssertThrowsError(try makeService().delete(runtime: locked)) { error in
            XCTAssertEqual(error as? SimulatorError, .runtimeNotDeletable)
        }
        XCTAssertEqual(fake.commands.count, before)
    }

    func testDeletesRuntime() throws {
        let runtime = try XCTUnwrap(try makeService().runtimes().first { $0.isDeletable })
        try makeService().delete(runtime: runtime)

        XCTAssertEqual(fake.commands.last, ["runtime", "delete", runtime.id])
    }

    func testRuntimesKnowHowManyDevicesUseThem() throws {
        let runtimes = try makeService().runtimes()
        XCTAssertEqual(runtimes.first { $0.name.hasPrefix("iOS 26.1") }?.deviceCount, 0)
    }
}
