import CleanerKit
import Foundation
import Observation

@MainActor
@Observable
final class CleanerModel {
    enum Phase: Equatable {
        case idle, scanning, results, removing, finished
    }

    private(set) var phase: Phase = .idle
    private(set) var scans: [CategoryScan] = []
    private(set) var report: RemovalReport?

    /// Идентификаторы отмеченных категорий. Пусто по умолчанию: выбор — за
    /// пользователем, приложение ничего не предрешает.
    var selection: Set<String> = []
    var isConfirming = false

    // MARK: Симуляторы — отдельный мир: удаление здесь необратимо

    private(set) var devices: [SimulatorDevice] = []
    private(set) var runtimes: [SimulatorRuntime] = []
    private(set) var simulatorsLoaded = false
    private(set) var simulatorFailures: [String] = []
    var deviceSelection: Set<String> = []
    var runtimeSelection: Set<String> = []
    var isConfirmingSimulators = false
    var acknowledgedIrreversible = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var pathGuard: PathGuard { Catalog.pathGuard(home: home) }

    var selectedScans: [CategoryScan] { scans.filter { selection.contains($0.id) } }
    var selectedItems: [ScanItem] { selectedScans.flatMap(\.items) }
    var selectedBytes: Int64 { selectedScans.reduce(0) { $0 + $1.totalBytes } }
    var foundBytes: Int64 { scans.reduce(0) { $0 + $1.totalBytes } }
    var canRemove: Bool { phase == .results && !selectedItems.isEmpty }

    func scan() async {
        phase = .scanning
        selection = []
        report = nil

        let scanner = DiskScanner(pathGuard: pathGuard)
        scans = await scanner.scan(Catalog.standard(home: home))

        phase = .results
    }

    func removeSelected() async {
        phase = .removing

        let remover = Remover(pathGuard: pathGuard, trash: SystemTrash())
        report = await remover.remove(selectedItems)

        phase = .finished
    }

    // MARK: Симуляторы

    var selectedDevices: [SimulatorDevice] { devices.filter { deviceSelection.contains($0.id) } }
    var selectedRuntimes: [SimulatorRuntime] { runtimes.filter { runtimeSelection.contains($0.id) } }

    var selectedSimulatorBytes: Int64 {
        selectedDevices.reduce(0) { $0 + $1.sizeBytes }
            + selectedRuntimes.reduce(0) { $0 + $1.sizeBytes }
    }

    var canDeleteSimulators: Bool {
        acknowledgedIrreversible && !(selectedDevices.isEmpty && selectedRuntimes.isEmpty)
    }

    /// Неиспользуемое: устройство без своего runtime и runtime без устройств.
    var unusedDevices: [SimulatorDevice] { devices.filter(\.isUnavailable) }
    var unusedRuntimes: [SimulatorRuntime] { runtimes.filter { $0.deviceCount == 0 && $0.isDeletable } }

    func loadSimulators() async {
        let service = SimulatorService()
        let loaded = await Task.detached {
            (devices: (try? service.devices()) ?? [], runtimes: (try? service.runtimes()) ?? [])
        }.value

        devices = loaded.devices
        runtimes = loaded.runtimes
        simulatorsLoaded = true
    }

    func selectUnused() {
        deviceSelection = Set(unusedDevices.map(\.id))
        runtimeSelection = Set(unusedRuntimes.map(\.id))
    }

    func deleteSelectedSimulators() async {
        let service = SimulatorService()
        let devicesToDelete = selectedDevices
        let runtimesToDelete = selectedRuntimes

        let failures = await Task.detached { () -> [String] in
            var problems: [String] = []
            for device in devicesToDelete {
                do { try service.delete(device: device) }
                catch { problems.append("\(device.name): \(Self.describe(error))") }
            }
            for runtime in runtimesToDelete {
                do { try service.delete(runtime: runtime) }
                catch { problems.append("\(runtime.name): \(Self.describe(error))") }
            }
            return problems
        }.value

        simulatorFailures = failures
        deviceSelection = []
        runtimeSelection = []
        acknowledgedIrreversible = false
        await loadSimulators()
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error as? SimulatorError {
        case .deviceIsBooted: "симулятор запущен, сначала завершите его"
        case .runtimeNotDeletable: "образ помечен как неудаляемый"
        case let .commandFailed(command): "не выполнилось: \(command)"
        case nil: error.localizedDescription
        }
    }

    func binding(for scan: CategoryScan) -> Bool {
        selection.contains(scan.id)
    }

    func toggle(_ scan: CategoryScan, on: Bool) {
        if on { selection.insert(scan.id) } else { selection.remove(scan.id) }
    }
}

extension Int64 {
    var formattedBytes: String {
        formatted(.byteCount(style: .file))
    }
}
