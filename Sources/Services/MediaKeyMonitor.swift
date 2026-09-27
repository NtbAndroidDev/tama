import AppKit
import ApplicationServices
import OSLog

/// Watches the volume and brightness keys so their level shows in the notch.
/// Volume changes from anywhere else (Control Center, other apps) arrive
/// through AudioOutputService's CoreAudio listener instead — the keys matter
/// for presses that don't change the level, like volume up at 100%.
///
/// With "Hide the macOS volume / brightness HUD" on and Accessibility granted,
/// those keys are taken with an event tap before macOS sees them: Tama
/// changes the level itself (in the same 1/16 steps, ⌥⇧ for quarter steps) and
/// only the notch HUD appears. Outputs without a software volume (HDMI, some
/// USB) and displays Tama can't dim are left to macOS, which shows that they
/// can't be changed. Without Accessibility it falls back to listening, and
/// both HUDs show.
///
/// Media keys arrive as `.systemDefined` events (subtype 8). The global monitor
/// may stay silent without Accessibility access; the CoreAudio listener still
/// covers volume, so nothing breaks, only the brightness HUD goes quiet.
@MainActor
public final class MediaKeyMonitor: ObservableObject {
    public static let shared = MediaKeyMonitor()
    private static let log = Logger(subsystem: "app.tama.macos", category: "MediaKeys")

    /// Whether the event tap is in place (it serves volume, brightness and playback keys).
    @Published public private(set) var isIntercepting = false

    /// The keys of each kind that are taken from macOS right now.
    public var interceptsVolume: Bool {
        isIntercepting && AppState.shared.showVolumeHUD && AppState.shared.replaceSystemVolumeHUD
    }
    public var interceptsBrightness: Bool {
        isIntercepting && AppState.shared.showBrightnessHUD && AppState.shared.replaceSystemBrightnessHUD
    }
    /// Settings › HUDs › Keyboard brightness keys: the backlight keys step it here.
    public var interceptsKeyboard: Bool {
        isIntercepting && AppState.shared.keyboardBrightnessKeys && KeyboardBacklightService.shared.isAvailable
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    /// Retries the tap until Accessibility is granted. macOS announces changes
    /// to the list (and the user comes back to Tama after granting), so those
    /// retry at once; the slow poll is a backstop for a missed announcement.
    private var permissionPoll: Timer?
    private var trustObservers: (distributed: NSObjectProtocol, local: NSObjectProtocol)?
    /// Playback keys whose press Tama took, so their key-up is taken too.
    private var takenPlaybackKeys: Set<Int> = []

    // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
    private enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
        /// Apple keyboards send these for ⏩ and ⏪ (F9 / F7).
        case fast = 19
        case rewind = 20
        case illuminationUp = 21
        case illuminationDown = 22
        case illuminationToggle = 23
    }

    /// One aux-control key event, parsed off the event so it can cross actors.
    struct KeyEvent: Sendable {
        let code: Int
        let isDown: Bool
        let isRepeat: Bool
        let isFine: Bool
        let invertsFeedback: Bool
    }

    /// macOS's volume keys move in sixteenths; ⌥⇧ moves in quarters of those.
    nonisolated static let coarseStep = 1.0 / 16
    nonisolated static let fineStep = 1.0 / 64

    private init() {}

    public func start() {
        guard globalMonitor == nil else { return }
        // Creates the CoreAudio volume / mute listener.
        _ = AudioOutputService.shared
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            let data = Self.keyEvent(event)
            MainActor.assumeIsolated { MediaKeyMonitor.shared.handle(data) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            let data = Self.keyEvent(event)
            MainActor.assumeIsolated { MediaKeyMonitor.shared.handle(data) }
            return event
        }
        syncInterception()
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        removeTap()
    }

    // MARK: Interception

