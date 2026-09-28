import AppKit
import SwiftUI
import CoreAudio
import Network

// The small system HUDs of Settings › HUDs › System that have no service of
// their own elsewhere: Caps Lock, recording status, Focus and No internet.
// Each posts a live activity (or a banner) and switches itself off with its
// card.

// MARK: - Caps Lock

/// A brief On / Off in the notch when Caps Lock changes. Modifier changes are
/// heard with `flagsChanged` monitors, which need Accessibility to hear other
/// apps; until it's granted the lock state is polled instead (reading the
/// current modifiers needs no permission).
@MainActor
public final class CapsLockService {
    public static let shared = CapsLockService()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var poll: Timer?
    private var pollTicks = 0
    private var trustObservers: (distributed: NSObjectProtocol, local: NSObjectProtocol)?
    private var isOn = NSEvent.modifierFlags.contains(.capsLock)

    private init() {}

    public func sync() {
        guard HUDSettings.shared.showCapsLockHUD else {
            [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
            globalMonitor = nil
            localMonitor = nil
            stopPolling()
            return
        }
        isOn = NSEvent.modifierFlags.contains(.capsLock)
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                let on = event.modifierFlags.contains(.capsLock)
                MainActor.assumeIsolated { CapsLockService.shared.update(on) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                let on = event.modifierFlags.contains(.capsLock)
                MainActor.assumeIsolated { CapsLockService.shared.update(on) }
                return event
            }
        }
        if !AXIsProcessTrusted(), poll == nil {
            let timer = Timer(timeInterval: 0.3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let service = CapsLockService.shared
                    service.update(NSEvent.modifierFlags.contains(.capsLock))
                    // The trust check is heavier than the flag read; the
                    // notifications below catch a grant, this is a backstop.
                    service.pollTicks += 1
                    if service.pollTicks % 20 == 0 { service.stopPollingIfTrusted() }
                }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
            watchTrust()
        }
    }

    /// macOS announces a change to the Accessibility list, and the user comes
    /// back to Tama after granting it; either is the moment to look.
    private func watchTrust() {
        guard trustObservers == nil else { return }
        let check: @Sendable (Notification) -> Void = { _ in
            // The list can lag its own announcement by a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { CapsLockService.shared.stopPollingIfTrusted() }
            }
        }
        trustObservers = (
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main, using: check),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: check)
        )
    }

    /// Once Accessibility is in, the monitors hear everything.
    private func stopPollingIfTrusted() {
        guard poll != nil, AXIsProcessTrusted() else { return }
        stopPolling()
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
        pollTicks = 0
        if let trustObservers {
            DistributedNotificationCenter.default().removeObserver(trustObservers.distributed)
            NotificationCenter.default.removeObserver(trustObservers.local)
        }
        trustObservers = nil
    }

    private func update(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        guard HUDSettings.shared.showCapsLockHUD else { return }
        LiveActivityCenter.shared.post(LiveActivity(
            id: "capsLock", icon: on ? "capslock.fill" : "capslock",
            tint: on ? DS.Palette.success : .white.opacity(0.7),
            trailing: .text(on ? "On" : "Off"), priority: .urgent,
            label: on ? "Caps Lock on" : "Caps Lock off", expiresAt: Date().addingTimeInterval(1.5)
        ))
    }
}

// MARK: - Recording status

/// A red timer in the notch while a microphone or the screen is being
/// recorded.
///
/// - **Microphone**: CoreAudio's "device is running somewhere" on every input
///   device — the same signal behind the orange dot, and it covers any app.
/// - **Screen**: there's no public signal. macOS's own recorder (⌘⇧5, the
///   Screenshot app, QuickTime) runs in `screencaptureui`, which puts a stop
///   button in the menu bar while it records; that button's window is looked
///   for, and only while `screencaptureui` is running. Other recorders
///   (OBS, Zoom's screen share…) can't be seen.
@MainActor
public final class RecordingIndicatorService: ObservableObject {
    public static let shared = RecordingIndicatorService()

    @Published public private(set) var isMicrophoneInUse = false
    @Published public private(set) var isScreenRecording = false

    private var watchedDevices: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenPoll: Timer?
    private var ticker: Timer?
    private var startedAt: Date?

    nonisolated private static let screenRecorderBundleID = "com.apple.screencaptureui"

