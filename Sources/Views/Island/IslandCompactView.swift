import SwiftUI
import AppKit

/// The resting notch. On a notched Mac it hugs the hardware and only grows two
/// small wings: album art on the left, the music wave on the right (or the
/// tray count / a running timer when nothing plays). Without a notch it is a
/// floating Dynamic Island pill with the same content.
public struct IslandCompactView: View {
    // High Alert isn't observed here: AppState forwards its on/off flips, and
    // the service's once-a-second countdown would redraw this whole view.
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var hudSettings = HUDSettings.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared
    @ObservedObject private var meetingSettings = MeetingSettings.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var media = MediaService.shared
    @ObservedObject private var live = LiveActivityCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandDisplayID) private var displayID

    public init() {}

    /// In fullscreen › Hide media leaves music out of this screen's island.
    private var track: MediaTrack { state.showsMedia(on: displayID) ? media.currentTrack : MediaTrack() }
    /// Beats music: a meeting about to start, a charger just plugged in —
    /// unless Settings › HUDs puts music first.
    private var urgent: LiveActivity? {
        if hudSettings.compactHUDPriority == .mediaFirst, track.hasTrack { return nil }
        return live.top(.urgent)
    }
    /// Shown only when nothing else wants the wings.
    private var ambient: LiveActivity? { live.top(.ambient) }
    private var hasNotch: Bool { state.notchHeight(on: displayID) > 0 }
    /// Settings › Pomodoro › Keep timer visible: the countdown outranks music and the Tray.
    private var pomodoroFirst: Bool { pomodoroSettings.keepVisible && state.isPomodoroActive }

    public var body: some View {
        ZStack {
            ScrollWheelListenerView { delta in handleScroll(delta) }

            if hasNotch {
                // The resting surface hugs the hardware notch, so the wings stay
                // small: art and wave only. The song's words go in the floating
                // pill (no notch) or the open player — see `showsTrackTitleInWings`.
                let wide = state.showsWideActivity(on: displayID)
                // Wings sit inside the shape's body, clear of the top fillets.
                let wing = AppState.restingNotchWing(isActive: true, wide: wide) - DroppyShelfMetrics.restingEar
                // Icons hug the outer edges, like Alcove.
                HStack(spacing: 0) {
                    leftWing
                        .padding(.leading, 7.5)
                        .frame(width: wing, alignment: .leading)
                    Spacer(minLength: state.hardwareNotchWidth(on: displayID))
                    rightWing
                        .padding(.trailing, 9)
                        .frame(width: wing, alignment: .trailing)
                }
                .padding(.horizontal, DroppyShelfMetrics.restingEar)
                .opacity(state.hasMiniActivity(on: displayID) ? 1 : 0)
            } else {
                HStack(spacing: 9) {
                    leftWing
                    if track.hasTrack, state.showsTrackTitleInWings(on: displayID) {
                        Text(track.title)
                            .font(DS.Typo.headline)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: DS.Space.sm)
                    rightWing
                }
                .padding(.horizontal, DS.Space.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // A double-tap recogniser makes every single click wait out the
        // double-click interval, so only attach it when there is something to
        // play/pause; otherwise the island opens on the first click.
        .gesture(
            TapGesture(count: 2).onEnded { media.togglePlayPause() }
                .exclusively(before: TapGesture().onEnded { openShelf() }),
            isEnabled: track.hasTrack
        )
        .onTapGesture { if !track.hasTrack { openShelf() } }
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: track.hasTrack)
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.shelfItems.isEmpty)
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: live.activities.map(\.id))
        .optionalHelp((urgent ?? ambient)?.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openShelf() }
        .accessibilityAction(named: track.isPlaying ? "Pause" : "Play") {
            if track.hasTrack { media.togglePlayPause() }
        }
    }

    /// What VoiceOver reads for the resting island: the same thing the wings
    /// show, in the same order, rather than just the app's name.
    private var spokenSummary: String {
        if let urgent { return urgent.label }
        if pomodoroFirst { return "Pomodoro \(state.formattedPomodoroTime)" }
        if track.hasTrack {
            let title = track.title.isEmpty ? "Now Playing" : track.title
            return track.isPlaying ? title : "\(title), paused"
        }
        if !state.shelfItems.isEmpty {
            let n = state.shelfItems.count
            return "Tray, \(n) \(n == 1 ? "item" : "items")"
        }
        if state.isPomodoroActive { return "Pomodoro \(state.formattedPomodoroTime)" }
        if state.sleepBlocker.isAwakeActive { return "High Alert" }
        return ambient?.label ?? "Tama"
    }

    /// Opens on the page picked in Settings, like hover does — or, with
    /// Settings › HUDs › On notch click › Media widget, on the player while
    /// music plays.
    private func openShelf() {
        // Settings › Shelf › The Shelf is off: the notch doesn't open.
        guard shelfSettings.isEnabled else { return }
        DroppyAudio.playTick()
        // Meetings' call HUD: a click on it opens the call controls.
        if meetingSettings.callHUD, MeetingControlService.shared.callState.isInCall,
           state.droplets.contains(where: { $0.id == "meetings" && $0.isEnabled }) {
            state.open(.widgets)
            state.activeDropletID = "meetings"
        } else if mediaSettings.notchClickOpensMedia, track.hasTrack {
            state.open(.home)
        } else if let page = shelfSettings.defaultPage.page {
            state.open(page)
        } else {
            state.setIslandExpanded(true)
        }
        NotchWindowController.shared.focusPanel()
    }

    // MARK: Wings

    @ViewBuilder
    private var leftWing: some View {
        if let urgent {
            LiveActivityWings(activity: urgent).leading
        } else if pomodoroFirst {
            pomodoroIcon
        } else if track.hasTrack {
            AlbumArtView(image: track.artworkImage, size: 20, radius: 5)
                .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.6).combined(with: .opacity)))
        } else if !state.shelfItems.isEmpty {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        } else if state.isPomodoroActive {
            pomodoroIcon
        } else if state.sleepBlocker.isAwakeActive {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.warning)
        } else if let ambient {
            LiveActivityWings(activity: ambient).leading
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let urgent {
            LiveActivityWings(activity: urgent).trailing
        } else if pomodoroFirst {
            pomodoroTime
        } else if track.hasTrack {
            Button {
                media.togglePlayPause()
            } label: {
                WaveBars(isPlaying: track.isPlaying, bars: 5, height: 12, barWidth: 2)
                    .frame(width: 17, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.8))
            .help(track.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")
            .accessibilityAddTraits(.isButton)
        } else if !state.shelfItems.isEmpty {
            Text("\(state.shelfItems.count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        } else if state.isPomodoroActive {
            pomodoroTime
        } else if state.sleepBlocker.isAwakeActive {
            Circle()
                .fill(DS.Palette.warning)
                .frame(width: 6, height: 6)
        } else if let ambient {
            LiveActivityWings(activity: ambient).trailing
        }
    }

    private var pomodoroIcon: some View {
        Image(systemName: state.isPomodoroWorkCycle ? "timer" : "cup.and.saucer.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RulerMetrics.orange)
    }

    private var pomodoroTime: some View {
        PomodoroTimeText()
            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
            .foregroundStyle(RulerMetrics.orange)
            .contentTransition(.numericText())
    }

    // MARK: Scroll → volume

    private func handleScroll(_ deltaY: CGFloat) {
        guard abs(deltaY) > 0.3 else { return }
        if NSEvent.modifierFlags.contains(.option) {
            guard hudSettings.scrollToChangeBrightness else { return }
            let display = BrightnessService.shared
            guard display.canSetBrightness, let level = display.level else { return }
            // The panel fades towards the new level, so show the target, not a read-back.
            let target = min(max(level + Double(deltaY) * 0.01, 0), 1)
            display.setBrightness(target)
            // The HUD settings only hide the feedback; the scroll still adjusts.
            if hudSettings.showBrightnessHUD { state.showHUD(.brightness, value: target) }
            return
        }
        guard hudSettings.scrollToChangeVolume else { return }
        let outputs = AudioOutputService.shared
        // No software volume on this output (HDMI, some USB): don't fake a change.
        guard outputs.canSetVolume else { return }
        outputs.setVolume(outputs.volume + Double(deltaY) * 0.01)
        outputs.presentHUD()
    }
}

public struct ScrollWheelListenerView: NSViewRepresentable {
    public var onScroll: (CGFloat) -> Void

    public init(onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
    }

    public func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onScroll = onScroll
        return view
    }

    public func updateNSView(_ nsView: ScrollCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    /// A trackpad sends 60–120 scroll events a second; each one would set the
    /// volume and rebuild the HUD. Deltas are summed and handed on at most
    /// every 1/30 s, so the total travel is the same but the work isn't.
    public class ScrollCatcherView: NSView {
        public var onScroll: ((CGFloat) -> Void)?
        private var pendingDelta: CGFloat = 0
        private var lastDelivery: TimeInterval = 0
        private var flushScheduled = false
        private static let interval: TimeInterval = 1.0 / 30

        public override func scrollWheel(with event: NSEvent) {
            pendingDelta += event.scrollingDeltaY
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastDelivery >= Self.interval {
                deliver(at: now)
            } else if !flushScheduled {
                flushScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval - (now - lastDelivery)) { [weak self] in
                    guard let self else { return }
                    self.flushScheduled = false
                    self.deliver(at: ProcessInfo.processInfo.systemUptime)
                }
            }
        }

        private func deliver(at now: TimeInterval) {
            let delta = pendingDelta
            pendingDelta = 0
            lastDelivery = now
            guard delta != 0 else { return }
            onScroll?(delta)
        }
    }
}
