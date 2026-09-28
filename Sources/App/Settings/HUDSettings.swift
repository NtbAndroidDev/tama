import SwiftUI

/// Settings › HUDs, Sound and Display: level HUDs, system HUDs, media keys and live activities.
@MainActor
public final class HUDSettings: SettingsStore {
    public static let shared = HUDSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "showVolumeHUD", "scrollToChangeVolume", "replaceSystemVolumeHUD", "hudDuration",
        "hudMeterStyle", "hudShowPercentage", "hudHideLabel", "hudAnimation", "hudLeading",
        "hudMeterCustomColor", "brightnessHUDDuration", "brightnessHUDMeterStyle",
        "brightnessHUDShowPercentage", "brightnessHUDHideLabel", "brightnessHUDAnimation",
        "brightnessHUDMeterCustomColor", "replaceSystemBrightnessHUD", "scrollToChangeBrightness",
        "showBrightnessHUD", "showVPNStatus", "collapsedHUDScope", "finishedHUDLinger",
        "keepHUDWhileHovered", "compactHUDPriority", "showKeyboardBrightnessHUD",
        "showFileTrayHUD", "showCapsLockHUD", "showRecordingHUD", "showFocusHUD", "showOfflineHUD",
        "volumeKeySound", "desktopVolumeSlider", "desktopBrightnessSlider", "mediaKeyTarget",
        "useBetterDisplay", "automaticBrightnessHUD", "keyboardBrightnessKeys", "playbackKeysMode",
        "showMeetingCountdown", "showBatteryAlerts", "alwaysUseBuiltInSpeakers",
        "showDeviceAlerts", "showDownloadActivity", "multiLiveActivities"
    ]

    /// Show the volume HUD in the notch when scrolling over it.
    @AppStorage("showVolumeHUD") public var showVolumeHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// Two-finger scroll on the resting notch changes the volume.
    @AppStorage("scrollToChangeVolume") public var scrollToChangeVolume: Bool = true
    /// The volume keys are handled by Tama so only the notch HUD shows, not
    /// the macOS one. Needs Accessibility; without it both appear.
    @AppStorage("replaceSystemVolumeHUD") public var replaceSystemVolumeHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// How the volume HUD looks and behaves (Settings › Sound).
    @AppStorage("hudDuration") public var hudDuration: Double = 1.5
    @AppStorage("hudMeterStyle") public var hudMeterStyle: HUDMeterStyle = .accent
    @AppStorage("hudShowPercentage") public var hudShowPercentage: Bool = true
    @AppStorage("hudHideLabel") public var hudHideLabel: Bool = false
    @AppStorage("hudAnimation") public var hudAnimation: HUDAnimation = .fast
    @AppStorage("hudLeading") public var hudLeading: HUDLeading = .symbol
    /// Meter colours for `HUDMeterStyle.custom`, per HUD: a `TapePalette` id or "#RRGGBB".
    @AppStorage("hudMeterCustomColor") public var hudMeterCustomColor: String = ""
    /// The brightness HUD's own look (Settings › Display).
    @AppStorage("brightnessHUDDuration") public var brightnessHUDDuration: Double = 1.5
    @AppStorage("brightnessHUDMeterStyle") public var brightnessHUDMeterStyle: HUDMeterStyle = .accent
    @AppStorage("brightnessHUDShowPercentage") public var brightnessHUDShowPercentage: Bool = true
    @AppStorage("brightnessHUDHideLabel") public var brightnessHUDHideLabel: Bool = false
    @AppStorage("brightnessHUDAnimation") public var brightnessHUDAnimation: HUDAnimation = .fast
    @AppStorage("brightnessHUDMeterCustomColor") public var brightnessHUDMeterCustomColor: String = ""
    /// The brightness keys are handled by Tama so the macOS HUD stays away.
    @AppStorage("replaceSystemBrightnessHUD") public var replaceSystemBrightnessHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// ⌥-scroll on the resting notch changes the built-in display's brightness.
    @AppStorage("scrollToChangeBrightness") public var scrollToChangeBrightness: Bool = true
    /// Brightness keys show a level readout in the notch; ⌥-scroll changes it.
    @AppStorage("showBrightnessHUD") public var showBrightnessHUD: Bool = true {
        didSet {
            MediaKeyMonitor.shared.syncInterception()
            BrightnessService.shared.syncAutoWatch()
        }
    }
    /// A connected VPN sits in the notch wings with its session time.
    @AppStorage("showVPNStatus") public var showVPNStatus: Bool = true {
        didSet { VPNService.shared.apply(enabled: showVPNStatus) }
    }
    @AppStorage("collapsedHUDScope") public var collapsedHUDScope: HUDScope = .underPointer
    /// How long a finished, transient HUD (charger, device, Caps Lock…) stays.
    @AppStorage("finishedHUDLinger") public var finishedHUDLinger: Double = 3
    /// A level HUD under the pointer stays until the pointer leaves.
    @AppStorage("keepHUDWhileHovered") public var keepHUDWhileHovered: Bool = true
    @AppStorage("compactHUDPriority") public var compactHUDPriority: CompactHUDPriority = .activitiesFirst
    @AppStorage("showKeyboardBrightnessHUD") public var showKeyboardBrightnessHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    @AppStorage("showFileTrayHUD") public var showFileTrayHUD: Bool = true
    @AppStorage("showCapsLockHUD") public var showCapsLockHUD: Bool = true {
        didSet { CapsLockService.shared.sync() }
    }
    @AppStorage("showRecordingHUD") public var showRecordingHUD: Bool = true {
        didSet { RecordingIndicatorService.shared.sync() }
    }
    @AppStorage("showFocusHUD") public var showFocusHUD: Bool = true {
        didSet { FocusModeService.shared.sync() }
    }
    @AppStorage("showOfflineHUD") public var showOfflineHUD: Bool = true {
        didSet { ConnectivityService.shared.sync() }
    }
    /// The feedback pop when the volume keys change the level (⇧ flips it).
    @AppStorage("volumeKeySound") public var volumeKeySound: Bool = false
    @AppStorage("desktopVolumeSlider") public var desktopVolumeSlider: Bool = false {
        didSet { DesktopSliderController.shared.sync() }
    }
    @AppStorage("desktopBrightnessSlider") public var desktopBrightnessSlider: Bool = false {
        didSet { DesktopSliderController.shared.sync() }
    }
    @AppStorage("mediaKeyTarget") public var mediaKeyTarget: MediaKeyTarget = .underPointer
    /// External displays' brightness goes through BetterDisplay's HTTP API when it's running.
    @AppStorage("useBetterDisplay") public var useBetterDisplay: Bool = true {
        didSet { BetterDisplayService.shared.refresh() }
    }
    /// The brightness HUD also shows when the level changes on its own (ambient light, Control Center).
    /// Off by default: with auto-brightness on, the panel drifts all day and the HUD kept popping up.
    @AppStorage("automaticBrightnessHUD") public var automaticBrightnessHUD: Bool = false {
        didSet { BrightnessService.shared.syncAutoWatch() }
    }
    /// Tama takes the keyboard backlight keys and steps the backlight itself.
    @AppStorage("keyboardBrightnessKeys") public var keyboardBrightnessKeys: Bool = false {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// Who answers play/pause, next and previous (Media keys › Playback keys).
    @AppStorage("playbackKeysMode") public var playbackKeysMode: PlaybackKeysMode = .system {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// Live activities in the resting notch.
    @AppStorage("showMeetingCountdown") public var showMeetingCountdown: Bool = true {
        didSet { MeetingService.shared.tick() }
    }
    @AppStorage("showBatteryAlerts") public var showBatteryAlerts: Bool = true {
        didSet { if !showBatteryAlerts { LiveActivityCenter.shared.end("battery") } }
    }
    /// Settings › HUDs › Media Controls › Always use built-in speakers: a
    /// device that just connected doesn't get to take the sound with it.
    @AppStorage("alwaysUseBuiltInSpeakers") public var alwaysUseBuiltInSpeakers: Bool = false
    @AppStorage("showDeviceAlerts") public var showDeviceAlerts: Bool = true {
        didSet { if !showDeviceAlerts { LiveActivityCenter.shared.end("audioDevice") } }
    }
    /// Off by default: watching ~/Downloads makes macOS ask for folder access.
    @AppStorage("showDownloadActivity") public var showDownloadActivity: Bool = false {
        didSet { DownloadWatcher.shared.apply(enabled: showDownloadActivity) }
    }
    /// A second concurrent activity gets its own round pill beside the notch.
    @AppStorage("multiLiveActivities") public var multiLiveActivities: Bool = true

    private init() { super.init(keys: Self.keys) }
}
