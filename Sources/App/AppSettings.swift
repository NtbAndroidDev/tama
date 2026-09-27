import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Settings plumbing
// @AppStorage on an ObservableObject doesn't publish objectWillChange, so views
// watching AppState (the island shape, its tint, Settings' own labels) kept
// their old look until something else happened to redraw them. Settings are
// watched in UserDefaults instead, which also catches writes made elsewhere
// (a view's own @AppStorage, Reset to Defaults).

extension AppState {
    /// Every UserDefaults key that is a user preference. Data — clipboard
    /// history, tray files, pinboards, notes, droplet switches and droplet
    /// state — is deliberately left out, so a reset never loses anything.
    static let settingsKeys: [String] = [
        "islandStyle", "expandOnHover", "hapticFeedback", "soundEffects", "autoHideDelay",
        "clipboardHistoryLimit", "showInMenuBar", "showInDock", "accentColor",
        "borderGlowIntensity", "notchEarFilletRadius", "displayTargetMode",
        "jiggleToOpenBasket", "showVolumeHUD", "showBrightnessHUD", "showVPNStatus",
        "removeOnDragOut", "trayCapacity", "showMeetingCountdown", "showBatteryAlerts",
        "alwaysUseBuiltInSpeakers", "showDeviceAlerts", "showDownloadActivity", "pomodoroWorkMinutes", "pomodoroBreakMinutes",
        GlobalShortcutService.modifierKey, LyricsService.onlineKey,
        "clipboardFilterSensitive", "clipboardRetention", "clipboardImageLimitMB",
        "hoverOpenDelay", "islandMotionStyle", "defaultShelfPage", "showCapturePreview", "capturePreviewPlacement",
        "scrollToChangeVolume", "replaceSystemVolumeHUD", "hudDuration", "hudMeterStyle",
        "hudShowPercentage", "hudHideLabel", "hudAnimation", "hudLeading",
        "brightnessHUDDuration", "brightnessHUDMeterStyle", "brightnessHUDShowPercentage",
        "brightnessHUDHideLabel", "brightnessHUDAnimation", "replaceSystemBrightnessHUD",
        "scrollToChangeBrightness", "snipperDelay", "snipperAutoTray", "snipperAutoCopy",
        "protectOriginals", "autoCopyOCRText", "notchedSurfaceStyle", "notchlessSurfaceStyle",
        "subtleOutline", "outlineInRestingState", "solidSettingsBackground", "windowTint", "hudMeterCustomColor",
        "brightnessHUDMeterCustomColor", "mediaHUDVerticalOffset", DroppyAccentColor.customHexKey,
        "rightClickToHide", "rightClickToReveal", "holdToReveal", "holdToRevealModifier",
        "hideFromScreenshots",
        "shelfEnabled", "shelfSize", "shelfNavigationStyle", "showCalendarButton", "floatingButtonSize", "floatingButtonStyle", "floatingButtonLightIcons", "shelfFavorites",
        "multiLiveActivities", "autoCollapse", "animationSpeed", "shelfGestures", "shelfSwipeReversed", "openTrayAfterDrop",
        "hideOnExternalDisplays", "showWhenIdle", "perDisplayVisibility", "hiddenDisplays", "hidePhysicalNotch",
        "islandHeightOffset", "islandWidthOffset", "notchHUDHeightOffset", "notchHUDWidthOffset",
        "collapsedHUDScope", "fullscreenBehavior", "hideInMissionControl", "finishedHUDLinger",
        "keepHUDWhileHovered", "compactHUDPriority", "showKeyboardBrightnessHUD", "showFileTrayHUD",
        "showCapsLockHUD", "showRecordingHUD", "showFocusHUD", "showOfflineHUD", "volumeKeySound",
        "desktopVolumeSlider", "desktopBrightnessSlider", "mediaKeyTarget", "useBetterDisplay",
        "automaticBrightnessHUD", "keyboardBrightnessKeys",
        "playbackKeysMode", "nowPlayingEnabled", "mediaAutoHide", "mediaAutoHideDelay", "nowPlayingDisplay",
        "nowPlayingSize", "notchTrackTitle", "visualizerStyle", "liveAudioVisualizer", "liveAlbumArtwork", "playerArtworkTint",
        "playerShowsRemaining", "defaultMusicApp", "trackSwipe", "trackSwipeReversed", "notchClickOpensMedia",
        "filterMediaSources", "blockedMediaSources", "hideIncognitoMedia", "autoExpandLyrics", "lyricsWindowPinned",
        "audioQualityBadge", "musicLeftButton", "musicRightButton", "spotifyLeftButton", "spotifyRightButton",
        "regularLeftButton", "regularRightButton",
        "weatherStyle", "weatherLocationMode", "weatherPlaceName", "weatherPlaceLatitude", "weatherPlaceLongitude",
        "weatherRefreshMinutes", "weatherShowsAQI", "weatherShowsSun",
        "trayExpiry", "trayTwoStacks", "basketInstantAppear", "basketInstantDelay", "basketAutoHide",
        "basketAutoHideDelay", "basketShakeSensitivity", "basketDragModifiers", "basketMode",
        "basketSecondBucket", "basketLayout", "quickActionsEnabled", "quickActionTiles", "quickActionMailApp",
        "quickshareConfirm", "convertDestination", "afterConvertAction", "smartExportEnabled",
        "smartExportFolder", "smartExportCompressed", "smartExportConverted", "smartExportCutouts",
        "trackedFoldersEnabled", "trackedFolders", "trackedFoldersCompressionLevel", "cutoutBackground", "cutoutPadding",
        "cutoutCornerRadius", "cutoutShadow",
        "clipboardEnabled", "clipboardInMenuBar", "clipboardInShelfMenu", "clipboardLayout",
        "clipboardTypeFilters", "clipboardClearOnQuit", "clipboardRejectDuplicates", "clipboardTagsEnabled",
        "clipboardFavoritesBar", "clipboardCopyFavorite", "clipboardAutoFocusSearch", "clipboardPasteIntoApp", "clipboardBlurSensitive",
        "lockScreenAnimation", "lockScreenSounds", "lockScreenLockSound", "lockScreenUnlockSound",
        "lockScreenVolumeSlider", "lockScreenBrightnessSlider", "lockScreenDuringScreensaver", "lockScreenKeepAwake",
        "lockScreenShowsStatusRow", "lockScreenWidgetStyle", "lockScreenWidgetLook", "lockScreenWidgetMaterial",
        "lockScreenMediaMaterial", "lockScreenEnabled", "lockScreenShowsBattery", "lockScreenShowsHeadphones",
        "lockScreenShowsWeather", "lockScreenShowsNextEvent", "lockScreenShowsPlayer",
        "pomodoroAmbientEnabled", "pomodoroAmbientSound", "pomodoroAmbientVolume", "pomodoroFocusShortcuts", "pomodoroMomentum", "pomodoroSessionsToday", "pomodoroMomentumDay", "pomodoroStreakDays", "pomodoroBestStreak",
        "pomodoroKeepVisible", "pomodoroHoverOpens", "highAlertMode", "highAlertMinutes",
        "tasksShowTasks", "tasksShowEvents", "tasksHideUndated", "tasksHiddenCalendars", "tasksHiddenLists",
        "tasksDefaultList", "tasksDefaultCalendar", "tasksCleanupDelay", "tasksDueAlerts", "tasksDueChime",
        "tasksHeadsUpMinutes", "tasksEventRing", "tasksNextEventWing", "tasksWeekNumbers", "calendarLayout",
        "calendarPopoutOnTop", "notesAppleSync", "notesShowToolbar", "notesGrowCanvas",
        "termiNotchTerminalApp", "termiNotchDroppyPrompt", "termiNotchQuickBar", "termiNotchFontSize",
        "meetingPauseMedia", "meetingResumeMedia", "meetingPauseTrigger", "meetingCallHUD", "meetingMicLevel",
        "notificationHUDDuration", "notificationHUDBlockedApps", "notificationHUDBurst", "notificationHUDPreview",
        "notificationHUDQuickReply", "notificationHUDHideAfterReply", "notificationHUDShowFilters",
        "agentsClaude", "agentsCodex", "agentsCursor", "agentsShowInNotch", "agentsNotifyDone",
        "notchfaceCamera", "notchfaceMirror",
        "snipperEditAfterCapture", "snipperSaveToFolder", "snipperFolderPath", "snipperAutoCompress",
        "captureExcludeDroppy", "captureEditorDefaultZoom", "captureAnnotationColor", "captureEditorFont",
        "screenshotRadius", "windowSnapShowPreview", "snipperMode",
        "voiceLiveTranscription", "voiceEngine", "voiceSkipResult", "voiceMenuBarIcon", "voiceRetention",
        "voiceFloatingRecorder", "thunderstormWebSearch", "thunderstormInlineAnswers", "thunderstormSystemCommands",
        "menuBarAlwaysHidden", "menuBarAutoRehide", "menuBarRehideDelay", "menuBarRehideOnAppSwitch",
        "menuBarToggleIcon", "menuBarIconTemplate", "menuBarShowDividers",
        "localSendDeviceName", "localSendReceiveMode", "localSendVisible", "localSendEncrypted", "localSendPIN",
        "localSendSaveFolder", "localSendAddToShelf", "localSendQuickSaveFavorites",
        "diagnosticLogging", "showTooltips", "showWhatsNew", "sidebarHiddenDroplets", CrashReportService.promptKey,
        // Keys the services name through their own constants; they belong here
        // too, or reset, export and import would walk straight past them.
        "meetingTarget", "thunderstormWholeMac", "voiceTranscribeLocale", "ringActions",
        "audioControlGains", "audioControlMuted",
        "obsidianVaultPath", "obsidianDailyFolder", "obsidianDailyFormat", "obsidianInboxPath",
        "obsidianTarget",
    ] + LiquidMouseService.Keys.all + MecheyService.Keys.all
      + ShortcutAction.defaultsKeys + ShortcutSlot.dropletDefaultsKeys

