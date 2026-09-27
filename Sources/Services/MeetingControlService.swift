import AppKit
import Combine
import CoreAudio
import CoreMediaIO

/// Settings › Meetings › when media pauses.
public enum MeetingPauseTrigger: String, CaseIterable, Identifiable, Sendable {
    /// As soon as a call is detected; resumes when it ends.
    case callStarts
    /// Only while your mic is live (unmuted) in a call; muting resumes it.
    case micUnmuted

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .callStarts: "When a meeting starts"
        case .micUnmuted: "When the mic is unmuted"
        }
    }
}

/// Where Meetings stands: nothing to watch, a meeting app open, or a call.
public enum MeetingCallState: Equatable, Sendable {
    /// "Sleeping until a supported meeting app launches."
    case sleeping
    /// "Watching for meetings…"
    case watching
    /// A supported app has the microphone.
    case inCall(appID: String, since: Date)

    public var isInCall: Bool { if case .inCall = self { true } else { false } }
}

/// A meeting app and the keyboard shortcuts it answers to.
public struct MeetingApp: Identifiable, Equatable, Sendable {
    public struct Shortcut: Equatable, Sendable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    public let id: String
    public let name: String
    /// Bundle IDs the app ships under; empty for Google Meet, which lives in a browser tab.
    let bundleIDs: [String]
    let mic: Shortcut?
    let camera: Shortcut?
    let share: Shortcut?
    let leave: Shortcut?

    public var isBrowser: Bool { bundleIDs.isEmpty }

    private static let cmdShift: CGEventFlags = [.maskCommand, .maskShift]

    // Virtual key codes (ANSI layout).
    private enum Key {
        static let a: CGKeyCode = 0, s: CGKeyCode = 1, d: CGKeyCode = 2, h: CGKeyCode = 4
        static let v: CGKeyCode = 9, w: CGKeyCode = 13, e: CGKeyCode = 14, o: CGKeyCode = 31
        static let m: CGKeyCode = 46, space: CGKeyCode = 49
    }

    public static let all: [MeetingApp] = [
        MeetingApp(id: "zoom", name: "Zoom", bundleIDs: ["us.zoom.xos"],
                   mic: .init(keyCode: Key.a, flags: cmdShift), camera: .init(keyCode: Key.v, flags: cmdShift),
                   share: .init(keyCode: Key.s, flags: cmdShift), leave: .init(keyCode: Key.w, flags: .maskCommand)),
        MeetingApp(id: "teams", name: "Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
                   mic: .init(keyCode: Key.m, flags: cmdShift), camera: .init(keyCode: Key.o, flags: cmdShift),
                   share: .init(keyCode: Key.e, flags: cmdShift), leave: .init(keyCode: Key.h, flags: cmdShift)),
        MeetingApp(id: "webex", name: "Webex", bundleIDs: ["Cisco-Systems.Spark"],
                   mic: .init(keyCode: Key.m, flags: cmdShift), camera: .init(keyCode: Key.v, flags: cmdShift),
                   share: .init(keyCode: Key.d, flags: cmdShift), leave: nil),
        MeetingApp(id: "slack", name: "Slack Huddle", bundleIDs: ["com.tinyspeck.slackmacgap"],
                   mic: .init(keyCode: Key.space, flags: cmdShift), camera: .init(keyCode: Key.v, flags: cmdShift),
                   share: nil, leave: .init(keyCode: Key.h, flags: cmdShift)),
        // WhatsApp and FaceTime have no documented call shortcuts: camera and
        // hang up go through their menus (Accessibility), mute is system-wide.
        MeetingApp(id: "whatsapp", name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"],
                   mic: nil, camera: nil, share: nil, leave: nil),
        MeetingApp(id: "facetime", name: "FaceTime", bundleIDs: ["com.apple.FaceTime"],
                   mic: nil, camera: nil, share: nil, leave: nil),
        MeetingApp(id: "meet", name: "Google Meet", bundleIDs: [],
                   mic: .init(keyCode: Key.d, flags: .maskCommand), camera: .init(keyCode: Key.e, flags: .maskCommand),
                   share: nil, leave: nil),
    ]

