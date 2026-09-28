import SwiftUI

/// Settings › Lock Screen: the status row under the clock and the player above the login field.
@MainActor
public final class LockScreenSettings: SettingsStore {
    public static let shared = LockScreenSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "lockScreenEnabled", "lockScreenShowsBattery", "lockScreenShowsHeadphones",
        "lockScreenShowsWeather", "lockScreenShowsNextEvent", "lockScreenShowsPlayer",
        "lockScreenAnimation", "lockScreenSounds", "lockScreenLockSound", "lockScreenUnlockSound",
        "lockScreenVolumeSlider", "lockScreenBrightnessSlider", "lockScreenDuringScreensaver",
        "lockScreenKeepAwake", "lockScreenShowsStatusRow", "lockScreenWidgetStyle",
        "lockScreenWidgetLook", "lockScreenWidgetMaterial", "lockScreenMediaMaterial"
    ]

    @AppStorage("lockScreenEnabled") public var isEnabled: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenShowsBattery") public var showsBattery: Bool = true
    @AppStorage("lockScreenShowsHeadphones") public var showsHeadphones: Bool = true
    /// Weather, air quality and the next sunrise/sunset; asks for Location.
    @AppStorage("lockScreenShowsWeather") public var showsWeather: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenShowsNextEvent") public var showsNextEvent: Bool = true
    @AppStorage("lockScreenShowsPlayer") public var showsPlayer: Bool = true {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Lock/unlock animation: the lock-screen panels fade and scale in and out.
    @AppStorage("lockScreenAnimation") public var animation: Bool = true
    /// Lock & unlock sound, and which sound each one is (see `LockSound`).
    @AppStorage("lockScreenSounds") public var sounds: Bool = false
    @AppStorage("lockScreenLockSound") public var lockSound: String = LockSound.none
    @AppStorage("lockScreenUnlockSound") public var unlockSound: String = LockSound.default
    /// Volume and brightness sliders on the lock screen.
    @AppStorage("lockScreenVolumeSlider") public var volumeSlider: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenBrightnessSlider") public var brightnessSlider: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Keep the panels over the screen saver instead of hiding them under it.
    @AppStorage("lockScreenDuringScreensaver") public var duringScreensaver: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Minutes the display is kept awake while locked (`LockKeepAwake`).
    @AppStorage("lockScreenKeepAwake") public var keepAwake: Int = 0 {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// The status widgets row under the clock.
    @AppStorage("lockScreenShowsStatusRow") public var showsStatusRow: Bool = true {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenWidgetStyle") public var widgetStyle: LockWidgetStyle = .inline
    @AppStorage("lockScreenWidgetLook") public var widgetLook: LockWidgetLook = .dark
    @AppStorage("lockScreenWidgetMaterial") public var widgetMaterial: LockSurfaceMaterial = .regular
    /// Lock screen media HUD material.
    @AppStorage("lockScreenMediaMaterial") public var mediaMaterial: LockSurfaceMaterial = .dark

    private init() { super.init(keys: Self.keys) }
}