    // MARK: Migrations

    /// One-time changes to existing installs, run at launch.
    func migrateSettings() {
        let defaults = UserDefaults.standard
        // Auto-expand on hover became opt-in, like the reference: switch it off
        // once for everyone, after which the user's choice sticks.
        if !defaults.bool(forKey: "didDisableShelfAutoExpandByDefault") {
            defaults.set(false, forKey: "expandOnHover")
            defaults.set(true, forKey: "didDisableShelfAutoExpandByDefault")
        }
        // The collapse delay used to default to 0.15s, and the slider goes down
        // to 0.10s. At those settings the shelf is gone before a deliberate
        // move can land on anything just outside it, so raise a delay that is
        // below the new default once. Anyone who liked it snappy can set it
        // straight back, and this never runs again.
        if !defaults.bool(forKey: "didRaiseShelfCollapseDelay") {
            if let raised = Self.raisedCollapseDelay(from: defaults.object(forKey: "autoHideDelay") as? Double) {
                defaults.set(raised, forKey: "autoHideDelay")
            }
            defaults.set(true, forKey: "didRaiseShelfCollapseDelay")
        }
    }

    /// What the one-time raise should store, or nil to leave the setting be:
    /// never set, or already at least as long as the new default.
    nonisolated static func raisedCollapseDelay(from stored: Double?) -> Double? {
        guard let stored, stored < defaultAutoHideDelay else { return nil }
        return defaultAutoHideDelay
    }

