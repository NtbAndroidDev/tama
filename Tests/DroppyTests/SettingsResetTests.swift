import Foundation
import Testing
@testable import Droppy

@Suite struct SettingsResetTests {
    /// Reset to Defaults removes exactly these keys, so user data must never be among them.
    @Test @MainActor func resetLeavesDataAlone() {
        let keys = Set(AppState.settingsKeys)
        #expect(keys.count == AppState.settingsKeys.count)
        for data in ["trayFiles", "scratchpadText", "pinboards", "disabledDroplets", "enabledDroplets", "colorSwatches"] {
            #expect(!keys.contains(data))
        }
        #expect(keys.contains(GlobalShortcutService.modifierKey))
        #expect(keys.contains("displayTargetMode"))
    }

    /// Settings a service names through its own constant are easy to forget,
    /// because they never appear as an `@AppStorage` literal in a settings store.
    /// Reset, export and import all walk `settingsKeys`, so they belong there.
    @Test @MainActor func keysDeclaredByServicesAreRegistered() {
        let keys = Set(AppState.settingsKeys)
        for key in LiquidMouseService.Keys.all { #expect(keys.contains(key), "\(key) is missing") }
        for key in MecheyService.Keys.all { #expect(keys.contains(key), "\(key) is missing") }
        for key in [MeetingControlService.targetKey, SpotlightSearchService.wholeMacKey,
                    LyricsService.onlineKey, DroppyAccentColor.customHexKey] {
            #expect(keys.contains(key), "\(key) is missing")
        }
        for key in ["voiceTranscribeLocale", "ringActions", "audioControlGains", "audioControlMuted",
                    "obsidianVaultPath", "obsidianDailyFolder", "obsidianDailyFormat",
                    "obsidianInboxPath", "obsidianTarget"] {
            #expect(keys.contains(key), "\(key) is missing")
        }
    }

    /// The other half: what a service stores is either a setting or data, and
    /// a key in neither list survives both a reset and an export.
    @Test @MainActor func keysHoldingDataAreRegisteredAsData() {
        let data = Set(AppState.dataKeys)
        for key in [TermiNotchSessions.directoryKey, "voiceTranscribeRecents",
                    "colorSwatches", "obsidianRecentEntries"] {
            #expect(data.contains(key), "\(key) is missing")
        }
        #expect(Set(AppState.settingsKeys).isDisjoint(with: data))
    }
}

/// The one-time raise of the collapse delay. It overwrites a setting someone
/// chose, so it has to be narrow: only values shorter than the new default,
/// and only once (the guard key lives in `dataKeys`, not `settingsKeys`, so
/// Reset to Defaults doesn't re-arm it while a hard reset does).
@Suite struct CollapseDelayMigrationTests {
    @Test @MainActor func aShortDelayIsRaisedToTheNewDefault() {
        #expect(AppState.raisedCollapseDelay(from: 0.10) == GeneralSettings.defaultAutoHideDelay)
        #expect(AppState.raisedCollapseDelay(from: 0.15) == GeneralSettings.defaultAutoHideDelay)
        #expect(AppState.raisedCollapseDelay(from: 0.39) == GeneralSettings.defaultAutoHideDelay)
    }

    @Test @MainActor func aDeliberatelyLongerDelayIsLeftAlone() {
        #expect(AppState.raisedCollapseDelay(from: GeneralSettings.defaultAutoHideDelay) == nil)
        #expect(AppState.raisedCollapseDelay(from: 1.0) == nil)
        #expect(AppState.raisedCollapseDelay(from: 3.0) == nil)
    }

    /// Never set means the new default already applies; nothing to write.
    @Test @MainActor func anUnsetDelayIsLeftAlone() {
        #expect(AppState.raisedCollapseDelay(from: nil) == nil)
    }

    @Test @MainActor func theGuardKeyIsDataAndTheDelayIsASetting() {
        #expect(AppState.dataKeys.contains("didRaiseShelfCollapseDelay"))
        #expect(!AppState.settingsKeys.contains("didRaiseShelfCollapseDelay"))
        #expect(AppState.settingsKeys.contains("autoHideDelay"))
    }
}
