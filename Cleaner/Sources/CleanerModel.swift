import AppKit
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
    private(set) var lastScan: Date?

    /// Marked findings. Empty by default: the choice belongs to the user and
    /// the app does not make it for them.
    var selection = SelectionState()
    var expanded: Set<String> = []
    var isConfirming = false

    // MARK: Simulators — a world apart, because removal there is irreversible

    private(set) var devices: [SimulatorDevice] = []
    private(set) var runtimes: [SimulatorRuntime] = []
    private(set) var simulatorsLoaded = false
    private(set) var simulatorFailures: [String] = []
    var deviceSelection: Set<String> = []
    var runtimeSelection: Set<String> = []
    var isConfirmingSimulators = false
    var acknowledgedIrreversible = false

    // MARK: What the Trash and the permissions say

    /// What sits in the Trash right now. Moving files there frees nothing
    /// until it is emptied, and the app says so rather than implying otherwise.
    private(set) var trashBytes: Int64 = 0
    private(set) var hasFullDiskAccess = true
    private(set) var volume: VolumeSpace?

    /// How far the running scan has got, and nil when none is running.
    private(set) var scanProgress: ScanProgress?
    /// Set when the user stopped a scan that had nothing to fall back on.
    /// Without it the window would sit on a spinner that never resolves.
    private(set) var wasStopped = false
    private var scanTask: Task<Void, Never>?

    /// Roots that exist but refused to be read. Not the same as empty.
    var unreadableRoots: [URL] { scans.flatMap(\.unreadableRoots) }
    var isUnderReporting: Bool { !hasFullDiskAccess || !unreadableRoots.isEmpty }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var pathGuard: PathGuard { Catalog.pathGuard(home: home) }

    var selectedItems: [ScanItem] { selection.items(from: scans) }
    var selectedBytes: Int64 { selection.bytes(in: scans) }

    /// Categories with something marked — used by the confirmation sheet.
    var touchedScans: [CategoryScan] {
        scans.filter { selection.coverage(of: $0.items) != .none }
    }

    func selectedBytes(in scan: CategoryScan) -> Int64 {
        selection.items(from: [scan]).reduce(0) { $0 + $1.sizeBytes }
    }

    func selectedCount(in scan: CategoryScan) -> Int {
        selection.items(from: [scan]).count
    }

    var foundBytes: Int64 { scans.reduce(0) { $0 + $1.totalBytes } }

    /// Found, next to what the disk actually has. Purgeable space is named
    /// only when there is enough of it to explain a confusing free figure.
    var summaryLine: String {
        let found = String(localized: "Found \(foundBytes.formattedBytes)")
        guard let volume else { return found }

        let room = String(localized: "\(volume.free.formattedBytes) free of \(volume.total.formattedBytes)")
        guard volume.purgeable > 1_073_741_824 else { return "\(found) · \(room)" }

        let purgeable = String(localized: "\(volume.purgeable.formattedBytes) purgeable")
        return "\(found) · \(room) · \(purgeable)"
    }
    var canRemove: Bool { phase == .results && !selectedItems.isEmpty }

    func scan() async {
        scanTask?.cancel()
        let task = Task { await runScan() }
        scanTask = task
        await task.value
    }

    /// Stops the scan without discarding what the previous one found: an
    /// empty window would punish the user for changing their mind.
    func cancelScan() {
        scanTask?.cancel()
    }

    private func runScan() async {
        phase = .scanning
        report = nil
        scanProgress = nil
        wasStopped = false

        let policy = ScanPolicy(home: home, runningApps: SystemRunningApps.current())
        let scanner = DiskScanner(pathGuard: pathGuard, policy: policy)
        // Building the catalog now walks the disk looking for cache
        // directories, which is not work for the main actor.
        let home = home
        let categories = await Task.detached { Catalog.standard(home: home) }.value
        let fresh = await scanner.scan(categories) { [weak self] progress in
            Task { @MainActor in self?.report(progress) }
        }

        guard !Task.isCancelled else {
            scanProgress = nil
            wasStopped = scans.isEmpty
            phase = scans.isEmpty ? .idle : .results
            return
        }

        // Biggest first: the reason to open this app is the top of the list.
        scans = fresh.sorted { $0.totalBytes > $1.totalBytes }
        selection.keepOnly(scans)
        lastScan = .now
        scanProgress = nil
        await refreshEnvironment()

        phase = .results
    }

    /// Progress arrives from parallel tasks, so a late report can land after
    /// an earlier one. Only forward movement is shown.
    private func report(_ progress: ScanProgress) {
        guard phase == .scanning else { return }
        guard progress.completed > (scanProgress?.completed ?? 0) else { return }
        scanProgress = progress
    }

    /// The window and the menu bar panel both want fresh numbers on first
    /// appearance, but only one of them should pay for the scan.
    func scanIfNeeded() async {
        guard phase == .idle else { return }
        await scan()
    }

    /// After cleaning from the menu bar there is no report screen to leave,
    /// so the panel goes straight back to showing results.
    func removeSelectedAndRescan() async {
        await removeSelected()
        await scan()
    }

    func removeSelected() async {
        phase = .removing

        let remover = Remover(pathGuard: pathGuard, trash: SystemTrash())
        report = await remover.remove(selectedItems)
        await refreshEnvironment()

        phase = .finished
    }

    /// Reading the Trash walks a directory tree, so it stays off the main
    /// actor even though the numbers it produces land there.
    private func refreshEnvironment() async {
        let home = home
        let measured = await Task.detached {
            (trash: TrashFolder.sizeBytes(home: home),
             access: FullDiskAccess.isGranted(home: home),
             volume: DiskSpace.volume(at: home))
        }.value
        trashBytes = measured.trash
        hasFullDiskAccess = measured.access
        volume = measured.volume
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func openTrash() {
        NSWorkspace.shared.open(TrashFolder.url(home: home))
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    // MARK: Simulators

    var selectedDevices: [SimulatorDevice] { devices.filter { deviceSelection.contains($0.id) } }
    var selectedRuntimes: [SimulatorRuntime] { runtimes.filter { runtimeSelection.contains($0.id) } }

    var selectedSimulatorBytes: Int64 {
        selectedDevices.reduce(0) { $0 + $1.sizeBytes }
            + selectedRuntimes.reduce(0) { $0 + $1.sizeBytes }
    }

    var canDeleteSimulators: Bool {
        acknowledgedIrreversible && !(selectedDevices.isEmpty && selectedRuntimes.isEmpty)
    }

    /// Unused: no runtime at all, or the directory has not been touched for
    /// more than SimulatorTriage.staleAfterDays; plus runtimes with no devices.
    var unusedDevices: [(device: SimulatorDevice, reason: SimulatorTriage.Reason)] {
        SimulatorTriage.unusedDevices(devices)
    }

    var unusedRuntimes: [SimulatorRuntime] { SimulatorTriage.unusedRuntimes(runtimes) }

    var hasUnused: Bool { !unusedDevices.isEmpty || !unusedRuntimes.isEmpty }

    /// Why there is nothing to offer. A dimmed button without an explanation
    /// is a riddle.
    var unusedExplanation: String {
        guard simulatorsLoaded else { return "" }
        if hasUnused {
            let bytes = unusedDevices.reduce(0) { $0 + $1.device.sizeBytes }
                + unusedRuntimes.reduce(0) { $0 + $1.sizeBytes }
            return String(localized: "Unused: \(bytes.formattedBytes)")
        }
        return String(localized: "Nothing unused: every device has its runtime and none has been idle for \(SimulatorTriage.staleAfterDays.daysText)")
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
        if device.isBooted { return String(localized: "running — cannot be deleted") }
        if device.isUnavailable { return String(localized: "runtime not installed, cannot launch") }
        guard let lastUsed = device.lastUsed else { return device.runtime }

        let days = Int(Date.now.timeIntervalSince(lastUsed) / 86_400)
        if days >= SimulatorTriage.staleAfterDays {
            return "\(device.runtime) · \(String(localized: "not opened for \(days.daysText)"))"
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
        case .deviceIsBooted:
            String(localized: "the simulator is running; shut it down first")
        case .runtimeNotDeletable:
            String(localized: "the image is marked as not deletable")
        case let .commandFailed(command):
            String(localized: "command failed: \(command)")
        case nil:
            error.localizedDescription
        }
    }

    // MARK: Selection

    func coverage(of items: [ScanItem]) -> Coverage { selection.coverage(of: items) }

    func toggleAll(_ items: [ScanItem]) { selection.toggleAll(items) }

    func toggle(_ item: ScanItem) { selection.toggle(item) }

    /// An explicit set rather than a toggle: SwiftUI may deliver the same
    /// value twice, and a toggle would then fire twice.
    func setSelected(_ item: ScanItem, _ on: Bool) { selection.set(item, selected: on) }

    func isSelected(_ item: ScanItem) -> Bool { selection.contains(item) }

    func isExpanded(_ scan: CategoryScan) -> Bool { expanded.contains(scan.id) }

    func setExpanded(_ scan: CategoryScan, _ open: Bool) {
        if open { expanded.insert(scan.id) } else { expanded.remove(scan.id) }
    }

    /// A readable root name: ".npm/_cacache" instead of a bare "_cacache".
    func title(for root: URL) -> String {
        root.pathComponents.suffix(2).joined(separator: "/")
    }

    func describe(_ item: ScanItem) -> String {
        item.modified.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Int64 {
    var formattedBytes: String {
        formatted(.byteCount(style: .file))
    }
}

/// Counted nouns live in their own strings with exactly one numeric argument:
/// Ukrainian needs one/few/many forms, and a plural rule can only key off a
/// single number.
extension Int {
    var itemsText: String { String(localized: "\(self) items") }
    var daysText: String { String(localized: "\(self) days") }
    var devicesText: String { String(localized: "\(self) devices") }
}
