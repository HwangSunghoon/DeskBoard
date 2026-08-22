import Foundation
import Darwin
import IOKit.ps

struct SystemSnapshot {
    var cpuUsage = 0.0
    var memoryUsage = 0.0
    var batteryPercent: Int?
    var isCharging = false
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
}

final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()

    private var timer: DispatchSourceTimer?
    private var previousCPUTicks: (used: UInt64, total: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?
    private var tick = 0

    func start() {
        guard timer == nil else { return }
        refresh(includeBattery: true, includeUptime: true)

        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.tick += 1
            self.refresh(includeBattery: self.tick.isMultiple(of: 8), includeUptime: self.tick.isMultiple(of: 30))
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }

    private func refresh(includeBattery: Bool, includeUptime: Bool) {
        let cpu = readCPUUsage()
        let memory = readMemoryUsage()
        let network = readNetworkSpeed()
        let battery = includeBattery ? readBattery() : nil
        let uptime = includeUptime ? ProcessInfo.processInfo.systemUptime : nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshot.cpuUsage = cpu
            self.snapshot.memoryUsage = memory
            self.snapshot.downloadBytesPerSecond = network.received
            self.snapshot.uploadBytesPerSecond = network.sent
            if let battery {
                self.snapshot.batteryPercent = battery.percent
                self.snapshot.isCharging = battery.charging
            }
            if let uptime { self.snapshot.uptime = uptime }
        }
    }

    private func readCPUUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.cpuUsage }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { previousCPUTicks = (used, total) }
        guard let previousCPUTicks, total > previousCPUTicks.total else { return 0 }
        return Double(used - previousCPUTicks.used) / Double(total - previousCPUTicks.total)
    }

    private func readMemoryUsage() -> Double {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let usedPages = UInt64(info.active_count + info.inactive_count + info.wire_count + info.compressor_page_count)
        let used = Double(usedPages * UInt64(pageSize))
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    private func readNetworkSpeed() -> (received: Double, sent: Double) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = item.pointee.ifa_data?.assumingMemoryBound(to: if_data.self),
                  (item.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNetwork = (received, sent, now) }
        guard let previousNetwork else { return (0, 0) }
        let elapsed = max(now.timeIntervalSince(previousNetwork.date), 0.1)
        return (
            Double(received >= previousNetwork.received ? received - previousNetwork.received : 0) / elapsed,
            Double(sent >= previousNetwork.sent ? sent - previousNetwork.sent : 0) / elapsed
        )
    }

    private func readBattery() -> (percent: Int?, charging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true ||
                (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Int((Double(current) / Double(maximum) * 100).rounded()), charging)
        }
        return (nil, false)
    }
}
