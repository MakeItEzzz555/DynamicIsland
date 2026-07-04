import AppKit
import Darwin
import Foundation
import IOKit.ps

struct SystemStatsSnapshot: Equatable {
    var cpuUsage: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryCachedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0
    var diskUsedBytes: UInt64 = 0
    var diskTotalBytes: UInt64 = 0
    var networkUploadBytesPerSecond: Double?
    var networkDownloadBytesPerSecond: Double?
    var batteryPercent: Double?
    var isCharging: Bool?
    var uptimeSeconds: TimeInterval = 0
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var diskHistory: [Double] = []
    var networkDownloadHistory: [Double] = []
    var networkUploadHistory: [Double] = []
}

enum SystemStatsFormatting {
    static func clampedFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }

        return value >= 10
            ? String(format: "%.0f %@", value, units[unitIndex])
            : String(format: "%.1f %@", value, units[unitIndex])
    }

    static func formatBytesPerSecond(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "Unavailable" }
        return "\(formatBytes(UInt64(max(0, bytesPerSecond))))/s"
    }

    static func memoryUsedBytes(active: UInt64, wired: UInt64, compressed: UInt64) -> UInt64 {
        active + wired + compressed
    }
}

struct SystemStatsHistory: Equatable {
    private(set) var samples: [Double] = []
    let limit: Int

    init(limit: Int = 24) {
        self.limit = max(1, limit)
    }

    mutating func append(_ value: Double) {
        samples.append(SystemStatsFormatting.clampedFraction(value))
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }
}

@MainActor
final class SystemStatsController: ObservableObject {
    @Published private(set) var snapshot = SystemStatsSnapshot()

    private let provider = SystemStatsProvider()
    private var timer: Timer?
    private var cpuHistory = SystemStatsHistory()
    private var memoryHistory = SystemStatsHistory()
    private var diskHistory = SystemStatsHistory()
    private var networkDownloadHistory = SystemStatsHistory()
    private var networkUploadHistory = SystemStatsHistory()

    init() {
        refresh()
        startPolling()
    }

    func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        var next = provider.snapshot()
        cpuHistory.append(next.cpuUsage)
        memoryHistory.append(fraction(used: next.memoryUsedBytes, total: next.memoryTotalBytes))
        diskHistory.append(fraction(used: next.diskUsedBytes, total: next.diskTotalBytes))
        networkDownloadHistory.append(networkFraction(next.networkDownloadBytesPerSecond))
        networkUploadHistory.append(networkFraction(next.networkUploadBytesPerSecond))
        next.cpuHistory = cpuHistory.samples
        next.memoryHistory = memoryHistory.samples
        next.diskHistory = diskHistory.samples
        next.networkDownloadHistory = networkDownloadHistory.samples
        next.networkUploadHistory = networkUploadHistory.samples
        snapshot = next
    }

    private func fraction(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return SystemStatsFormatting.clampedFraction(Double(used) / Double(total))
    }

    private func networkFraction(_ bytesPerSecond: Double?) -> Double {
        guard let bytesPerSecond else { return 0 }
        return SystemStatsFormatting.clampedFraction(bytesPerSecond / 1_000_000)
    }
}

private final class SystemStatsProvider {
    private var previousCPU: CPUCounters?
    private var previousNetwork: NetworkCounters?
    private var previousNetworkDate: Date?

    func snapshot(now: Date = Date()) -> SystemStatsSnapshot {
        let memory = memoryUsage()
        let disk = diskUsage()
        let network = networkUsage(now: now)
        let battery = batteryStatus()

        return SystemStatsSnapshot(
            cpuUsage: cpuUsage(),
            memoryUsedBytes: memory.used,
            memoryCachedBytes: memory.cached,
            memoryTotalBytes: memory.total,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            networkUploadBytesPerSecond: network?.upload,
            networkDownloadBytesPerSecond: network?.download,
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    private func cpuUsage() -> Double {
        guard let counters = cpuCounters() else { return 0 }
        defer { previousCPU = counters }

        guard let previousCPU else {
            return 0
        }

        let user = counters.user - previousCPU.user
        let system = counters.system - previousCPU.system
        let nice = counters.nice - previousCPU.nice
        let idle = counters.idle - previousCPU.idle
        let total = user + system + nice + idle
        guard total > 0 else { return 0 }

        return SystemStatsFormatting.clampedFraction(Double(user + system + nice) / Double(total))
    }

    private func cpuCounters() -> CPUCounters? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var counters = CPUCounters()
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(processorCount) {
            let offset = cpu * stride
            counters.user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            counters.system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            counters.nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            counters.idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }
        return counters
    }

    private func memoryUsage() -> (used: UInt64, cached: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return (0, 0, total)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)
        let active = UInt64(stats.active_count) * pageBytes
        let wired = UInt64(stats.wire_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let inactive = UInt64(stats.inactive_count) * pageBytes
        let speculative = UInt64(stats.speculative_count) * pageBytes

        // Displayed "used" intentionally excludes inactive/speculative pages, which
        // macOS can reclaim for apps. Counting only free pages makes RAM look full.
        let used = SystemStatsFormatting.memoryUsedBytes(
            active: active,
            wired: wired,
            compressed: compressed
        )
        return (min(used, total), inactive + speculative, total)
    }

    private func diskUsage() -> (used: UInt64, total: UInt64) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else {
            return (0, 0)
        }

        let totalBytes = total.uint64Value
        let freeBytes = free.uint64Value
        return (totalBytes > freeBytes ? totalBytes - freeBytes : 0, totalBytes)
    }

    private func networkUsage(now: Date) -> (upload: Double, download: Double)? {
        guard let counters = networkCounters() else { return nil }
        defer {
            previousNetwork = counters
            previousNetworkDate = now
        }

        guard let previousNetwork,
              let previousNetworkDate else {
            return nil
        }

        let interval = max(now.timeIntervalSince(previousNetworkDate), 0.1)
        let upload = Double(counters.sent - previousNetwork.sent) / interval
        let download = Double(counters.received - previousNetwork.received) / interval
        return (max(0, upload), max(0, download))
    }

    private func networkCounters() -> NetworkCounters? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var counters = NetworkCounters()
        var pointer: UnsafeMutablePointer<ifaddrs>? = interfaces
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0,
                  current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = current.pointee.ifa_data else {
                continue
            }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            counters.received += UInt64(data.ifi_ibytes)
            counters.sent += UInt64(data.ifi_obytes)
        }

        return counters
    }

    private func batteryStatus() -> (percent: Double?, isCharging: Bool?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return (nil, nil)
        }

        let current = description[kIOPSCurrentCapacityKey] as? Double
        let max = description[kIOPSMaxCapacityKey] as? Double
        let percent: Double?
        if let current, let max, max > 0 {
            percent = SystemStatsFormatting.clampedFraction(current / max)
        } else {
            percent = nil
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        return (percent, state == kIOPSACPowerValue)
    }
}

private struct CPUCounters {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var nice: UInt64 = 0
    var idle: UInt64 = 0
}

private struct NetworkCounters {
    var sent: UInt64 = 0
    var received: UInt64 = 0
}
