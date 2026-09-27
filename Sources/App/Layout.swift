import SwiftUI

// Every size the island, the shelf and its pages are built from, in one place:
// change a value here and the SwiftUI layout, the NSPanel frame and the
// hit-testing follow, since they all read these through AppState's geometry.
// Colours, type ramp, spacing and springs are design tokens in DS
// (Views/Theme/DroppyDesign.swift).

public struct DroppyShelfMetrics {
    /// Width of the open shelf. Every page is laid out against this.
    /// The reference's shelf body measures ~562 pt; the shape's top fillets
    /// (Theming's 12 pt ears, one each side) come on top of that.
    public static let width: CGFloat = 586
    /// The home page with two widgets side by side: the same regular width.
    public static let wideWidth: CGFloat = 586
    /// The full player alone: narrower, like Alcove's, so it doesn't sprawl.
    /// Settings › HUDs › Media › Now Playing Size shrinks it with the rest.
    public static var playerWidth: CGFloat { (400 * PlayerMetrics.scale).rounded() }
    /// The full player with Lyrics or Playing Next open beside it.
    public static var playerWithSidePanelWidth: CGFloat {
        playerWidth + PlayerMetrics.sidePanelGap + PlayerMetrics.sidePanelWidth
    }
    /// Height of the full player without a panel folded out.
    public static var playerHeight: CGFloat {
        PlayerMetrics.artwork + PlayerMetrics.scrubberGap + PlayerMetrics.scrubberHeight
            + PlayerMetrics.controlsGap + PlayerMetrics.controlsHeight
    }
    public static let horizontalPadding: CGFloat = 26
    public static let bottomPadding: CGFloat = 18
    /// Bottom corners of the open shelf, the big soft curve Tama is known for.
    public static let cornerRadius: CGFloat = 35
    /// Settings › Shelf › Enlarged: the whole open shelf is drawn this much larger.
    public static let enlargedScale: CGFloat = 1.12
    /// Wings used by the volume / brightness HUD.
    public static let hudWing: CGFloat = 118
    /// Wings the resting notch grows on each side while music plays. The outer
    /// `restingEar` of it is eaten by the shape's top fillet, so only
    /// `miniWing - restingEar` is visible. Matched to Alcove: 37 pt per side.
    public static let miniWing: CGFloat = 43
    /// Top fillet of the resting notch; the shape's body starts this far in.
    public static let restingEar: CGFloat = 6
    /// The floating navigation bar under the open shelf: one glass capsule of
    /// three ~29 pt segments (95 × 30 pt), ~12 pt below the shelf.
    public static let lanePillHeight: CGFloat = 30
    public static let lanePillGap: CGFloat = 12
    public static let navSegmentWidth: CGFloat = 29
    public static let navSegmentHeight: CGFloat = 26
    public static let navBarWidth: CGFloat = navSegmentWidth * 3 + 2 * 2 + 4
    /// Round glass buttons beside the bar (Calendar, favorites, page buttons).
    /// Settings › Shelf › Favorites › Floating button size picks the diameter;
    /// reading it here keeps the layout and the panel geometry in step.
    public static var floatingButton: CGFloat { FloatingButtonSize.stored.diameter }
    public static let floatingButtonSpacing: CGFloat = 8
    /// "Regular buttons": the page tabs inside the notch wings.
    public static let wingTab: CGFloat = 26
    /// Without a notch the tabs need a row of their own at the top.
    public static let wingTabRow: CGFloat = 38
    /// The secondary live activity's round pill, and its gap to the island.
    public static let secondaryActivityGap: CGFloat = 6
    /// A live activity with words beside its icon (the call timer) or the
    /// mic meter needs a little more than a mini wing.
    public static let activityWing: CGFloat = 78
    /// The Home page's weather card beside the player.
    public static let weatherCardWidth: CGFloat = 210
    /// The floating lyrics window and the expanded album art.
    public static let lyricsWindowSize = CGSize(width: 350, height: 240)
    public static let artworkWindowSide: CGFloat = 380
    /// The floating Basket: header, a two-row grid (or list) of files.
    public static let basketWidth: CGFloat = 340
    public static let basketHeight: CGFloat = 238
    /// A file tile on the Shelf and in the Basket.
    public static let fileTile: CGFloat = 56

    // MARK: Island shapes

