import Foundation
import IOKit.pwr_mgt
import IOKit.ps

/// What High Alert keeps awake. The gear button cycles through them.
public enum HighAlertMode: String, CaseIterable, Identifiable, Sendable {
    /// Screen and Mac stay awake.
    case display
    /// Mac awake, screen can turn off.
    case system
    /// Mac stays awake with the lid closed (`pmset disablesleep`, needs an admin password).
    case lidClosed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .display: "Screen"
        case .system: "System"
        case .lidClosed: "Lid Closed"
        }
    }

    public var summary: String {
        switch self {
        case .display: "Screen and Mac stay awake"
        case .system: "Mac awake, screen can turn off"
        case .lidClosed: "Mac stays awake with lid closed"
        }
    }

    public var icon: String {
        switch self {
        case .display: "display"
        case .system: "gearshape.2"
        case .lidClosed: "laptopcomputer"
        }
    }

    public var next: HighAlertMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

@MainActor
public final class SleepBlockerService: ObservableObject {
    public static let shared = SleepBlockerService()

    @Published public private(set) var isAwakeActive: Bool = false
    @Published public private(set) var remainingSeconds: Int = 0
    /// The mode of the running session.
    @Published public private(set) var activeMode: HighAlertMode = .display
    /// `pmset` reports sleep disabled system-wide (ours or someone else's).
    @Published public private(set) var isSystemSleepDisabled = false
    /// Waiting on the administrator prompt for Lid-Closed mode.
    @Published public private(set) var isAuthorizing = false

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    /// Set while Tama has switched `disablesleep` on, so it's put back even
    /// after a crash (checked at launch).
    private static let lidFlagKey = "highAlertDisabledSleep"

    private init() {}

    public var mode: HighAlertMode {
        HighAlertMode(rawValue: UserDefaults.standard.string(forKey: "highAlertMode") ?? "") ?? .display
    }

    public func toggleIndefinite() {
        if isAwakeActive {
            disable()
        } else {
            enable(durationSeconds: 0)
        }
    }

    public func activateForDuration(minutes: Int) {
        enable(durationSeconds: minutes * 60)
    }

    /// Starts in the mode picked in Settings (or with the gear button).
    public func enable(durationSeconds: Int, mode: HighAlertMode? = nil) {
        let mode = mode ?? self.mode
        disable()
        if mode == .lidClosed {
            isAuthorizing = true
            Self.setSystemSleepDisabled(true) { [weak self] error in
                guard let self else { return }
                self.isAuthorizing = false
                if let error {
                    AppState.shared.showNotification(appName: "High Alert", title: "Lid-Closed High Alert is off",
                                                     message: error, icon: "exclamationmark.triangle.fill")
                    return
                }
                UserDefaults.standard.set(true, forKey: Self.lidFlagKey)
                self.begin(durationSeconds: durationSeconds, mode: mode)
                self.refreshSystemSleepStatus()
                // Lid closed and awake is only safe on power. Started on
                // battery it's one closed lid away from cooking in a bag.
                if !Self.isOnPower {
                    AppState.shared.showNotification(
                        appName: "High Alert", title: "Lid-Closed High Alert is on battery",
                        message: "Your Mac won't sleep with the lid closed. Plug in, or don't put it in a bag.",
                        icon: "exclamationmark.triangle.fill", duration: 10
                    )
                }
            }
        } else {
            begin(durationSeconds: durationSeconds, mode: mode)
        }
    }

    private func begin(durationSeconds: Int, mode: HighAlertMode) {
        let reason = "Tama High Alert" as CFString
        let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)

        guard result == kIOReturnSuccess else {
            assertionID = 0
            if mode == .lidClosed { restoreSystemSleep() }
            AppState.shared.showNotification(appName: "High Alert", title: "Couldn't keep your Mac awake",
                                             message: "macOS refused the sleep assertion (error \(result)).")
            return
        }
        activeMode = mode
        isAwakeActive = true
        remainingSeconds = durationSeconds
        guard durationSeconds > 0 else { return }

