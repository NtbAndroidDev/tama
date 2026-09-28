import SwiftUI
import EventKit

/// What can sit on the home page, and how big it is. The ids are Droplet ids,
/// plus `media` for the player.
public enum HomeWidget {
    public static let media = "media"
    /// Today and what's next, from the Calendar page's data. Built in like the
    /// player, so it's offered whether or not any Droplet is switched on.
    public static let calendar = "calendar"
    /// Conditions where the Mac is, from WeatherService; asks for Location.
    public static let weather = "weather"
    /// The Mac's battery and the connected headphones'.
    public static let battery = "battery"
    public static let limit = 2
    /// Droplets with a home card; the rest only have a full console.
    public static let cardDroplets: Set<String> = ["pomodoro", "timer", "caffeine", "systemStats", "meetings", "scratchpad"]

    /// A row of cards; the same height as the full player, so the shelf
    /// doesn't jump when a second widget joins it.
    public static let cardHeight: CGFloat = 150
    /// Room the dashed edit outline takes around a card.
    public static let editInset: CGFloat = 7
    public static let pickerHeight: CGFloat = 62
    public static let pickerSpacing: CGFloat = 12
    public static let editPageHeight: CGFloat = cardHeight + editInset * 2 + pickerSpacing + pickerHeight

    @MainActor static func name(_ id: String) -> String {
        if id == calendar { return "Tasks & Calendar" }
        if id == weather { return "Weather" }
        if id == battery { return "Battery" }
        return id == media ? "Media" : AppState.shared.droplets.first(where: { $0.id == id })?.name ?? id
    }

    @MainActor static func icon(_ id: String) -> String {
        if id == calendar { return "calendar" }
        if id == weather { return "cloud.sun.fill" }
        if id == battery { return "battery.75percent" }
        return id == media ? "music.note" : AppState.shared.droplets.first(where: { $0.id == id })?.iconSystemName ?? "square"
    }

    /// The installed Apple app whose icon stands for a widget in the picker,
    /// read at run time (never bundled). The player shows whichever app is
    /// playing. Widgets without a counterpart keep their symbol tile.
    @MainActor static func appIconBundleID(_ id: String) -> String? {
        switch id {
        case media:
            let track = MediaService.shared.currentTrack
            let playing = track.sourceBundleID.isEmpty ? AppIcon.bundleID(forPlayer: track.sourceApp) : track.sourceBundleID
            return playing ?? "com.apple.Music"
        case calendar: return "com.apple.iCal"
        case weather: return "com.apple.weather"
        default: return DropletPalette.appBundleID(for: id)
        }
    }

    static func tint(_ id: String) -> Color {
        if id == calendar { return Color(red: 0.96, green: 0.30, blue: 0.27) }
        if id == weather { return Color(red: 0.25, green: 0.58, blue: 0.98) }
        if id == battery { return Color(red: 0.20, green: 0.78, blue: 0.40) }
        return id == media ? Color(red: 0.98, green: 0.26, blue: 0.38) : DropletPalette.tint(for: id)
    }
}

