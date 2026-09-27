import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shelf

/// Settings › Shelf, laid out like the reference: The Shelf (on/off, Regular |
/// Enlarged), Navigation style, Multi Live Activities, Widgets (Custom Shelf,
/// Widget icons, Widget settings, Favorites) and Behavior — then our own
/// Pages, Player, Tray, then Tasks & Calendar, Pomodoro, High Alert and Notes.
struct ShelfSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @AppStorage(LyricsService.onlineKey) private var lyricsOnline = false

    private var enabledWidgetCount: Int { state.droplets.filter(\.isEnabled).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("The Shelf") {
                SettingsGroup {
                    SettingsToggleRow("The Shelf",
                                      subtitle: state.shelfEnabled ? nil : "Off: the size, navigation, widget and behavior options below don't apply.",
                                      icon: "tray.fill",
                                      help: "The shelf that opens out of the notch, with Home, Tray, Widgets and Calendar. Off, the notch never opens into it; volume and brightness HUDs, banners and live activities still show.",
                                      anchor: "shelf.enable", isOn: $state.shelfEnabled)
                    ChoiceTiles([
                        .init(ShelfSize.regular, "Regular", icon: "rectangle.inset.topleft.filled"),
                        .init(.enlarged, "Enlarged", icon: "arrow.up.left.and.arrow.down.right"),
                    ], selection: $state.shelfSize, anchor: "shelf.size")
                    .settingsDisabled(!state.shelfEnabled)
                }
            }

            Group {
                SettingsSection("Navigation style",
                                help: "Where the Home, Tray and Widgets buttons appear while the shelf is open: tabs in the notch wings, or a glass capsule floating under the shelf.") {
                    SettingsGroup {
                        PreviewCardPicker([
                            .init(ShelfNavigationStyle.regularButtons, "Regular buttons"),
                            .init(.floatingBar, "Floating bar"),
                        ], selection: $state.shelfNavigationStyle, thumbnailHeight: 84, anchor: "shelf.navStyle") { style in
                            NavigationStyleThumbnail(style: style)
                        }
                        SettingsDivider()
                        SettingsToggleRow("Calendar button",
                                          subtitle: state.shelfNavigationStyle == .floatingBar
                                            ? "A round button beside the floating bar. ⌘4 opens the Calendar either way."
                                            : "Regular buttons keep the Calendar in the right wing.",
                                          anchor: "shelf.calendarButton", isOn: $state.showCalendarButton)
                            .settingsDisabled(state.shelfNavigationStyle != .floatingBar)
                    }
                }

                SettingsSection("Multi Live Activities",
                                help: "When two things are live at once — a call and music, a timer and a download — the second gets its own round pill beside the notch instead of waiting its turn.") {
                    SettingsGroup {
                        PreviewCardPicker([
                            .init(true, "On"),
                            .init(false, "Off"),
                        ], selection: $state.multiLiveActivities, thumbnailHeight: 84, anchor: "shelf.multiLive") { on in
                            MultiLiveThumbnail(isOn: on)
                        }
                    }
                }

                widgets
                behavior
            }
            .settingsDisabled(!state.shelfEnabled)

            pages

            SettingsSection("Player") {
                SettingsGroup {
                    SettingsToggleRow("Fetch lyrics online (LRCLIB)",
                                      subtitle: "Sends the playing song's title, artist, album and length to lrclib.net. Results are cached on your Mac.",
                                      anchor: "shelf.player", isOn: $lyricsOnline)
                    SettingsDivider()
                    SettingsToggleRow("Auto-expand lyrics",
                                      subtitle: lyricsOnline
                                        ? "Open the lyrics card beside the player on its own when the song has lyrics."
                                        : "Needs Fetch lyrics online.",
                                      help: "Timed lyrics beside your media widget: when the shelf opens on the player and LRCLIB has the song, the lyrics card opens next to it. The card's expand button pops them out into a floating window.",
                                      anchor: "shelf.autoExpandLyrics", isOn: $state.autoExpandLyrics)
                        .settingsDisabled(!lyricsOnline)
                    SettingsNote("Lyrics and Playing Next open beside the player. Playing Next shows the upcoming tracks of Apple Music's current playlist; Spotify and browsers don't share their queue.")
                }
            }

            SettingsSection("Tray & screenshots") {
                SettingsGroup {
                    SettingsRow("Tray capacity", subtitle: "The oldest unpinned files leave first.", anchor: "shelf.tray") {
                        Stepper("\(state.trayCapacity) files", value: $state.trayCapacity, in: 5...100, step: 5)
                    }
                    SettingsDivider()
                    ShelfFileRows()
                    SettingsDivider()
                    SettingsToggleRow("Show a preview in the corner after a snip",
                                      subtitle: "Annotate, copy, keep in the Tray, copy its text or pin it on screen.",
                                      anchor: "shelf.screenshots", isOn: $state.showCapturePreview)
                    Group {
                        SettingsRow("Preview placement",
                                    subtitle: state.showCapturePreview ? nil : "Needs the preview above.",
                                    help: "Bottom right keeps the card in the same place every time. Closest corner puts it in the screen corner nearest the pointer, so it doesn't land on what you just captured.",
                                    anchor: "shelf.capturePlacement")
                        ChoiceTiles(CapturePreviewPlacement.allCases.map { .init($0, $0.title, icon: $0.icon) },
                                    selection: $state.capturePreviewPlacement)
                    }
                    .settingsDisabled(!state.showCapturePreview)
                }
            }

            TasksCalendarSettingsSection()
            PomodoroSettingsSection()
            HighAlertSettingsSection()
            NotesSettingsSection()
        }
    }

    // MARK: Widgets

    private var widgets: some View {
        SettingsSection("Widgets") {
            VStack(spacing: 12) {
                SettingsGroup {
                    SettingsRow("Custom Shelf",
                                help: "A live preview of Home. Pick up to two widgets below, or use the hand to open the real shelf in edit mode.",
                                anchor: "shelf.customShelf")
                    CustomShelfPreview()
                        .padding(.horizontal, 12)
                    HomeWidgetChips()
                        .padding(12)
                }
                SettingsGroup {
                    SettingsRow("Widget icons",
                                help: "The widgets on the Widgets page, in their order. Drag an icon to move it, or use the hand to rearrange them on the shelf itself.",
                                anchor: "shelf.widgetIcons")
                    WidgetIconsPreview()
                        .padding([.horizontal, .bottom], 12)
                }
                SettingsGroup {
                    SummaryDisclosureRow("Widget settings",
                                         subtitle: "Configure every widget, whether or not it's on the shelf.",
                                         done: enabledWidgetCount, total: state.droplets.count,
                                         unit: "widgets active", anchor: "shelf.widgetSettings") {
                        VStack(alignment: .leading, spacing: 0) {
                            // Keyed by the droplet's id, not its index, so a
                            // reorder moves rows instead of relabelling them.
                            ForEach($state.droplets) { $droplet in
                                if droplet.id != state.droplets.first?.id { SettingsDivider() }
                                HStack(spacing: 10) {
                                    DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(droplet.name).font(SettingsStyle.rowTitle)
                                        Text(droplet.tag).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Toggle(droplet.name, isOn: $droplet.isEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                            }
                        }
                    }
                }
                SettingsGroup {
                    SettingsRow("Favorites",
                                help: "Up to four round buttons beside the navigation bar under the shelf: a widget, an app, or a Shortcut from the Shortcuts app.",
                                anchor: "shelf.favorites")
                    FavoritesEditor()
                        .padding(.horizontal, 12)
                    SettingsNote("Click a slot to pick a widget, an app or a shortcut, or to remove it. Favorites sit beside the floating navigation bar under your shelf.",
                                 icon: "hand.point.up.left")
                        .padding(.top, 10)
                    SettingsDivider()
                    SettingsRow("Floating button size",
                                help: "How big the round buttons under the shelf are — the Calendar, the page's own buttons and your favorites.",
                                anchor: "shelf.floatingSize")
                    ChoiceTiles(FloatingButtonSize.allCases.map { .init($0, $0.title, icon: $0.icon) },
                                selection: $state.floatingButtonSize)
                    SettingsDivider()
                    SettingsRow("Floating button style",
                                help: "Glass keeps the grey capsule look with each widget's own color on its symbol. Colored fills the circle with that color. Monochrome draws every symbol white.",
                                anchor: "shelf.floatingStyle")
                    ChoiceTiles(FloatingButtonStyle.allCases.map { .init($0, $0.title, icon: $0.icon) },
                                selection: $state.floatingButtonStyle)
                    if state.floatingButtonStyle == .colored {
                        SettingsRow("Icon color",
                                    subtitle: "Set icon and text color for colored floating buttons.",
                                    anchor: "shelf.floatingIconColor")
                        ChoiceTiles([
                            .init(true, "Light", icon: "sun.max"),
                            .init(false, "Dark", icon: "moon"),
                        ], selection: $state.floatingButtonLightIcons)
                    }
                }
            }
        }
    }

    // MARK: Behavior

    private var behavior: some View {
        SettingsSection("Behavior") {
            SettingsGroup {
                SettingsRow("Shelf behavior",
                            help: "Auto-collapse closes the shelf once the pointer has left it for the collapse delay; off, it stays open until you click elsewhere or press Esc. Auto-expand opens it when the pointer rests on the notch; off, it opens on a click.",
                            anchor: "shelf.behavior")
                ToggleTiles([
                    ToggleTile("Auto-collapse", icon: "arrow.down.right.and.arrow.up.left", isOn: $state.autoCollapse),
                    ToggleTile("Auto-expand", icon: "arrow.up.left.and.arrow.down.right", isOn: $state.expandOnHover),
                ])
                SettingsDivider()
                SettingsSlider("Collapse delay", value: $state.autoHideDelay, in: 0.1...3, step: 0.05,
                               defaultValue: AppState.defaultAutoHideDelay,
                               help: "How long the pointer can be away before the shelf closes. Needs Auto-collapse.",
                               anchor: "shelf.collapseDelay") { String(format: "%.2f s", $0) }
                    .settingsDisabled(!state.autoCollapse)
                SettingsDivider()
                SettingsSlider("Auto-expand delay", value: $state.hoverOpenDelay, in: 0...1, step: 0.05,
                               defaultValue: 0.25,
                               help: "How long the pointer rests on the notch before the shelf opens. Needs Auto-expand.",
                               anchor: "shelf.expandDelay") { String(format: "%.2f s", $0) }
                    .settingsDisabled(!state.expandOnHover)
                SettingsDivider()
                SettingsRow("Animation speed",
                            help: "Retimes the shelf and island opening and closing without changing the animation style.",
                            anchor: "shelf.speed")
                ChoiceTiles(ShelfAnimationSpeed.allCases.map { .init($0, $0.title, icon: $0.icon) },
                            selection: $state.animationSpeed)
                SettingsDivider()
                SettingsRow("Animation style",
                            help: "Reduce Motion in System Settings › Accessibility turns the morph off whatever the style.",
                            anchor: "shelf.motion") {
                    Button("Preview") {
                        let state = AppState.shared
                        state.setIslandExpanded(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { state.setIslandExpanded(false) }
                    }
                }
                ChoiceTiles([
                    .init(IslandMotionStyle.dynamicIsland, "Dynamic Island", icon: "capsule.fill"),
                    .init(.snappy, "Snappy", icon: "bolt.fill"),
                    .init(.gentle, "Gentle", icon: "leaf.fill"),
                    .init(.minimal, "Minimal", icon: "minus"),
                ], selection: $state.islandMotionStyle)
                SettingsNote(state.islandMotionStyle.summary).padding(.top, 10)
                SettingsDivider()
                SettingsRow("Gestures",
                            help: "Swipe down with two fingers on the notch to open the shelf, and sideways on the open shelf to move between its pages. Trackpad only.",
                            anchor: "shelf.gestures")
                ChoiceTiles([
                    .init(true, "On", icon: "hand.point.up.left"),
                    .init(false, "Off", icon: "hand.raised.slash"),
                ], selection: $state.shelfGestures)
                SettingsDivider()
                SettingsRow("Scroll on the notch",
                            subtitle: !state.shelfGestures ? "Needs Gestures." : state.scrollToChangeVolume
                                ? "Scrolling on the resting notch changes the volume, so swipe-down-to-open is off. ⌥-scroll changes brightness."
                                : "Swiping down on the resting notch opens the shelf. ⌥-scroll still changes brightness.",
                            anchor: "shelf.scrollAction")
                ChoiceTiles([
                    .init(true, "Volume", icon: "speaker.wave.2.fill"),
                    .init(false, "Open shelf", icon: "arrow.down.to.line"),
                ], selection: $state.scrollToChangeVolume)
                .settingsDisabled(!state.shelfGestures)
                SettingsDivider()
                SettingsRow("Swipe direction",
                            subtitle: state.shelfGestures
                                ? "Which way a sideways swipe moves between pages, and an up-down swipe between the Tray's two stacks."
                                : "Needs Gestures.",
                            help: "Standard follows the fingers: swiping left brings in the page to the right. Reversed flips it.",
                            anchor: "shelf.swipeDirection")
                ChoiceTiles([
                    .init(false, "Standard", icon: "arrow.left.arrow.right"),
                    .init(true, "Reversed", icon: "arrow.right.arrow.left"),
                ], selection: $state.shelfSwipeReversed)
                .settingsDisabled(!state.shelfGestures)
                SettingsDivider()
                SettingsToggleRow("Open tray after drop",
                                  help: "Dropping files on the notch's Keep tile opens the Tray to show them. Off, they're added quietly and the notch shows the count.",
                                  anchor: "shelf.openTrayAfterDrop", isOn: $state.openTrayAfterDrop)
            }
        }
    }

    // MARK: Pages

    private var pages: some View {
        SettingsSection("Pages",
                        subtitle: "One page at a time under the notch. Switch with the navigation bar, a sideways swipe, or ⌘1–⌘4 while it's open.") {
            SettingsGroup {
                SettingsRow("Open the shelf on", anchor: "shelf.pages") {
                    Picker("Open the shelf on", selection: $state.defaultShelfPage) {
                        ForEach(DefaultShelfPage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ForEach(Array(ShelfPage.allCases.enumerated()), id: \.element.id) { index, page in
                    SettingsDivider()
                    SettingsRow(page.title, subtitle: blurb(page), icon: page.iconName) {
                        KeyPill("⌘\(index + 1)")
                        Button("Open") { state.open(page) }
                            .disabled(!state.shelfEnabled)
                            .help(state.shelfEnabled ? "Open the \(page.title) page" : "Turn on The Shelf to open its pages")
                            .accessibilityLabel("Open \(page.title)")
                    }
                }
            }
        }
    }

    private func blurb(_ page: ShelfPage) -> String {
        switch page {
        case .home: return "The full player, with lyrics, Playing Next and an audio output picker."
        case .tray: return "Files you dropped on the notch, ready to drag out again."
        case .widgets: return "Your enabled Droplets, one tap away."
        case .calendar: return "Month view, agenda and reminders with natural-language entry."
        }
    }
}

// MARK: - Previews

/// A glass circle with a hand, in a preview's corner: opens the real shelf in
/// its edit mode.
private struct EditHandButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(NavGlass(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The black shelf silhouette the previews draw on: flat top (it hangs from
/// the notch), the 35 pt bottom corners.
private struct ShelfSilhouette: Shape {
    var radius: CGFloat = DroppyShelfMetrics.cornerRadius

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous).path(in: rect)
    }
}

/// Settings › Shelf › Custom Shelf: the real Home page, live, scaled into a
/// miniature shelf on the desktop wallpaper.
struct CustomShelfPreview: View {
    @ObservedObject private var state = AppState.shared
    private let height: CGFloat = 230

    var body: some View {
        let fullPlayer = state.showsFullPlayer
        let width = fullPlayer ? DroppyShelfMetrics.playerWidth : DroppyShelfMetrics.wideWidth
        let pageHeight = fullPlayer ? DroppyShelfMetrics.playerHeight
            : (state.isCustomizingHome ? HomeWidget.editPageHeight : HomeWidget.cardHeight)
        let top: CGFloat = 26
        let shelfHeight = top + pageHeight + DroppyShelfMetrics.bottomPadding
        GeometryReader { geo in
            let scale = min(1, (geo.size.width - 60) / width, (height - 36) / shelfHeight)
            ZStack(alignment: .top) {
                PreviewWallpaper()
                HomePage()
                    .frame(width: width - DroppyShelfMetrics.horizontalPadding * 2, height: pageHeight, alignment: .top)
                    .padding(.top, top)
                    .padding(.horizontal, DroppyShelfMetrics.horizontalPadding)
                    .padding(.bottom, DroppyShelfMetrics.bottomPadding)
                    .background(IslandSurfaceFill(surface: state.notchedSurfaceStyle == .black ? .black : .dynamicGlass,
                                                  solidTop: top, tint: state.windowTintColor))
                    .clipShape(ShelfSilhouette())
                    .allowsHitTesting(false)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: width * scale, height: shelfHeight * scale, alignment: .top)
                    .padding(.top, 14)
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            EditHandButton(help: "Open the real shelf and edit Home") { state.beginCustomizingHome() }
                .padding(12)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home preview: \(state.visibleHomeWidgets.map(HomeWidget.name).joined(separator: ", "))")
    }
}

/// The widgets Home can show, as chips: tap to add or remove (two at most;
/// a third replaces the second, like the shelf's own picker).
struct HomeWidgetChips: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let current = state.homeWidgets
        FlowLayout(spacing: 6) {
            ForEach(state.availableHomeWidgets, id: \.self) { id in
                let isOn = current.contains(id)
                Button { toggle(id) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : HomeWidget.icon(id))
                            .foregroundStyle(isOn ? AnyShapeStyle(state.accentColor.color) : AnyShapeStyle(.secondary))
                        Text(HomeWidget.name(id))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(isOn ? 0.16 : 0.06), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .disabled(state.isCustomizingHome)
    }

    private func toggle(_ id: String) {
        var list = state.homeWidgets.filter(state.availableHomeWidgets.contains)
        if let index = list.firstIndex(of: id) {
            list.remove(at: index)
        } else if list.count >= HomeWidget.limit {
            list[list.count - 1] = id
        } else {
            list.append(id)
        }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.homeWidgets = list.isEmpty ? [HomeWidget.media] : list }
        DroppyAudio.playTick()
    }
}

/// Lays chips out in rows, wrapping at the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Settings › Shelf › Widget icons: the Widgets page's icons, in order, on a
/// miniature shelf. Drag to reorder here, or open rearrange mode on the shelf.
struct WidgetIconsPreview: View {
    @ObservedObject private var state = AppState.shared
    /// The card's width, fed back from the reader so the outer height matches
    /// the number of rows the icons really take. Guessing it left dead space
    /// under the grid in a wide window.
    @State private var measuredWidth: CGFloat = 520
    private static let cell = CGSize(width: 70, height: 78)

    var body: some View {
        let enabled = state.droplets.filter(\.isEnabled)
        GeometryReader { geo in
            let columns = Self.columns(for: geo.size.width)
            let rows = max((enabled.count + columns - 1) / columns, 1)
            ZStack(alignment: .top) {
                PreviewWallpaper()
                Group {
                    if enabled.isEmpty {
                        Text("No widgets are turned on")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(height: 90)
                    } else {
                        ReorderableIconGrid(ids: enabled.map(\.id), columns: columns, cellSize: Self.cell,
                                            wiggles: false, onReorder: { state.reorderWidgets($0) }) { id in
                            if let droplet = enabled.first(where: { $0.id == id }) {
                                VStack(spacing: 6) {
                                    DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 44)
                                    Text(droplet.name)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .frame(width: Self.cell.width - 4)
                                }
                            }
                        }
                        .frame(height: CGFloat(rows) * Self.cell.height)
                    }
                }
                .padding(.vertical, 18)
                .frame(width: CGFloat(columns) * Self.cell.width + 40)
                .background(Color.black, in: ShelfSilhouette(radius: 28))
                .padding(.top, 16)
            }
            .frame(width: geo.size.width, height: Self.height(width: geo.size.width, count: enabled.count))
            .onChange(of: geo.size.width, initial: true) { _, width in
                if width > 0 { measuredWidth = width }
            }
        }
        .frame(height: Self.height(width: measuredWidth, count: enabled.count))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            EditHandButton(help: "Rearrange widgets on the shelf") { state.beginRearrangingWidgets() }
                .padding(12)
        }
        .environment(\.colorScheme, .dark)
    }

    static func columns(for width: CGFloat) -> Int {
        max(Int((width - 80) / Self.cell.width), 1)
    }

    static func height(width: CGFloat, count: Int) -> CGFloat {
        let rows = max((count + columns(for: width) - 1) / columns(for: width), 1)
        return CGFloat(rows) * Self.cell.height + 36 + 34 + 12
    }
}

// MARK: - Favorites

/// The navigation capsule on the wallpaper with the favorite slots beside it and a
/// dashed + slot while there's room. Tapping a slot picks what goes there.
struct FavoritesEditor: View {
    @ObservedObject private var state = AppState.shared
    @State private var editing: Int?

    var body: some View {
        let favorites = state.shelfFavorites
        ZStack {
            PreviewWallpaper()
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(FloatingNavBar.lanes) { lane in
                        Image(systemName: lane.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(lane == .home ? 1 : 0.8))
                            .frame(width: 38, height: 32)
                            .background(Capsule().fill(Color.white.opacity(lane == .home ? 0.2 : 0)))
                    }
                }
                .padding(4)
                .background(NavGlass(shape: Capsule()))
                .accessibilityHidden(true)
                ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                    slot(index) {
                        FavoriteGlyph(favorite: favorite, size: 20)
                            .frame(width: 42, height: 42)
                            .background {
                                if state.floatingButtonStyle == .colored, let tint = favorite.tint {
                                    Circle().fill(tint)
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
                                } else {
                                    NavGlass(shape: Circle())
                                }
                            }
                    }
                    .help(favorite.title)
                    .accessibilityLabel("Favorite \(index + 1): \(favorite.title)")
                }
                if favorites.count < ShelfFavorite.limit {
                    slot(favorites.count) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
                    }
                    .help("Add a favorite")
                    .accessibilityLabel("Add a favorite")
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func slot<Label: View>(_ index: Int, @ViewBuilder label: () -> Label) -> some View {
        Button { editing = index } label: { label().contentShape(Circle()) }
            .buttonStyle(PressableStyle(scale: 0.9))
            .popover(isPresented: Binding(get: { editing == index }, set: { if !$0 { editing = nil } }),
                     arrowEdge: .bottom) {
                FavoritePicker(index: index) { editing = nil }
            }
    }
}

/// What a favorite slot can hold: a widget, an app, or a Shortcut.
private struct FavoritePicker: View {
    let index: Int
    let dismiss: () -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shortcuts = ShortcutsLibrary.shared

    private var current: ShelfFavorite? {
        state.shelfFavorites.indices.contains(index) ? state.shelfFavorites[index] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                header("Widgets")
                if !state.droplets.contains(where: \.isEnabled) {
                    note("No widgets are turned on. Turn them on in Settings › Droplets.")
                }
                ForEach(state.droplets.filter(\.isEnabled)) { droplet in
                    row(droplet.name, selected: current == ShelfFavorite(kind: .droplet, value: droplet.id)) {
                        DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 20)
                    } action: {
                        pick(ShelfFavorite(kind: .droplet, value: droplet.id))
                    }
                }
                header("Apps")
                if let current, current.kind == .app {
                    row(current.title, selected: true) { FavoriteGlyph(favorite: current, size: 18, stylized: false) } action: { dismiss() }
                }
                row("Choose an app…", selected: false) {
                    Image(systemName: "app.badge").frame(width: 20)
                } action: {
                    dismiss()
                    DispatchQueue.main.async { chooseApp() }
                }
                header("Shortcuts")
                if !ShortcutsLibrary.isAvailable {
                    note("The Shortcuts app isn't available on this Mac.")
                } else if shortcuts.names.isEmpty {
                    note(shortcuts.isLoading ? "Loading your shortcuts…" : "No shortcuts yet. Make one in the Shortcuts app.")
                } else {
                    ForEach(shortcuts.names, id: \.self) { name in
                        row(name, selected: current == ShelfFavorite(kind: .shortcut, value: name)) {
                            FavoriteGlyph(favorite: ShelfFavorite(kind: .shortcut, value: name), size: 18)
                        } action: {
                            pick(ShelfFavorite(kind: .shortcut, value: name))
                        }
                    }
                }
                if current != nil {
                    Divider().padding(.vertical, 6)
                    Button(role: .destructive) {
                        state.setFavorite(nil, at: index)
                        dismiss()
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Palette.danger)
                }
            }
            .padding(10)
        }
        .frame(width: 260, height: 340)
        .onAppear { shortcuts.refresh() }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func row<Icon: View>(_ title: String, selected: Bool, @ViewBuilder icon: () -> Icon,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ favorite: ShelfFavorite) {
        state.setFavorite(favorite, at: index)
        dismiss()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to Favorites"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppState.shared.setFavorite(ShelfFavorite(kind: .app, value: url.path), at: index)
    }
}

// MARK: - Thumbnails

/// Navigation style card: the top of a shelf with tabs in the wings, or a
/// floating capsule under it.
private struct NavigationStyleThumbnail: View {
    let style: ShelfNavigationStyle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                ShelfSilhouette(radius: 12)
                    .fill(Color.black)
                    .frame(width: w * 0.72, height: style == .regularButtons ? 30 : 34)
                if style == .regularButtons {
                    HStack(spacing: 6) {
                        icon("house.fill", selected: true)
                        icon("tray.fill")
                        Spacer()
                        icon("square.grid.2x2.fill")
                    }
                    .frame(width: w * 0.72 - 20, height: 26)
                } else {
                    HStack(spacing: 4) {
                        icon("house.fill", selected: true)
                        icon("tray.fill")
                        icon("square.grid.2x2.fill")
                    }
                    .padding(3)
                    .background(Capsule().fill(Color(white: 0.16)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .padding(.top, 44)
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .top)
        }
    }

    private func icon(_ name: String, selected: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
            .frame(width: 20, height: 16)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.22 : 0)))
    }
}

/// Multi Live Activities card: a call pill, plus the second activity's circle when on.
private struct MultiLiveThumbnail: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "phone.fill").font(.system(size: 9, weight: .bold))
                Text("05:12").font(.system(size: 10, weight: .semibold).monospacedDigit())
                Spacer(minLength: 4)
                HStack(spacing: 1.5) {
                    ForEach([4, 8, 11, 6, 9, 5, 10, 7], id: \.self) { h in
                        Capsule().frame(width: 1.8, height: CGFloat(h))
                    }
                }
            }
            .foregroundStyle(Color.green)
            .padding(.horizontal, 12)
            .frame(width: 124, height: 28)
            .background(Capsule().fill(Color.black))
            if isOn {
                Circle()
                    .fill(Color.black)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.4), Color(red: 0.45, green: 0.15, blue: 0.3)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Image(systemName: "music.note").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                            .padding(4)
                    )
            }
        }
    }
}