    private init() {}

    public func sync() {
        if HUDSettings.shared.showRecordingHUD {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard devicesListener == nil else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in RecordingIndicatorService.shared.rebindInputs() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        devicesListener = block
        rebindInputs()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == RecordingIndicatorService.screenRecorderBundleID else { return }
                MainActor.assumeIsolated { RecordingIndicatorService.shared.syncScreenWatch() }
            })
        }
        syncScreenWatch()
    }

    private func stop() {
        if let devicesListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, devicesListener)
        }
        devicesListener = nil
        unbindInputs()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        screenPoll?.invalidate()
        screenPoll = nil
        isMicrophoneInUse = false
        isScreenRecording = false
        updateActivity()
    }

    // MARK: Microphone

    private static var runningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func unbindInputs() {
        for (device, block) in watchedDevices {
            var address = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
        watchedDevices.removeAll()
    }

    private func rebindInputs() {
        unbindInputs()
        for device in Self.inputDevices() {
            var address = Self.runningAddress
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in RecordingIndicatorService.shared.refreshMicrophone() }
            }
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
            watchedDevices[device] = block
        }
        refreshMicrophone()
    }

    private func refreshMicrophone() {
        let inUse = watchedDevices.keys.contains { device in
            var address = Self.runningAddress
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
        }
        guard inUse != isMicrophoneInUse else { return }
        isMicrophoneInUse = inUse
        updateActivity()
    }

    private static func inputDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    // MARK: Screen

    private func syncScreenWatch() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.screenRecorderBundleID).isEmpty
        if running, screenPoll == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { RecordingIndicatorService.shared.refreshScreen() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            screenPoll = timer
            refreshScreen()
        } else if !running {
            screenPoll?.invalidate()
            screenPoll = nil
            if isScreenRecording {
                isScreenRecording = false
                updateActivity()
            }
        }
    }

    private func refreshScreen() {
        let recording = Self.recorderShowsStopButton()
        guard recording != isScreenRecording else { return }
        isScreenRecording = recording
        updateActivity()
    }

    /// `screencaptureui` with a window at the status-item level: the stop
    /// button it shows only while recording. Owner names and layers need no
    /// Screen Recording permission.
    private static func recorderShowsStopButton() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windows.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "screencaptureui"
                && (info[kCGWindowLayer as String] as? Int) == statusLevel
        }
    }

    // MARK: Activity

    private func updateActivity() {
        let active = isMicrophoneInUse || isScreenRecording
        guard active, HUDSettings.shared.showRecordingHUD else {
            ticker?.invalidate()
            ticker = nil
            startedAt = nil
            LiveActivityCenter.shared.end("recording")
            return
        }
        if startedAt == nil { startedAt = Date() }
        if ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { RecordingIndicatorService.shared.postActivity() }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        postActivity()
    }

    private func postActivity() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let what = isScreenRecording ? (isMicrophoneInUse ? "Screen and microphone" : "Screen") : "Microphone"
        LiveActivityCenter.shared.post(LiveActivity(
            id: "recording", icon: isScreenRecording ? "record.circle" : "mic.fill", tint: DS.Palette.danger,
            trailing: .text(String(format: "%d:%02d", seconds / 60, seconds % 60)), priority: .urgent,
            label: "\(what) in use"
        ))
    }
}

// MARK: - Focus

/// Focus (Do Not Disturb and the other modes) turning on or off. There's no
/// public API; macOS keeps the manually-set Focus in
/// `~/Library/DoNotDisturb/DB/Assertions.json` and names the modes in
/// `ModeConfigurations.json`. That folder is privacy-protected, so this only
/// works once Tama has Full Disk Access; without it the service says so and
/// stays quiet. Focus turned on by a schedule or automation isn't recorded
/// there and isn't seen.
@MainActor
public final class FocusModeService: ObservableObject {
    public static let shared = FocusModeService()

    public enum Status: Equatable {
        case unknown
        /// The Focus database can't be read (no Full Disk Access).
        case unreadable
        case off
        case on(name: String)
    }

    @Published public private(set) var status: Status = .unknown

    private var source: DispatchSourceFileSystemObject?
    private var readDebounce: DispatchWorkItem?

    private static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    private init() {}

