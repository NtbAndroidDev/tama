import Foundation
import IOKit.ps

public struct SystemHealthMetrics: Sendable, Equatable {
    public var cpuUsagePercent: Double
    public var memoryUsedGigabytes: Double
    public var memoryTotalGigabytes: Double
    public var batteryPercent: Int
    public var isCharging: Bool
    /// False on desktops (Mac mini, Studio, iMac): no battery to report.
    public var hasBattery: Bool
    
    public init(
        cpuUsagePercent: Double = 0,
        memoryUsedGigabytes: Double = 0,
        memoryTotalGigabytes: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
        batteryPercent: Int = 0,
        isCharging: Bool = false,
        hasBattery: Bool = false
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedGigabytes = memoryUsedGigabytes
        self.memoryTotalGigabytes = memoryTotalGigabytes
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.hasBattery = hasBattery
    }
    
    public var memoryUsagePercent: Double {
        guard memoryTotalGigabytes > 0 else { return 0 }
        return (memoryUsedGigabytes / memoryTotalGigabytes) * 100.0
    }
}

@MainActor
public final class SystemMonitorService: ObservableObject {
    public static let shared = SystemMonitorService()
    
    @Published public private(set) var metrics = SystemHealthMetrics()
    private var timer: Timer?
    /// Previous CPU tick counters; usage is the difference between two samples.
    private var lastCPUTicks: (active: Double, total: Double)?
    
    public var cpuUsage: Double { metrics.cpuUsagePercent / 100.0 }
    public var memoryUsage: Double { metrics.memoryUsagePercent / 100.0 }
    public var batteryLevel: Int { metrics.batteryPercent }
    public var isCharging: Bool { metrics.isCharging }
    public var hasBattery: Bool { metrics.hasBattery }
    public var batteryIconName: String {
        if !metrics.hasBattery { return "powerplug.fill" }
        if metrics.isCharging { return "battery.100.bolt" }
        if metrics.batteryPercent > 70 { return "battery.100" }
        if metrics.batteryPercent > 40 { return "battery.50" }
        return "battery.25"
    }
    
    /// Views on screen that show these metrics (System Stats console, Home card).
    private var subscriberCount = 0
    /// Whether the last timer tick sampled; a gap means the CPU baseline is stale.
    private var wasSampling = false

    private init() {
        refreshMetrics()
        startPeriodicUpdate()
    }

    /// Call from `onAppear`: keeps polling alive while the view is on screen and
    /// refreshes straight away. Balance with `unsubscribe()` in `onDisappear`.
    public func subscribe() {
        subscriberCount += 1
        guard subscriberCount == 1 else { return }
        startPeriodicUpdate()
        guard !wasSampling else { return refreshMetrics() }
        resumeSampling()
        // Memory and battery now; CPU once there is a short interval to measure.
        refreshMetrics(sampleCPU: false)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.isNeeded else { return }
            self.refreshMetrics()
        }
    }

    public func unsubscribe() {
        subscriberCount = max(subscriberCount - 1, 0)
    }

    private var isNeeded: Bool {
        subscriberCount > 0 || AppState.shared.isLiveActivityPresented
    }

    /// Runs until a tick finds nobody watching; `subscribe()` starts it again.
    private func startPeriodicUpdate() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                // Only the Live Activity HUD and on-screen stats views show
                // these; with nobody watching the timer stops altogether.
                guard let self else { return }
                guard self.isNeeded else {
                    self.wasSampling = false
                    self.timer?.invalidate()
                    self.timer = nil
                    return
                }
                // The lock screen's battery keeps a subscriber while the lid
                // is shut; PowerStateService refreshes on wake.
                guard !PowerStateService.shared.isDormant else { return }
                guard self.wasSampling else { return self.resumeSampling() }
                self.refreshMetrics()
            }
        }
        timer.tolerance = 0.4
        self.timer = timer
    }

    /// After a pause a CPU delta over the whole gap would average away the
    /// current load, so take a fresh baseline for the next sample to measure from.
    private func resumeSampling() {
        lastCPUTicks = nil
        _ = readCPUUsage()
        wasSampling = true
    }

    public func refreshMetrics(sampleCPU: Bool = true) {
        let cpu = sampleCPU ? readCPUUsage() : nil
        let (memUsed, memTotal) = readMemory()
        let battery = readBattery()
        
        let sample = SystemHealthMetrics(
            cpuUsagePercent: cpu ?? metrics.cpuUsagePercent,
            memoryUsedGigabytes: memUsed,
            memoryTotalGigabytes: memTotal,
            batteryPercent: battery?.percent ?? 0,
            isCharging: battery?.charging ?? false,
            hasBattery: battery != nil
        )
        // Every assignment redraws each view of the metrics, changed or not.
        if sample != metrics { metrics = sample }
    }
    
    private func readCPUUsage() -> Double? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let user = Double(cpuLoad.cpu_ticks.0)
            let system = Double(cpuLoad.cpu_ticks.1)
            let idle = Double(cpuLoad.cpu_ticks.2)
            let nice = Double(cpuLoad.cpu_ticks.3)
            let total = user + system + idle + nice
            let active = user + system + nice
            defer { lastCPUTicks = (active, total) }
            guard let last = lastCPUTicks else {
                return total > 0 ? active / total * 100 : nil
            }
            let deltaTotal = total - last.total
            guard deltaTotal > 0 else { return nil }
            return min(max((active - last.active) / deltaTotal * 100.0, 0), 100)
        }
        return nil
    }
    
    private func readMemory() -> (Double, Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let res = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / (1024 * 1024 * 1024)
        
        if res == KERN_SUCCESS {
            let pageSize = Double(getpagesize())
            let active = Double(stats.active_count) * pageSize
            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            let usedGB = (active + wired + compressed) / (1024 * 1024 * 1024)
            return (usedGB, totalGB)
        }
        return (totalGB * 0.65, totalGB)
    }
    
    /// The internal battery, or nil on Macs without one.
    private func readBattery() -> (percent: Int, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
            let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maxCapacity > 0 ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : current
            return (percent, desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}