/// The home page: the full player on its own, or a row of one or two widget
/// cards. In edit mode each card gets a dashed outline and a remove button,
/// and a picker underneath adds widgets until the change is confirmed.
public struct HomePage: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Group {
            if state.showsFullPlayer {
                PlayerPage()
            } else {
                VStack(spacing: HomeWidget.pickerSpacing) {
                    cards
                    if state.isCustomizingHome {
                        HomeWidgetPicker()
                            .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .bottom))))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: state.visibleHomeWidgets)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: state.isCustomizingHome)
        .onAppear(perform: offerCustomizeTipOnce)
    }

    private static let customizeTipKey = "homeCustomizeTipShown"

    /// The first time Home opens with just the player, point out that it can
    /// hold more. Shown once, ever; it's a hint, not a nag.
    private func offerCustomizeTipOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.customizeTipKey),
              state.homeWidgets == [HomeWidget.media], !state.isCustomizingHome else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let s = AppState.shared
            // Only if they're still looking at Home and nothing else is being said.
            guard s.isIslandExpanded, s.shelfPage == .home, !s.isCustomizingHome,
                  s.activeNotification == nil,
                  !UserDefaults.standard.bool(forKey: Self.customizeTipKey) else { return }
            UserDefaults.standard.set(true, forKey: Self.customizeTipKey)
            s.showNotification(
                appName: "Home",
                title: "Make Home yours",
                message: "Put Calendar, Pomodoro or System Stats next to the player.",
                actionTitle: "Customize"
            ) { AppState.shared.beginCustomizingHome() }
        }
    }

    private var cards: some View {
        let widgets = state.visibleHomeWidgets
        let editing = state.isCustomizingHome
        return HStack(spacing: editing ? DS.Space.lg : 22) {
            if widgets.isEmpty {
                emptySlot
            }
            ForEach(Array(widgets.enumerated()), id: \.element) { index, id in
                if index > 0, !editing {
                    Rectangle()
                        .fill(DS.Palette.hairline)
                        .frame(width: 1)
                        .padding(.vertical, DS.Space.lg)
                }
                slot(id, solo: widgets.count == 1)
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.92))))
            }
        }
        .frame(height: HomeWidget.cardHeight + (editing ? HomeWidget.editInset * 2 : 0))
    }

    @ViewBuilder
    private func slot(_ id: String, solo: Bool) -> some View {
        if state.isCustomizingHome {
            card(id, solo: solo)
                // Like a Home Screen in jiggle mode: the widgets are for arranging now, not using.
                .allowsHitTesting(false)
                .padding(HomeWidget.editInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .overlay(alignment: .topTrailing) {
                    Button { state.toggleHomeWidget(id) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(DS.Palette.danger))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.8))
                    .offset(x: 8, y: -8)
                    .help("Remove \(HomeWidget.name(id))")
                    .accessibilityLabel("Remove \(HomeWidget.name(id))")
                }
        } else if id == HomeWidget.weather, !solo {
            // Beside another widget the weather keeps to a compact card.
            card(id, solo: solo)
                .frame(width: DroppyShelfMetrics.weatherCardWidth)
                .frame(maxHeight: .infinity)
        } else {
            card(id, solo: solo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func card(_ id: String, solo: Bool) -> some View {
        switch id {
        // On its own the player keeps its full layout; beside another widget it
        // folds down to a card.
        case HomeWidget.media where solo: PlayerPage()
        case HomeWidget.media: MediaCard()
        case "pomodoro": PomodoroCard()
        case "timer": TimerCard()
        case "caffeine": HighAlertCard()
        case "systemStats": SystemStatsCard()
        case "meetings": MeetingsCard()
        case HomeWidget.calendar: CalendarCard()
        case HomeWidget.weather: WeatherCard()
        case HomeWidget.battery: BatteryCard()
        case "scratchpad": ScratchpadCard()
        default: EmptyView()
        }
    }

    private var emptySlot: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 22, weight: .medium))
                .accessibilityHidden(true)
            Text("Pick up to two widgets below")
                .font(DS.Typo.headline)
        }
        .foregroundStyle(NotchPalette.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

// MARK: - Picker

/// The row under the cards in edit mode: every widget that can go on the home
/// page, checked when it's in the draft, then cancel and confirm.
private struct HomeWidgetPicker: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let draft = state.homeDraft ?? []
        HStack(spacing: 2) {
            // More widgets than fit scroll sideways, fading out at the edge.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(state.availableHomeWidgets, id: \.self) { id in
                        item(id, isOn: draft.contains(id))
                    }
                }
                .padding(.trailing, 14)
            }
            .mask(
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 18)
                }
            )
            Spacer(minLength: 10)
            DroppyIconButton("xmark", size: 34, help: "Cancel") { state.cancelHomeCustomization() }
            // DroppyPressStyle dims it to 0.4 while the draft is empty.
            DroppyIconButton("checkmark", size: 34, tone: .accent, help: "Done (↩)") { state.commitHomeCustomization() }
                .disabled(draft.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(height: HomeWidget.pickerHeight)
    }

    private func item(_ id: String, isOn: Bool) -> some View {
        let tint = HomeWidget.tint(id)
        return Button { state.toggleHomeWidget(id) } label: {
            VStack(spacing: 5) {
                Group {
                    if let appIcon = AppIcon.image(bundleID: HomeWidget.appIconBundleID(id)) {
                        // macOS icons carry their own margin; draw them a little
                        // larger so they sit the same size as the symbol tiles.
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 50, height: 50)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                            Image(systemName: HomeWidget.icon(id))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 42, height: 42)
                .overlay(alignment: .bottomTrailing) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(DS.accent))
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                            .transition(DS.Motion.transition(reduceMotion, .scale.combined(with: .opacity)))
                    }
                }
                Text(HomeWidget.name(id))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 52)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.87))
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isOn)
        .help(isOn ? "Remove \(HomeWidget.name(id))" : "Add \(HomeWidget.name(id))")
        .accessibilityLabel(HomeWidget.name(id))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Cards

