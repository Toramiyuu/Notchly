import Foundation
import IOKit.ps
import Combine

class SystemMonitorManager: ObservableObject {

    static let shared = SystemMonitorManager()

    @Published var cpuUsage: Double = 0       // 0-1
    @Published var memoryUsed: Double = 0     // GB
    @Published var memoryTotal: Double = 0    // GB
    @Published var memoryPressure: Double = 0 // 0-1
    @Published var batteryPercent: Int = 100
    @Published var isCharging: Bool = false
    @Published var hasBattery: Bool = false

    private var timer: Timer?
    private var prevCPUInfo: [Int32]?
    private var prevCPUInfoCount: mach_msg_type_number_t = 0

    private init() { startPolling() }
    deinit { timer?.invalidate() }

    private func startPolling() {
        let interval = UserDefaults.standard.object(forKey: "sysmon.pollInterval") as? TimeInterval ?? 2.0
        applyPollInterval(interval)
    }

    func applyPollInterval(_ interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = interval * 0.2
        refresh()
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cpu = self?.readCPU() ?? 0
            let (used, total, pressure) = self?.readMemory() ?? (0, 0, 0)
            let (pct, charging, hasBatt) = self?.readBattery() ?? (100, false, false)
            DispatchQueue.main.async {
                self?.cpuUsage = cpu
                self?.memoryUsed = used
                self?.memoryTotal = total
                self?.memoryPressure = pressure
                self?.batteryPercent = pct
                self?.isCharging = charging
                self?.hasBattery = hasBatt
            }
        }
    }

    // MARK: - CPU (host_processor_info delta)

    private func readCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &numCPUs, &cpuInfo, &numCPUInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else {
            // Clear stale snapshot so the next successful call uses absolute values
            prevCPUInfo = nil
            prevCPUInfoCount = 0
            return 0
        }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var totalUsed: Int32 = 0
        var totalTicks: Int32 = 0

        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            let user   = info[base + Int(CPU_STATE_USER)]
            let system = info[base + Int(CPU_STATE_SYSTEM)]
            let nice   = info[base + Int(CPU_STATE_NICE)]
            let idle   = info[base + Int(CPU_STATE_IDLE)]

            if let prev = prevCPUInfo, prevCPUInfoCount > mach_msg_type_number_t(base + Int(CPU_STATE_IDLE)) {
                let dUser   = user   - prev[base + Int(CPU_STATE_USER)]
                let dSystem = system - prev[base + Int(CPU_STATE_SYSTEM)]
                let dNice   = nice   - prev[base + Int(CPU_STATE_NICE)]
                let dIdle   = idle   - prev[base + Int(CPU_STATE_IDLE)]
                totalUsed  += dUser + dSystem + dNice
                totalTicks += dUser + dSystem + dNice + dIdle
            } else {
                totalUsed  += user + system + nice
                totalTicks += user + system + nice + idle
            }
        }

        // Store current snapshot
        let count = Int(numCPUInfo)
        prevCPUInfo = (0..<count).map { info[$0] }
        prevCPUInfoCount = numCPUInfo

        guard totalTicks > 0 else { return 0 }
        return Double(totalUsed) / Double(totalTicks)
    }

    // MARK: - Memory (host_statistics64)

    private func readMemory() -> (used: Double, total: Double, pressure: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let pageSize = Double(vm_kernel_page_size)
        let gb = 1_073_741_824.0

        let active    = Double(stats.active_count)   * pageSize
        let wired     = Double(stats.wire_count)     * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = (active + wired + compressed) / gb

        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
        let total = Double(size) / gb

        let pressure = total > 0 ? min(used / total, 1.0) : 0
        return (used, total, pressure)
    }

    // MARK: - Battery (IOKit Power Sources)

    private func readBattery() -> (percent: Int, charging: Bool, hasBattery: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else { return (100, false, false) }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let type = desc[kIOPSTypeKey] as? String ?? ""
            guard type == kIOPSInternalBatteryType else { continue }

            let pct = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            return (pct, charging, true)
        }
        return (100, false, false)
    }
}
