import SwiftUI

// MARK: - Clipboard

/// Settings › Clipboard, in the reference's order: the manager and where it
/// appears, its appearance (Alpha or Legacy, type filters, a live preview),
/// shortcuts and history rules, clipboard actions, then excluded apps.
struct ClipboardSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var clipboardSettings = ClipboardSettings.shared
    @ObservedObject private var privacy = ClipboardPrivacy.shared
    @ObservedObject private var permissions = PermissionService.shared
    @State private var imageBytes: Int64?
    /// The history-limit slider's stop while dragging; applied on release,
    /// so dragging down doesn't trim (and toast) at every notch.
    @State private var limitIndex: Double = 2
    @State private var isDraggingLimit = false
    @State private var isConfirmingClear = false

    private static let imageLimits = [100, 250, 500, 1000, 2000]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Clipboard") {
                SettingsGroup {
                    SettingsToggleRow("Clipboard manager", icon: "list.clipboard.fill",
                                      help: "Keeps a history of what you copy. The tiles below choose where the clipboard is offered: the menu bar and the shelf's right-click menu.",
                                      anchor: "clipboard.enable", isOn: $clipboardSettings.isEnabled)
                    ToggleTiles([
                        ToggleTile("Menu bar", icon: "menubar.rectangle", isOn: $clipboardSettings.inMenuBar),
                        ToggleTile("Shelf right-click menu", icon: "list.bullet.rectangle", isOn: $clipboardSettings.inShelfMenu),
                    ], anchor: "clipboard.locations")
                    .settingsDisabled(!clipboardSettings.isEnabled)
                    if clipboardSettings.isEnabled {
                        SettingsDivider()
                        SettingsRow(privacy.pauseDescription,
                                    icon: privacy.isPaused ? "pause.circle.fill" : "record.circle",
                                    help: "While paused, nothing you copy is saved. Timed pauses resume on their own.",
                                    anchor: "clipboard.recording") {
                            if privacy.isPaused {
                                Button("Resume") { privacy.resume() }
                            } else {
                                Menu("Pause") {
                                    ForEach(ClipboardPauseDuration.allCases) { duration in
                                        Button(duration.title) { privacy.pause(duration) }
                                    }
                                }
                                .fixedSize()
                            }
                        }
                        SettingsDivider()
                        SettingsRow("Show the clipboard now") {
                            Button("Open Clipboard") { state.showClipboard() }
                        }
                    } else {
                        SettingsNote("Clipboard is off: nothing you copy is recorded, and its shortcut points here.",
                                     icon: "info.circle")
                            .padding(.top, 10)
                        // Turning the clipboard off keeps the saved history,
                        // so it must still be clearable from here.
                        SettingsDivider()
                        clearHistoryRow
                    }
                }
            }

            Group {
                appearance
                shortcuts
                filtering
            }
            .settingsDisabled(!clipboardSettings.isEnabled)
        }
        .task { imageBytes = await AppState.clipboardImageStorageBytes() }
        .onAppear {
            limitIndex = Double(ClipboardHistoryLimit.index(of: clipboardSettings.historyLimit))
            permissions.refresh()
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        SettingsSection("Clipboard appearance") {
            SettingsGroup {
                SettingsRow("Clipboard layout",
                            help: "Choose between the regular clipboard window and the compact clipboard layout. Alpha docks a strip of cards at the bottom of the screen; Legacy is a list with a preview pane.",
                            anchor: "clipboard.layout")
                ChoiceTiles([
                    .init(ClipboardLayout.alpha, "Alpha clipboard", icon: "rectangle.stack.fill"),
                    .init(ClipboardLayout.legacy, "Legacy clipboard", icon: "list.bullet.rectangle.fill"),
                ], selection: $clipboardSettings.layout)
                SettingsDivider()
                SettingsToggleRow("Type filters", help: "Show the type-filter rail (All, Favorites, Text, Images, Links, Colors, Files).",
                                  anchor: "clipboard.typeFilters", isOn: $clipboardSettings.typeFilters)
                SettingsDivider()
                SettingsToggleRow("Favorites bar",
                                  subtitle: clipboardSettings.layout == .alpha
                                      ? "Starred clips get a strip of chips above the cards."
                                      : "Only in the Alpha clipboard layout.",
                                  help: "Every favorite, one click away whatever the search or the pinboard tab is showing. A chip pastes its clip; its menu can take the favorite off the bar.",
                                  anchor: "clipboard.favoritesBar", isOn: $clipboardSettings.favoritesBar)
                    .settingsDisabled(clipboardSettings.layout != .alpha)
                SettingsDivider()
                SettingsRow(clipboardSettings.layout == .alpha ? "Alpha preview" : "Legacy preview",
                            help: "How the clipboard looks with these settings.")
                ClipboardLayoutPreview(layout: clipboardSettings.layout, showsFilters: clipboardSettings.typeFilters)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(clipboardSettings.layout == .alpha ? "Preview of the Alpha clipboard" : "Preview of the Legacy clipboard")
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding([.horizontal, .bottom], 12)
            }
        }
    }

    // MARK: Shortcuts & history

    private var shortcuts: some View {
        SettingsSection("Shortcuts") {
            SettingsGroup {
                ShortcutRecorderRow(.toggleClipboard, title: "Open shortcut",
                                    help: "Open clipboard history from anywhere.", anchor: "clipboard.shortcut")
                SettingsDivider()
                ShortcutRecorderRow(.pasteFromClipboard, title: "Paste shortcut",
                                    help: "Opens the clipboard ready to paste: the clip you pick goes straight into the app you came from, even with \u{201C}Paste into the previous app\u{201D} off. Pasting needs Accessibility access.",
                                    anchor: "clipboard.pasteShortcut")
                SettingsDivider()
                historyLimit
                SettingsDivider()
                SettingsRow("Keep history for", anchor: "clipboard.retention") {
                    Picker("Keep history for", selection: $privacy.retention) {
                        ForEach(ClipboardRetention.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsDivider()
                SettingsRow("Image storage limit") {
                    Picker("Image storage limit", selection: $privacy.imageLimitMB) {
                        ForEach(Self.imageLimits, id: \.self) { mb in
                            Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsNote(storageCaption)
                SettingsDivider()
                SettingsToggleRow("Skip passwords",
                                  help: "Passwords, card numbers, private keys, AWS keys, GitHub tokens and access tokens (JWTs) aren't saved. One-time codes are kept. Copies marked concealed by password managers are always ignored.",
                                  anchor: "clipboard.privacy", isOn: $privacy.filterSensitive)
                SettingsDivider()
                SettingsToggleRow("Blur sensitive content",
                                  subtitle: privacy.filterSensitive ? "Applies when Skip passwords is off." : nil,
                                  help: "Keep passwords and keys in history, but blurred until you point at them. Blurred clips are always pasted as plain text.",
                                  anchor: "clipboard.blur", isOn: $privacy.blurSensitive)
                    .settingsDisabled(privacy.filterSensitive)
                SettingsDivider()
                SettingsToggleRow("Clear history on quit",
                                  help: "Clears the history when Tama quits. Pinned items never expire from history.",
                                  anchor: "clipboard.clearOnQuit", isOn: $clipboardSettings.clearOnQuit)
                SettingsDivider()
                SettingsToggleRow("Reject duplicates",
                                  help: "Ignore a copy that's already in history. Off, copying it again moves the existing clip back to the front.",
                                  anchor: "clipboard.duplicates", isOn: $clipboardSettings.rejectDuplicates)
                SettingsDivider()
                SettingsToggleRow("Paste into the previous app",
                                  help: "Picking a clip pastes it into the app you were in. Off, it's only copied. ⌥↩ or ⇧↩ pastes as plain text.",
                                  anchor: "clipboard.pasteIntoApp", isOn: $clipboardSettings.pasteIntoApp)
                if clipboardSettings.pasteIntoApp {
                    SettingsDivider()
                    PermissionRow(kind: .accessibility, status: permissions.status(.accessibility))
                        .settingsAnchor("clipboard.accessibility")
                    SettingsNote("Pasting into another app needs Accessibility access. Grant it here if picking a clip doesn't paste.")
                }
                SettingsDivider()
                SettingsRow("Clipboard actions",
                            help: "Tags: assign any number of tags to clips and filter by them. Copy + favorite: copy a clip and star it in one go. Auto-focus: focus the search bar automatically when the clipboard opens.",
                            anchor: "clipboard.actions")
                ToggleTiles([
                    ToggleTile("Tags", icon: "tag.fill", isOn: $clipboardSettings.tagsEnabled),
                    ToggleTile("Copy + favorite", icon: "star.fill", isOn: $clipboardSettings.copyFavorite),
                    ToggleTile("Auto-focus", icon: "magnifyingglass", isOn: $clipboardSettings.autoFocusSearch),
                ])
                if clipboardSettings.tagsEnabled {
                    tagsRow
                }
                SettingsDivider()
                clearHistoryRow
            }
        }
    }

    private var clearHistoryRow: some View {
        SettingsRow("Clear history", subtitle: "Removes every clip that isn't starred or on a pinboard.",
                    anchor: "clipboard.clear") {
            Button("Clear…", role: .destructive) { isConfirmingClear = true }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { state.clearClipboardWithUndo() }
        } message: {
            Text("Every clip that isn't starred or on a pinboard is removed. You can undo this from the banner that appears.")
        }
    }

    /// "13 of 50 items saved" over a dotted slider of stops.
    private var historyLimit: some View {
        let steps = ClipboardHistoryLimit.steps
        let shown = steps[min(max(Int(limitIndex.rounded()), 0), steps.count - 1)]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("History limit").font(SettingsStyle.rowTitle)
                InfoButton("Choose how many clipboard items Tama keeps. Pinned items never expire from history.")
                Spacer()
                Text("\(min(state.clipboardHistoryCount, shown)) of \(shown) items saved")
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $limitIndex, in: 0...Double(steps.count - 1), step: 1) { editing in
                isDraggingLimit = editing
                if !editing { commitLimit() }
            }
            .labelsHidden()
            .accessibilityLabel("History limit")
            .accessibilityValue("\(shown) items")
            .onChange(of: limitIndex) { _, _ in if !isDraggingLimit { commitLimit() } }
        }
        .padding(SettingsStyle.rowPadding)
        .settingsAnchor("clipboard.history")
    }

    private func commitLimit() {
        let steps = ClipboardHistoryLimit.steps
        let value = steps[min(max(Int(limitIndex.rounded()), 0), steps.count - 1)]
        if value != clipboardSettings.historyLimit { clipboardSettings.historyLimit = value }
    }

    /// The tags that exist, each removable, plus New Tag…
    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                if state.clipboardTags.isEmpty {
                    chip("No tags yet")
                }
                ForEach(state.clipboardTags) { tag in
                    HStack(spacing: 5) {
                        Circle().fill(tag.color).frame(width: 8, height: 8)
                        Text(tag.name)
                        Button { state.removeClipTag(tag) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete the tag \(tag.name)")
                        .accessibilityLabel("Delete tag \(tag.name)")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                Button { state.promptNewClipTag(for: []) } label: {
                    Label("New Tag…", systemImage: "plus.circle.fill").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .settingsAnchor("clipboard.tags")
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var storageCaption: String {
        let limit = "Oldest unstarred image clips are removed past the limit. Starred and pinboard clips are always kept."
        guard let imageBytes else { return limit }
        let used = ByteCountFormatter.string(fromByteCount: imageBytes, countStyle: .file)
        return "Images use \(used). " + limit
    }

    // MARK: Filtering

    private var filtering: some View {
        SettingsSection("Filtering") {
            SettingsGroup {
                SettingsRow("Excluded apps",
                            help: "Prevent selected apps from appearing in clipboard history. Nothing copied while one of them is in front is saved.",
                            anchor: "clipboard.excluded")
                FlowLayout(spacing: 6) {
                    if privacy.excludedBundleIDs.isEmpty {
                        chip("No apps added")
                    }
                    ForEach(privacy.excludedBundleIDs, id: \.self) { bundleID in
                        let name = ClipboardPrivacy.appName(for: bundleID)
                        HStack(spacing: 6) {
                            if let icon = AppIcon.image(bundleID: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app.dashed")
                            }
                            Text(name)
                            Button { privacy.include(bundleID) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop excluding \(name)")
                            .accessibilityLabel("Remove \(name)")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .help(bundleID)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                SettingsDivider()
                SettingsRow("Add excluded app") {
                    Menu("Running App") {
                        ForEach(privacy.runningAppsToExclude, id: \.bundleID) { app in
                            Button(app.name) { privacy.exclude(app.bundleID) }
                        }
                        Divider()
                        Button("Restore Default Exclusions") {
                            for id in ClipboardPrivacy.defaultExcludedApps { privacy.exclude(id) }
                        }
                    }
                    .fixedSize()
                    Button {
                        privacy.chooseAppToExclude()
                    } label: {
                        Label("Choose App…", systemImage: "plus.circle.fill")
                    }
                    .help("Pick an app in Applications to exclude")
                }
            }
        }
    }
}

// MARK: - Preview

/// A miniature of the chosen layout on the desktop wallpaper, drawn from sample
/// clips (nothing from your real history is shown in Settings).
private struct ClipboardLayoutPreview: View {
    let layout: ClipboardLayout
    let showsFilters: Bool

    private struct Sample {
        let title: String
        let time: String
        let tint: Color?
        let icon: String
        let body: String?
        let chip: String
        let lines: String?
        let starred: Bool
    }

    private let samples = [
        Sample(title: "Screenshot", time: "now", tint: Color(red: 0.55, green: 0.36, blue: 0.2), icon: "safari.fill",
               body: nil, chip: "1728 × 1117", lines: nil, starred: true),
        Sample(title: "Text", time: "2 min ago", tint: nil, icon: "note.text",
               body: "Sent! Thanks for participating in the beta.", chip: "66 characters", lines: "2", starred: false),
        Sample(title: "Work", time: "5 min ago", tint: Color(red: 0.2, green: 0.4, blue: 0.75), icon: "envelope.fill",
               body: "Join the Discord for updates and early builds.", chip: "154 characters", lines: "3", starred: false),
    ]

    var body: some View {
        ZStack {
            PreviewWallpaper()
            if layout == .alpha { alpha } else { legacy }
        }
    }

    private var alpha: some View {
        VStack(spacing: 8) {
            if showsFilters {
                HStack(spacing: 4) {
                    ForEach(ClipFilter.allCases) { filter in
                        Image(systemName: filter.iconName)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(filter == .all ? 1 : 0.55))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(filter == .all ? 0.14 : 0)))
                    }
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                ForEach(samples.indices, id: \.self) { card(samples[$0], selected: $0 == 0) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.85)))
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func card(_ sample: Sample, selected: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sample.title).font(.system(size: 10, weight: .bold))
                    Text(sample.time).font(.system(size: 8)).opacity(0.75)
                }
                Spacer()
                Image(systemName: sample.icon).font(.system(size: 13)).opacity(0.9)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(sample.tint ?? Color.white.opacity(0.08))
            ZStack(alignment: .bottom) {
                if let body = sample.body {
                    Text(body).font(.system(size: 8.5, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(7)
                } else {
                    Image(systemName: "photo").font(.system(size: 18)).opacity(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 3) {
                    if sample.starred { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        Text(sample.chip)
                        if let lines = sample.lines {
                            Image(systemName: "line.3.horizontal")
                            Text(lines)
                        }
                    }
                    .padding(.horizontal, 5).frame(height: 13)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                }
                .font(.system(size: 7.5, weight: .semibold))
                .padding(5)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white, lineWidth: selected ? 1.5 : 0))
    }

    private var legacy: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                Text("Search clipboard")
                Spacer()
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10).frame(height: 22)
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(samples.indices, id: \.self) { index in
                        let sample = samples[index]
                        HStack(spacing: 5) {
                            Image(systemName: sample.icon).font(.system(size: 9))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(sample.body ?? sample.title).font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
                                Text("\(sample.title) · \(sample.time)").font(.system(size: 7)).opacity(0.55)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 6).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(index == 1 ? DS.accent.opacity(0.85) : .clear))
                    }
                    Spacer()
                }
                .padding(4)
                .frame(width: 170)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                Text(samples[1].body ?? "")
                    .font(.system(size: 9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 340, height: 130)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.85)))
    }
}
