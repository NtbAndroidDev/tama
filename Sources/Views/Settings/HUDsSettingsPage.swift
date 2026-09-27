import SwiftUI
import AppKit

/// Settings › HUDs, laid out like the reference: Display style, Size,
/// Behavior, Media, Media Controls, the System and Droplets HUD grids, Media
/// keys and Keyboard backlight — then Tama's own Live Activities and the
/// detailed Volume and Brightness sections.
struct HUDsSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var mediaKeys = MediaKeyMonitor.shared
    @ObservedObject private var focus = FocusModeService.shared
    @ObservedObject private var betterDisplay = BetterDisplayService.shared
    /// Kept in state so plugging in or removing a display refreshes the lists.
    @State private var screens = NSScreen.screens

    private var externalScreens: [NSScreen] { screens.filter { !$0.isBuiltIn } }
    private var hasNotchedScreen: Bool { screens.contains { $0.safeAreaInsets.top > 0 } }
    private var isAccessibilityTrusted: Bool { permissions.status(.accessibility) == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            displayStyle
            size
            behavior
            HUDsMediaSections()
            systemHUDs
            dropletHUDs
            mediaKeysSection
            keyboardBacklight
            liveActivities
            LevelHUDSettingsTab(kind: .volume).id("sound")
            LevelHUDSettingsTab(kind: .brightness).id("display")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
        .onAppear {
            screens = NSScreen.screens
            BetterDisplayService.shared.refresh()
            if focus.status == .unreadable { FocusModeService.shared.retry() }
        }
    }

    // MARK: - Display style

    private var displayStyle: some View {
        SettingsSection("Display style") {
            SettingsGroup {
                SettingsToggleRow("Hide on external displays",
                                  help: "Turns the notch or island off on every connected monitor; only the MacBook's own display keeps it. With the lid closed there is no built-in display, so the island is hidden everywhere.",
                                  anchor: "huds.hideExternal", isOn: $state.hideOnExternalDisplays)
                SettingsDivider()
                Group {
                    SettingsRow("External displays",
                                subtitle: state.hideOnExternalDisplays ? "Off while Hide on external displays is on." : nil,
                                help: "Pick the notch or the floating island pill for displays without a physical notch. A display with a notch always uses the notch.",
                                anchor: "huds.displayStyle")
                    PreviewCardPicker([
                        PreviewCardOption(IslandStyle.notchAttached, "Notch", subtitle: "Carved black silhouette"),
                        PreviewCardOption(IslandStyle.floatingPill, "Island", subtitle: "Floating pill surface"),
                    ], selection: $state.islandStyle, thumbnailHeight: 76) { style in
                        HUDStyleThumbnail(style: style)
                    }
                    .padding(.top, -8)
                    SettingsDivider()
                    SettingsToggleRow("Show when idle",
                                      help: "Keep the external notch or island surface visible when nothing is playing. Off, it fades away while nothing is live on that display and comes back when the pointer or a file drag reaches it.",
                                      anchor: "huds.showWhenIdle", isOn: $state.showWhenIdle)
                    SettingsDivider()
                    SettingsToggleRow("Per-display visibility",
                                      help: "Choose exactly which external displays show the top HUD surface.",
                                      anchor: "huds.perDisplay", isOn: $state.perDisplayVisibility)
                }
                .settingsDisabled(state.hideOnExternalDisplays)
                if state.perDisplayVisibility && !state.hideOnExternalDisplays {
                    perDisplayList
                }
                SettingsDivider()
                SettingsToggleRow("Hide physical notch",
                                  help: "Paints the strip beside the notch black, as tall as the menu bar, so the camera housing disappears into it. The menu bar stays on top and clickable; it reads best with a dark menu bar. Fullscreen apps aren't covered.",
                                  anchor: "huds.hideNotch", isOn: $state.hidePhysicalNotch)
                if state.hidePhysicalNotch && !hasNotchedScreen {
                    SettingsNote("No display with a notch is connected; the bar appears when one is.")
                }
                SettingsDivider()
                SettingsRow("Show Tama on", help: "Which display carries the live island. Follow Mouse and All Displays move it to the screen you're using.",
                            anchor: "huds.targetDisplay") {
                    Picker("Show Tama on", selection: $state.displayTargetMode) {
                        ForEach(DisplayTargetMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                if state.displayTargetMode == .all {
                    SettingsNote("Every screen shows the notch. The live one follows the pointer, so the screen you're on is the one that opens.")
                }
                SettingsDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected screens (\(screens.count))").font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                        screenRow(screen, index: index)
                    }
                }
                .padding(SettingsStyle.rowPadding)
            }
        }
    }

    private var perDisplayList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if externalScreens.isEmpty {
                Text("No external display is connected. Displays appear here when they are.")
                    .font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(externalScreens, id: \.droppyDisplayKey) { screen in
                Toggle(isOn: Binding(
                    get: { !state.hiddenDisplayKeys.contains(screen.droppyDisplayKey) },
                    set: { shown in
                        var hidden = state.hiddenDisplayKeys
                        if shown { hidden.remove(screen.droppyDisplayKey) } else { hidden.insert(screen.droppyDisplayKey) }
                        state.hiddenDisplayKeys = hidden
                    }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "display").foregroundStyle(.secondary)
                        Text(screen.localizedName.isEmpty ? "Display" : screen.localizedName)
                            .font(SettingsStyle.rowTitle)
                        Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height))")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showsDroppy(on screen: NSScreen) -> Bool {
        guard state.allowsSurface(on: screen) else { return false }
        return state.displayTargetMode == .all || state.getTargetScreen() == screen
    }

    private func screenRow(_ screen: NSScreen, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundColor(showsDroppy(on: screen) ? state.accentColor.color : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName)
                        .font(.system(size: 11, weight: .semibold))
                    if screen == screens.first { badge("Primary", .blue) }
                    if screen.safeAreaInsets.top > 0 { badge("Notch", .purple) }
                    if showsDroppy(on: screen) { badge("Active", .green) }
                    if !state.allowsSurface(on: screen) { badge("Hidden", .gray) }
                }
                Text(verbatim: "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt (Scale \(Int(screen.backingScaleFactor))x)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .accessibilityLabel(text)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    // MARK: - Size

    private func points(_ value: Double) -> String {
        abs(value) < 0.5 ? "Standard" : String(format: "%+.0f pt", value)
    }

    private var size: some View {
        SettingsSection("Size", subtitle: "Island sizes apply to displays without a notch; Notch sizes to the HUD around a physical notch.") {
            SettingsGroup {
                SettingsSlider("Island height", value: $state.islandHeightOffset, in: DroppyShelfMetrics.islandHeightRange,
                               step: 1, defaultValue: 0, anchor: "huds.islandHeight", format: points)
                SettingsDivider()
                SettingsSlider("Island width", value: $state.islandWidthOffset, in: DroppyShelfMetrics.islandWidthRange,
                               step: 2, defaultValue: 0, anchor: "huds.islandWidth", format: points)
                SettingsDivider()
                SettingsSlider("Island position", value: $state.mediaHUDVerticalOffset, in: -8...40, step: 1,
                               defaultValue: 0, help: "Moves the floating island down from the top of a display without a notch. The same setting as Theming › Media HUD position.",
                               anchor: "huds.islandPosition", format: points)
                SettingsDivider()
                SettingsSlider("Notch height", value: $state.notchHUDHeightOffset, in: DroppyShelfMetrics.notchHeightRange,
                               step: 1, defaultValue: 0,
                               help: "How far the volume and brightness HUD reaches below a physical notch.",
                               anchor: "huds.notchHeight", format: points)
                SettingsDivider()
                SettingsSlider("Notch width", value: $state.notchHUDWidthOffset, in: DroppyShelfMetrics.notchWidthRange,
                               step: 2, defaultValue: 0,
                               help: "Fine-tune how wide the physical-notch HUD surface appears.",
                               anchor: "huds.notchWidth", format: points)
            }
        }
        // The HUD sizes are only seen with a HUD up: show one while they change.
        .onChange(of: state.notchHUDHeightOffset) { _, _ in previewHUD() }
        .onChange(of: state.notchHUDWidthOffset) { _, _ in previewHUD() }
    }

    private func previewHUD() {
        let outputs = AudioOutputService.shared
        state.showHUD(.volume, value: outputs.volume, isMuted: outputs.isMuted)
    }

    // MARK: - Behavior

    private var behavior: some View {
        SettingsSection("Behavior") {
            SettingsGroup {
                Group {
                    SettingsRow("Collapsed HUD scope",
                                subtitle: state.displayTargetMode == .all ? nil : "Applies when Show Tama on is set to All Displays.",
                                help: "With Show Tama on › All Displays: whether the volume and brightness HUD shows only on the display under the pointer or on every display's island.",
                                anchor: "huds.scope")
                    ChoiceTiles([
                        .init(HUDScope.underPointer, "Under pointer", icon: "cursorarrow.rays"),
                        .init(HUDScope.allDisplays, "All displays", icon: "rectangle.on.rectangle"),
                    ], selection: $state.collapsedHUDScope)
                }
                .settingsDisabled(state.displayTargetMode != .all)
                SettingsDivider()
                SettingsRow("In fullscreen",
                            help: "Choose what Tama does while an app or video is fullscreen on a display. Hide media leaves the music out of the resting island; Hide all hides the island and its level HUD there (macOS shows its own volume HUD instead). An open shelf and banners still show.",
                            anchor: "huds.fullscreen")
                ChoiceTiles([
                    .init(FullscreenBehavior.show, "Show", icon: "eye"),
                    .init(FullscreenBehavior.hideMedia, "Hide media", icon: "music.note"),
                    .init(FullscreenBehavior.hideAll, "Hide all", icon: "eye.slash"),
                ], selection: $state.fullscreenBehavior)
                if state.fullscreenBehavior != .show && !isAccessibilityTrusted {
                    SettingsNote("Without \(PermissionService.accessibilityName) access only windows that cover the whole display, menu bar included, count as fullscreen.",
                                 icon: "info.circle")
                        .padding(.top, 8)
                }
                SettingsDivider()
                SettingsToggleRow("Hide in Mission Control",
                                  help: "Hide the notch or island while Mission Control or App Exposé is open.",
                                  anchor: "huds.missionControl", isOn: $state.hideInMissionControl)
                if state.hideInMissionControl && !isAccessibilityTrusted {
                    accessibilityNote("Mission Control is announced to apps with \(PermissionService.accessibilityName) access.")
                }
                SettingsDivider()
                SettingsRow("Compact HUD priority",
                            help: "What the resting wings show when music plays and something urgent happens (a charger, a device, Caps Lock, a meeting). The other one gets the round pill with Multi Live Activities.",
                            anchor: "huds.priority")
                ChoiceTiles([
                    .init(CompactHUDPriority.activitiesFirst, "Live activities first", icon: "bolt.fill"),
                    .init(CompactHUDPriority.mediaFirst, "Music first", icon: "music.note"),
                ], selection: $state.compactHUDPriority)
                SettingsDivider()
                SettingsSlider("Finished HUD linger", value: $state.finishedHUDLinger, in: 1...10, step: 0.5,
                               defaultValue: 3,
                               help: "How long a brief HUD — charger, headphones, Caps Lock, Focus, a finished download — stays in the notch.",
                               anchor: "huds.linger") { String(format: "%.1f s", $0) }
                SettingsDivider()
                SettingsToggleRow("Keep HUD visible while hovered",
                                  help: "The volume or brightness HUD stays while the pointer rests on it, and goes a moment after it leaves.",
                                  anchor: "huds.keepHovered", isOn: $state.keepHUDWhileHovered)
            }
        }
    }

    // MARK: - System HUD grid

    private var systemHUDs: some View {
        SettingsSection("System", subtitle: "Click a card to turn its HUD on or off.") {
            SettingsGroup {
                PreviewCardGrid {
                    card("Volume", "Replace system OSD", $state.showVolumeHUD, anchor: "huds.volumeCard") {
                        MiniHUD(icon: "speaker.wave.2.fill", level: 0.18, tint: .green, trailing: "18%")
                    }
                    card("Brightness", "Replace brightness OSD", $state.showBrightnessHUD, anchor: "huds.brightnessCard") {
                        MiniHUD(icon: "sun.max.fill", level: 0.3, tint: .yellow, trailing: "30%")
                    }
                    card("Keyboard brightness", "Replace backlight OSD", $state.showKeyboardBrightnessHUD,
                         anchor: "huds.keyboardHUD") {
                        MiniHUD(icon: "light.min", level: 0.22, tint: .white, trailing: "22%")
                    }
                    card("Battery status", "Charge + low battery", $state.showBatteryAlerts, anchor: "huds.batteryHUD") {
                        MiniHUD(label: "Charging", trailing: "64%", trailingIcon: "battery.75percent", trailingTint: .green)
                    }
                    card("File tray", "After drop sessions", $state.showFileTrayHUD, anchor: "huds.fileTrayHUD") {
                        MiniHUD(icon: "tray.fill", trailing: "3", trailingTint: .yellow)
                    }
                    card("Caps Lock", "On / Off indicator", $state.showCapsLockHUD, anchor: "huds.capsLock") {
                        MiniHUD(icon: "circle.fill", iconScale: 0.4, trailing: "Off")
                    }
                    card("Recording status", "Mic + screen indicator", $state.showRecordingHUD, anchor: "huds.recording") {
                        MiniHUD(icon: "waveform", iconTint: DS.Palette.danger, trailing: "0:00", trailingTint: DS.Palette.danger)
                    }
                    card("AirPods & headphones", "Show when connected", $state.showDeviceAlerts, anchor: "huds.airpods") {
                        MiniHUD(icon: "airpodspro", label: "Connected", trailingIcon: "circle", trailingTint: .green)
                    }
                    card("Focus mode", "Show when toggled", $state.showFocusHUD, anchor: "huds.focus") {
                        MiniHUD(icon: "moon.fill", trailing: "Off")
                    }
                    card("No internet", "Pop up when offline", $state.showOfflineHUD, anchor: "huds.offline") {
                        MiniHUD(icon: "wifi.exclamationmark", iconTint: .green, chips: ["OK", "Settings"])
                    }
                    card("VPN connected", "Tunnel name + timer", $state.showVPNStatus, anchor: "huds.vpn") {
                        MiniHUD(icon: "globe", label: "Secure Tunnel", trailing: "00:04", trailingTint: .orange)
                    }
                }
                systemNotes
            }
        }
    }

    @ViewBuilder
    private var systemNotes: some View {
        if state.showKeyboardBrightnessHUD && !KeyboardBacklightService.shared.isAvailable {
            SettingsNote("This Mac has no keyboard backlight Tama can read, so the keyboard brightness HUD stays quiet.",
                         icon: "info.circle")
        }
        if state.showRecordingHUD {
            SettingsNote("Recording status watches every microphone. For the screen only macOS's own recorder (⌘⇧5, QuickTime) can be seen; other apps' screen capture has no public signal.",
                         icon: "info.circle")
        }
        if state.showFocusHUD && focus.status == .unreadable {
            HStack(alignment: .firstTextBaseline) {
                Label("Focus mode reads macOS's Focus database, which needs Full Disk Access. Scheduled Focus isn't recorded there.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                Button("Check Again") { FocusModeService.shared.retry() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func card<Thumbnail: View>(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>, anchor: String,
                                       @ViewBuilder thumbnail: () -> Thumbnail) -> some View {
        PreviewActionCard(title, subtitle: subtitle, isOn: isOn.wrappedValue, anchor: anchor,
                          action: { isOn.wrappedValue.toggle() }, thumbnail: thumbnail)
    }

    // MARK: - Droplet HUD grid

    private var dropletHUDs: some View {
        SettingsSection("Droplets", subtitle: "HUDs that come with a droplet. Set one up in its droplet's settings.") {
            SettingsGroup {
                PreviewCardGrid {
                    dropletCard("Meetings", "Call timer + live audio", id: "meetings") {
                        MiniHUD(icon: "phone.fill", iconTint: .green, trailing: "5:12", trailingIcon: "waveform", trailingTint: .green)
                    }
                    dropletCard("Pomodoro", "Focus / break timer", id: "pomodoro") {
                        MiniHUD(icon: "circle.dashed", iconTint: .orange, trailing: "15:24", trailingTint: .orange)
                    }
                    dropletCard("Calendar", "Event progress ring", id: "calendar") {
                        MiniHUD(icon: "calendar", iconTint: .red, trailingIcon: "circle.dashed", trailingTint: .red)
                    }
                    dropletCard("Notifications", "Live notification HUD", id: "notifications") {
                        MiniHUD(icon: "person.crop.circle.fill", iconTint: .purple, label: "Are we still on?", trailing: "now")
                    }
                    dropletCard("High Alert", "Stay-awake status", id: "caffeine") {
                        MiniHUD(icon: "cup.and.saucer.fill", iconTint: .orange, trailing: "42:00", trailingTint: .orange)
                    }
                    dropletCard("TermiNotch", "Terminal in the notch", id: "termiNotch") {
                        MiniHUD(icon: "apple.terminal", iconTint: .cyan, label: "npm run", trailing: "1:24")
                    }
                    dropletCard("Agents", "Claude, Codex & Cursor status", id: "agents") {
                        MiniHUD(icon: "sparkle", iconTint: .orange, trailingIcon: "circle.dashed", trailingTint: .orange)
                    }
                }
            }
        }
        .settingsAnchor("huds.droplets")
    }

    private func dropletCard<Thumbnail: View>(_ title: String, _ subtitle: String, id: String,
                                              @ViewBuilder thumbnail: () -> Thumbnail) -> some View {
        PreviewActionCard(title, subtitle: subtitle, isOn: false, badge: "Set up", action: {
            let navigator = SettingsNavigator.shared
            navigator.open(.droplets)
            // Droplets Tama has open their detail page; the others the store.
            if state.droplets.contains(where: { $0.id == id }) { navigator.openDropletID = id }
        }, thumbnail: thumbnail)
    }

    // MARK: - Media keys

    private var mediaKeysSection: some View {
        SettingsSection("Media keys") {
            SettingsGroup {
                SettingsRow("Key sound", icon: "speaker.wave.2.bubble",
                            help: "Play the feedback pop when the volume keys change the level (hold ⇧ to flip it for one press). Applies while Tama handles the volume keys.",
                            anchor: "huds.keySound")
                ChoiceTiles([
                    .init(false, "Off", icon: "speaker.slash"),
                    .init(true, "On", icon: "waveform"),
                ], selection: $state.volumeKeySound)
                SettingsDivider()
                SettingsToggleRow("Desktop volume slider", icon: "speaker.wave.2",
                                  help: "A small volume slider on the desktop, under your windows, on every Space. Drag its edge to move it.",
                                  anchor: "huds.desktopVolume", isOn: $state.desktopVolumeSlider)
                SettingsDivider()
                SettingsToggleRow("Desktop brightness slider", icon: "sun.max",
                                  help: "A small slider on the desktop for the built-in display's brightness.",
                                  anchor: "huds.desktopBrightness", isOn: $state.desktopBrightnessSlider)
                if state.desktopBrightnessSlider && !BrightnessService.shared.canSetBrightness {
                    SettingsNote("This Mac's display brightness can't be set by Tama, so the slider isn't shown.", icon: "info.circle")
                }
                SettingsDivider()
                SettingsRow("Media key target", icon: "scope",
                            help: "Where the brightness keys apply. Under pointer dims the display the pointer is on when Tama can (the built-in panel, Apple displays, or others through BetterDisplay); any other display is left to macOS. Main MacBook always dims the built-in display.",
                            anchor: "huds.keyTarget")
                ChoiceTiles([
                    .init(MediaKeyTarget.underPointer, "Under pointer", icon: "cursorarrow.rays"),
                    .init(MediaKeyTarget.mainMacBook, "Main MacBook", icon: "laptopcomputer"),
                ], selection: $state.mediaKeyTarget)
                SettingsDivider()
                betterDisplayRow
                SettingsDivider()
                SettingsRow("Playback keys", icon: "playpause",
                            help: "Choose what Tama handles for media keys. macOS: play/pause, next and previous go where macOS sends them. Now Playing: Tama sends them to the app its player shows (browser tabs stay with macOS), and play with nothing playing opens the default music app. Default app: they always control Apple Music or Spotify, as picked in Media Controls.",
                            anchor: "huds.playbackKeys")
                ChoiceTiles([
                    .init(PlaybackKeysMode.system, "macOS", icon: "applelogo"),
                    .init(PlaybackKeysMode.nowPlaying, "Now Playing", icon: "play.circle"),
                    .init(PlaybackKeysMode.defaultApp, "Default app", icon: "music.note.list"),
                ], selection: $state.playbackKeysMode)
                if state.playbackKeysMode != .system && !mediaKeys.isIntercepting {
                    accessibilityNote("Taking the playback keys needs \(PermissionService.accessibilityName) access. Until then macOS handles them.")
                        .padding(.top, 8)
                }
                SettingsDivider()
                SettingsToggleRow("Automatic brightness HUD",
                                  subtitle: state.showBrightnessHUD ? nil : "Turn on the Brightness card under System to use this.",
                                  icon: "sun.max",
                                  help: "Also show the brightness HUD when the built-in display changes on its own — ambient light, Control Center, another app.",
                                  anchor: "huds.autoBrightness", isOn: $state.automaticBrightnessHUD)
                    .settingsDisabled(!state.showBrightnessHUD)
                SettingsDivider()
                SettingsToggleRow("Keyboard brightness keys", icon: "keyboard",
                                  help: "Tama takes the keyboard backlight keys (on keyboards that have them) and steps the backlight itself, with its HUD instead of the macOS one.",
                                  anchor: "huds.keyboardKeys", isOn: $state.keyboardBrightnessKeys)
                if state.keyboardBrightnessKeys {
                    if !KeyboardBacklightService.shared.isAvailable {
                        SettingsNote("No keyboard backlight Tama can control was found; macOS keeps these keys.", icon: "info.circle")
                    } else if !mediaKeys.isIntercepting {
                        accessibilityNote("Taking the keys needs \(PermissionService.accessibilityName) access. Until then macOS handles them and Tama only shows its HUD.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var betterDisplayRow: some View {
        SettingsRow("BetterDisplay integration",
                    help: "BetterDisplay can dim external monitors. With its HTTP server on (BetterDisplay › Settings › Integration, port 55777), the brightness keys for an external display go through it and show Tama's HUD.",
                    anchor: "huds.betterDisplay") {
            if betterDisplay.isInstalled {
                Toggle("BetterDisplay integration", isOn: $state.useBetterDisplay)
                    .labelsHidden().toggleStyle(.switch)
            } else {
                Button("Get BetterDisplay") { NSWorkspace.shared.open(BetterDisplayService.downloadURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow.opacity(0.85))
                    // Dark text: white on yellow is too faint to read.
                    .foregroundStyle(.black)
            }
        }
        if betterDisplay.isInstalled && state.useBetterDisplay {
            if betterDisplay.isReachable {
                SettingsNote("Connected to BetterDisplay.", icon: "checkmark.circle.fill", tint: DS.Palette.success)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    SettingsNote("BetterDisplay isn't answering. Open it and switch on Settings › Integration › HTTP server.",
                                 icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
                    Button("Check Again") { BetterDisplayService.shared.refresh() }
                        .controlSize(.small)
                        .padding(.trailing, 14)
                }
            }
        }
    }

    private func accessibilityNote(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(DS.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Allow…") { permissions.request(.accessibility) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Keyboard backlight

    private var keyboardBacklight: some View {
        SettingsSection("Keyboard backlight") {
            SettingsGroup {
                ShortcutRecorderRow(.keyboardBacklightUp, title: "Brighten shortcut",
                                    help: "Press or hold to step the keyboard backlight up.", anchor: "huds.backlightShortcuts")
                SettingsDivider()
                ShortcutRecorderRow(.keyboardBacklightDown, title: "Dim shortcut",
                                    help: "Press or hold to step the keyboard backlight down.")
            }
        }
    }

    // MARK: - Live Activities (Tama's own)

    private var liveActivities: some View {
        SettingsSection("Live Activities",
                        subtitle: "Shown in the notch's wings. Meetings show a Join button for Zoom, Meet, Teams and Webex links. Downloads asks for access to your Downloads folder.") {
            SettingsGroup {
                SettingsToggleRow("Next meeting countdown", anchor: "huds.liveActivities", isOn: $state.showMeetingCountdown)
                // Without full Calendar access the countdown has no events and silently shows nothing.
                if state.showMeetingCountdown && permissions.status(.calendars) != .granted {
                    HStack {
                        Label("Needs full Calendar access to find your meetings.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(DS.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Allow…") { permissions.request(.calendars) }.controlSize(.small)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                SettingsDivider()
                SettingsToggleRow("Downloads in progress", isOn: $state.showDownloadActivity)
            }
        }
    }
}

// MARK: - Thumbnails

/// A HUD in the notch or island style, as the External displays cards show it.
private struct HUDStyleThumbnail: View {
    let style: IslandStyle

    var body: some View {
        VStack(spacing: 0) {
            if style == .notchAttached {
                NotchWithEarsShape(cornerRadius: 9, earRadius: 6)
                    .fill(Color.black)
                    .frame(width: 150, height: 28)
                    .overlay(meter.padding(.horizontal, 20).padding(.bottom, 2))
            } else {
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .frame(width: 150, height: 28)
                    .overlay(meter.padding(.horizontal, 14))
                    .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
    }

    private var meter: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(Color.yellow).frame(width: geo.size.width * 0.3)
                }
            }
            .frame(height: 4)
        }
    }
}

/// A miniature resting HUD for the System and Droplets cards: a black pill
/// with a leading icon, then a meter, a label, text or chips.
private struct MiniHUD: View {
    var icon: String?
    var iconTint: Color = .white
    var iconScale: CGFloat = 1
    var level: Double?
    var tint: Color = .white
    var label: String?
    var trailing: String?
    var trailingIcon: String?
    var trailingTint: Color = .white
    var chips: [String] = []

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11 * iconScale, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            if let level {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(tint).frame(width: max(geo.size.width * level, 4))
                    }
                }
                .frame(height: 4)
            }
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            if level == nil { Spacer(minLength: 2) }
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(chip == chips.last ? Color.accentColor : .white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(trailingTint)
                    .lineLimit(1)
            }
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trailingTint)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