    private static func settingsSnapshot() -> NSDictionary {
        UserDefaults.standard.dictionaryWithValues(forKeys: settingsKeys) as NSDictionary
    }

    /// Republishes AppState (and ClipboardPrivacy) when a setting changes, and
    /// applies what a plain value can't: a smaller Tray capacity drops the
    /// oldest files right away instead of on the next drop.
    func observeSettings() -> AnyCancellable {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { _ in Self.settingsSnapshot() }
            .prepend(Self.settingsSnapshot())
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                ClipboardPrivacy.shared.objectWillChange.send()
                self.trimTray(reason: "Tray capacity lowered")
                // Reset / Import write the keys directly, past the didSets.
                MediaKeyMonitor.shared.syncInterception()
                JiggleService.shared.syncIdleWatch()
            }
    }

    /// Switching a Droplet off in Settings also stops what it left running:
    /// its widget is gone, so a held sleep assertion or a ticking timer would
    /// otherwise carry on with no way to stop it. (Mechey, Audio Control and
    /// the Ring hotkey follow the switch in their own services.)
    func observeDropletSwitches() -> AnyCancellable {
        $droplets
            .map { Set($0.filter { !$0.isEnabled }.map(\.id)) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] disabled in
                guard let self else { return }
                if disabled.contains("caffeine") { SleepBlockerService.shared.disable() }
                if disabled.contains("pomodoro"), self.isPomodoroActive { self.resetPomodoro() }
                if disabled.contains("timer"), TimerService.shared.isRunning { TimerService.shared.reset() }
                if disabled.contains("ring"), RingWindowController.shared.isVisible { RingWindowController.shared.close() }
                if disabled.contains("termiNotch") { TermiNotchSessions.shared.terminateAll() }
                if disabled.contains("notchface") { NotchfaceCamera.shared.stop() }
                // These follow the switch both ways.
                MeetingControlService.shared.evaluateCall()
                MeetingControlService.shared.refreshCallActivity()
                NotificationHUDService.shared.sync()
                AgentActivityService.shared.sync()
                if let open = self.activeDropletID, disabled.contains(open) { self.activeDropletID = nil }
            }
    }

    /// Puts every setting back to its default, live. Data is kept.
    public func resetSettingsToDefaults() {
        let defaults = UserDefaults.standard
        for key in Self.settingsKeys { defaults.removeObject(forKey: key) }
        ClipboardPrivacy.shared.excludedBundleIDs = ClipboardPrivacy.defaultExcludedApps
        applyStoredSettings()
    }

    // MARK: Backup

    /// Writes every preference (not clips, files or notes) to a JSON file.
    public func exportSettings() {
        let panel = NSSavePanel()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH-mm"
        panel.nameFieldStringValue = "Tama Settings \(stamp.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var values: [String: Any] = [:]
        for key in Self.settingsKeys {
            if let value = UserDefaults.standard.object(forKey: key), JSONSerialization.isValidJSONObject([value]) {
                values[key] = value
            }
        }
        values["excludedApps"] = ClipboardPrivacy.shared.excludedBundleIDs
        let file: [String: Any] = ["tamaSettings": 1, "values": values]
        do {
            let data = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            showNotification(appName: "Settings", title: "Settings exported", message: url.lastPathComponent)
        } catch {
            showNotification(appName: "Settings", title: "Couldn't export settings", message: error.localizedDescription)
        }
    }

    /// Reads a file from `exportSettings()`. Unknown keys are ignored, so a
    /// file from a newer Tama can't write anything this one doesn't know.
    public func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              file["tamaSettings"] != nil,
              let values = file["values"] as? [String: Any] else {
            showNotification(appName: "Settings", title: "Not a Tama settings file", message: url.lastPathComponent)
            return
        }
        let known = Set(Self.settingsKeys)
        var applied = 0
        for (key, value) in values where known.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
            applied += 1
        }
        if let apps = values["excludedApps"] as? [String] {
            ClipboardPrivacy.shared.excludedBundleIDs = apps
        }
        applyStoredSettings()
        showNotification(appName: "Settings", title: "Settings imported", message: "\(applied) preference\(applied == 1 ? "" : "s") from \(url.lastPathComponent)")
    }

    /// Writing UserDefaults directly skips the properties' didSet; run their
    /// effects so a reset or an import applies at once.
    private func applyStoredSettings() {
        let limit = clipboardHistoryLimit
        clipboardHistoryLimit = limit
        let work = pomodoroWorkMinutes
        pomodoroWorkMinutes = work
        VPNService.shared.apply(enabled: showVPNStatus)
        DownloadWatcher.shared.apply(enabled: showDownloadActivity)
        MeetingService.shared.tick()
        applyClipboardRetention()
        CaptureExclusion.apply()
        IslandVisibilityService.shared.sync()
        applyHUDSettings()
        applyMediaSettings()
        DroppyDiagnostics.applyTooltipPreference(showTooltips)
        // Services that cache their keys in memory: without this they keep the
        // old values until the next launch, so a reset or import looks ignored.
        ObsidianService.shared.reloadFromDefaults()
        RingActionStore.shared.reloadFromDefaults()
        MeetingControlService.shared.reloadFromDefaults()
        AppAudioService.shared.reloadFromDefaults()
        LocalSendService.shared.restart()
        onIslandFrameChange?(isIslandExpanded)
        objectWillChange.send()
        DroppyAudio.playTick()
    }

    // MARK: Hard reset

    /// Set while a hard reset wipes everything, so quitting doesn't write the
    /// old Tray and clips straight back.
    static var isHardResetting = false

    /// Settings › About › Hard reset: every setting and all data go back to a
    /// fresh install — Tray, notes, pinboards, droplet switches, onboarding —
    /// optionally keeping the clipboard history (and its pinboards). Then
    /// Tama relaunches.
    public func hardReset(keepClipboard: Bool) {
        let defaults = UserDefaults.standard
        let pinboards = defaults.object(forKey: "pinboards")
        let tags = defaults.object(forKey: "clipboardTags")
        Self.isHardResetting = true
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        } else {
            for key in Self.settingsKeys + Self.dataKeys { defaults.removeObject(forKey: key) }
        }
        if keepClipboard, let pinboards { defaults.set(pinboards, forKey: "pinboards") }
        if keepClipboard, let tags { defaults.set(tags, forKey: "clipboardTags") }
        defaults.synchronize()

        let fm = FileManager.default
        try? fm.removeItem(at: Self.trayStorageDirectory)
        if !keepClipboard {
            try? fm.removeItem(at: Self.supportDirectory.appendingPathComponent("clipboard.json"))
            try? fm.removeItem(at: ClipboardImageStore.directory)
        }
        // A save still queued would write the notes back after the delete.
        NotesStore.shared.flush()
        try? fm.removeItem(at: NotesStore.fileURL)
        PermissionService.shared.relaunch()
    }

    /// Data kept outside `settingsKeys`, for a hard reset without a bundle ID.
    static let dataKeys = [
        "trayFiles", "scratchpadText", "pinboards", "clipboardTags", "disabledDroplets", "enabledDroplets",
        "homeWidgets", "hasCompletedOnboarding", "didDisableShelfAutoExpandByDefault",
        "dropletOrder", "trayItems", "baskets", "quickshareUploads",
        "localSendFavorites", "localSendHTTPFingerprint", "setupGuideDone", "NSInitialToolTipDelay",
        "didRaiseShelfCollapseDelay",
        "termiNotchDirectory", "voiceTranscribeRecents", "colorSwatches", "obsidianRecentEntries",
        // One-shot hints, so a reset offers them again.
        "homeCustomizeTipShown",
    ]
}

