import SwiftUI
import Combine

// The island's shape for every mode and screen. The panel is only a
// transparent canvas; these sizes drive the SwiftUI shape, so the morph runs
// on one spring and the NSPanel frame and hit-testing agree with it.

extension AppState {
    /// Height of the hardware notch on the target screen (0 without one).
    public var notchHeight: CGFloat { notchHeight(on: nil) }

    /// Notch height on a given screen; nil is the live island's screen.
    public func notchHeight(on displayID: CGDirectDisplayID?) -> CGFloat {
        screen(for: displayID)?.safeAreaInsets.top ?? 0
    }

    /// Vertical room the hardware notch steals from the top of the shelf.
    public var islandTopInset: CGFloat {
        notchHeight > 0 ? notchHeight + 4 : DS.Space.lg
    }

    /// Room above the open shelf's pages: the notch, or — without one — a
    /// small margin, or a row for the page tabs in "Regular buttons" style.
    public var shelfTopInset: CGFloat {
        if notchHeight > 0 { return notchHeight + 4 }
        return ShelfSettings.shared.navigationStyle == .regularButtons ? DroppyShelfMetrics.wingTabRow : DS.Space.lg
    }

    /// Settings › Shelf › Regular | Enlarged.
    public var shelfScale: CGFloat { ShelfSettings.shared.size.scale }

    /// Whether the island is allowed to close itself right now.
    public var canAutoCollapse: Bool {
        // Customising keeps the shelf open until it's confirmed or cancelled.
        !isIslandPinned && !isModalPresented && !isDragHovering && !isCustomizingHome && !isEditingText
            && !isRearrangingWidgets
    }

    // MARK: - Island geometry
    // The panel is only a transparent canvas; these sizes drive the SwiftUI shape,
    // so the morph runs on one spring instead of racing an NSWindow animation.

    /// Gap above the island when it floats free of the bezel.
    public var islandTopOffset: CGFloat { islandTopOffset(on: nil) }

    public func islandTopOffset(on displayID: CGDirectDisplayID?) -> CGFloat {
        let hasNotch = notchHeight(on: displayID) > 0
        // Settings › Theming › Media HUD position nudges the floating pill.
        return (GeneralSettings.shared.islandStyle == .floatingPill && !hasNotch) ? max(0, 8 + DisplaySettings.shared.mediaHUDVerticalOffset) : 0
    }

    public var hardwareNotchWidth: CGFloat { hardwareNotchWidth(on: nil) }

    public func hardwareNotchWidth(on displayID: CGDirectDisplayID?) -> CGFloat {
        guard let screen = screen(for: displayID),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.width > 0, right.width > 0 else { return DroppyShelfMetrics.fallbackNotchWidth }
        let diff = right.minX - left.maxX
        return diff > 50 ? diff : DroppyShelfMetrics.fallbackNotchWidth
    }

    /// Something worth a wing on the resting notch: music, held files or a running timer.
    public var hasMiniActivity: Bool { hasMiniActivity(on: nil) }

    /// The same for one screen: In fullscreen › Hide media leaves music out there.
    /// The urgent live activity in the wings wants the wider wings (a call
    /// timer with its mic meter).
    public func showsWideActivity(on displayID: CGDirectDisplayID?) -> Bool {
        guard let urgent = LiveActivityCenter.shared.top(.urgent), urgent.isWide else { return false }
        return !(HUDSettings.shared.compactHUDPriority == .mediaFirst && mediaService.currentTrack.hasTrack && showsMedia(on: displayID))
    }

    public func hasMiniActivity(on displayID: CGDirectDisplayID?) -> Bool {
        (mediaService.currentTrack.hasTrack && showsMedia(on: displayID)) || !shelfItems.isEmpty || isPomodoroActive
            || sleepBlocker.isAwakeActive || !LiveActivityCenter.shared.activities.isEmpty
    }

    // MARK: Size sliders (Settings › HUDs › Size)

