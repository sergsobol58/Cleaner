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

    /// Неиспользуемое: нет runtime, либо каталогом не пользовались более
    /// SimulatorTriage.staleAfterDays дней; плюс runtime без устройств.
    var unusedDevices: [(device: SimulatorDevice, reason: SimulatorTriage.Reason)] {
        SimulatorTriage.unusedDevices(devices)
    }

    var unusedRuntimes: [SimulatorRuntime] { SimulatorTriage.unusedRuntimes(runtimes) }

    var hasUnused: Bool { !unusedDevices.isEmpty || !unusedRuntimes.isEmpty }

    /// Почему предлагать нечего. Погашенная кнопка без объяснения — загадка.
    var unusedExplanation: String {
        guard simulatorsLoaded else { return "" }
        if hasUnused {
            let bytes = unusedDevices.reduce(0) { $0 + $1.device.sizeBytes }
                + unusedRuntimes.reduce(0) { $0 + $1.sizeBytes }
            return "Неиспользуемого: \(bytes.formattedBytes)"
        }
        return "Неиспользуемого нет: у всех есть runtime, всеми пользовались за последние \(SimulatorTriage.staleAfterDays) дней"
    }

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
        deviceSelection = Set(unusedDevices.map(\.device.id))
        runtimeSelection = Set(unusedRuntimes.map(\.id))
    }

    func note(for device: SimulatorDevice) -> String {
        if device.isBooted { return "запущен — удалить нельзя" }
        if device.isUnavailable { return "runtime не установлен, запустить нельзя" }
        guard let lastUsed = device.lastUsed else { return device.runtime }

        let days = Int(Date.now.timeIntervalSince(lastUsed) / 86_400)
        if days >= SimulatorTriage.staleAfterDays {
            return "\(device.runtime) · не открывался \(days) дней"
        }
        return "\(device.runtime) · \(lastUsed.formatted(date: .abbreviated, time: .omitted))"
    }

    func isStale(_ device: SimulatorDevice) -> Bool {
        unusedDevices.contains { $0.device.id == device.id }
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
