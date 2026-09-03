import Foundation

public enum SimulatorError: Error, Equatable {
    case deviceIsBooted
    case runtimeNotDeletable
    case commandFailed(String)
}

/// Runs `simctl`. A separate protocol so tests never touch real simulators.
public protocol SimctlRunning: Sendable {
    func run(_ arguments: [String]) throws -> String
}

public struct Simctl: SimctlRunning {
    public init() {}

    public func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SimulatorError.commandFailed("simctl \(arguments.joined(separator: " "))")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Simulators and runtime images.
///
/// Unlike the file categories, removal here is irreversible: `simctl` has no
/// notion of the Trash, and moving the directory behind its back would leave
/// the CoreSimulator database out of sync.
public struct SimulatorService: Sendable {
    private let simctl: SimctlRunning
    private let devicesRoot: URL

    public init(simctl: SimctlRunning = Simctl(),
                devicesRoot: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Developer/CoreSimulator/Devices")) {
        self.simctl = simctl
        self.devicesRoot = devicesRoot
    }

    public func devices() throws -> [SimulatorDevice] {
        SimulatorParser.devices(from: try simctl.run(["list", "devices"]))
            .map { device in
                var sized = device
                let directory = devicesRoot.appending(path: device.id)
                sized.sizeBytes = allocatedSize(of: directory)
                sized.lastUsed = (try? directory.appending(path: "data")
                    .resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return sized
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public func runtimes() throws -> [SimulatorRuntime] {
        SimulatorParser.countDevices(
            runtimes: SimulatorParser.runtimes(from: try simctl.run(["runtime", "list", "-v"])),
            devices: SimulatorParser.devices(from: try simctl.run(["list", "devices"]))
        )
    }

    public func delete(device: SimulatorDevice) throws {
        // A running simulator must be shut down first: deleting it from
        // under itself leaves the system in a contradictory state.
        guard !device.isBooted else { throw SimulatorError.deviceIsBooted }
        _ = try simctl.run(["delete", device.id])
    }

    public func delete(runtime: SimulatorRuntime) throws {
        guard runtime.isDeletable else { throw SimulatorError.runtimeNotDeletable }
        _ = try simctl.run(["runtime", "delete", runtime.id])
    }
}
