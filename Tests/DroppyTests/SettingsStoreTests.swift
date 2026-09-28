import Foundation
import Testing
@testable import Droppy

@Suite struct SettingsStoreTests {
    /// Every settings store's keys, by store. A new store belongs here.
    static let storeKeys: [(String, [String])] = [
        ("General", GeneralSettings.keys), ("Theme", ThemeSettings.keys),
        ("Shelf", ShelfSettings.keys), ("Tray", TraySettings.keys),
        ("Basket", BasketSettings.keys), ("FileAction", FileActionSettings.keys),
        ("Clipboard", ClipboardSettings.keys), ("Capture", CaptureSettings.keys),
        ("Display", DisplaySettings.keys), ("HUD", HUDSettings.keys),
        ("Media", MediaSettings.keys), ("LockScreen", LockScreenSettings.keys),
        ("Calendar", CalendarSettings.keys), ("Pomodoro", PomodoroSettings.keys),
        ("HighAlert", HighAlertSettings.keys), ("Notes", NotesSettings.keys),
        ("TermiNotch", TermiNotchSettings.keys), ("Meeting", MeetingSettings.keys),
        ("NotificationHUD", NotificationHUDSettings.keys), ("Agents", AgentsSettings.keys),
        ("Notchface", NotchfaceSettings.keys), ("Voice", VoiceSettings.keys),
        ("Thunderstorm", ThunderstormSettings.keys), ("MenuBar", MenuBarSettings.keys),
        ("LocalSend", LocalSendSettings.keys), ("Weather", WeatherSettings.keys),
    ]

    /// Reset, Export and Import walk `settingsKeys`; a store key left out of
    /// it would survive a reset and never reach a backup.
    @Test @MainActor func everyStoreKeyIsASettingsKey() {
        let registered = Set(AppState.settingsKeys)
        for (store, keys) in Self.storeKeys {
            for key in keys { #expect(registered.contains(key), "\(store)Settings.\(key) is missing") }
        }
    }

    /// One key, one owner: two stores writing the same default would each
    /// believe they hold the truth.
    @Test func noKeyBelongsToTwoStores() {
        var owner: [String: String] = [:]
        for (store, keys) in Self.storeKeys {
            for key in keys {
                #expect(owner[key] == nil, "\(key) is in both \(owner[key] ?? "") and \(store)")
                owner[key] = store
            }
        }
    }

    /// A store republishes when one of its own keys is written from outside
    /// it (a view's own @AppStorage, Reset, Import).
    @Test @MainActor func storeRepublishesOnOutsideWrite() async {
        let store = NotchfaceSettings.shared
        let key = "notchfaceMirror"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }

        var fired = false
        let watch = store.objectWillChange.sink { fired = true }
        UserDefaults.standard.set(!store.mirror, forKey: key)
        // The change is delivered on the next main-queue turn.
        for _ in 0..<20 where !fired { try? await Task.sleep(for: .milliseconds(10)) }
        watch.cancel()
        #expect(fired)
    }
}