// MARK: - Level HUD style

/// How one kind of level HUD looks: Sound and Display each have their own.
public struct LevelHUDStyle: Equatable, Sendable {
    public var duration: Double
    public var meter: HUDMeterStyle
    public var showPercentage: Bool
    public var hideLabel: Bool
    public var animation: HUDAnimation
    /// Symbol or output device; brightness always shows its symbol.
    public var leading: HUDLeading
}

extension AppState {
    /// The meter colour picked on the Theming tape, for `HUDMeterStyle.custom`.
    public func hudCustomColor(for kind: IslandHUD.Kind) -> Color? {
        TapePalette.color(for: kind == .volume ? hudMeterCustomColor : brightnessHUDMeterCustomColor)
    }

    public func hudStyle(for kind: IslandHUD.Kind) -> LevelHUDStyle {
        switch kind {
        case .volume:
            return LevelHUDStyle(duration: hudDuration, meter: hudMeterStyle, showPercentage: hudShowPercentage,
                                 hideLabel: hudHideLabel, animation: hudAnimation, leading: hudLeading)
        // The keyboard backlight shares the brightness HUD's look.
        case .brightness, .keyboard:
            return LevelHUDStyle(duration: brightnessHUDDuration, meter: brightnessHUDMeterStyle,
                                 showPercentage: brightnessHUDShowPercentage, hideLabel: brightnessHUDHideLabel,
                                 animation: brightnessHUDAnimation, leading: .symbol)
        }
    }
}
