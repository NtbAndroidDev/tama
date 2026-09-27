import AppKit
import ApplicationServices
import CoreGraphics
import EventKit
import UserNotifications

/// One place that knows which system permissions Tama has, so Settings can
/// show them and the user can fix a missing one in a click. Statuses are
/// re-read whenever Tama comes to the front, since grants happen in System Settings.
@MainActor
public final class PermissionService: ObservableObject {
    public static let shared = PermissionService()

    /// What System Settings calls the Accessibility list: newer macOS renamed
    /// it, and users look for the name they see there.
    public nonisolated static var accessibilityName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? "Accessibility (Device Control and Data Access)"
            : "Accessibility"
    }

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case accessibility, screenRecording, calendars, reminders, notifications, automationMusic, automationSpotify
        case microphone, speechRecognition, inputMonitoring

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .accessibility: PermissionService.accessibilityName
            case .screenRecording: "Screen Recording"
            case .calendars: "Calendars"
            case .reminders: "Reminders"
            case .notifications: "Notifications"
            case .automationMusic: "Control Music"
            case .automationSpotify: "Control Spotify"
            case .microphone: "Microphone"
            case .speechRecognition: "Speech Recognition"
            case .inputMonitoring: "Input Monitoring"
            }
        }

        public var purpose: String {
            switch self {
            case .accessibility: "Paste from the clipboard, Window Snap, meeting shortcuts, Mouse Scrolling, media keys for browser playback and hiding the system volume and brightness HUD."
            case .screenRecording: "Snips and screen capture into the Tray."
            case .calendars: "Events on the Calendar page."
            case .reminders: "Tasks on the Calendar page."
            case .notifications: "Pomodoro alerts when the notch is out of view."
            case .automationMusic: "Play, skip, scrub and favourite in Apple Music."
            case .automationSpotify: "Play, skip and scrub in Spotify."
            case .microphone: "Voice recordings in Voice Transcribe."
            case .speechRecognition: "Turning voice recordings and audio files into text."
            case .inputMonitoring: "Hearing key presses for Mechey's keyboard sounds."
            }
        }

        public var iconName: String {
            switch self {
            case .accessibility: "accessibility"
            case .screenRecording: "rectangle.dashed.badge.record"
            case .calendars: "calendar"
            case .reminders: "checklist"
            case .notifications: "bell.badge"
            case .automationMusic: "music.note"
            case .automationSpotify: "waveform"
            case .microphone: "mic"
            case .speechRecognition: "waveform.badge.mic"
            case .inputMonitoring: "keyboard"
            }
        }

        /// System Settings pane for the privacy category.
        var settingsURL: URL? {
            let anchor: String
            switch self {
            case .accessibility: anchor = "Privacy_Accessibility"
            case .screenRecording: anchor = "Privacy_ScreenCapture"
            case .calendars: anchor = "Privacy_Calendars"
            case .reminders: anchor = "Privacy_Reminders"
            case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            case .automationMusic, .automationSpotify: anchor = "Privacy_Automation"
            case .microphone: anchor = "Privacy_Microphone"
            case .speechRecognition: anchor = "Privacy_SpeechRecognition"
            case .inputMonitoring: anchor = "Privacy_ListenEvent"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        }

        /// The TCC service `tccutil reset` takes, for clearing a stale grant.
        var tccService: String? {
            switch self {
            case .accessibility: "Accessibility"
            case .screenRecording: "ScreenCapture"
            case .calendars: "Calendar"
            case .reminders: "Reminders"
            case .automationMusic, .automationSpotify: "AppleEvents"
            case .microphone: "Microphone"
            case .speechRecognition: "SpeechRecognition"
            case .inputMonitoring: "ListenEvent"
            case .notifications: nil
            }
        }

        var automationBundleID: String? {
            switch self {
            case .automationMusic: "com.apple.Music"
            case .automationSpotify: "com.spotify.client"
            default: nil
            }
        }

        /// The app an Automation row controls, as shown in the "Open …" button.
        public var automationAppName: String? {
            switch self {
            case .automationMusic: "Music"
            case .automationSpotify: "Spotify"
            default: nil
            }
        }
    }

    public enum Status: Sendable {
        case granted, denied, notDetermined
        /// The target app isn't running, so macOS can't be asked yet.
        case unavailable
        /// Still being read (notifications answer asynchronously).
        case checking
    }

    @Published public private(set) var statuses: [Kind: Status] = [:]
    /// Screen Recording was requested this session. macOS only applies the
    /// grant to a fresh process, so the row offers a relaunch until then.
    @Published public private(set) var screenRecordingNeedsRelaunch = false
    /// CGRequestScreenCaptureAccess prompts only the first time; after that it
    /// just returns false, and System Settings is the only way in.
    private static let screenRecordingAskedKey = "screenRecordingRequested"
    private static let inputMonitoringAskedKey = "inputMonitoringRequested"
    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PermissionService.shared.refresh() }
        }
    }

    public func status(_ kind: Kind) -> Status { statuses[kind] ?? .notDetermined }

    public func refresh() {
        var next: [Kind: Status] = [:]
        next[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        let screenRecording = CGPreflightScreenCaptureAccess()
        next[.screenRecording] = screenRecording ? .granted : .denied
        if screenRecording { screenRecordingNeedsRelaunch = false }
        next[.calendars] = Self.eventKitStatus(.event)
        next[.reminders] = Self.eventKitStatus(.reminder)
        next[.automationMusic] = Self.automationStatus(for: "com.apple.Music", ask: false)
        next[.automationSpotify] = Self.automationStatus(for: "com.spotify.client", ask: false)
        next[.notifications] = statuses[.notifications] ?? (Self.canUseNotifications ? .checking : .notDetermined)
        next[.microphone] = Self.voiceStatus(microphone: true)
        next[.speechRecognition] = Self.voiceStatus(microphone: false)
        // Preflight can't tell "never asked" from "denied"; only call it denied
        // once Tama has asked, so people who never use Mechey see no red row.
        next[.inputMonitoring] = CGPreflightListenEventAccess() ? .granted
            : (UserDefaults.standard.bool(forKey: Self.inputMonitoringAskedKey) ? .denied : .notDetermined)
        statuses = next

        guard Self.canUseNotifications else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: Status = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            default: .notDetermined
            }
            Task { @MainActor in PermissionService.shared.statuses[.notifications] = status }
        }
    }

    /// Asks macOS for the permission where it can prompt, otherwise opens
    /// the right pane of System Settings.
    public func request(_ kind: Kind) {
        switch kind {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings(kind) }
        case .screenRecording:
            guard !CGPreflightScreenCaptureAccess() else { return refresh() }
            // The first request shows the system prompt; opening System
            // Settings on top of it would bury it. Later ones go straight there.
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: Self.screenRecordingAskedKey) {
                openSettings(kind)
            } else {
                defaults.set(true, forKey: Self.screenRecordingAskedKey)
                _ = CGRequestScreenCaptureAccess()
            }
            screenRecordingNeedsRelaunch = true
        case .calendars, .reminders:
            guard status(kind) == .notDetermined else { return openSettings(kind) }
            Task {
                let store = EKEventStore()
                _ = kind == .calendars
                    ? try? await store.requestFullAccessToEvents()
                    : try? await store.requestFullAccessToReminders()
                refresh()
            }
        case .notifications:
            guard status(kind) == .notDetermined, Self.canUseNotifications else { return openSettings(kind) }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { @MainActor in PermissionService.shared.refresh() }
            }
        case .automationMusic, .automationSpotify:
            guard let bundleID = kind.automationBundleID else { return }
            // Prompting blocks until the user answers, so do it off the main thread.
            Task.detached {
                let status = PermissionService.automationStatus(for: bundleID, ask: true)
                await MainActor.run {
                    if status == .denied { PermissionService.shared.openSettings(kind) }
                    PermissionService.shared.refresh()
                }
            }
        case .microphone, .speechRecognition:
            requestVoice(microphone: kind == .microphone)
        case .inputMonitoring:
            // Like Screen Recording: the request returns before the user answers,
            // so the first one only shows the prompt; later ones open System Settings.
            let defaults = UserDefaults.standard
            if CGPreflightListenEventAccess() {
                // Already allowed: nothing to ask.
            } else if defaults.bool(forKey: Self.inputMonitoringAskedKey) {
                openSettings(kind)
            } else {
                defaults.set(true, forKey: Self.inputMonitoringAskedKey)
                _ = CGRequestListenEventAccess()
            }
            refresh()
            MecheyService.shared.refreshPermission()
        }
    }

    public func openSettings(_ kind: Kind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// Whether the app an Automation row controls is installed, so it can be opened.
    public func canLaunchAutomationTarget(_ kind: Kind) -> Bool {
        guard let bundleID = kind.automationBundleID else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Opens Music or Spotify in the background: macOS can only be asked about
    /// Automation while the target app is running.
    public func launchAutomationTarget(_ kind: Kind) {
        guard let bundleID = kind.automationBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in PermissionService.shared.refresh() }
        }
    }

    /// Quits and opens a fresh copy, which is the only way a new Screen
    /// Recording grant takes effect. The new copy waits for this one to exit,
    /// so it can claim the global shortcuts.
    public func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$0\"",
            Bundle.main.bundleURL.path,
        ]
        do { try process.run() } catch { return }
        NSApp.terminate(nil)
    }

    /// Clears a grant that no longer matches this build (every ad-hoc signed
    /// rebuild changes the code hash, so the old switch stays on but doesn't apply).
    /// AppleEvents is one TCC service, so resetting either automation row
    /// clears Tama's Automation grants for every app.
    /// With `thenRequest`, asks again once the reset lands, so a stale grant
    /// becomes a fresh prompt in one click.
    public func reset(_ kind: Kind, thenRequest: Bool = false) {
        guard let service = kind.tccService, let bundleID = Bundle.main.bundleIdentifier else { return }
        if kind == .inputMonitoring {
            UserDefaults.standard.removeObject(forKey: Self.inputMonitoringAskedKey)
        }
        if kind == .screenRecording {
            UserDefaults.standard.removeObject(forKey: Self.screenRecordingAskedKey)
            screenRecordingNeedsRelaunch = false
        }
        // A filtering event tap whose grant is pulled out from under it stalls
        // every scroll or key event in the session until Tama quits, so the
        // taps come down first and go back up once the reset has landed.
        let releasesTaps = kind == .accessibility || kind == .inputMonitoring
        if releasesTaps {
            LiquidMouseService.shared.shutdown()
            MediaKeyMonitor.shared.releaseTap()
            MecheyService.shared.shutdown()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.terminationHandler = { _ in
            Task { @MainActor in
                if releasesTaps {
                    LiquidMouseService.shared.refreshPermission()
                    MediaKeyMonitor.shared.syncInterception()
                    MecheyService.shared.refreshPermission()
                }
                PermissionService.shared.refresh()
                if thenRequest { PermissionService.shared.request(kind) }
            }
        }
        try? process.run()
    }

    // MARK: Status readers

    private static var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func eventKitStatus(_ type: EKEntityType) -> Status {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    nonisolated static func automationStatus(for bundleID: String, ask: Bool) -> Status {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .unavailable }
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .unavailable
        }
    }
}
