import Darwin
import Foundation

/// Reads what the kernel says about memory and processes.
///
/// A protocol so the views and the model can be exercised against made-up
/// numbers; a machine under test has no interesting memory pressure.
public protocol SystemMonitoring: Sendable {
    func memory() -> MemorySnapshot?
    /// `previous` carries the tick counters from the last reading; ticks are
    /// cumulative and only become a percentage as a difference.
    func processor(previous: ProcessorTicks?) -> (snapshot: ProcessorSnapshot,
                                                  ticks: ProcessorTicks?)
    /// `previous` carries the processor counters from the last reading, which
    /// is the only way a cumulative counter becomes a percentage.
    func processes(previous: [pid_t: Int64], elapsed: TimeInterval,
                   processGuard: ProcessGuard) -> (processes: [RunningProcess],
                                                   counters: [pid_t: Int64])
}

public struct SystemMonitor: SystemMonitoring {
    public init() {}

    public func memory() -> MemorySnapshot? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return MemoryCounters(
            pageSize: Int64(vm_kernel_page_size),
            totalBytes: Self.sysctl("hw.memsize", as: UInt64.self).map(Int64.init) ?? 0,
            free: Int64(statistics.free_count),
            speculative: Int64(statistics.speculative_count),
            wired: Int64(statistics.wire_count),
            compressed: Int64(statistics.compressor_page_count),
            internalPages: Int64(statistics.internal_page_count),
            externalPages: Int64(statistics.external_page_count),
            purgeable: Int64(statistics.purgeable_count),
            swapUsedBytes: Int64(Self.sysctl("vm.swapusage", as: xsw_usage.self)?.xsu_used ?? 0),
            pressureLevel: Self.sysctl("kern.memorystatus_vm_pressure_level",
                                       as: Int32.self) ?? 1
        ).snapshot
    }

    public func processor(previous: ProcessorTicks?) -> (snapshot: ProcessorSnapshot,
                                                         ticks: ProcessorTicks?) {
        let cores = Int(ProcessInfo.processInfo.activeProcessorCount)
        var averages = [Double](repeating: 0, count: 3)
        if getloadavg(&averages, 3) != 3 { averages = [] }

        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (ProcessorSnapshot(userPercent: 0, systemPercent: 0,
                                      coreCount: cores, loadAverage: averages), nil)
        }

        let ticks = ProcessorTicks(
            user: Int64(info.cpu_ticks.0), system: Int64(info.cpu_ticks.1),
            idle: Int64(info.cpu_ticks.2), nice: Int64(info.cpu_ticks.3))

        return (ProcessorSnapshot.between(previous: previous, current: ticks,
                                          coreCount: cores, loadAverage: averages), ticks)
    }

    public func processes(previous: [pid_t: Int64], elapsed: TimeInterval,
                          processGuard: ProcessGuard) -> (processes: [RunningProcess],
                                                          counters: [pid_t: Int64]) {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return ([], [:]) }

        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let returned = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size) * capacity)
        guard returned > 0 else { return ([], [:]) }

        var found: [RunningProcess] = []
        var counters: [pid_t: Int64] = [:]
        let wanted = Int32(MemoryLayout<proc_taskallinfo>.size)

        for pid in pids.prefix(Int(returned)) where pid > 0 {
            var info = proc_taskallinfo()
            // Processes owned by other users refuse to be read at all, which
            // is a refusal to report rather than an error worth surfacing.
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, wanted) == wanted else {
                continue
            }

            let name = withUnsafeBytes(of: info.pbsd.pbi_name) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            let processorTime = Int64(info.ptinfo.pti_total_user)
                + Int64(info.ptinfo.pti_total_system)
            counters[pid] = processorTime

            found.append(RunningProcess(
                pid: pid,
                name: name.isEmpty ? "pid \(pid)" : name,
                residentBytes: Int64(info.ptinfo.pti_resident_size),
                cpuPercent: ProcessorTime.percent(previous: previous[pid],
                                                  current: processorTime, elapsed: elapsed),
                uid: info.pbsd.pbi_uid,
                protection: processGuard.validate(name: name, uid: info.pbsd.pbi_uid, pid: pid)))
        }

        return (found, counters)
    }

    private static func sysctl<T>(_ name: String, as type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard sysctlbyname(name, value, &size, nil, 0) == 0 else { return nil }
        return value.pointee
    }
}