    /// Installs or removes the event tap to match the settings and permission.
    public func syncInterception() {
        let state = AppState.shared
        let wanted = globalMonitor != nil
            && ((state.showVolumeHUD && state.replaceSystemVolumeHUD)
                || (state.showBrightnessHUD && state.replaceSystemBrightnessHUD)
                || state.keyboardBrightnessKeys
                || state.playbackKeysMode != .system)
        guard wanted else {
            removeTap()
            return
        }
        guard tap == nil else { return }
        let trusted = AXIsProcessTrusted()
        if trusted, installTap() {
            Self.log.notice("Level keys intercepted; macOS HUD hidden")
            stopPermissionWatch()
        } else if permissionPoll == nil {
            Self.log.notice("Volume key tap not installed (Accessibility trusted: \(trusted, privacy: .public)); polling")
            let poll = Timer(timeInterval: 10, repeats: true) { _ in
                MainActor.assumeIsolated { MediaKeyMonitor.shared.syncInterception() }
            }
            poll.tolerance = 2
            RunLoop.main.add(poll, forMode: .common)
            permissionPoll = poll
            let retry: @Sendable (Notification) -> Void = { _ in
                // The list can lag its own announcement by a moment.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { MediaKeyMonitor.shared.syncInterception() }
                }
            }
            trustObservers = (
                DistributedNotificationCenter.default().addObserver(
                    forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main, using: retry),
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: retry)
            )
        }
    }

    private func stopPermissionWatch() {
        permissionPoll?.invalidate()
        permissionPoll = nil
        if let trustObservers {
            DistributedNotificationCenter.default().removeObserver(trustObservers.distributed)
            NotificationCenter.default.removeObserver(trustObservers.local)
        }
        trustObservers = nil
    }

    /// Drops the tap without polling for it back, ahead of a permission reset;
    /// `syncInterception()` reinstalls it once the reset lands.
    public func releaseTap() {
        removeTap()
    }

    private func installTap() -> Bool {
        // NX_SYSDEFINED (14) isn't a CGEventType case, but the mask bit works.
        let mask = CGEventMask(1 << 14)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                // Added to the main run loop, so this runs on the main thread.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { MediaKeyMonitor.shared.reenableTap() }
                    return Unmanaged.passUnretained(event)
                }
                // Keys Tama posts itself (MediaKeys) go on to macOS untouched.
                if event.getIntegerValueField(.eventSourceUserData) == MediaKeys.postedMarker {
                    return Unmanaged.passUnretained(event)
                }
                guard let ns = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
                let data = MediaKeyMonitor.keyEvent(ns)
                let consumed = MainActor.assumeIsolated { MediaKeyMonitor.shared.intercept(data) }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        isIntercepting = true
        return true
    }

    private func removeTap() {
        stopPermissionWatch()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        isIntercepting = false
    }

    /// macOS switches a tap off when a callback runs long or the user revokes
    /// Accessibility; switch it back on, or fall back if permission is gone.
    private func reenableTap() {
        guard let tap else { return }
        if AXIsProcessTrusted() {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            removeTap()
            syncInterception()
        }
    }

    /// True when the event was handled here and must not reach macOS.
    private func intercept(_ data: KeyEvent?) -> Bool {
        guard let data, let key = Key(rawValue: data.code) else { return false }
        // The island is hidden here (a switched-off display, Hide all in
        // fullscreen, Mission Control): macOS shows its own HUD instead.
        let isHidden = AppState.shared.isSurfaceSuppressed(on: nil)
        switch key {
        case .soundUp, .soundDown, .mute:
            guard interceptsVolume, !isHidden else { return false }
            let outputs = AudioOutputService.shared
            // No software volume: let macOS say so with its own HUD.
            guard outputs.canSetVolume else { return false }
            // The key-up is swallowed too, so macOS never sees half a press.
            guard data.isDown else { return true }
            apply(key, to: outputs, fine: data.isFine)
            if !data.isRepeat { playFeedback(inverted: data.invertsFeedback) }
            outputs.presentHUD()
            return true
        case .brightnessUp, .brightnessDown:
            guard interceptsBrightness, !isHidden else { return false }
            let step = data.isFine ? Self.fineStep : Self.coarseStep
            let delta = key == .brightnessUp ? step : -step
            switch brightnessTarget() {
            case let .native(displayID):
                let display = BrightnessService.shared
                guard let level = display.level(on: displayID) else { return false }
                guard data.isDown else { return true }
                let target = Self.steppedVolume(level, by: delta, step: step)
                display.setBrightness(target, on: displayID)
                // The panel fades towards it, so show the target, not a read-back.
                AppState.shared.showHUD(.brightness, value: target)
            case let .betterDisplay(screen):
                guard data.isDown else { return true }
                BetterDisplayService.shared.step(screen, by: delta, step: step)
            case .system:
                // A display Tama can't dim: macOS handles it (and says so).
                return false
            }
            return true
        case .play, .next, .previous, .fast, .rewind:
            // Settings › HUDs › Media keys › Playback keys.
            if !data.isDown {
                return takenPlaybackKeys.remove(data.code) != nil
            }
            if data.isRepeat { return takenPlaybackKeys.contains(data.code) }
            guard AppState.shared.playbackKeysMode != .system else { return false }
            let mapped: MediaKeys.Key = key == .play ? .playPause : (key == .next || key == .fast) ? .next : .previous
            guard MediaService.shared.handlePlaybackKey(mapped) else { return false }
            takenPlaybackKeys.insert(data.code)
            return true
        case .illuminationUp, .illuminationDown, .illuminationToggle:
            guard interceptsKeyboard, !isHidden else { return false }
            guard data.isDown else { return true }
            let backlight = KeyboardBacklightService.shared
            if key == .illuminationToggle {
                // Off, or back to half when it's already off.
                let target = (backlight.level ?? 0) > 0.01 ? 0 : 0.5
                backlight.setBrightness(target)
                if AppState.shared.showKeyboardBrightnessHUD { AppState.shared.showHUD(.keyboard, value: target) }
            } else {
                backlight.step(up: key == .illuminationUp, fine: data.isFine)
            }
            return true
        }
    }

    /// Where the brightness keys go (Settings › HUDs › Media key target).
    enum BrightnessTarget {
        /// A display DisplayServices can dim: the built-in panel or an Apple display.
        case native(CGDirectDisplayID)
        /// An external display dimmed through BetterDisplay's API.
        case betterDisplay(NSScreen)
        /// Nothing Tama can dim: macOS keeps the keys.
        case system
    }

    func brightnessTarget() -> BrightnessTarget {
        let display = BrightnessService.shared
        let builtIn = display.builtInDisplay
        let fallback: BrightnessTarget = display.canSetBrightness(on: builtIn) ? .native(builtIn) : .system
        guard AppState.shared.mediaKeyTarget == .underPointer else { return fallback }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let id = screen.displayID else { return fallback }
        if display.canSetBrightness(on: id) { return .native(id) }
        if BetterDisplayService.shared.routes(screen) { return .betterDisplay(screen) }
        return .system
    }

    private func apply(_ key: Key, to outputs: AudioOutputService, fine: Bool) {
        switch key {
        case .mute:
            outputs.setMuted(!outputs.isMuted)
        case .soundUp, .soundDown:
            let step = fine ? Self.fineStep : Self.coarseStep
            let direction: Double = key == .soundUp ? 1 : -1
            // Like macOS, volume up unmutes; setVolume does that.
            outputs.setVolume(Self.steppedVolume(outputs.volume, by: step * direction, step: step))
        default:
            break
        }
    }

    /// Snaps to the step grid first, so a level set elsewhere (37%) lands on
    /// the same notches the macOS keys use.
    nonisolated static func steppedVolume(_ volume: Double, by delta: Double, step: Double) -> Double {
        let snapped = (volume / step).rounded() * step
        return min(max(snapped + delta, 0), 1)
    }

    /// The volume "pop" (Settings › HUDs › Key sound). Holding ⇧ flips it,
    /// as it does for the macOS keys.
    private func playFeedback(inverted: Bool) {
        guard AppState.shared.volumeKeySound != inverted else { return }
        Self.feedbackSound?.stop()
        Self.feedbackSound?.play()
    }

    private static let feedbackSound: NSSound? = {
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Pop")
    }()

    // MARK: Listening

    /// Parsed aux-control key, or nil for anything else.
    nonisolated static func keyEvent(_ event: NSEvent) -> KeyEvent? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let code = (event.data1 & 0xFFFF_0000) >> 16
        let flags = event.data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        let modifiers = event.modifierFlags
        return KeyEvent(
            code: code,
            isDown: state == 0x0A,
            isRepeat: flags & 0x1 == 1,
            isFine: modifiers.contains(.option) && modifiers.contains(.shift),
            invertsFeedback: modifiers.contains(.shift)
        )
    }

    private func handle(_ data: KeyEvent?) {
        guard let data, data.isDown, let key = Key(rawValue: data.code) else { return }
        switch key {
        case .soundUp, .soundDown, .mute:
            // Taken by the tap: already applied and shown.
            guard !interceptsVolume, AppState.shared.showVolumeHUD else { return }
            // Let CoreAudio apply the change before reading it back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                AudioOutputService.shared.presentHUD()
            }
        case .brightnessUp, .brightnessDown:
            // Taken by the tap it's already shown; left to macOS for a display
            // Tama can't dim, the built-in panel's level would be wrong.
            guard !interceptsBrightness else { return }
            BrightnessService.shared.presentHUD()
        case .illuminationUp, .illuminationDown, .illuminationToggle:
            // Taken by the tap: already applied and shown.
            guard !interceptsKeyboard else { return }
            KeyboardBacklightService.shared.presentHUD()
        case .play, .next, .previous, .fast, .rewind:
            // Routed by the tap, or left to macOS: nothing to show.
            break
        }
    }
}