    /// Stand-in notch width when the screen doesn't report its notch areas.
    public static let fallbackNotchWidth: CGFloat = 190
    /// The floating pill on notchless screens: resting, and with a live activity.
    public static let pillWidth: CGFloat = 170
    public static let pillActiveWidth: CGFloat = 250
    public static let pillHeight: CGFloat = 34
    /// The level HUD's body between its wings on a notchless screen.
    public static let hudPillBody: CGFloat = 110
    /// Settings › HUDs › Size: how far each slider may move its surface, in
    /// points from the standard size above (0 = "Standard").
    public static let islandHeightRange: ClosedRange<Double> = -6...12
    public static let islandWidthRange: ClosedRange<Double> = -40...80
    public static let notchHeightRange: ClosedRange<Double> = -8...12
    public static let notchWidthRange: ClosedRange<Double> = -60...80
    /// A notch HUD is never squeezed shorter than this.
    public static let minimumHUDHeight: CGFloat = 24
    /// The floating desktop volume / brightness sliders.
    public static let desktopSliderSize = CGSize(width: 220, height: 40)
    /// The notch banner: this much wider than the notch, never narrower than
    /// `notificationMinWidth`, and this far below it (or this tall as a pill).
    public static let notificationExtraWidth: CGFloat = 180
    public static let notificationMinWidth: CGFloat = 420
    public static let notificationDrop: CGFloat = 48
    public static let notificationPillHeight: CGFloat = 56
    /// The Keep / Share / AirDrop / Convert tiles under the notch.
    public static let quickActionsHeight: CGFloat = 98
    /// Extra canvas around the island so the spring can overshoot unclipped.
    public static let canvasSlack = CGSize(width: 80, height: 60)

    // MARK: Page heights (the content under the notch, without padding)

    public static let trayPageHeight: CGFloat = 132
    public static let widgetsPageHeight: CGFloat = 124
    /// The widgets page with a droplet's console open.
    public static let widgetsConsoleHeight: CGFloat = 290
    /// Rearrange mode: every widget in a grid you can drag icons around in.
    public static let widgetsGridColumns = 7
    public static let widgetsGridCell = CGSize(width: 72, height: 76)
    public static let widgetsGridHeader: CGFloat = 36
    public static let calendarPageHeight: CGFloat = 184
    /// Pomodoro, High Alert and the Timer: a ruler over one row of controls,
    /// with no header (✕ beside the navigation bar closes them).
    public static let rulerConsoleHeight: CGFloat = 118
    /// The Timer adds its Timer | Stopwatch switch above the ruler.
    public static let timerConsoleHeight: CGFloat = 130
    /// Notes can grow the console up to this with Grow canvas on.
    public static let notesMaxConsoleHeight: CGFloat = 440
    /// The Ring lists up to eight actions, the catalog of the rest and Reset.
    public static let ringConsoleHeight: CGFloat = 440
    /// LiquidMouse adds a permission banner above its rows until access is granted.
    public static let liquidMouseConsoleHeight: CGFloat = 350
    /// The pop-out calendar window.
    public static let calendarPopoutSize = CGSize(width: 560, height: 260)

    /// The open console's page height for a droplet.
    public static func consoleHeight(for id: String) -> CGFloat {
        switch id {
        case "pomodoro", "caffeine": return rulerConsoleHeight
        case "timer": return timerConsoleHeight
        case "ring": return ringConsoleHeight
        case "liquidMouse": return liquidMouseConsoleHeight
        default: return widgetsConsoleHeight
        }
    }

    /// Consoles drawn without the back-button header.
    public static let headerlessConsoles: Set<String> = ["pomodoro", "caffeine", "timer", "scratchpad", "obsidian", "termiNotch"]
    /// TermiNotch: the whole shelf is the terminal; the quick bar is short.
    public static let termiNotchExpandedHeight: CGFloat = 300
    public static let termiNotchBarHeight: CGFloat = 116
}

/// Sizes inside the full player (Settings-free, matched to Alcove). The
/// player's own height, `DroppyShelfMetrics.playerHeight`, is the sum of the
/// rows below: artwork + scrubber gap + scrubber + controls gap + controls.
public enum PlayerMetrics {
    /// Settings › HUDs › Media › Now Playing Size. Smaller draws the whole
    /// player at this factor, so the shelf is more compact while music plays.
    /// Read straight from the defaults: the metrics are `static`, so there is
    /// nowhere isolated to cache it, and a defaults read is a dictionary hit.
    public static var scale: CGFloat { NowPlayingSize.stored.scale }
    /// Rounded to a whole point, so rows still line up.
    private static func pt(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }
    /// Type and hairlines keep their fractions.
    private static func fine(_ value: CGFloat) -> CGFloat { value * scale }

