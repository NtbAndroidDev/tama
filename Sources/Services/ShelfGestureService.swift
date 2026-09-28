import AppKit
import SwiftUI

/// Settings › Shelf › Gestures: two-finger trackpad swipes on the island.
///
/// - Swiping down on the resting notch opens the shelf — unless scrolling
///   there is set to change the volume (Settings › Shelf › Scroll on the
///   notch), which keeps the two from fighting over the same motion.
/// - Swiping up or down on the open Tray moves between Stack 1 and Stack 2
///   while Settings › Shelf › Tray › Two Stacks is on. Vertical is free on the
///   open shelf, so it never fights the sideways page swipe.
/// - Swiping sideways on the open shelf moves between its pages, except where
///   a sideways scroll already means something: the widget row (it flips its
///   own pages), a Tray full of files, and Home while it's being customised.
///   Settings › Shelf › Swipe direction › Reversed flips both of these.
///
/// - Settings › HUDs › Track swipe: sideways over the resting music wings,
///   or over the player / media card on the open shelf, skips tracks (fingers
///   moving left go to the next one; Reversed flips it). It takes precedence
///   over the page swipe there, and works with Gestures off.
///
/// Only trackpad gestures count (precise deltas with phases); a mouse wheel
/// keeps its plain scrolling. One gesture fires at most once; its momentum
/// tail is ignored.
@MainActor
final class ShelfGestureService {
    static let shared = ShelfGestureService()

    private var monitor: Any?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false
    /// The gesture was used for a track skip on the resting notch.
    private var firedTrack = false

    /// Points a swipe must travel before it counts.
    private static let openDistance: CGFloat = 28
    private static let pageDistance: CGFloat = 70
    private static let trackDistance: CGFloat = 60

    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true when the event was used up by a gesture.
    private func handle(_ event: NSEvent) -> Bool {
        let state = AppState.shared
        let gestures = ShelfSettings.shared.gestures && ShelfSettings.shared.isEnabled
        let trackSwipe = MediaSettings.shared.trackSwipe && MediaService.shared.currentTrack.hasTrack
        guard gestures || trackSwipe,
              event.window === NotchWindowController.shared.panel,
              event.hasPreciseScrollingDeltas else { return false }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            dx = 0
            dy = 0
            fired = false
            firedTrack = false
        }
        // Momentum after the fingers lift: swallow it if it follows a page
        // switch or a skip, so nothing scrolls on the old gesture.
        if event.phase.isEmpty {
            return !event.momentumPhase.isEmpty && fired && (state.isIslandExpanded || firedTrack)
        }
        defer {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                dx = 0
                dy = 0
            }
        }
        guard !fired else { return state.isIslandExpanded || firedTrack }

        // Physical finger direction, whatever the natural-scrolling setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        dx += event.scrollingDeltaX * sign
        dy += event.scrollingDeltaY * sign

        if trackSwipe, abs(dx) > Self.trackDistance, abs(dx) > abs(dy) * 2, isOverMedia(state) {
            fired = true
            firedTrack = !state.isIslandExpanded
            // Standard: fingers moving left skip ahead, like flicking a cover away.
            let forward = (dx < 0) != MediaSettings.shared.trackSwipeReversed
            if forward { MediaService.shared.nextTrack() } else { MediaService.shared.previousTrack() }
            return true
        }
        guard gestures else { return false }

        if !state.isIslandExpanded {
            // Resting notch: fingers moving down open the shelf.
            guard !HUDSettings.shared.scrollToChangeVolume, !NSEvent.modifierFlags.contains(.option),
                  NotchWindowController.shared.isOverIsland(NSEvent.mouseLocation),
                  dy > Self.openDistance, dy > abs(dx) * 1.5 else { return false }
            fired = true
            DroppyAudio.playTick()
            state.open(ShelfSettings.shared.defaultPage.page ?? state.shelfPage)
            return true
        }

        // The Tray's two stacks take the vertical swipe, which nothing else on
        // the open shelf uses, so it never fights the sideways page swipe.
        if state.shelfPage == .tray, TraySettings.shared.twoStacks,
           abs(dy) > Self.pageDistance, abs(dy) > abs(dx) * 2 {
            fired = true
            // Fingers moving up bring the next stack in from below.
            let step = Self.direction(dy < 0, reversed: ShelfSettings.shared.swipeReversed)
            let next = min(max(state.activeTrayStack + step, 0), 1)
            guard next != state.activeTrayStack else { return true }
            DroppyAudio.playTick()
            withAnimation(DS.Motion.fluid) { state.activeTrayStack = next }
            return true
        }

        guard canSwipePages(state), abs(dx) > Self.pageDistance, abs(dx) > abs(dy) * 2 else { return false }
        fired = true
        // Fingers moving left reveal the page to the right, like a Space swipe.
        state.selectAdjacentPage(Self.direction(dx < 0, reversed: ShelfSettings.shared.swipeReversed))
        return true
    }

    /// +1 forwards, -1 back. Settings › Shelf › Swipe direction flips it.
    nonisolated static func direction(_ forward: Bool, reversed: Bool) -> Int {
        (forward != reversed) ? 1 : -1
    }

    /// The music in the resting wings, or the player / media card on Home.
    private func isOverMedia(_ state: AppState) -> Bool {
        if state.isIslandExpanded {
            return state.shelfPage == .home && state.isPointerOverMediaWidget && !state.isCustomizingHome
        }
        return state.showsMedia(on: nil) && NotchWindowController.shared.isOverIsland(NSEvent.mouseLocation)
    }

    private func canSwipePages(_ state: AppState) -> Bool {
        switch state.shelfPage {
        case .widgets: return state.activeDropletID != nil && !state.isRearrangingWidgets
        case .tray: return state.shelfItems.isEmpty
        case .home: return !state.isCustomizingHome
        case .calendar: return !state.isEditingText
        }
    }
}
