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