    /// Menu items that end a call, tried in order when there is no shortcut.
    static let leaveMenuTitles = ["Leave Meeting", "End Meeting", "Leave Call", "End Call", "Hang Up", "Leave", "End"]
    static let cameraMenuTitles = ["Turn Off Camera", "Turn On Camera", "Stop Video", "Start Video",
                                   "Camera Off", "Camera On", "Turn Camera Off", "Turn Camera On", "Video Off", "Video On"]

    /// The meeting app a process using the microphone belongs to. Helpers
    /// (Chrome's, Teams' web view) share their app's bundle ID prefix;
    /// FaceTime's audio runs in avconferenced, and browsers mean Google Meet.
    static func owner(ofAudioProcess bundleID: String, running: Set<String>) -> MeetingApp? {
        if bundleID == "com.apple.avconferenced", running.contains("com.apple.FaceTime") {
            return all.first { $0.id == "facetime" }
        }
        if let app = all.first(where: { app in app.bundleIDs.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") } }) {
            return app
        }
        let browsers = ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
                        "com.apple.Safari", "com.apple.WebKit", "org.mozilla.firefox", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
        if browsers.contains(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") }) {
            return all.first { $0.id == "meet" }
        }
        return nil
    }
}

/// Meetings: mute the microphone for every app at once, and send camera,
/// screen-share and leave shortcuts to the meeting app without switching to it
/// by hand. The mic is muted at the system level, so it works in any call even
/// when the app has no shortcut; the other controls need Accessibility.
@MainActor
public final class MeetingControlService: ObservableObject {
    public static let shared = MeetingControlService()

    public static let targetKey = "meetingTarget"

    @Published public private(set) var isMicMuted = false
    /// Some app is recording from the default input right now: a call is live.
    @Published public private(set) var isMicInUse = false
    @Published public private(set) var inputName = ""
    /// Installed meeting apps that are running, plus Google Meet (always offered).
    @Published public private(set) var available: [MeetingApp] = []
    @Published public var targetID: String {
        didSet { UserDefaults.standard.set(targetID, forKey: Self.targetKey) }
    }
    @Published public private(set) var callState: MeetingCallState = .sleeping
    /// Some camera is streaming (any app); nil when it can't be read.
    @Published public private(set) var isCameraOn: Bool?
    /// Media Tama paused for this call, to resume afterwards.
    private var pausedMedia = false
    private var callCandidate: (appID: String, since: Date)?
    private var callEndWork: DispatchWorkItem?
    private var callStartWork: DispatchWorkItem?
    private var cameraTimer: Timer?
    private var processListObserved = false

    private var inputListener: AudioObjectPropertyListenerBlock?
    private var watchedInput = AudioObjectID(kAudioObjectUnknown)
    private var cancellables = Set<AnyCancellable>()
    /// Volume to put back when the device can only be muted by turning it down.
    private var savedVolume: Float32?
    private var started = false

    private init() {
        targetID = UserDefaults.standard.string(forKey: Self.targetKey) ?? "zoom"
    }

    /// Re-reads the chosen meeting app after Reset to Defaults or Import Settings.
    public func reloadFromDefaults() {
        targetID = UserDefaults.standard.string(forKey: Self.targetKey) ?? "zoom"
    }

    public var target: MeetingApp? {
        available.first(where: { $0.id == targetID }) ?? available.first
    }

    public func start() {
        guard !started else { return }
        started = true
        // CoreAudio says when the default input, its mute or its use changes;
        // polling for that woke Tama every 1.5 s for nothing.
        var defaultInput = Self.address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInput, DispatchQueue.main) { _, _ in
            MainActor.assumeIsolated { MeetingControlService.shared.refresh() }
        }
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: center.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { _ in
                MeetingControlService.shared.refreshApps()
                MeetingControlService.shared.evaluateCall()
            }
            .store(in: &cancellables)
        refreshApps()
        observeProcessList()
        evaluateCall()
    }

