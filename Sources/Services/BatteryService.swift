import Foundation
import IOKit.ps
import Combine

/// Power-source events in the notch: charger plugged in or out, battery low,
/// fully charged. Driven by IOKit's power-source notification, not polling.
/// Also owns Low Power Mode: offered on the low-battery banner, announced when
/// it changes.
@MainActor
public final class BatteryService: ObservableObject {
    public static let shared = BatteryService()

    private struct Reading: Equatable {
        var percent: Int
        var onAC: Bool
        var isCharging: Bool
    }

    private var last: Reading?
    private var warnedLevels: Set<Int> = []
    private var didAnnounceFull = false
    private var runLoopSource: CFRunLoopSource?

    @Published public private(set) var isLowPowerModeOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The admin prompt is up; keeps the toggle from firing twice.
    @Published public private(set) var isChangingLowPowerMode = false
    private var powerStateObserver: NSObjectProtocol?

    private init() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { BatteryService.shared.lowPowerModeChanged() }
        }
    }

    public func start() {
        guard runLoopSource == nil else { return }
        last = Self.read()
        let callback: IOPowerSourceCallbackType = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { BatteryService.shared.powerSourceChanged() }
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() else { return }
        // Common modes: a charger plugged in while a menu is open still shows.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    /// Re-reads the power source now, outside a change notification. Used when
    /// the Mac wakes, since a charger plugged in while it slept was never announced.
    public func refreshNow() {
        powerSourceChanged()
    }

    private func powerSourceChanged() {
        // Before the alert settings are consulted: Lid-Closed High Alert has to
        // hear about the charger coming out whether or not battery alerts are on.
        SleepBlockerService.shared.powerSourceChanged()
        guard let now = Self.read() else { return }
        defer { last = now }
        guard AppState.shared.showBatteryAlerts, let previous = last else { return }

        if now.onAC != previous.onAC {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "battery",
                icon: now.onAC ? "bolt.fill" : Self.batterySymbol(now.percent),
                tint: now.onAC ? DS.Palette.success : .white,
                trailing: .text("\(now.percent)%"),
                priority: .urgent,
                label: now.onAC ? "Charging · \(now.percent)%" : "On battery · \(now.percent)%",
                expiresAt: Date().addingTimeInterval(3.5)
            ))
            if now.onAC { warnedLevels.removeAll() } else { didAnnounceFull = false }
        }

        if !now.onAC {
            for level in [20, 10] where now.percent <= level && !warnedLevels.contains(level) {
                warnedLevels.insert(level)
                LiveActivityCenter.shared.post(LiveActivity(
                    id: "battery",
                    icon: "battery.25",
                    tint: level == 10 ? DS.Palette.danger : DS.Palette.warning,
                    trailing: .text("\(now.percent)%"),
                    priority: .urgent,
                    label: "Battery low · \(now.percent)%",
                    expiresAt: Date().addingTimeInterval(6)
                ))
                let offerLowPower = !ProcessInfo.processInfo.isLowPowerModeEnabled
                let enableLowPower: @MainActor @Sendable () -> Void = { BatteryService.shared.setLowPowerMode(true) }
                AppState.shared.showNotification(
                    appName: "Battery",
                    title: "Battery at \(now.percent)%",
                    message: level == 10 ? "Plug in soon — your Mac will sleep when it runs out." : "Consider plugging in.",
                    actionTitle: offerLowPower ? "Low Power" : nil,
                    action: offerLowPower ? enableLowPower : nil
                )
                break
            }
        }

        if now.onAC, now.percent >= 100, !didAnnounceFull {
            didAnnounceFull = true
            LiveActivityCenter.shared.post(LiveActivity(
                id: "battery",
                icon: "battery.100",
                tint: DS.Palette.success,
                trailing: .text("100%"),
                priority: .urgent,
                label: "Fully charged",
                expiresAt: Date().addingTimeInterval(3.5)
            ))
        }
    }

    // MARK: Low Power Mode

    private func lowPowerModeChanged() {
        let on = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard on != isLowPowerModeOn else { return }
        isLowPowerModeOn = on
        guard AppState.shared.showBatteryAlerts else { return }
        LiveActivityCenter.shared.post(LiveActivity(
            id: "battery",
            icon: on ? "leaf.fill" : "leaf",
            tint: on ? DS.Palette.warning : .white.opacity(0.7),
            trailing: .text(on ? "On" : "Off"),
            priority: .urgent,
            label: on ? "Low Power Mode on" : "Low Power Mode off",
            expiresAt: Date().addingTimeInterval(3)
        ))
    }

    /// There's no public API to flip Low Power Mode, so this goes through pmset,
    /// which needs an administrator password each time.
    public func setLowPowerMode(_ on: Bool) {
        guard !isChangingLowPowerMode, on != ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        isChangingLowPowerMode = true
        Task {
            let failure = await Task.detached(priority: .userInitiated) { Self.runPmset(lowPower: on) }.value
            isChangingLowPowerMode = false
            // The power-state notification can lag pmset slightly.
            lowPowerModeChanged()
            if let failure {
                AppState.shared.showNotification(appName: "Battery", title: "Couldn't change Low Power Mode", message: failure)
            }
        }
    }

    /// nil on success or when the user cancels the password prompt.
    nonisolated private static func runPmset(lowPower on: Bool) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"pmset -a lowpowermode \(on ? 1 : 0)\" with administrator privileges"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return error.localizedDescription }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // -128: the user pressed Cancel.
        if message.contains("-128") { return nil }
        return message.isEmpty ? "pmset exited with status \(process.terminationStatus)." : message
    }

    private static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 76...: "battery.100"
        case 51...: "battery.75"
        case 26...: "battery.50"
        default: "battery.25"
        }
    }

    /// The internal battery, or nil on a Mac without one.
    private static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            return Reading(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return nil
    }
}
