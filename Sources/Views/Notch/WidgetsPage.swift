import SwiftUI

/// "Build your own shelf of widgets": the enabled Droplets as a row of app-like
/// icons. Opening one swaps the row for that Droplet's console, in place.
public struct WidgetsPage: View {
    // High Alert isn't observed here: AppState forwards its on/off flips, and
    // the service's once-a-second countdown would redraw this whole view.
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var timerUpdates = TimerService.shared
    @ObservedObject private var pomodoroClock = PomodoroClock.shared
    @ObservedObject private var meetingUpdates = MeetingControlService.shared
    @ObservedObject private var liquidMouseUpdates = LiquidMouseService.shared
    @ObservedObject private var agentUpdates = AgentActivityService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var enabled: [DropletModel] { state.droplets.filter(\.isEnabled) }

    public var body: some View {
        ZStack {
            if let id = state.activeDropletID {
                console(for: id)
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            } else if state.isRearrangingWidgets {
                rearrangeGrid
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            } else {
                row
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.activeDropletID)
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.isRearrangingWidgets)
    }

    // MARK: Rearrange

    /// Every widget in a grid; drag one to a new spot. The order is the one
    /// the widget row and Settings › Shelf › Widget icons show.
    private var rearrangeGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "hand.draw")
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityHidden(true)
                Text("Drag widgets to rearrange")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                DroppyPillButton("Done", tone: .accent, help: "Done (↩)") { state.endRearrangingWidgets() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            .frame(height: DroppyShelfMetrics.widgetsGridHeader - DS.Space.sm)
            .padding(.bottom, DS.Space.sm)
            if enabled.isEmpty {
                // Reachable from the island's menu with every widget off.
                DroppyEmptyState(systemName: "square.grid.2x2", title: "No widgets to rearrange", compact: true)
            } else {
                ReorderableIconGrid(ids: enabled.map(\.id), columns: DroppyShelfMetrics.widgetsGridColumns,
                                    cellSize: DroppyShelfMetrics.widgetsGridCell,
                                    onReorder: { state.reorderWidgets($0) }) { id in
                    if let droplet = enabled.first(where: { $0.id == id }) {
                        VStack(spacing: 5) {
                            DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 44)
                                .accessibilityHidden(true)
                            Text(droplet.name)
                                .font(DS.Typo.caption.weight(.semibold))
                                .foregroundStyle(DS.Palette.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: DroppyShelfMetrics.widgetsGridCell.width - DS.Space.xs)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }

    /// Round buttons a console puts beside the navigation bar: ✕ closes a
    /// timer-like widget back to the row.
    private func consoleAccessories(_ id: String) -> [ShelfAccessory] {
        guard ["pomodoro", "timer", "caffeine", "systemStats", "calculator", "colorPicker"].contains(id) else { return [] }
        return [ShelfAccessory(id: "widgets.close.\(id)", icon: "xmark", help: "Back to widgets", page: .widgets, dropletID: id) {
            DroppyAudio.playTick()
            AppState.shared.activeDropletID = nil
        }]
    }

    // MARK: Row

    @ViewBuilder
    private var row: some View {
        if enabled.isEmpty {
            VStack(spacing: DS.Space.sm) {
                DroppyEmptyState(systemName: "square.grid.2x2", title: "No widgets yet", compact: true)
                DroppyPillButton("Turn on Droplets in Settings", systemName: "gearshape",
                                 help: "Open Settings › Droplets") {
                    SettingsWindowController.shared.showWindow()
                    // Straight to the Droplets pane the button names, as the Weather console does.
                    SettingsNavigator.shared.open(.droplets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WidgetPager(droplets: enabled, badge: badge(for:)) { droplet in
                DroppyAudio.playTick()
                state.activeDropletID = droplet.id
            }
        }
    }

    private func badge(for droplet: DropletModel) -> String? {
        switch droplet.id {
        case "pomodoro": return state.isPomodoroActive ? state.formattedPomodoroTime : nil
        case "timer": return TimerService.shared.isRunning ? TimerService.format(TimerService.shared.displaySeconds, compact: true) : nil
        case "caffeine": return state.sleepBlocker.isAwakeActive ? "ON" : nil
        case "meetings":
            if MeetingControlService.shared.isMicMuted { return "MUTED" }
            return MeetingControlService.shared.callState.isInCall ? "CALL" : nil
        case "liquidMouse": return LiquidMouseService.shared.isActive ? "ON" : nil
        case "weather": return WeatherService.shared.snapshot?.bareTemperatureText
        case "agents":
            return AgentActivityService.shared.sessions.contains { $0.activity.isWorking } ? "LIVE" : nil
        case "notchface": return NotchfaceCamera.shared.isRunning ? "ON" : nil
        case "voiceTranscribe": return VoiceTranscribeService.shared.phase == .recording ? "REC" : nil
        case "menuBar": return MenuBarManagerService.shared.isRevealed ? "SHOWN" : nil
        case "localSend":
            if LocalSendService.shared.incoming != nil { return "NEW" }
            return LocalSendService.shared.receiving != nil ? "IN" : nil
        case "notifications":
            let count = NotificationHUDService.shared.recent.count
            return count > 0 ? "\(min(count, 99))" : nil
        case "appleMusic":
            let track = MediaService.shared.currentTrack
            return track.isPlaying && track.sourceBundleID == "com.apple.Music" ? "♪" : nil
        default: return nil
        }
    }

    // MARK: Console

    private func console(for id: String) -> some View {
        VStack(spacing: DS.Space.md) {
            // Pomodoro, High Alert and the Timer are short and headerless, like
            // the reference; the ✕ beside the navigation bar closes them.
            if !DroppyShelfMetrics.headerlessConsoles.contains(id) {
            HStack(spacing: DS.Space.md) {
                NotchCircleButton("chevron.left", size: 26, iconSize: 11, help: "Back to widgets") {
                    DroppyAudio.playTick()
                    state.activeDropletID = nil
                }
                let title = state.droplets.first(where: { $0.id == id })?.name ?? "Droplet"
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .help(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            }
            // Consoles that scroll themselves would fight an outer scroll view.
            if Self.selfScrolling.contains(id) {
                dropletBody(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    dropletBody(id)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .shelfAccessories("widgets.console", consoleAccessories(id))
    }

    private static let selfScrolling: Set<String> = ["scratchpad", "termiNotch", "thunderstorm", "obsidian", "pomodoro", "caffeine", "timer", "voiceTranscribe",
                                                      "notifications", "agents", "notchface"]

    @ViewBuilder
    private func dropletBody(_ id: String) -> some View {
        // A shortcut or ring action can name a Droplet the user has turned off.
        if state.droplets.contains(where: { $0.id == id && !$0.isEnabled }) {
            DroppyEmptyState(systemName: "drop", title: "This Droplet is turned off",
                             subtitle: "Turn it on in Settings to use it here.")
        } else {
            enabledDropletBody(id)
        }
    }

    @ViewBuilder
    private func enabledDropletBody(_ id: String) -> some View {
        switch id {
        case "pomodoro": PomodoroConsoleView()
        case "timer": TimerConsoleView()
        case "calculator": QuickMathConsoleView()
        case "scratchpad": ScratchpadConsoleView()
        case "caffeine": HighAlertConsoleView()
        case "systemStats": SystemStatsConsoleView()
        case "snipper": ScreenSnipperConsoleView()
        case "aiCutout": AICutoutConsoleView()
        case "colorPicker": ColorPickerConsoleView()
        case "converter": QuickConvertConsoleView()
        case "windowSnapper": WindowSnapperConsoleView()
        case "termiNotch": TermiNotchConsoleView()
        case "thunderstorm": ThunderstormConsoleView()
        case "ring": RingConsoleView()
        case "ocr": OCRConsoleView()
        case "voiceTranscribe": VoiceTranscribeConsoleView()
        case "audioControl": AudioControlConsoleView()
        case "obsidian": ObsidianConsoleView()
        case "mechey": MecheyConsoleView()
        case "liquidMouse": LiquidMouseConsoleView()
        case "meetings": MeetingsConsoleView()
        case "appleMusic": AppleMusicConsoleView()
        case "weather": WeatherConsoleView()
        case "notifications": NotificationHUDConsoleView()
        case "agents": AgentsConsoleView()
        case "notchface": NotchfaceConsoleView()
        case "menuBar": MenuBarManagerConsoleView()
        case "localSend": LocalSendConsoleView()
        default:
            DroppyEmptyState(systemName: "questionmark.square.dashed", title: "This Droplet isn't available",
                             subtitle: "It may have been removed in this version of Tama.")
        }
    }
}

// MARK: - Icon

/// A Droplet drawn like an app icon: a tinted squircle with a white glyph and
/// its name underneath. Pressing squishes it, the way Tama's widgets do.
public struct WidgetIcon: View {
    public let droplet: DropletModel
    public var badge: String?
    public let action: () -> Void

    @State private var isHovered = false

    public init(droplet: DropletModel, badge: String? = nil, action: @escaping () -> Void) {
        self.droplet = droplet
        self.badge = badge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 56)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white))
                            .fixedSize()
                            .offset(x: 8, y: -6)
                            .accessibilityHidden(true)
                    }
                }

                Text(droplet.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(width: 74)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.87))
        .brightness(isHovered ? 0.06 : 0)
        .onHover { isHovered = $0 }
        .help(droplet.summary)
        // The name, not the name run together with the badge ("Timer 4:59").
        .accessibilityLabel(droplet.name)
        .accessibilityValue(badge ?? "")
        .accessibilityHint(droplet.summary)
    }
}

/// A droplet's icon: the matching Apple app's own icon when that app is on
/// this Mac (read at run time, never bundled), otherwise a tinted tile with
/// the droplet's symbol. Used by the Widgets page, the Home picker and Settings.
public struct DropletIcon: View {
    public let id: String
    public let symbol: String
    public var size: CGFloat

    public init(id: String, symbol: String, size: CGFloat) {
        self.id = id
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        if let icon = AppIcon.image(bundleID: DropletPalette.appBundleID(for: id)) {
            // macOS icons carry their own margin; draw them a little larger so
            // they sit the same size as the symbol tiles beside them.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.2, height: size * 1.2)
                .frame(width: size, height: size)
        } else {
            let tint = DropletPalette.tint(for: id)
            let shape = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .frame(width: size, height: size)
        }
    }
}

public enum DropletPalette {
    /// The Apple app a droplet stands in for, whose icon it borrows.
    public static func appBundleID(for id: String) -> String? {
        switch id {
        case "pomodoro": "com.apple.clock"
        case "systemStats": "com.apple.ActivityMonitor"
        case "meetings": "com.apple.FaceTime"
        case "calculator": "com.apple.calculator"
        case "scratchpad": "com.apple.Stickies"
        case "voiceTranscribe": "com.apple.VoiceMemos"
        case "snipper": "com.apple.screenshot.launcher"
        case "colorPicker": "com.apple.DigitalColorMeter"
        case "termiNotch": "com.apple.Terminal"
        case "obsidian": "md.obsidian"
        case "appleMusic": "com.apple.Music"
        case "weather": "com.apple.weather"
        default: nil
        }
    }

    public static func tint(for id: String) -> Color {
        switch id {
        case "pomodoro": return Color(red: 0.96, green: 0.33, blue: 0.36)
        case "timer": return Color(red: 0.99, green: 0.62, blue: 0.16)
        case "calculator": return Color(red: 0.19, green: 0.72, blue: 0.45)
        case "scratchpad": return Color(red: 0.98, green: 0.72, blue: 0.19)
        case "caffeine": return Color(red: 0.98, green: 0.52, blue: 0.20)
        case "systemStats": return Color(red: 0.31, green: 0.56, blue: 0.99)
        case "snipper": return Color(red: 0.93, green: 0.36, blue: 0.62)
        case "aiCutout": return Color(red: 0.62, green: 0.40, blue: 0.98)
        case "colorPicker": return Color(red: 0.18, green: 0.72, blue: 0.74)
        case "converter": return Color(red: 0.24, green: 0.46, blue: 0.90)
        case "windowSnapper": return Color(red: 0.22, green: 0.68, blue: 0.95)
        case "termiNotch": return Color(red: 0.28, green: 0.28, blue: 0.32)
        case "thunderstorm": return Color(red: 0.99, green: 0.78, blue: 0.14)
        case "ring": return Color(red: 0.45, green: 0.36, blue: 0.96)
        case "ocr": return Color(red: 0.20, green: 0.66, blue: 0.62)
        case "voiceTranscribe": return Color(red: 0.95, green: 0.27, blue: 0.40)
        case "audioControl": return Color(red: 0.36, green: 0.60, blue: 0.98)
        case "obsidian": return Color(red: 0.49, green: 0.33, blue: 0.87)
        case "mechey": return Color(red: 0.40, green: 0.42, blue: 0.48)
        case "liquidMouse": return Color(red: 0.36, green: 0.78, blue: 0.95)
        case "meetings": return Color(red: 0.20, green: 0.74, blue: 0.42)
        case "appleMusic": return Color(red: 0.98, green: 0.26, blue: 0.38)
        case "weather": return Color(red: 0.25, green: 0.58, blue: 0.98)
        case "notifications": return Color(red: 0.96, green: 0.30, blue: 0.30)
        case "agents": return Color(red: 0.84, green: 0.48, blue: 0.34)
        case "notchface": return Color(red: 0.30, green: 0.36, blue: 0.46)
        case "menuBar": return Color(red: 0.42, green: 0.45, blue: 0.52)
        case "localSend": return LocalSendConsoleView.tint
        default: return Color(red: 0.36, green: 0.50, blue: 0.83)
        }
    }
}