    /// macOS 14.2+: CoreAudio says which processes record, so a call is
    /// told apart from Voice Memos or dictation.
    private func observeProcessList() {
        guard #available(macOS 14.2, *), !processListObserved else { return }
        processListObserved = true
        var address = Self.address(kAudioHardwarePropertyProcessObjectList, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in
            MainActor.assumeIsolated { MeetingControlService.shared.evaluateCall() }
        }
    }

    private var isDropletEnabled: Bool {
        AppState.shared.droplets.first(where: { $0.id == "meetings" })?.isEnabled ?? false
    }

    public func refresh() {
        guard let device = Self.defaultInput() else { return }
        watchInput(device)
        let muted = Self.isMuted(device) || (savedVolume != nil && (Self.volume(device) ?? 1) == 0)
        let inUse = Self.isRunningSomewhere(device)
        let name = Self.name(of: device)
        if muted != isMicMuted {
            isMicMuted = muted
            // Muted from the app or a headset button: the call HUD and the
            // "pause while unmuted" rule follow it too.
            if callState.isInCall {
                updatePauseForMic()
                refreshCallActivity()
            }
        }
        if inUse != isMicInUse { isMicInUse = inUse }
        if name != inputName { inputName = name }
        updateActivity()
        evaluateCall()
    }