    public static var artwork: CGFloat { pt(70) }
    public static var artworkRadius: CGFloat { pt(14) }
    public static var sourceBadge: CGFloat { pt(21) }
    public static var headerSpacing: CGFloat { pt(14) }
    public static var titleSize: CGFloat { fine(15) }
    public static var subtitleSize: CGFloat { fine(13) }
    public static var scrubberGap: CGFloat { pt(12) }
    public static var scrubberHeight: CGFloat { pt(14) }
    public static var trackThickness: CGFloat { fine(5) }
    public static var trackThicknessScrubbing: CGFloat { fine(7) }
    public static var timeSize: CGFloat { fine(10.5) }
    public static var timeMinWidth: CGFloat { pt(30) }
    public static var controlsGap: CGFloat { pt(4) }
    public static var controlsHeight: CGFloat { pt(34) }
    public static var playIcon: CGFloat { fine(22) }
    public static var skipIcon: CGFloat { fine(17) }
    public static var transportFrame: CGSize { CGSize(width: pt(36), height: pt(34)) }
    public static var sideButton: CGFloat { pt(28) }
    public static var sideIcon: CGFloat { fine(12.5) }
    /// Lyrics / Playing Next beside the player, after a hairline divider.
    public static var sidePanelWidth: CGFloat { pt(250) }
    public static var sidePanelGap: CGFloat { pt(25) }
    /// Playing Next rows: a cover thumbnail, title and artist.
    public static var queueRowHeight: CGFloat { pt(38) }
    public static var queueArtwork: CGFloat { pt(30) }
    /// The audio quality badge beside the title.
    public static var qualityBadgeHeight: CGFloat { pt(15) }
    /// The output picker: its grabber row, then one row per output.
    public static var outputPickerTop: CGFloat { pt(26) }
    public static var outputRowPitch: CGFloat { pt(38) }
}

/// Settings › HUDs › Media › Now Playing Size.
public enum NowPlayingSize: String, CaseIterable, Identifiable, Sendable {
    case regular
    case smaller

    public static let key = "nowPlayingSize"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .regular: "Regular"
        case .smaller: "Smaller"
        }
    }

    public var icon: String {
        switch self {
        case .regular: "rectangle"
        case .smaller: "rectangle.compress.vertical"
        }
    }

    public var scale: CGFloat {
        switch self {
        case .regular: 1
        case .smaller: 0.86
        }
    }

    /// What the metrics read. `AppState.nowPlayingSize` writes the same key.
    static var stored: NowPlayingSize {
        NowPlayingSize(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .regular
    }
}

/// The screenshot preview card and pinned screenshots.
public enum CaptureMetrics {
    public static let previewWidth: CGFloat = 360
    public static let previewPadding: CGFloat = 18
    public static let previewRadius: CGFloat = 26
    public static let previewHeader: CGFloat = 40
    public static let previewWellRadius: CGFloat = 16
    public static let previewWellMin: CGFloat = 96
    public static let previewWellMax: CGFloat = 210
    public static let previewButton: CGFloat = 50
    public static let previewSpacing: CGFloat = 14
    /// Distance from the screen's visible edges.
    public static let previewMargin: CGFloat = 20
    /// A new pin's longest side, and the smallest it can be resized to.
    public static let pinLongestSide: CGFloat = 420
    public static let pinMinSide: CGFloat = 80
}

public struct DroppyLayout {
    // Resting pill
    public static let compactWidth: CGFloat = 220
    public static let compactHeight: CGFloat = 34
    public static let compactCornerRadius: CGFloat = 17

    // Expanded panel — the Shelf Stack sizes itself, see DroppyStackMetrics
    public static let expandedCornerRadius: CGFloat = 24

    // Island-level springs. Everything inside the panel uses DS.Motion.
    public static let springAnimation = DS.Motion.fluid
    public static let expandSpring = DS.Motion.morphOpen
    public static let collapseSpring = DS.Motion.morphClose
    public static let hoverSpring = DS.Motion.hover
}

/// Sizes of the free-floating tool windows (not part of the island).
public enum ToolWindowMetrics {
    /// Voice Transcribe › External Recorder.
    public static let recorderSize = CGSize(width: 380, height: 300)
    /// Thunderstorm: the bar alone, and the most the results may grow it to.
    public static let launcherWidth: CGFloat = 680
    public static let launcherBarHeight: CGFloat = 56
    public static let launcherMaxHeight: CGFloat = 470
    public static let launcherRowHeight: CGFloat = 50
    public static let launcherCornerRadius: CGFloat = 26
    /// LocalSend's incoming-transfer prompt.
    public static let localSendPromptSize = CGSize(width: 360, height: 150)
    /// Settings › Droplets: hero carousel height and list icon size.
    public static let dropletHeroHeight: CGFloat = 230
    public static let dropletListIcon: CGFloat = 56
    /// What's New and Setup Guide sheets.
    public static let whatsNewSize = CGSize(width: 460, height: 520)
    /// The crash-report panel: wide enough for a backtrace line to fit.
    public static let crashReportSize = CGSize(width: 560, height: 520)
}

extension ClosedRange where Bound == Double {
    /// The value pulled inside the range.
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
