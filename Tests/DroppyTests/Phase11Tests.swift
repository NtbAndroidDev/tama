import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Droppy

/// Pomodoro › Momentum: sessions today and the day-by-day streak.
@Suite struct PomodoroMomentumTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)!
    }

    @Test func firstSessionStartsBothCounts() {
        let after = PomodoroMomentum().recording(date(10), calendar: calendar)
        #expect(after.sessionsToday == 1)
        #expect(after.streakDays == 1)
        #expect(after.bestStreak == 1)
    }

    @Test func moreSessionsSameDayDoNotGrowTheStreak() {
        var momentum = PomodoroMomentum().recording(date(10), calendar: calendar)
        momentum = momentum.recording(date(10), calendar: calendar)
        momentum = momentum.recording(date(10), calendar: calendar)
        #expect(momentum.sessionsToday == 3)
        #expect(momentum.streakDays == 1)
    }

    @Test func consecutiveDaysExtendTheStreak() {
        var momentum = PomodoroMomentum().recording(date(10), calendar: calendar)
        momentum = momentum.recording(date(11), calendar: calendar)
        momentum = momentum.recording(date(12), calendar: calendar)
        #expect(momentum.streakDays == 3)
        #expect(momentum.sessionsToday == 1)
        #expect(momentum.bestStreak == 3)
    }

    @Test func aMissedDayStartsOverButKeepsTheBest() {
        var momentum = PomodoroMomentum().recording(date(10), calendar: calendar)
        momentum = momentum.recording(date(11), calendar: calendar)
        momentum = momentum.recording(date(15), calendar: calendar)
        #expect(momentum.streakDays == 1)
        #expect(momentum.bestStreak == 2)
    }

    @Test func todayResetsAndTheStreakLapses() {
        let momentum = PomodoroMomentum().recording(date(10), calendar: calendar)
        #expect(momentum.sessions(on: date(10), calendar: calendar) == 1)
        #expect(momentum.sessions(on: date(11), calendar: calendar) == 0)
        // Yesterday's streak still counts today…
        #expect(momentum.currentStreak(on: date(11), calendar: calendar) == 1)
        // …but a whole missed day ends it, with no timer needed.
        #expect(momentum.currentStreak(on: date(12), calendar: calendar) == 0)
    }

    @Test func summaryReadsAsASentence() {
        var momentum = PomodoroMomentum().recording(date(10), calendar: calendar)
        momentum = momentum.recording(date(11), calendar: calendar)
        momentum = momentum.recording(date(11), calendar: calendar)
        #expect(momentum.summary(on: date(11), calendar: calendar) == "2 today · 2-day streak")
        #expect(PomodoroMomentum().summary(on: date(11), calendar: calendar) == nil)
    }
}

/// Settings › Shelf › Swipe direction.
@Suite struct SwipeDirectionTests {
    @Test func standardFollowsTheFingers() {
        #expect(ShelfGestureService.direction(true, reversed: false) == 1)
        #expect(ShelfGestureService.direction(false, reversed: false) == -1)
    }

    @Test func reversedFlipsBothWays() {
        #expect(ShelfGestureService.direction(true, reversed: true) == -1)
        #expect(ShelfGestureService.direction(false, reversed: true) == 1)
    }
}

/// Settings › Shelf › Preview placement (the reference's "Closest Corner").
@Suite struct CapturePreviewPlacementTests {
    private let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 200, height: 150)
    private var margin: CGFloat { CaptureMetrics.previewMargin }

    @Test func bottomRightIgnoresThePointer() {
        for pointer in [NSPoint(x: 10, y: 10), NSPoint(x: 990, y: 790)] {
            let origin = CapturePreviewController.origin(for: size, on: visible, pointer: pointer, placement: .bottomRight)
            #expect(origin.x == visible.maxX - size.width - margin)
            #expect(origin.y == visible.minY + margin)
        }
    }

    @Test func closestCornerFollowsThePointer() {
        let topLeft = CapturePreviewController.origin(for: size, on: visible, pointer: NSPoint(x: 20, y: 780),
                                                      placement: .closestCorner)
        #expect(topLeft.x == visible.minX + margin)
        #expect(topLeft.y == visible.maxY - size.height - margin)

        let bottomRight = CapturePreviewController.origin(for: size, on: visible, pointer: NSPoint(x: 980, y: 20),
                                                          placement: .closestCorner)
        #expect(bottomRight.x == visible.maxX - size.width - margin)
        #expect(bottomRight.y == visible.minY + margin)
    }

    @Test func theCardAlwaysFitsOnScreen() {
        for pointer in [NSPoint(x: 1, y: 1), NSPoint(x: 999, y: 799), NSPoint(x: 500, y: 400)] {
            let origin = CapturePreviewController.origin(for: size, on: visible, pointer: pointer, placement: .closestCorner)
            #expect(origin.x >= visible.minX)
            #expect(origin.y >= visible.minY)
            #expect(origin.x + size.width <= visible.maxX)
            #expect(origin.y + size.height <= visible.maxY)
        }
    }
}

/// Settings › HUDs › Media › Now Playing Size and the floating-button styles.
@Suite struct Phase11OptionTests {
    @Test func smallerIsActuallySmaller() {
        #expect(NowPlayingSize.regular.scale == 1)
        #expect(NowPlayingSize.smaller.scale < 1)
    }

    @Test func floatingButtonSizesAreOrdered() {
        #expect(FloatingButtonSize.small.diameter < FloatingButtonSize.regular.diameter)
        #expect(FloatingButtonSize.regular.diameter < FloatingButtonSize.large.diameter)
    }

    @Test func floatingSymbolTakesTheRightColor() {
        let tint = Color.orange
        #expect(FloatingButtonSymbol.color(style: .glass, tint: tint, lightIcons: true) == tint)
        #expect(FloatingButtonSymbol.color(style: .monochrome, tint: tint, lightIcons: true) != tint)
        #expect(FloatingButtonSymbol.color(style: .colored, tint: tint, lightIcons: true) == Color.white)
        #expect(FloatingButtonSymbol.color(style: .colored, tint: tint, lightIcons: false) == Color.black.opacity(0.85))
        // No widget colour (an app or a Shortcut): the symbol stays readable.
        #expect(FloatingButtonSymbol.color(style: .colored, tint: nil, lightIcons: false) == Color.white.opacity(0.92))
    }

    /// Every new switch must be in `settingsKeys`, or Reset / Export miss it.
    @Test @MainActor func newSettingsAreResettable() {
        let keys = Set(AppState.settingsKeys)
        for key in ["solidSettingsBackground", "shelfSwipeReversed", "nowPlayingSize",
                    "alwaysUseBuiltInSpeakers", "capturePreviewPlacement", "pomodoroMomentum",
                    "clipboardFavoritesBar", FloatingButtonSize.key, "floatingButtonStyle",
                    "floatingButtonLightIcons"] {
            #expect(keys.contains(key), "\(key) is missing from settingsKeys")
        }
    }

    /// "ZIP Hover" is a drop tile like the others.
    @Test func zipIsAChoosableQuickAction() {
        #expect(QuickAction.choosable.contains(.zip))
        #expect(QuickAction.zip.title == "ZIP Hover")
        #expect(QuickAction.tiles(from: "zip,airDrop") == [.zip, .airDrop])
    }
}
