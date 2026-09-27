import AVFoundation
import SwiftUI

// Droplet detail options for TermiNotch, Meetings, Notification HUD, Agents
// and Notchface (Settings › Droplets › the droplet's page). Anchors are
// "droplet.<id>.<option>", indexed in SettingsSearch.

// InfoToggle is shared with ToolsDropletSettings.swift.

/// "Show … as a floating button": the droplet as one of the round buttons
/// beside the navigation bar (Settings › Shelf › Favorites holds up to four).
@MainActor
private func floatingButton(_ id: String) -> Binding<Bool> {
    let state = AppState.shared
    let favorite = ShelfFavorite(kind: .droplet, value: id)
    return Binding(
        get: { state.shelfFavorites.contains(favorite) },
        set: { on in
            var list = state.shelfFavorites.filter { $0 != favorite }
            if on {
                if list.count >= ShelfFavorite.limit { list.removeLast() }
                list.append(favorite)
            }
            state.shelfFavorites = list
        }
    )
}

// MARK: - TermiNotch

struct TermiNotchDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            Picker(selection: $state.termiNotchTerminalApp) {
                ForEach(TerminalApp.allCases) { app in
                    Text(app.isInstalled ? app.title : "\(app.title) (not installed)").tag(app)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Open in Terminal")
                    InfoButton("Choose which app opens when you use \u{201C}Open in Terminal\u{201D} (↗). It opens in the folder the TermiNotch shell is in.")
                }
            }
            .settingsAnchor("droplet.termiNotch.app")
            InfoToggle("Show TermiNotch bar",
                       info: "Open TermiNotch as the quick command bar — one line to type a command over its last output — instead of the expanded full-shelf terminal. Switch any time with the buttons in TermiNotch.",
                       isOn: $state.termiNotchQuickBar)
                .settingsAnchor("droplet.termiNotch.bar")
            InfoToggle("Tama prompt",
                       info: "zsh shows user@host ~ and a green $ after running your own .zshrc. Turn off to keep your own prompt. Applies to new tabs.",
                       isOn: $state.termiNotchDroppyPrompt)
                .settingsAnchor("droplet.termiNotch.prompt")
            LabeledContent("Text size") {
                Stepper("\(Int(state.termiNotchFontSize)) pt", value: $state.termiNotchFontSize, in: 9...18, step: 1)
            }
            .settingsAnchor("droplet.termiNotch.fontSize")
            Toggle("Show TermiNotch as a floating button", isOn: floatingButton("termiNotch"))
                .settingsAnchor("droplet.termiNotch.floating")
        } header: {
            Text("TermiNotch")
        } footer: {
            Text("A real login shell on a pseudo-terminal: colors, Ctrl-C, vim and top work, and it keeps running while the shelf is closed. ⌘T new tab, ⌘W close tab, ⌘K clear, ⌘C/⌘V copy and paste.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Meetings

struct MeetingsDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var meetings = MeetingControlService.shared

    private var stateLine: String {
        switch meetings.callState {
        case .sleeping: "Sleeping until a supported meeting app launches."
        case .watching: "Watching for meetings…"
        case let .inCall(appID, _): "In a call (\(MeetingApp.all.first { $0.id == appID }?.name ?? "call"))."
        }
    }

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(stateLine).foregroundStyle(.secondary)
            }
            InfoToggle("Show active call HUD",
                       info: "While a call is on: a green phone, the elapsed time and your live microphone level in the notch. Click it for the call controls.",
                       isOn: $state.meetingCallHUD)
                .settingsAnchor("droplet.meetings.callHUD")
            InfoToggle("Live mic level",
                       info: "Moves the bars with your voice. Uses the microphone only during a call and only once Tama has Microphone access; nothing is recorded. Needs macOS 14.2 or later.",
                       isOn: $state.meetingMicLevel)
                .settingsAnchor("droplet.meetings.micLevel")
                .disabled(!state.meetingCallHUD)
            if state.meetingCallHUD, state.meetingMicLevel, !MicLevelMeter.isAuthorized {
                HStack {
                    Text("Microphone access is needed for the level.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow") { PermissionService.shared.request(.microphone) }
                }
            }
        } header: {
            Text("Meetings")
        } footer: {
            Text("Detecting meetings in Zoom, Google Meet, Teams, Webex, Slack, WhatsApp and FaceTime: a call is an app from that list using the microphone.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            InfoToggle("Pause media during meetings",
                       info: "Pauses music when a meeting starts.",
                       isOn: $state.meetingPauseMedia)
                .settingsAnchor("droplet.meetings.pause")
            Picker("Pause", selection: $state.meetingPauseTrigger) {
                ForEach(MeetingPauseTrigger.allCases) { Text($0.title).tag($0) }
            }
            .settingsAnchor("droplet.meetings.pauseTrigger")
            .disabled(!state.meetingPauseMedia)
            if state.meetingPauseTrigger == .micUnmuted {
                Text("Pauses media when mic is unmuted, and plays it again when you mute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Resume media after meeting", isOn: $state.meetingResumeMedia)
                .settingsAnchor("droplet.meetings.resume")
                .disabled(!state.meetingPauseMedia)
        } header: {
            Text("Media")
        }
    }
}