    /// The floating pill's height on screens without a notch (Island height).
    public var pillHeight: CGFloat {
        DroppyShelfMetrics.pillHeight + CGFloat(DroppyShelfMetrics.islandHeightRange.clamp(DisplaySettings.shared.islandHeightOffset))
    }

    /// Extra width of the floating pill, resting or with a HUD (Island width).
    public var pillWidthOffset: CGFloat {
        CGFloat(DroppyShelfMetrics.islandWidthRange.clamp(DisplaySettings.shared.islandWidthOffset))
    }

    /// Each wing of a level HUD: on a notched display Notch width tunes it.
    public func hudWing(on displayID: CGDirectDisplayID?) -> CGFloat {
        guard notchHeight(on: displayID) > 0 else { return DroppyShelfMetrics.hudWing }
        return DroppyShelfMetrics.hudWing + CGFloat(DroppyShelfMetrics.notchWidthRange.clamp(DisplaySettings.shared.notchHUDWidthOffset)) / 2
    }

    /// The wing the resting notch grows on each side. The physical notch is a
    /// fixed cut-out, so the resting surface hugs it: only a small wing for the
    /// art and the wave (a little more for a wide live activity). The track
    /// title never widens it — that belongs to the floating pill and the open
    /// player, or the resting notch would draw a black bar across the menu bar.
    nonisolated static func restingNotchWing(isActive: Bool, wide: Bool) -> CGFloat {
        guard isActive else { return 0 }
        return wide ? DroppyShelfMetrics.activityWing : DroppyShelfMetrics.miniWing
    }

    public var islandCompactSize: CGSize { islandCompactSize(on: nil) }

    /// A mirror (another screen's look-alike) never peeks: the pointer and the
    /// drag belong to the live island.
    public func islandCompactSize(on displayID: CGDirectDisplayID?) -> CGSize {
        // Hovering the resting notch lets the shape peek out a little — the
        // glass itself grows, like the Dynamic Island, rather than scaling.
        let notchHeight = notchHeight(on: displayID)
        let isLive = displayID == nil
        let base: CGSize
        let isActive = hasMiniActivity(on: displayID)
        if notchHeight > 0 {
            let wing = Self.restingNotchWing(isActive: isActive, wide: showsWideActivity(on: displayID))
            base = CGSize(width: hardwareNotchWidth(on: displayID) + wing * 2, height: notchHeight)
        } else {
            // No notch: Tama floats a Dynamic Island pill instead.
            let width = isActive ? DroppyShelfMetrics.pillActiveWidth : DroppyShelfMetrics.pillWidth
            base = CGSize(width: width + pillWidthOffset, height: pillHeight)
        }
        // A nearby file drag pulls it a touch further (~5% wider, 6 pt taller).
        let peek: CGSize
        if isLive && isDragNear {
            peek = CGSize(width: (base.width * 0.05).rounded(), height: 6)
        } else if isLive && isIslandHovered && notchHeight == 0 {
            // A notched island keeps the hardware's outline; only the pill peeks.
            peek = CGSize(width: 6, height: 4)
        } else {
            peek = .zero
        }
        return CGSize(width: base.width + peek.width, height: base.height + peek.height)
    }

    public var islandHUDSize: CGSize { islandHUDSize(on: nil) }

    public func islandHUDSize(on displayID: CGDirectDisplayID?) -> CGSize {
        let notchHeight = notchHeight(on: displayID)
        let wings = hudWing(on: displayID) * 2
        guard notchHeight > 0 else {
            return CGSize(width: DroppyShelfMetrics.hudPillBody + pillWidthOffset + wings, height: pillHeight)
        }
        // Notch height tunes how far the HUD reaches below the hardware notch.
        let height = max(notchHeight + CGFloat(DroppyShelfMetrics.notchHeightRange.clamp(DisplaySettings.shared.notchHUDHeightOffset)),
                         DroppyShelfMetrics.minimumHUDHeight)
        return CGSize(width: hardwareNotchWidth(on: displayID) + wings, height: height)
    }

    public var islandNotificationSize: CGSize { islandNotificationSize(on: nil) }

