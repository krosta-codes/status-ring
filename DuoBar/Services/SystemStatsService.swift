import Darwin
import Foundation

/// CPU load, memory and storage, taken over from StatBar. Sampled every two
/// seconds and only while the popover is open, so it costs nothing otherwise.
struct SystemStats: Equatable, Sendable {
    var cpuPercent: Int?
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var storageAvailableBytes: Int64
    var storageTotalBytes: Int64

    var memoryPercent: Int? {
        guard memoryTotalBytes > 0 else { return nil }
        return Int((Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100).rounded())
    }
}

@MainActor
final class SystemStatsService {
    var onStatsChange: ((SystemStats?) -> Void)?

    private var timer: Timer?
    private var previousCPU: host_cpu_load_info?
    private let memoryTotal: UInt64 = {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        return total
    }()

    func start() {
        guard timer == nil else { return }
        previousCPU = Self.cpuLoad()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.2
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        // CPU needs two readings; publish memory and storage right away.
        sample(includeCPU: false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPU = nil
        onStatsChange?(nil)
    }

    private func sample(includeCPU: Bool = true) {
        var cpuPercent: Int?
        if includeCPU, let current = Self.cpuLoad(), let previous = previousCPU {
            let user = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
            let system = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
            let idle = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
            let nice = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
            let busy = user + system + nice
            let total = busy + idle
            cpuPercent = total > 0 ? Int((busy / total * 100).rounded()) : nil
            previousCPU = current
        }
        let storage = Self.storage()
        onStatsChange?(
            SystemStats(
                cpuPercent: cpuPercent,
                memoryUsedBytes: Self.memoryUsed(),
                memoryTotalBytes: memoryTotal,
                storageAvailableBytes: storage.available,
                storageTotalBytes: storage.total
            )
        )
    }

    private static func cpuLoad() -> host_cpu_load_info? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// Activity Monitor's "Memory Used": active + wired + compressed pages.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_page_size)
    }

    /// Boot volume; "available for important usage" matches Finder's figure.
    private static func storage() -> (available: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return (0, 0) }
        return (values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeTotalCapacity ?? 0))
    }
}