/// Small label at the top of a Droplet card, so two cards side by side read apart.
private struct CardHeader<Trailing: View>: View {
    let id: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: HomeWidget.icon(id))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(HomeWidget.tint(id))
            Text(HomeWidget.name(id).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(NotchPalette.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
        .frame(height: 16)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(id: String) {
        self.init(id: id) { EmptyView() }
    }
}

/// The player folded down to fit beside another widget.
private struct MediaCard: View {
    @ObservedObject private var media = MediaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    private var track: MediaTrack { media.currentTrack }
    private var progress: Double { isScrubbing ? scrubValue : track.progress }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { media.openSourceApp() } label: {
                    AlbumArtView(image: track.artworkImage, size: 56, radius: 12)
                        .overlay(alignment: .bottomTrailing) {
                            if let icon = AppIcon.image(bundleID: track.sourceBundleID.isEmpty ? AppIcon.bundleID(forPlayer: track.sourceApp) : track.sourceBundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                    .offset(x: 3, y: 3)
                            }
                        }
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .help(track.sourceApp.isEmpty ? "Now Playing" : "Open \(track.sourceApp)")
                .accessibilityLabel(track.sourceApp.isEmpty ? "Album art" : "Open \(track.sourceApp)")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(track.hasTrack ? track.title : "Not playing")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .optionalHelp(track.hasTrack ? track.title : nil)
                        if track.hasTrack {
                            WaveBars(isPlaying: track.isPlaying, bars: 5, height: 9, barWidth: 2)
                                .fixedSize()
                        }
                    }
                    Text(track.hasTrack ? track.artist : "Play something")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchPalette.secondary)
                        .lineLimit(1)
                        .optionalHelp(track.hasTrack ? track.artist : nil)
                }
            }

            scrubber.padding(.top, 12)
            Spacer(minLength: 4)
            controls
        }
        .padding(.vertical, 4)
        // Settings › HUDs › Track swipe works over the card too.
        .onHover { AppState.shared.isPointerOverMediaWidget = $0 }
        .onDisappear { AppState.shared.isPointerOverMediaWidget = false }
    }

    private var scrubber: some View {
        HStack(spacing: 9) {
            Text(track.duration <= 0 ? "--:--" : format(track.duration * progress))
                .frame(minWidth: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchPalette.track)
                    Capsule().fill(Color.white).frame(width: max(6, geo.size.width * progress))
                }
                .frame(height: isScrubbing ? 7 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            isScrubbing = true
                            scrubValue = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                        }
                        .onEnded { _ in
                            // An unknown length would turn any drag into a seek to 0:00.
                            if track.duration > 0 { media.seek(to: track.duration * scrubValue) }
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 10)
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isScrubbing)
            // The drag is invisible to VoiceOver, so expose the bar as an adjustable control.
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(track.duration <= 0 ? "Unavailable" : "\(track.formattedPosition) of \(track.formattedDuration)")
            .accessibilityAdjustableAction { direction in
                guard track.supportsSeek, !track.needsBrowserJavaScript, track.duration > 0 else { return }
                let step: TimeInterval = direction == .increment ? 10 : direction == .decrement ? -10 : 0
                media.seek(to: min(max(media.livePosition() + step, 0), track.duration))
            }
            Text(track.duration <= 0 ? "--:--" : "-" + format(max(track.duration - track.duration * progress, 0)))
                .frame(minWidth: 30, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(DS.Palette.textSecondary)
        .opacity(track.hasTrack ? 1 : 0.4)
        .allowsHitTesting(track.supportsSeek && !track.needsBrowserJavaScript)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            // Like the full player: nothing to skip until something plays.
            transport("backward.fill", size: 18, help: "Previous") { media.previousTrack() }
                .disabled(!track.hasTrack)
            transport(track.isPlaying ? "pause.fill" : "play.fill", size: 25, help: track.isPlaying ? "Pause" : "Play") {
                media.togglePlayPause()
            }
            transport("forward.fill", size: 18, help: "Next") { media.nextTrack() }
                .disabled(!track.hasTrack)
        }
        .frame(height: 36)
    }

    private func transport(_ name: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.8))
        .help(help)
        .accessibilityLabel(help)
    }

    private func format(_ time: TimeInterval) -> String {
        let t = Int(max(time, 0).rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

private struct PomodoroCard: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @ObservedObject private var pomodoroClock = PomodoroClock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        let total = Double(max(state.pomodoroCycleSeconds, 1))
        return max(0, min(1, (total - Double(state.pomodoroSecondsRemaining)) / total))
    }

    var body: some View {
        VStack(spacing: 10) {
            CardHeader(id: "pomodoro") {
                Text(state.isPomodoroWorkCycle ? "Focus · \(pomodoroSettings.workMinutes)m" : "Break · \(pomodoroSettings.breakMinutes)m")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchPalette.tertiary)
            }
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(DS.Palette.hairline, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                    Image(systemName: state.isPomodoroWorkCycle ? "brain.head.profile" : "cup.and.saucer.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 10) {
                    Text(state.formattedPomodoroTime)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(state.isPomodoroActive ? .orange : .white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 8) {
                        DroppyIconButton(state.isPomodoroActive ? "pause.fill" : "play.fill", size: 32, tone: .accent,
                                         help: state.isPomodoroActive ? "Pause" : "Start focus") {
                            state.isPomodoroActive ? state.pausePomodoro() : state.startPomodoro()
                            DroppyAudio.playTick()
                        }
                        DroppyIconButton("arrow.counterclockwise", size: 32, tone: .tonal, help: "Reset") {
                            state.resetPomodoro()
                            DroppyAudio.playTick()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct TimerCard: View {
    @ObservedObject private var timer = TimerService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            CardHeader(id: "timer") {
                Text(timer.mode.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchPalette.tertiary)
            }
            HStack(spacing: 10) {
                if timer.mode == .timer, !timer.isRunning {
                    adjust("minus", by: -60)
                }
                Text(TimerService.format(timer.displaySeconds))
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isRunning ? DropletPalette.tint(for: "timer") : .white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                if timer.mode == .timer, !timer.isRunning {
                    adjust("plus", by: 60)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                DroppyPillButton(timer.isRunning ? "Pause" : (timer.hasStarted ? "Resume" : "Start"),
                                 systemName: timer.isRunning ? "pause.fill" : "play.fill", tone: .accent) {
                    timer.toggle()
                    DroppyAudio.playTick()
                }
                DroppyIconButton("arrow.counterclockwise", size: 28, tone: .tonal, help: "Reset") {
                    timer.reset()
                    DroppyAudio.playTick()
                }
                .disabled(!timer.hasStarted)
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: timer.isRunning)
    }

    private func adjust(_ symbol: String, by delta: TimeInterval) -> some View {
        DroppyIconButton(symbol, size: 26, tone: .tonal, help: delta > 0 ? "Add a minute" : "Remove a minute") {
            timer.adjust(by: delta)
            DroppyAudio.playTick()
        }
    }
}

private struct HighAlertCard: View {
    @ObservedObject private var blocker = SleepBlockerService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        guard blocker.isAwakeActive else { return "Your Mac can sleep" }
        guard blocker.remainingSeconds > 0 else { return "Awake until turned off" }
        let s = blocker.remainingSeconds
        let time = s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
        return "Awake · \(time) left"
    }

    var body: some View {
        VStack(spacing: 10) {
            CardHeader(id: "caffeine")
            HStack(spacing: 14) {
                Button {
                    blocker.toggleIndefinite()
                    DroppyAudio.playTick()
                } label: {
                    Image(systemName: blocker.isAwakeActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(blocker.isAwakeActive ? .black : .white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(blocker.isAwakeActive ? Color.orange : NotchPalette.control))
                        .shadow(color: blocker.isAwakeActive ? .orange.opacity(0.5) : .clear, radius: 10)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .help(blocker.isAwakeActive ? "Turn off High Alert" : "Keep awake")
                .accessibilityLabel("High Alert")
                .accessibilityValue(blocker.isAwakeActive ? "On" : "Off")
                .accessibilityHint(blocker.isAwakeActive ? "Lets your Mac sleep again" : "Keeps your Mac awake")

                VStack(alignment: .leading, spacing: 8) {
                    Text(status)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(blocker.isAwakeActive ? .orange : .white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        ForEach([15, 60], id: \.self) { minutes in
                            DroppyChip(minutes == 60 ? "1 h" : "\(minutes) min", isSelected: false) {
                                blocker.activateForDuration(minutes: minutes)
                                DroppyAudio.playTick()
                            }
                            .help(minutes == 60 ? "Keep awake for an hour" : "Keep awake for \(minutes) minutes")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: blocker.isAwakeActive)
    }
}

private struct SystemStatsCard: View {
    @ObservedObject private var monitor = SystemMonitorService.shared

    var body: some View {
        let m = monitor.metrics
        VStack(spacing: 9) {
            CardHeader(id: "systemStats")
            VStack(spacing: 8) {
                MetricRowView(label: "CPU", valueText: "\(Int(m.cpuUsagePercent))%",
                              percentage: m.cpuUsagePercent / 100, tintColor: DS.Palette.info)
                MetricRowView(label: "Memory", valueText: String(format: "%.1f / %d GB", m.memoryUsedGigabytes, Int(m.memoryTotalGigabytes)),
                              percentage: m.memoryUsagePercent / 100, tintColor: .purple)
                MetricRowView(label: "Battery",
                              valueText: m.hasBattery ? "\(m.batteryPercent)%\(m.isCharging ? " ⚡" : "")" : "AC Power",
                              percentage: m.hasBattery ? Double(m.batteryPercent) / 100 : 1,
                              tintColor: !m.hasBattery || m.batteryPercent > 20 ? DS.Palette.success : DS.Palette.danger)
            }
            .frame(maxHeight: .infinity)
        }
        // Keeps the monitor polling while this card is on screen.
        .whileShown(start: { monitor.subscribe() }, stop: { monitor.unsubscribe() })
    }
}

private struct MeetingsCard: View {
    @ObservedObject private var meetings = MeetingControlService.shared

    var body: some View {
        VStack(spacing: 10) {
            CardHeader(id: "meetings") {
                Text([meetings.isMicInUse ? "In a call" : nil, meetings.target?.name]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(meetings.isMicInUse ? DS.Palette.success : NotchPalette.tertiary)
                    .lineLimit(1)
            }
            MeetingControlsRow(size: 40)
                .frame(maxHeight: .infinity)
        }
        .onAppear { MeetingControlService.shared.refreshApps() }
    }
}

/// Today's date as a Calendar-style tile, then the next few events and
/// reminders. Clicking it opens the Calendar page.
private struct CalendarCard: View {
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared

    private var hasAccess: Bool { calendar.hasEventAccess || calendar.hasReminderAccess }

    /// What's still ahead: events that haven't ended, and open reminders.
    private var upcoming: [AgendaEntry] {
        let now = Date()
        return Array(calendar.agenda.filter { entry in
            entry.kind == .reminder ? !entry.isCompleted : (entry.end ?? entry.start ?? .distantFuture) > now
        }.prefix(3))
    }

    var body: some View {
        let today = Date()
        VStack(spacing: 10) {
            CardHeader(id: HomeWidget.calendar) {
                Text(today.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchPalette.secondary)
            }
            HStack(spacing: 14) {
                dayTile(today)
                Group {
                    if !hasAccess {
                        accessPrompt
                    } else if upcoming.isEmpty {
                        Text("Nothing else planned this week")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NotchPalette.secondary)
                            .lineLimit(2)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(upcoming) { row($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(.calendar) }
        .help("Open Tasks & Calendar (⌘4)")
        // The agenda follows the day picked on the Calendar page; come back to today.
        .onAppear { if hasAccess { calendar.load(from: today) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open Tasks & Calendar") { state.select(.calendar) }
    }

    private func dayTile(_ day: Date) -> some View {
        VStack(spacing: 0) {
            Text(day.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(HomeWidget.tint(HomeWidget.calendar))
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 60, height: 60)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NotchPalette.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    }

    private func row(_ entry: AgendaEntry) -> some View {
        HStack(spacing: 7) {
            Group {
                if entry.kind == .reminder {
                    Circle().strokeBorder(entry.color, lineWidth: 1.5)
                } else {
                    Circle().fill(entry.color)
                }
            }
            .frame(width: 7, height: 7)
            Text(entry.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(when(entry))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchPalette.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .help(entry.title)
        .accessibilityElement(children: .combine)
    }

    private func when(_ entry: AgendaEntry) -> String {
        guard let start = entry.start else { return entry.kind == .reminder ? "Reminder" : "" }
        let cal = Calendar.current
        if entry.isAllDay {
            return cal.isDateInToday(start) ? "All day" : start.formatted(.dateTime.weekday(.abbreviated))
        }
        if cal.isDateInToday(start) { return start.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInTomorrow(start) { return "Tomorrow" }
        return start.formatted(.dateTime.weekday(.abbreviated))
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("See today's events here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchPalette.secondary)
                .lineLimit(2)
            DroppyPillButton("Allow Calendar", systemName: "calendar.badge.plus", tone: .accent,
                             help: "Let Tama read your calendars and reminders") {
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    calendar.load(from: Date())
                    calendar.requestAccessIfNeeded()
                } else {
                    // Asked before and declined: only System Settings can turn it on.
                    PermissionService.shared.openSettings(.calendars)
                }
            }
        }
    }
}

/// Temperature, sky, today's range and the next hours for where the Mac is
/// (or a fixed city), on the style picked in Settings › Droplets › Weather.
/// Location is asked for from here, when the card is added.
private struct WeatherCard: View {
    var body: some View {
        WeatherGlassCard()
            .whileShown(start: { WeatherService.shared.start(for: "home") },
                        stop: { WeatherService.shared.stop(for: "home") })
    }
}

/// The Mac's charge and the connected headphones', bud by bud.
private struct BatteryCard: View {
    @ObservedObject private var monitor = SystemMonitorService.shared
    @ObservedObject private var headphones = HeadphoneBatteryService.shared

    var body: some View {
        VStack(spacing: 10) {
            CardHeader(id: HomeWidget.battery)
            VStack(spacing: 9) {
                if monitor.hasBattery {
                    row(symbol: monitor.isCharging ? "laptopcomputer.and.arrow.down" : "laptopcomputer",
                        name: "This Mac", level: monitor.batteryLevel,
                        detail: monitor.isCharging ? "Charging" : nil)
                }
                if let buds = headphones.battery, let level = buds.level {
                    row(symbol: buds.name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones",
                        name: buds.name, level: level,
                        detail: buds.detail ?? buds.caseLevel.map { "Case \($0)%" })
                }
                if !monitor.hasBattery && headphones.battery == nil {
                    Text("No batteries to show. Connect AirPods or Beats to see theirs.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchPalette.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .whileShown(start: {
            monitor.subscribe()
            headphones.start(for: "home")
        }, stop: {
            monitor.unsubscribe()
            headphones.stop(for: "home")
        })
    }

    private func row(symbol: String, name: String, level: Int, detail: String?) -> some View {
        let tint = level <= 20 ? DS.Palette.danger : DS.Palette.success
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(NotchPalette.secondary)
                        .lineLimit(1)
                }
                Text("\(level)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.white)
            DroppyMeter(value: Double(level) / 100, tint: tint, height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(level) percent\(detail.map { ", \($0)" } ?? "")")
    }
}

/// Runs `start` while the card is really on screen and `stop` when it isn't.
/// The shelf stays mounted at zero opacity while the notch rests, so
/// `onDisappear` alone never came and the cards polled with the shelf shut.
private struct WhileShown: ViewModifier {
    let start: () -> Void
    let stop: () -> Void

    @Environment(\.isIslandLayerVisible) private var isLayerVisible
    @State private var isMounted = false
    @State private var isRunning = false

    func body(content: Content) -> some View {
        content
            .onAppear { isMounted = true; sync() }
            .onDisappear { isMounted = false; sync() }
            .onChange(of: isLayerVisible) { _, _ in sync() }
    }

    private func sync() {
        let wanted = isMounted && isLayerVisible
        guard wanted != isRunning else { return }
        isRunning = wanted
        if wanted { start() } else { stop() }
    }
}

private extension View {
    func whileShown(start: @escaping () -> Void, stop: @escaping () -> Void) -> some View {
        modifier(WhileShown(start: start, stop: stop))
    }
}

/// Notes on the home page, like the reference's card beside the player:
/// "Notes", a compose button, and the latest notes. A row opens it in Notes.
private struct ScratchpadCard: View {
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Notes")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                NotchCircleButton("square.and.pencil", size: 24, iconSize: 10.5, help: "New note") {
                    open(store.create())
                }
            }
            if store.notes.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(store.ordered.prefix(2)) { note in
                    NoteRow(note: note, compact: true) { open(note.id) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func open(_ id: UUID) {
        DroppyAudio.playTick()
        store.requestedNoteID = id
        state.open(.widgets)
        state.activeDropletID = "scratchpad"
    }
}