    public func sync() {
        guard HUDSettings.shared.showFocusHUD else {
            source?.cancel()
            source = nil
            status = .unknown
            return
        }
        guard source == nil else { return }
        let fd = open(Self.folder.path, O_EVTONLY)
        guard fd >= 0 else {
            status = .unreadable
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { FocusModeService.shared.scheduleRead() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        // The first read only learns the current state.
        status = Self.read()
    }

    /// Re-checks access, e.g. after Full Disk Access was granted.
    public func retry() {
        source?.cancel()
        source = nil
        sync()
    }

    private func scheduleRead() {
        readDebounce?.cancel()
        let work = DispatchWorkItem { FocusModeService.shared.readAndAnnounce() }
        readDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func readAndAnnounce() {
        let new = Self.read()
        let old = status
        status = new
        guard HUDSettings.shared.showFocusHUD else { return }
        switch (old, new) {
        case let (.off, .on(name)):
            announce(on: true, name: name)
        case let (.on(previous), .on(name)) where previous != name:
            announce(on: true, name: name)
        case let (.on(name), .off):
            announce(on: false, name: name)
        default:
            break
        }
    }

    private func announce(on: Bool, name: String) {
        LiveActivityCenter.shared.post(LiveActivity(
            id: "focus", icon: on ? "moon.fill" : "moon", tint: on ? Color(red: 0.55, green: 0.5, blue: 1) : .white.opacity(0.7),
            trailing: .text(on ? "On" : "Off"), priority: .urgent,
            label: "\(name) \(on ? "on" : "off")", expiresAt: Date().addingTimeInterval(2.5)
        ))
    }

    private static func read() -> Status {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("Assertions.json")) else { return .unreadable }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return .off }
        let records = entries.flatMap { $0["storeAssertionRecords"] as? [[String: Any]] ?? [] }
        guard let record = records.last else { return .off }
        let details = record["assertionDetails"] as? [String: Any]
        let mode = details?["assertionDetailsModeIdentifier"] as? String
        return .on(name: mode.flatMap(modeName) ?? "Focus")
    }

    /// "Do Not Disturb", "Work"… from the modes' own configuration.
    private static func modeName(_ identifier: String) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("ModeConfigurations.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        for entry in entries {
            let configurations = entry["modeConfigurations"] as? [String: Any]
            if let configuration = configurations?[identifier] as? [String: Any],
               let mode = configuration["mode"] as? [String: Any],
               let name = mode["name"] as? String, !name.isEmpty {
                return name
            }
        }
        return identifier.hasSuffix(".default") ? "Do Not Disturb" : nil
    }
}

// MARK: - No internet

/// Watches the network path. When the Mac loses its internet connection (and
/// stays offline for a moment, so a Wi-Fi hand-over doesn't count) the notch
/// pops a banner with OK and a shortcut to Network settings.
@MainActor
public final class ConnectivityService: ObservableObject {
    public static let shared = ConnectivityService()

    @Published public private(set) var isOnline = true

    private var monitor: NWPathMonitor?
    private var hasFirstPath = false
    private var offlineWork: DispatchWorkItem?

    private init() {}

    public func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in ConnectivityService.shared.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "app.tama.connectivity", qos: .utility))
        self.monitor = monitor
    }

    /// The HUD follows its card; the path is watched either way, since other
    /// features can ask whether the Mac is online.
    public func sync() {
        if !HUDSettings.shared.showOfflineHUD {
            offlineWork?.cancel()
            offlineWork = nil
        }
    }

    private func update(_ online: Bool) {
        defer { hasFirstPath = true }
        guard online != isOnline || !hasFirstPath else { return }
        let wasOnline = isOnline
        isOnline = online
        offlineWork?.cancel()
        offlineWork = nil
        guard hasFirstPath, wasOnline, !online, HUDSettings.shared.showOfflineHUD else { return }
        let work = DispatchWorkItem {
            let service = ConnectivityService.shared
            guard !service.isOnline, HUDSettings.shared.showOfflineHUD else { return }
            AppState.shared.showNotification(
                appName: "Network", title: "No Internet Connection",
                message: "Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue.",
                icon: "wifi.exclamationmark", actionTitle: "Settings",
                action: { ConnectivityService.openNetworkSettings() },
                dismissTitle: "OK", duration: 8
            )
        }
        offlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    public static func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