    public func islandNotificationSize(on displayID: CGDirectDisplayID?) -> CGSize {
        let notchHeight = notchHeight(on: displayID)
        return CGSize(
            width: max(hardwareNotchWidth(on: displayID) + DroppyShelfMetrics.notificationExtraWidth, DroppyShelfMetrics.notificationMinWidth),
            height: notchHeight > 0 ? notchHeight + DroppyShelfMetrics.notificationDrop : DroppyShelfMetrics.notificationPillHeight
        )
    }

    public var islandQuickActionsSize: CGSize {
        CGSize(width: DroppyShelfMetrics.width, height: islandTopInset + DroppyShelfMetrics.quickActionsHeight)
    }

    public var islandExpandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedPanelHeight)
    }

    /// The open shelf's width as drawn (Enlarged scales it).
    public var expandedWidth: CGFloat { (unscaledExpandedWidth * shelfScale).rounded() }

    /// Two home cards need the wide shelf; the full player alone a narrow one.
    /// The pages lay out against this; Enlarged scales the result.
    public var unscaledExpandedWidth: CGFloat {
        if isHomeWide { return DroppyShelfMetrics.wideWidth }
        if shelfPage == .home && showsFullPlayer {
            // Lyrics and Playing Next open beside the player, not under it.
            return playerPanel == .none ? DroppyShelfMetrics.playerWidth : DroppyShelfMetrics.playerWithSidePanelWidth
        }
        return DroppyShelfMetrics.width
    }

    /// The Widgets page in rearrange mode: a header and a grid of every widget.
    public var widgetsGridHeight: CGFloat {
        let count = max(droplets.filter(\.isEnabled).count, 1)
        let rows = (count + DroppyShelfMetrics.widgetsGridColumns - 1) / DroppyShelfMetrics.widgetsGridColumns
        return DroppyShelfMetrics.widgetsGridHeader + CGFloat(rows) * DroppyShelfMetrics.widgetsGridCell.height
    }

    /// What the island is showing right now — the one state machine the shape,
    /// its content and the hit-testing all read from. Higher cases win.
    public var islandMode: IslandMode {
        IslandMode.resolve(isDragHovering: isDragHovering, isExpanded: isIslandExpanded,
                           hasNotification: activeNotification != nil, hasHUD: hud != nil)
    }

    /// The mode a screen shows. The shelf and the drop tiles only open on the
    /// live island's screen; the other screens' mirrors keep resting.
    /// A level HUD answers a key press, so it belongs where the user is looking:
    /// in All Displays the mirrors keep resting instead of flashing it too.
    public func islandMode(on displayID: CGDirectDisplayID?) -> IslandMode {
        let mode = islandMode
        guard displayID != nil, mode.isOpen || mode == .hud else { return mode }
        // Settings › HUDs › Collapsed HUD scope › All displays: every island shows it.
        if mode == .hud, HUDSettings.shared.collapsedHUDScope == .allDisplays { return .hud }
        return IslandMode.resolve(isDragHovering: false, isExpanded: false,
                                  hasNotification: activeNotification != nil, hasHUD: false)
    }

    /// The shape for the current mode. Everything about the outline lives here,
    /// so the view animates one value on one spring.
    public var islandGeometry: IslandGeometry { islandGeometry(on: nil) }

    /// The shape on a given screen: a mirror draws its own screen's notch (or
    /// pill), not the live screen's.
    public func islandGeometry(on displayID: CGDirectDisplayID?) -> IslandGeometry {
        let mode = islandMode(on: displayID)
        let notchHeight = notchHeight(on: displayID)
        let size: CGSize
        switch mode {
        case .dropTarget: size = islandQuickActionsSize
        case .shelf: size = islandExpandedSize
        case .notification: size = islandNotificationSize(on: displayID)
        case .hud: size = islandHUDSize(on: displayID)
        case .resting: size = islandCompactSize(on: displayID)
        }

        let cornerRadius: CGFloat
        switch mode {
        case .dropTarget, .shelf: cornerRadius = DroppyShelfMetrics.cornerRadius
        case .notification, .hud: cornerRadius = 14
        // The MacBook notch's own bottom corners.
        case .resting: cornerRadius = notchHeight > 0 ? 9 : DroppyLayout.compactCornerRadius
        }

        let earRadius: CGFloat
        if notchHeight > 0 || GeneralSettings.shared.islandStyle == .notchAttached {
            earRadius = mode.isOpen ? ThemeSettings.shared.notchEarFilletRadius : DroppyShelfMetrics.restingEar
        } else {
            earRadius = 0
        }
        return IslandGeometry(size: size, cornerRadius: cornerRadius, earRadius: earRadius)
    }

    /// Size the island shape should be right now.
    public var islandSize: CGSize { islandGeometry.size }

    /// Whether the shelf (or the drag tiles) is open, i.e. the big shape.
    public var isIslandOpen: Bool { islandMode.isOpen }

    // MARK: Navigation under the shelf

    /// Settings › Shelf › Favorites, decoded.
    public var shelfFavorites: [ShelfFavorite] {
        get { ShelfFavorite.decode(ShelfSettings.shared.favoritesStorage) }
        set { ShelfSettings.shared.favoritesStorage = ShelfFavorite.encode(newValue) }
    }

    /// The floating Calendar button: only with the floating bar, which has no
    /// Calendar segment ("Regular buttons" puts Calendar in the right wing).
    public var showsCalendarFloatingButton: Bool {
        ShelfSettings.shared.navigationStyle == .floatingBar && ShelfSettings.shared.showCalendarButton
    }

    /// How many round glass buttons sit beside (or, without the bar, make up)
    /// the navigation row: Calendar, the page's own buttons, then favorites.
    public var floatingButtonCount: Int {
        (showsCalendarFloatingButton ? 1 : 0) + ShelfAccessoryCenter.shared.visible.count + shelfFavorites.count
    }

    /// Size of the navigation row floating under the open shelf.
    public var lanePillSize: CGSize {
        let bar = ShelfSettings.shared.navigationStyle == .floatingBar ? 1 : 0
        let buttons = floatingButtonCount
        let items = bar + buttons
        let width = CGFloat(bar) * DroppyShelfMetrics.navBarWidth
            + CGFloat(buttons) * DroppyShelfMetrics.floatingButton
            + CGFloat(max(items - 1, 0)) * DroppyShelfMetrics.floatingButtonSpacing
        return CGSize(width: width, height: DroppyShelfMetrics.lanePillHeight)
    }

    /// Whether the navigation row is on screen: the shelf is open and there's
    /// a bar or at least one button to show.
    public var showsLanePill: Bool {
        isIslandExpanded && !isDragHovering && lanePillSize.width > 0
    }

    /// Transparent canvas the panel needs for the state it is in, plus room for
    /// the spring to overshoot and for the lane pill under the shelf.
    public var islandCanvasSize: CGSize {
        let size = islandSize
        let pill = showsLanePill ? DroppyShelfMetrics.lanePillGap + DroppyShelfMetrics.lanePillHeight : 0
        let width = max(size.width, showsLanePill ? lanePillSize.width : 0)
        return CGSize(width: width + DroppyShelfMetrics.canvasSlack.width,
                      height: size.height + islandTopOffset + pill + DroppyShelfMetrics.canvasSlack.height)
    }

    /// Full height of the open shelf, shared by the SwiftUI layout and the NSPanel frame.
    /// Enlarged scales everything below the notch; the notch itself doesn't grow.
    public var expandedPanelHeight: CGFloat {
        (shelfTopInset + (pageHeight(shelfPage) + DroppyShelfMetrics.bottomPadding) * shelfScale).rounded()
    }

    // MARK: Multi Live Activities

    /// Diameter of the round pill a second live activity gets beside the
    /// resting island: as tall as the island.
    public func secondaryActivityDiameter(on displayID: CGDirectDisplayID?) -> CGFloat {
        let notch = notchHeight(on: displayID)
        return notch > 0 ? notch : pillHeight
    }
}

extension NSScreen {
    /// The Mac's own panel, whatever the display is called in this locale.
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
}