        // Counted against an end date, so sleep or a busy main thread can't stretch it,
        // and in .common mode so it keeps ticking while a menu is open.
        let endDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let left = Int(endDate.timeIntervalSinceNow.rounded(.up))
                if left > 0 {
                    self.remainingSeconds = left
                } else {
                    self.disable()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func disable() {
        if isAwakeActive {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isAwakeActive = false
            remainingSeconds = 0
            timer?.invalidate()
            timer = nil
            if activeMode == .lidClosed { restoreSystemSleep() }
        }
    }

    // MARK: Safety

    /// Whether the Mac is running on an adapter right now.
    static var isOnPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return true }
        return (IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String?) == kIOPMACPowerKey
    }

    /// The charger came out. Lid-Closed High Alert keeps the Mac awake with the
    /// lid shut, and a Mac that can't sleep in a closed bag on battery gets hot
    /// and flat — so unplugging ends the session and puts system sleep back.
    /// `BatteryService` calls this on every power-source change, whether or not
    /// battery alerts are switched on.
    public func powerSourceChanged() {
        guard isAwakeActive, activeMode == .lidClosed, !Self.isOnPower else { return }
        disable()
        AppState.shared.showNotification(
            appName: "High Alert", title: "Lid-Closed High Alert ended",
            message: "You unplugged the charger, so your Mac can sleep with the lid closed again.",
            icon: "powerplug.fill", duration: 8
        )
    }

    // MARK: System sleep

    /// Puts `disablesleep` back if Tama switched it on (asks for the password again).
    public func restoreSystemSleep(synchronously: Bool = false) {
        guard UserDefaults.standard.bool(forKey: Self.lidFlagKey) else { return }
        if synchronously {
            if Self.runPrivileged("/usr/bin/pmset -a disablesleep 0") == nil {
                UserDefaults.standard.removeObject(forKey: Self.lidFlagKey)
            }
            return
        }
        Self.setSystemSleepDisabled(false) { [weak self] error in
            if error == nil { UserDefaults.standard.removeObject(forKey: Self.lidFlagKey) }
            self?.refreshSystemSleepStatus()
            if let error {
                AppState.shared.showNotification(appName: "High Alert", title: "System sleep is still disabled",
                                                 message: error, icon: "exclamationmark.triangle.fill",
                                                 actionTitle: "Try Again",
                                                 action: { SleepBlockerService.shared.restoreSystemSleep() })
            }
        }
    }

    /// At launch: a crash or force-quit during Lid-Closed mode left sleep off.
    public func checkLeftoverLidMode() {
        refreshSystemSleepStatus()
        guard UserDefaults.standard.bool(forKey: Self.lidFlagKey) else { return }
        AppState.shared.showNotification(appName: "High Alert", title: "System sleep is still disabled",
                                         message: "Lid-Closed High Alert didn't finish cleanly.",
                                         icon: "exclamationmark.triangle.fill", actionTitle: "Restore",
                                         action: { SleepBlockerService.shared.restoreSystemSleep() }, duration: 12)
    }

    /// Reads `SleepDisabled` from `pmset -g` off the main thread.
    public func refreshSystemSleepStatus() {
        Task.detached(priority: .utility) {
            let output = Self.capture("/usr/bin/pmset", ["-g"])
            let disabled = output.split(separator: "\n").contains {
                let parts = $0.split(whereSeparator: \.isWhitespace)
                return parts.first == "SleepDisabled" && parts.last == "1"
            }
            await MainActor.run { SleepBlockerService.shared.isSystemSleepDisabled = disabled }
        }
    }

    /// Put your Mac to sleep.
    public func sleepNow() {
        disable()
        Task.detached(priority: .userInitiated) { _ = Self.capture("/usr/bin/pmset", ["sleepnow"]) }
    }

    private static func setSystemSleepDisabled(_ disabled: Bool, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        let command = "/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)"
        Task.detached(priority: .userInitiated) {
            let error = runPrivileged(command)
            await MainActor.run { completion(error) }
        }
    }

    /// Runs a fixed command through AppleScript's administrator prompt. Returns
    /// an error message, or nil on success.
    nonisolated private static func runPrivileged(_ command: String) -> String? {
        let script = "do shell script \"\(command)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return error.localizedDescription }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(data: data, encoding: .utf8) ?? ""
        if message.contains("-128") || message.localizedCaseInsensitiveContains("cancel") {
            return "The administrator prompt was cancelled."
        }
        return message.isEmpty ? "pmset failed." : message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func capture(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
