import SwiftUI

/// Settings › Shelf: the open shelf's size, navigation and behaviour.
@MainActor
public final class ShelfSettings: SettingsStore {
    public static let shared = ShelfSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "shelfEnabled", "shelfSize", "shelfNavigationStyle", "showCalendarButton",
        FloatingButtonSize.key, "floatingButtonStyle", "floatingButtonLightIcons",
        "shelfFavorites", "autoCollapse", "animationSpeed", "shelfGestures", "shelfSwipeReversed",
        "openTrayAfterDrop", "defaultShelfPage"
    ]

    /// The Shelf master switch. Off, the island never opens into the shelf;
    /// HUDs, banners and live activities still show in the notch.
    @AppStorage("shelfEnabled") public var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                AppState.shared.cancelHomeCustomization()
                AppState.shared.isRearrangingWidgets = false
                AppState.shared.isIslandPinned = false
                AppState.shared.setIslandExpanded(false)
            }
            AppState.shared.islandFrameChanged()
        }
    }
    /// Regular or Enlarged: the open shelf is scaled as a whole.
    @AppStorage("shelfSize") public var size: ShelfSize = .regular {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("shelfNavigationStyle") public var navigationStyle: ShelfNavigationStyle = .floatingBar {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// A round Calendar button beside the floating bar (the Calendar page's
    /// way in, now that the bar only holds Home, Tray and Widgets).
    @AppStorage("showCalendarButton") public var showCalendarButton: Bool = true {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Settings › Shelf › Favorites: how the round buttons under the shelf
    /// are drawn. The size key is `FloatingButtonSize.key`, which
    /// `DroppyShelfMetrics.floatingButton` reads back.
    @AppStorage(FloatingButtonSize.key) public var floatingButtonSize: FloatingButtonSize = .regular {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("floatingButtonStyle") public var floatingButtonStyle: FloatingButtonStyle = .glass
    /// Icon and text colour on a colored floating button.
    @AppStorage("floatingButtonLightIcons") public var floatingButtonLightIcons: Bool = true
    /// Up to four favorites beside the floating bar; see `ShelfFavorite`.
    @AppStorage("shelfFavorites") public var favoritesStorage: String = "" {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Off: the shelf stays open until a click elsewhere or Esc.
    @AppStorage("autoCollapse") public var autoCollapse: Bool = true
    @AppStorage("animationSpeed") public var animationSpeed: ShelfAnimationSpeed = .human
    /// Two-finger swipes: down on the notch opens the shelf (when scrolling
    /// there isn't set to change the volume), sideways switches pages.
    @AppStorage("shelfGestures") public var gestures: Bool = true
    /// Settings › Shelf › Behavior › Swipe direction: Reversed flips which way
    /// a sideways swipe moves between pages and between the Tray's two stacks.
    @AppStorage("shelfSwipeReversed") public var swipeReversed: Bool = false
    /// Dropping files on the notch opens the Tray to show them.
    @AppStorage("openTrayAfterDrop") public var openTrayAfterDrop: Bool = true
    @AppStorage("defaultShelfPage") public var defaultPage: DefaultShelfPage = .home

    private init() { super.init(keys: Self.keys) }
}
