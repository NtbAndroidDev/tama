import AppKit

/// Battery of the connected Bluetooth headphones (AirPods, Beats…).
public struct HeadphoneBattery: Sendable, Equatable {
    public var name: String
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    /// Headphones that report one level (over-ears) rather than two buds.
    public var main: Int?
    /// Apple's product ID ("0x2014"), which tells AirPods models apart
    /// whatever they've been renamed to.
    public var productID: Int?

    /// The headline number: the single level, or the buds' average.
    public var level: Int? {
        if let main { return main }
        let buds = [left, right].compactMap { $0 }
        return buds.isEmpty ? nil : buds.reduce(0, +) / buds.count
    }

    /// "L 72% · R 66%" when both buds report.
    public var detail: String? {
        guard let left, let right else { return nil }
        return "L \(left)% · R \(right)%"
    }

    /// Every level there is: "L 72% · R 66% · Case 40%", or "80%".
    public var fullDetail: String? {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if left == nil, right == nil, let main { parts.append("\(main)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The SF Symbol for the model, from the product ID, else the name.
    public var symbol: String {
        switch productID {
        case 0x2013, 0x2019, 0x201B: return HeadphoneSymbol.available("airpods.gen3", fallback: "airpods")
        case 0x2002, 0x200F: return "airpods"
        case 0x200E, 0x2014, 0x2024: return "airpodspro"
        case 0x200A, 0x201F: return "airpodsmax"
        default: return HeadphoneSymbol.forName(name) ?? "headphones"
        }
    }
}

/// SF Symbols for headphones by name, for the connect HUD and the volume HUD's device.
public enum HeadphoneSymbol {
    public static func forName(_ name: String) -> String? {
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods 3") || name.contains("airpods (3") || name.contains("airpods 4")
            || name.contains("airpods (4") {
            return available("airpods.gen3", fallback: "airpods")
        }
        if name.contains("airpods") { return "airpods" }
        if name.contains("studio buds") { return available("beats.studiobuds", fallback: "earbuds") }
        if name.contains("fit pro") { return available("beats.fitpro", fallback: "earbuds") }
        if name.contains("powerbeats") { return available("beats.powerbeatspro", fallback: "earbuds") }
        if name.contains("beats") { return available("beats.headphones", fallback: "headphones") }
        if name.contains("buds") || name.contains("earbud") { return available("earbuds", fallback: "headphones") }
        if name.contains("headphone") || name.contains("headset") { return "headphones" }
        return nil
    }

    /// The symbol when this macOS has it, else the fallback.
    public static func available(_ symbol: String, fallback: String) -> String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallback
    }
}

/// There's no public API for AirPods battery, so this reads what System
/// Information shows (`system_profiler SPBluetoothDataType`), off the main
/// thread, every few minutes while something is watching.
@MainActor
public final class HeadphoneBatteryService: ObservableObject {
    public static let shared = HeadphoneBatteryService()

    @Published public private(set) var battery: HeadphoneBattery?

    private var timer: Timer?
    private var isReading = false
    private var lastRead: Date?
    /// Who is showing the battery ("lockScreen", "home"); polls while any is.
    private var holders: Set<String> = []

    private init() {}

    public func start(for holder: String) {
        holders.insert(holder)
        guard timer == nil else { return }
        // Home's card starts and stops with the shelf; system_profiler is too
        // heavy to run on every open, so a reading from the last minute stands.
        if lastRead.map({ Date().timeIntervalSince($0) > 60 }) ?? true { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in
            MainActor.assumeIsolated {
                // The lock screen holds this while the lid is shut; spawning
                // system_profiler in every dark wake is heat for nothing.
                guard !PowerStateService.shared.isDormant else { return }
                HeadphoneBatteryService.shared.refresh()
            }
        }
        timer?.tolerance = 20
    }

    public func stop(for holder: String) {
        holders.remove(holder)
        guard holders.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Reads the battery again; `completion` gets the new reading (also
    /// when a read already in flight delivers it).
    /// A plain refresh with nothing to call back, for the wake-up sweep.
    /// `refresh()` already does nothing when nobody is watching.
    public func refreshNow() {
        guard !holders.isEmpty else { return }
        refresh()
    }

    public func refresh(completion: (@MainActor (HeadphoneBattery?) -> Void)? = nil) {
        if let completion { waiting.append(completion) }
        guard !isReading else { return }
        isReading = true
        Task {
            let reading = await Task.detached(priority: .utility) { Self.read() }.value
            if battery != reading { battery = reading }
            lastRead = Date()
            isReading = false
            let callbacks = waiting
            waiting.removeAll()
            callbacks.forEach { $0(reading) }
        }
    }

    private var waiting: [@MainActor (HeadphoneBattery?) -> Void] = []

    private nonisolated static func read() -> HeadphoneBattery? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let connected = sections.first?["device_connected"] as? [[String: Any]]
        else { return nil }

        func percent(_ value: Any?) -> Int? {
            (value as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        }
        // Each entry is { "<device name>": { properties } }.
        for entry in connected {
            for (name, value) in entry {
                guard let props = value as? [String: Any] else { continue }
                let battery = HeadphoneBattery(
                    name: name,
                    left: percent(props["device_batteryLevelLeft"]),
                    right: percent(props["device_batteryLevelRight"]),
                    caseLevel: percent(props["device_batteryLevelCase"]),
                    main: percent(props["device_batteryLevelMain"]),
                    productID: (props["device_productID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                )
                // Keyboards and mice report a level too; only take audio gear.
                let kind = (props["device_minorType"] as? String ?? "").lowercased()
                let isAudio = kind.contains("head") || kind.contains("ear") || battery.left != nil
                if isAudio, battery.level != nil { return battery }
            }
        }
        return nil
    }
}