// MARK: - Notification HUD

struct NotificationHUDDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var service = NotificationHUDService.shared

    private static let durations: [(Double, String)] = [(3, "3 seconds"), (5, "5 seconds"), (8, "8 seconds"), (12, "12 seconds"), (20, "20 seconds")]

    /// Apps you've seen notifications from, plus the ones already hidden.
    private var knownApps: [String] {
        Array(Set(service.recent.map(\.bundleID)).union(service.blockedApps)).sorted {
            NotificationHUDService.appName(for: $0).localizedCaseInsensitiveCompare(NotificationHUDService.appName(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            LabeledContent("Notification store") {
                switch service.status {
                case .watching: Label("Reading", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .checking: Text("Checking the macOS notification store…").foregroundStyle(.secondary)
                case .needsFullDiskAccess:
                    Button("Open Full Disk Access") { service.openFullDiskAccessSettings() }
                case .notFound: Text("Not found on this macOS").foregroundStyle(.secondary)
                case .unsupported: Text("Store format not recognized").foregroundStyle(.orange)
                case .off: Text("Off — turn the droplet on").foregroundStyle(.secondary)
                }
            }
            .settingsAnchor("droplet.notifications.access")
            if service.status == .needsFullDiskAccess {
                Text("Required to read notifications. Turn on Tama in System Settings › Privacy & Security › Full Disk Access (add it with + if it isn't listed), then come back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(selection: $state.notificationHUDDuration) {
                ForEach(Self.durations, id: \.0) { Text($0.1).tag($0.0) }
            } label: {
                HStack(spacing: 6) {
                    Text("Show for")
                    InfoButton("How long a notification stays visible in the notch. Hovering keeps it up.")
                }
            }
            .settingsAnchor("droplet.notifications.duration")
            InfoToggle("App icon and notification preview",
                       info: "Show the title and text. Off, the notch only says which app has a new notification.",
                       isOn: $state.notificationHUDPreview)
                .settingsAnchor("droplet.notifications.preview")
            InfoToggle("Burst notifications",
                       info: "Three or more arriving together fold into one summary instead of queueing one by one.",
                       isOn: $state.notificationHUDBurst)
                .settingsAnchor("droplet.notifications.burst")
            InfoToggle("Show filter choices",
                       info: "Shows filter choices above the notifications in the widget.",
                       isOn: $state.notificationHUDShowFilters)
                .settingsAnchor("droplet.notifications.filters")
            Toggle("Show Notifications as a floating button", isOn: floatingButton("notifications"))
                .settingsAnchor("droplet.notifications.floating")
        } header: {
            Text("Notification HUD")
        } footer: {
            Text("Surface incoming notifications in the notch. Recent notifications are kept in memory only and forgotten when Tama quits.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            InfoToggle("Quick reply",
                       info: "Quick reply for supported messaging apps. iMessage/SMS replies are sent through Messages (it asks once for permission to control Messages). WhatsApp and Telegram can't be sent to by other apps: your reply is copied and the app opens.",
                       isOn: $state.notificationHUDQuickReply)
                .settingsAnchor("droplet.notifications.reply")
            Toggle("Auto-hide after replying", isOn: $state.notificationHUDHideAfterReply)
                .settingsAnchor("droplet.notifications.hideAfterReply")
                .disabled(!state.notificationHUDQuickReply)
        } header: {
            Text("Reply")
        }

        Section {
            if knownApps.isEmpty {
                Text("Apps appear here once they've sent a notification.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(knownApps, id: \.self) { bundleID in
                Toggle(isOn: Binding(get: { !service.blockedApps.contains(bundleID) },
                                     set: { service.setBlocked(bundleID, !$0) })) {
                    HStack(spacing: 8) {
                        if let icon = AppIcon.image(bundleID: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(NotificationHUDService.appName(for: bundleID))
                    }
                }
            }
            Button("Hide an App…") { addApp() }
        } header: {
            Text("Apps")
        } footer: {
            Text("Per-app notification filtering: switch an app off to not show its notifications in the notch. Hide an App… adds one that hasn't sent anything yet, already switched off.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .settingsAnchor("droplet.notifications.apps")

        Section {
            LabeledContent("Hide native banners") {
                Button("Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .settingsAnchor("droplet.notifications.native")
            Text("Tama can't switch macOS's own banners off for you — doing that means editing another app's private settings. To see notifications only in the notch, set an app's alert style to None in System Settings › Notifications; macOS still records them, so Tama still shows them.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("System banners")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Hide Notifications"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        service.setBlocked(bundleID, true)
    }
}

// MARK: - Agents

struct AgentsDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var agents = AgentActivityService.shared
    @State private var confirmsRemoveHooks = false

    var body: some View {
        Section {
            Toggle(isOn: $state.agentsClaude) { Label("Claude Code", systemImage: AgentKind.claude.symbol) }
                .settingsAnchor("droplet.agents.claude")
            LabeledContent("Claude Code hooks") {
                if agents.claudeHooksInstalled {
                    HStack {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Remove…") { confirmsRemoveHooks = true }
                    }
                } else {
                    Button("Install Hooks…") { agents.installClaudeHooks() }
                }
            }
            .settingsAnchor("droplet.agents.hooks")
            .disabled(!state.agentsClaude)
            .confirmationDialog("Remove Tama's Claude Code hooks?", isPresented: $confirmsRemoveHooks) {
                Button("Remove Hooks", role: .destructive) { agents.removeClaudeHooks() }
            } message: {
                Text("Tama's entries come out of ~/.claude/settings.json and Claude Code stops reporting to the notch. Your other settings are left as they are.")
            }
            Toggle(isOn: $state.agentsCodex) { Label("Codex", systemImage: AgentKind.codex.symbol) }
                .settingsAnchor("droplet.agents.codex")
            Toggle(isOn: $state.agentsCursor) { Label("Cursor", systemImage: AgentKind.cursor.symbol) }
                .settingsAnchor("droplet.agents.cursor")
            if let error = agents.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Claude Code reports through hooks Tama adds to ~/.claude/settings.json only when you click Install (you see the exact change first, and a backup is kept). Codex is read from its session logs in ~/.codex/sessions. Cursor's newest chat title and whether it's generating are read from its local database — Cursor doesn't publish more, so that part is best effort.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            InfoToggle("Show in the notch",
                       info: "The working agent's glyph and a spinner in the resting notch.",
                       isOn: $state.agentsShowInNotch)
                .settingsAnchor("droplet.agents.notch")
            InfoToggle("Tell me when it's done",
                       info: "A banner when an agent finishes, stops, or waits for you (Background task completed / failed).",
                       isOn: $state.agentsNotifyDone)
                .settingsAnchor("droplet.agents.done")
        } header: {
            Text("Notch")
        }
        .onAppear { agents.refreshHookStatus() }
    }
}

// MARK: - Notchface

struct NotchfaceDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var camera = NotchfaceCamera.shared

    var body: some View {
        Section {
            Picker(selection: $state.notchfaceCamera) {
                Text("System default").tag("")
                ForEach(camera.cameras) { Text($0.name).tag($0.id) }
            } label: {
                HStack(spacing: 6) {
                    Text("Camera")
                    InfoButton("Choose which connected camera to use.")
                }
            }
            .settingsAnchor("droplet.notchface.camera")
            Toggle("Mirror the preview", isOn: $state.notchfaceMirror)
                .settingsAnchor("droplet.notchface.mirror")
            LabeledContent("Camera access") {
                switch camera.access {
                case .granted: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .notDetermined: Button("Allow…") { camera.requestAccess() }
                case .denied: Button("Open Camera Settings") { camera.openCameraSettings() }
                case .restricted: Text("Restricted on this Mac").foregroundStyle(.secondary)
                }
            }
            .settingsAnchor("droplet.notchface.access")
            Toggle("Show Notchface as a floating button", isOn: floatingButton("notchface"))
                .settingsAnchor("droplet.notchface.floating")
        } header: {
            Text("Notchface")
        } footer: {
            Text("Camera stays off until you start it, and turns off when the shelf closes. Nothing is recorded.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            camera.refreshAccess()
            camera.refreshCameras()
        }
    }
}
