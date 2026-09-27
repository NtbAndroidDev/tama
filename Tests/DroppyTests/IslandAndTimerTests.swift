import Foundation
import Testing
@testable import Droppy

@Suite struct IslandModeTests {
    @Test func priorityOrder() {
        #expect(IslandMode.resolve(isDragHovering: true, isExpanded: true, hasNotification: true, hasHUD: true) == .dropTarget)
        #expect(IslandMode.resolve(isDragHovering: false, isExpanded: true, hasNotification: true, hasHUD: true) == .shelf)
        #expect(IslandMode.resolve(isDragHovering: false, isExpanded: false, hasNotification: true, hasHUD: true) == .notification)
        #expect(IslandMode.resolve(isDragHovering: false, isExpanded: false, hasNotification: false, hasHUD: true) == .hud)
        #expect(IslandMode.resolve(isDragHovering: false, isExpanded: false, hasNotification: false, hasHUD: false) == .resting)
    }

    @Test func openModes() {
        #expect(IslandMode.shelf.isOpen && IslandMode.dropTarget.isOpen)
        #expect(!IslandMode.resting.isOpen && !IslandMode.hud.isOpen && !IslandMode.notification.isOpen)
    }
}

@Suite struct TimerFormatTests {
    @Test(arguments: [
        (0.0, "0:00"), (-5, "0:00"), (0.2, "0:01"), (59.2, "1:00"), (61, "1:01"),
        (599, "9:59"), (3600, "1:00:00"), (3661, "1:01:01"), (36000, "10:00:00"),
    ])
    func standard(_ seconds: Double, _ expected: String) {
        #expect(TimerService.format(seconds) == expected)
    }

    @Test func compactShowsHoursAndMinutesOnly() {
        #expect(TimerService.format(3661, compact: true) == "1h01")
        #expect(TimerService.format(125, compact: true) == "2:05")
    }

    @Test func tenths() {
        #expect(TimerService.format(0, tenths: true) == "0:00.0")
        #expect(TimerService.format(61.25, tenths: true) == "1:01.2")
        // Regression: 2.3 * 10 is 22.999… in binary and printed "0:02.2".
        #expect(TimerService.format(2.3, tenths: true) == "0:02.3")
        #expect(TimerService.format(59.99, tenths: true) == "0:59.9")
    }
}

/// The resting island on a notched Mac must hug the hardware notch: the wings
/// only make room for the art and the wave, never for the song's words.
@Suite struct RestingNotchGeometryTests {
    @Test func nothingPlayingLeavesTheNotchBare() {
        #expect(AppState.restingNotchWing(isActive: false, wide: false) == 0)
        #expect(AppState.restingNotchWing(isActive: false, wide: true) == 0)
    }

    @Test func activityTakesOnlyTheSmallWings() {
        #expect(AppState.restingNotchWing(isActive: true, wide: false) == DroppyShelfMetrics.miniWing)
        #expect(AppState.restingNotchWing(isActive: true, wide: true) == DroppyShelfMetrics.activityWing)
    }

    /// Regression: the track title used to grow each wing to 112 pt, which drew
    /// a ~460 pt black bar across the menu bar instead of the notch.
    @Test func restingWidthStaysCloseToTheHardwareNotch() {
        let notch: CGFloat = 200
        let playing = notch + AppState.restingNotchWing(isActive: true, wide: false) * 2
        #expect(playing == notch + DroppyShelfMetrics.miniWing * 2)
        #expect(playing < notch * 2)
    }

    @Test func trackTitleIsOnlyForTheFloatingPill() {
        #expect(!AppState.showsTrackTitle(enabled: true, hasNotch: true, hasTrack: true,
                                          showsMedia: true, activitiesFirst: false))
        #expect(AppState.showsTrackTitle(enabled: true, hasNotch: false, hasTrack: true,
                                         showsMedia: true, activitiesFirst: false))
        #expect(!AppState.showsTrackTitle(enabled: false, hasNotch: false, hasTrack: true,
                                          showsMedia: true, activitiesFirst: false))
        #expect(!AppState.showsTrackTitle(enabled: true, hasNotch: false, hasTrack: false,
                                          showsMedia: true, activitiesFirst: false))
        #expect(!AppState.showsTrackTitle(enabled: true, hasNotch: false, hasTrack: true,
                                          showsMedia: false, activitiesFirst: false))
        #expect(!AppState.showsTrackTitle(enabled: true, hasNotch: false, hasTrack: true,
                                          showsMedia: true, activitiesFirst: true))
    }
}
