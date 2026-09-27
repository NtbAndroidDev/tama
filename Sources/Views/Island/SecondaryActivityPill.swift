import SwiftUI

/// What can occupy the resting notch, in the order the wings pick from: an
/// urgent live activity, music, held files, a Pomodoro, High Alert, then the
/// ambient activities. The first is drawn in the wings (IslandCompactView);
/// with Multi Live Activities on, the next one gets a round pill of its own.
enum RestingSlot: Equatable {
    case activity(LiveActivity)
    case music
    case tray
    case pomodoro
    case awake

    /// Settings › HUDs: music can outrank urgent activities, and In
    /// fullscreen › Hide media leaves it out on a fullscreen screen.
    @MainActor static func ordered(on displayID: CGDirectDisplayID? = nil) -> [RestingSlot] {
        let state = AppState.shared
        let live = LiveActivityCenter.shared.activities
        let urgent: [RestingSlot] = live.filter { $0.priority == .urgent }.reversed().map { .activity($0) }
        let hasMusic = state.mediaService.currentTrack.hasTrack && state.showsMedia(on: displayID)
        var slots: [RestingSlot] = []
        if hasMusic, state.compactHUDPriority == .mediaFirst {
            slots = [.music] + urgent
        } else {
            slots = urgent
            if hasMusic { slots.append(.music) }
        }
        if !state.shelfItems.isEmpty { slots.append(.tray) }
        if state.isPomodoroActive { slots.append(.pomodoro) }
        if state.sleepBlocker.isAwakeActive { slots.append(.awake) }
        slots += live.filter { $0.priority == .ambient }.reversed().map { .activity($0) }
        // Settings › Pomodoro › Keep timer visible: right after urgent activities.
        if state.pomodoroKeepVisible, let index = slots.firstIndex(of: .pomodoro) {
            slots.remove(at: index)
            let urgentCount = slots.prefix { if case let .activity(a) = $0 { return a.priority == .urgent } else { return false } }.count
            slots.insert(.pomodoro, at: urgentCount)
        }
        return slots
    }

    /// The second concurrent activity. Held files are a count, not something
    /// happening, so they never take the extra pill.
    @MainActor static func secondary(on displayID: CGDirectDisplayID?) -> RestingSlot? {
        let slots = ordered(on: displayID)
        guard slots.count > 1 else { return nil }
        return slots.dropFirst().first { $0 != .tray }
    }
}

/// Settings › Shelf › Multi Live Activities: a second activity drawn as a
/// round pill just right of the resting island, like the iPhone's split
/// Dynamic Island (a call in the island, the song's artwork in the circle).
struct SecondaryActivityPill: View {
    let displayID: CGDirectDisplayID?
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var live = LiveActivityCenter.shared
    @ObservedObject private var media = MediaService.shared
    // High Alert isn't observed here: AppState forwards its on/off flips, and
    // the service's once-a-second countdown would redraw this whole view.
    @ObservedObject private var pomodoroClock = PomodoroClock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slot: RestingSlot? {
        guard state.multiLiveActivities,
              state.islandMode(on: displayID) == .resting,
              !state.isRestingSurfaceHidden,
              !state.isSurfaceSuppressed(on: displayID) else { return nil }
        return RestingSlot.secondary(on: displayID)
    }

    var body: some View {
        let d = state.secondaryActivityDiameter(on: displayID)
        let hasNotch = state.notchHeight(on: displayID) > 0
        ZStack {
            if let slot {
                content(slot, diameter: d)
                    .frame(width: d, height: d)
                    .liquidGlass(cornerRadius: d / 2, showBorder: !hasNotch, isNotchAttached: false,
                                 solidTop: d, isResting: true)
                    .clipShape(Circle())
                    .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.4, anchor: .leading).combined(with: .opacity)))
                    .help(label(slot))
                    .accessibilityElement()
                    .accessibilityLabel(label(slot))
            }
        }
        .frame(width: d, height: d, alignment: .leading)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.morphOpen), value: slot)
        // Status only: clicks go to whatever is behind it (the menu bar).
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ slot: RestingSlot, diameter d: CGFloat) -> some View {
        let inner = max(d - 10, 12)
        switch slot {
        case .music:
            AlbumArtView(image: media.currentTrack.artworkImage, size: inner, radius: inner / 2)
        case let .activity(activity):
            ZStack {
                if case let .progress(value) = activity.trailing {
                    ring(value, tint: activity.tint, size: inner)
                }
                Image(systemName: activity.icon)
                    .font(.system(size: d * 0.36, weight: .semibold))
                    .foregroundStyle(activity.tint)
            }
        case .pomodoro:
            let total = Double(max(state.pomodoroCycleSeconds, 1))
            ZStack {
                ring(Double(state.pomodoroSecondsRemaining) / total, tint: NotchPalette.calendarRed, size: inner)
                Image(systemName: "timer")
                    .font(.system(size: d * 0.32, weight: .semibold))
                    .foregroundStyle(NotchPalette.calendarRed)
            }
        case .awake:
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: d * 0.34, weight: .semibold))
                .foregroundStyle(DS.Palette.warning)
        case .tray:
            Image(systemName: "tray.full.fill")
                .font(.system(size: d * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func ring(_ value: Double, tint: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(value, 0.02), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func label(_ slot: RestingSlot) -> String {
        switch slot {
        case .music: media.currentTrack.title.isEmpty ? "Now Playing" : media.currentTrack.title
        case let .activity(activity): activity.label
        case .pomodoro: "Pomodoro \(state.formattedPomodoroTime)"
        case .awake: "High Alert"
        case .tray: "Tray"
        }
    }
}
