import CleanerKit
import Darwin
import Foundation
import Observation

/// What the machine is doing right now, shared by the memory and processor
/// sections.
///
/// One model for both: they read the same process table on the same tick, and
/// two models would mean two sweeps of seventeen hundred processes every
/// couple of seconds to show the same list ordered differently.
@MainActor
@Observable
final class SystemModel {
    enum Sorting: Hashable {
        case memory, processor
    }

    private(set) var memory: MemorySnapshot?
    private(set) var processor: ProcessorSnapshot?
    private(set) var processes: [RunningProcess] = []
    private(set) var report: QuitReport?

    var selection: Set<pid_t> = []
    var query = ""
    var isConfirming = false
    var acknowledged = false

    private var counters: [pid_t: Int64] = [:]
    private var ticks: ProcessorTicks?
    private var lastRead: Date?
    private var isReading = false

    private let monitor: SystemMonitoring
    private let processGuard: ProcessGuard
    private let signal: ProcessSignalling

    init(monitor: SystemMonitoring = SystemMonitor(),
         signal: ProcessSignalling = SystemSignal()) {
        self.monitor = monitor
        self.signal = signal
        self.processGuard = ProcessGuard(currentUser: getuid(), ownPID: getpid())
    }

    var selected: [RunningProcess] { processes.filter { selection.contains($0.pid) } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.residentBytes } }
    var canQuit: Bool { !selected.isEmpty && acknowledged }

    /// Eight hundred processes is more than a list; without a way to narrow
    /// it, finding the one you came for means scrolling past the rest.
    func sorted(by sorting: Sorting) -> [RunningProcess] {
        let matching = query.isEmpty
            ? processes
            : processes.filter { $0.name.localizedCaseInsensitiveContains(query) }

        return switch sorting {
        case .memory:    matching.sorted { $0.residentBytes > $1.residentBytes }
        case .processor: matching.sorted { $0.cpuPercent > $1.cpuPercent }
        }
    }

    /// Runs until the view that started it goes away, which is what cancels it.
    func watch() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }

        let now = Date()
        let elapsed = lastRead.map { now.timeIntervalSince($0) } ?? 0
        let previousCounters = counters
        let previousTicks = ticks
        let monitor = monitor
        let processGuard = processGuard

        // Seventeen hundred processes is a lot of kernel round trips to make
        // the interface wait on.
        let reading = await Task.detached {
            (memory: monitor.memory(),
             processor: monitor.processor(previous: previousTicks),
             listed: monitor.processes(previous: previousCounters, elapsed: elapsed,
                                       processGuard: processGuard))
        }.value

        memory = reading.memory
        processor = reading.processor.snapshot
        ticks = reading.processor.ticks
        processes = reading.listed.processes
        counters = reading.listed.counters
        lastRead = now
        // A process that has exited is no longer anything to act on.
        selection.formIntersection(Set(processes.map(\.pid)))
    }

    func setSelected(_ process: RunningProcess, _ isOn: Bool) {
        guard isOn else {
            selection.remove(process.pid)
            return
        }
        if process.canQuit { selection.insert(process.pid) }
    }

    func isSelected(_ process: RunningProcess) -> Bool { selection.contains(process.pid) }

    func quitSelected() async {
        let terminator = ProcessTerminator(processGuard: processGuard, signal: signal)
        report = await terminator.quit(selected)
        selection.removeAll()
        acknowledged = false
        // Quitting takes a moment to show up in the numbers.
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func dismissReport() { report = nil }
}