    public func refreshApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let apps = MeetingApp.all.filter { $0.isBrowser || !running.isDisjoint(with: $0.bundleIDs) }
        if apps != available { available = apps }
    }

    // MARK: Mic

    public func toggleMic() {
        setMicMuted(!isMicMuted)
    }

    public func setMicMuted(_ muted: Bool) {
        guard let device = Self.defaultInput() else {
            AppState.shared.showNotification(appName: "Meetings", title: "No microphone", message: "There's no input device to mute.")
            return
        }
        if Self.setMute(device, muted) {
            savedVolume = nil
        } else if muted {
            // No mute switch on this device: turn it all the way down instead.
            if savedVolume == nil { savedVolume = Self.volume(device) ?? 1 }
            _ = Self.setVolume(device, 0)
        } else {
            _ = Self.setVolume(device, savedVolume ?? 1)
            savedVolume = nil
        }
        DroppyAudio.playTick()
        refresh()
        updatePauseForMic()
        refreshCallActivity()
    }

    /// The notch says so while a call is listening and the mic is off, since
    /// the app's own button may still show it as on. During a detected call
    /// the call HUD shows the mute instead.
    private func updateActivity() {
        if isDropletEnabled, isMicMuted, isMicInUse, !(callState.isInCall && AppState.shared.meetingCallHUD) {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "meetingMic", icon: "mic.slash.fill", tint: DS.Palette.danger,
                trailing: .text("Muted"), priority: .ambient, label: "Microphone muted"
            ))
        } else {
            LiveActivityCenter.shared.end("meetingMic")
        }
    }

    // MARK: Call state machine

    /// The meeting app recording from the microphone right now, if any.
    private func appUsingMicrophone() -> MeetingApp? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if #available(macOS 14.2, *) {
            let own = getpid()
            for object in Self.objectList(kAudioHardwarePropertyProcessObjectList) {
                let pid: pid_t = Self.value(object, kAudioProcessPropertyPID) ?? -1
                guard pid > 0, pid != own,
                      (Self.value(object, kAudioProcessPropertyIsRunningInput) as UInt32? ?? 0) != 0 else { continue }
                let bundleID = Self.string(object, kAudioProcessPropertyBundleID)
                    ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                if let app = MeetingApp.owner(ofAudioProcess: bundleID, running: running) { return app }
            }
            return nil
        }
        // Older macOS: the mic is busy and a meeting app is open.
        guard isMicInUse else { return nil }
        return MeetingApp.all.first { !$0.isBrowser && !running.isDisjoint(with: $0.bundleIDs) }
    }

    /// Moves between sleeping, watching and in a call. A call starts after
    /// the mic has been held for a moment and ends a few seconds after it's
    /// let go, so a blip (a sound check, switching devices) doesn't flicker.
    func evaluateCall() {
        guard started else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let nativeOpen = MeetingApp.all.contains { !$0.isBrowser && !running.isDisjoint(with: $0.bundleIDs) }
        let user = isDropletEnabled ? appUsingMicrophone() : nil

        if let user {
            callEndWork?.cancel()
            callEndWork = nil
            if case let .inCall(appID, since) = callState {
                if appID != user.id { setCallState(.inCall(appID: user.id, since: since)) }
                updatePauseForMic()
                return
            }
            guard callStartWork == nil else { return }
            let work = DispatchWorkItem {
                MainActor.assumeIsolated {
                    let service = MeetingControlService.shared
                    service.callStartWork = nil
                    guard let still = service.isDropletEnabled ? service.appUsingMicrophone() : nil else { return }
                    service.beginCall(still)
                }
            }
            callStartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            callStartWork?.cancel()
            callStartWork = nil
            if callState.isInCall {
                guard callEndWork == nil else { return }
                let work = DispatchWorkItem {
                    MainActor.assumeIsolated {
                        let service = MeetingControlService.shared
                        service.callEndWork = nil
                        guard (service.isDropletEnabled ? service.appUsingMicrophone() : nil) == nil else { return }
                        service.endCall()
                    }
                }
                callEndWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            } else {
                let next: MeetingCallState = nativeOpen ? .watching : .sleeping
                if next != callState { setCallState(next) }
            }
        }
    }

    private func setCallState(_ next: MeetingCallState) {
        callState = next
        refreshCallActivity()
        updateActivity()
    }

    private func beginCall(_ app: MeetingApp) {
        // The controls follow the app you're actually in a call with.
        if available.contains(where: { $0.id == app.id }) { targetID = app.id }
        setCallState(.inCall(appID: app.id, since: Date()))
        let state = AppState.shared
        if state.meetingPauseMedia, state.meetingPauseTrigger == .callStarts { pauseMediaForMeeting() }
        updatePauseForMic()
        startCameraWatch()
    }

    private func endCall() {
        setCallState(.watching)
        MicLevelMeter.shared.stop()
        stopCameraWatch()
        resumeMediaAfterMeeting()
        evaluateCall()
    }

    /// The call HUD in the resting notch: green phone, elapsed time, mic bars.
    func refreshCallActivity() {
        guard case let .inCall(appID, since) = callState, AppState.shared.meetingCallHUD, isDropletEnabled else {
            LiveActivityCenter.shared.end("meetingCall")
            MicLevelMeter.shared.stop()
            return
        }
        if AppState.shared.meetingMicLevel, !isMicMuted {
            if #available(macOS 14.2, *) { MicLevelMeter.shared.start() }
        } else {
            MicLevelMeter.shared.stop()
        }
        let name = MeetingApp.all.first { $0.id == appID }?.name ?? "Call"
        LiveActivityCenter.shared.post(LiveActivity(
            id: "meetingCall", icon: "phone.fill", tint: DS.Palette.success,
            trailing: AppState.shared.meetingMicLevel ? .micLevel(muted: isMicMuted) : (isMicMuted ? .text("Muted") : .none),
            priority: .urgent,
            label: "In a \(name) call\(isMicMuted ? ", microphone muted" : "")",
            detail: .elapsed(since: since)
        ))
    }

    // MARK: Media around calls

    private func updatePauseForMic() {
        let state = AppState.shared
        guard callState.isInCall, state.meetingPauseMedia, state.meetingPauseTrigger == .micUnmuted else { return }
        if isMicMuted {
            resumeMediaAfterMeeting()
        } else {
            pauseMediaForMeeting()
        }
        refreshCallActivity()
    }

    private func pauseMediaForMeeting() {
        let media = MediaService.shared
        guard media.currentTrack.isPlaying, !pausedMedia else { return }
        media.togglePlayPause()
        pausedMedia = AppState.shared.meetingResumeMedia
        AppState.shared.showNotification(appName: "Meetings", title: "Media paused for meeting",
                                         message: AppState.shared.meetingResumeMedia ? "It resumes when the call ends." : media.currentTrack.title,
                                         icon: "pause.fill", duration: 2.5)
    }

    private func resumeMediaAfterMeeting() {
        guard pausedMedia else { return }
        pausedMedia = false
        let media = MediaService.shared
        if media.currentTrack.hasTrack, !media.currentTrack.isPlaying { media.togglePlayPause() }
    }

    // MARK: Camera

    /// Whether any camera is streaming, from CoreMediaIO; read every couple of
    /// seconds during a call only.
    private func startCameraWatch() {
        refreshCamera()
        cameraTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MeetingControlService.shared.refreshCamera() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        cameraTimer = timer
    }

    private func stopCameraWatch() {
        cameraTimer?.invalidate()
        cameraTimer = nil
        isCameraOn = nil
    }

    private func refreshCamera() {
        let on = Self.isAnyCameraRunning()
        if on != isCameraOn { isCameraOn = on }
    }

    nonisolated static func isAnyCameraRunning() -> Bool? {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return nil }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return nil }
        var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        for device in devices {
            var value: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &value) == 0, value != 0 {
                return true
            }
        }
        return false
    }

    // MARK: App shortcuts

    public enum Control { case camera, share, leave, appMic }

    public func send(_ control: Control) {
        guard let app = target else { return }
        let shortcut: MeetingApp.Shortcut? = switch control {
        case .camera: app.camera
        case .share: app.share
        case .leave: app.leave
        case .appMic: app.mic
        }
        let menuTitles: [String] = switch control {
        case .leave: MeetingApp.leaveMenuTitles
        case .camera: MeetingApp.cameraMenuTitles
        default: []
        }
        guard shortcut != nil || (!menuTitles.isEmpty && !app.isBrowser) else { return }
        guard AXIsProcessTrusted() else {
            PermissionService.shared.request(.accessibility)
            AppState.shared.showNotification(appName: "Meetings", title: "\(PermissionService.accessibilityName) needed",
                                             message: "Allow Tama to send shortcuts to \(app.name).",
                                             actionTitle: "Open Settings") {
                PermissionService.shared.openSettings(.accessibility)
            }
            return
        }
        DroppyAudio.playTick()
        let previous = NSWorkspace.shared.frontmostApplication
        if app.isBrowser {
            guard let shortcut else { return }
            focusMeetTab { found in
                guard found else {
                    AppState.shared.showNotification(appName: "Meetings", title: "No Google Meet tab",
                                                     message: "Open the call in Chrome, Arc, Edge, Brave or Safari.")
                    return
                }
                Self.press(shortcut, thenReturnTo: previous)
            }
        } else {
            guard let running = NSWorkspace.shared.runningApplications.first(where: {
                app.bundleIDs.contains($0.bundleIdentifier ?? "")
            }) else { return }
            if let shortcut {
                running.activate()
                Self.press(shortcut, thenReturnTo: previous)
            } else if !MenuPresser.press(in: running.processIdentifier, titles: menuTitles) {
                AppState.shared.showNotification(
                    appName: "Meetings", title: control == .leave ? "Couldn't hang up" : "Couldn't switch the camera",
                    message: "\(app.name) has no menu item for it right now. Use the button in its call window.")
            }
        }
    }

    /// Hang up / leave the call in whichever app has it.
    public func hangUp() { send(.leave) }

    /// The app needs a moment to come forward before it takes the keystroke,
    /// then the app you were in gets focus back.
    private static func press(_ shortcut: MeetingApp.Shortcut, thenReturnTo previous: NSRunningApplication?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
                event?.flags = shortcut.flags
                event?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let previous, previous.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                previous.activate()
            }
        }
    }

    /// Brings the first Google Meet call tab to the front of its browser.
    private func focusMeetTab(completion: @escaping @MainActor (Bool) -> Void) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let chromium = [("com.google.Chrome", "Google Chrome"), ("company.thebrowser.Browser", "Arc"),
                        ("com.microsoft.edgemac", "Microsoft Edge"), ("com.brave.Browser", "Brave Browser")]
            .filter { running.contains($0.0) }.map(\.1)
        let safari = running.contains("com.apple.Safari")
        DispatchQueue.global(qos: .userInitiated).async {
            var found = false
            for browser in chromium where !found {
                let source = """
                tell application "\(browser)"
                    repeat with w in windows
                        set i to 0
                        repeat with t in tabs of w
                            set i to i + 1
                            if URL of t contains "meet.google.com/" and URL of t does not end with "meet.google.com/" then
                                set active tab index of w to i
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end tell
                return false
                """
                found = Self.runBool(source)
            }
            if !found, safari {
                let source = """
                tell application "Safari"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "meet.google.com/" then
                                set current tab of w to t
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end tell
                return false
                """
                found = Self.runBool(source)
            }
            let result = found
            DispatchQueue.main.async { completion(result) }
        }
    }

    nonisolated private static func runBool(_ source: String) -> Bool {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).booleanValue ?? false
    }

    // MARK: CoreAudio

    private static let watchedInputProperties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput),
        (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput),
        (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal),
        (kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal),
    ]

    /// Moves the property listeners to the current default input.
    private func watchInput(_ device: AudioObjectID) {
        guard device != watchedInput else { return }
        if let inputListener, watchedInput != kAudioObjectUnknown {
            for (selector, scope) in Self.watchedInputProperties {
                var address = Self.address(selector, scope: scope)
                AudioObjectRemovePropertyListenerBlock(watchedInput, &address, DispatchQueue.main, inputListener)
            }
        }
        watchedInput = device
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { MeetingControlService.shared.refresh() }
        }
        inputListener = block
        for (selector, scope) in Self.watchedInputProperties {
            var address = Self.address(selector, scope: scope)
            if AudioObjectHasProperty(device, &address) {
                AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
            }
        }
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    private static func defaultInput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func setMute(_ device: AudioObjectID, _ muted: Bool) -> Bool {
        var address = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func volume(_ device: AudioObjectID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setVolume(_ device: AudioObjectID, _ volume: Float32) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    private static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func name(of device: AudioObjectID) -> String {
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "Microphone" }
        return value as String
    }
}

/// Clicks a menu item by title through Accessibility, for apps whose call
/// controls have no keyboard shortcut (FaceTime, WhatsApp).
@MainActor
enum MenuPresser {
    static func press(in pid: pid_t, titles: [String]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let bar = menuBar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        var items: [(AXUIElement, String)] = []
        collect(bar as! AXUIElement, depth: 0, into: &items)
        let wanted = titles.map { $0.lowercased() }
        for title in wanted {
            if let match = items.first(where: { $0.1.lowercased() == title }) {
                return AXUIElementPerformAction(match.0, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    /// Enabled menu items (not the menu titles themselves), four levels deep at most.
    private static func collect(_ element: AXUIElement, depth: Int, into items: inout [(AXUIElement, String)]) {
        guard depth < 4, items.count < 800 else { return }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for child in list {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXMenuItemRole as String) {
                var title: CFTypeRef?
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled)
                if let text = title as? String, !text.isEmpty, (enabled as? Bool) ?? true {
                    items.append((child, text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "…", with: "")))
                }
            }
            collect(child, depth: depth + 1, into: &items)
        }
    }
}
