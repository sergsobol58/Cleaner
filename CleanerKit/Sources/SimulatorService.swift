import Foundation

public enum SimulatorError: Error, Equatable {
    case deviceIsBooted
    case runtimeNotDeletable
    case commandFailed(String)
}

/// Запуск `simctl`. Отдельный протокол — чтобы тесты не трогали
/// настоящие симуляторы.
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

/// Симуляторы и runtime-образы.
///
/// В отличие от файловых категорий, удаление здесь необратимо: `simctl` не
/// умеет в Корзину, а перенести каталог мимо него нельзя — рассинхронизируется
/// база CoreSimulator.
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
                sized.sizeBytes = allocatedSize(of: devicesRoot.appending(path: device.id))
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
        // Запущенный симулятор сначала надо завершить: удаление под ним
        // оставит систему в противоречивом состоянии.
        guard !device.isBooted else { throw SimulatorError.deviceIsBooted }
        _ = try simctl.run(["delete", device.id])
    }

    public func delete(runtime: SimulatorRuntime) throws {
        guard runtime.isDeletable else { throw SimulatorError.runtimeNotDeletable }
        _ = try simctl.run(["runtime", "delete", runtime.id])
    }
}
