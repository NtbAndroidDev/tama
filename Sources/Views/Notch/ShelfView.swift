import SwiftUI

/// The open shelf: one page at a time under the notch. Pages cross-fade with a
/// little scale and blur, the way Tama swaps between player, tray and widgets.
public struct ShelfView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        let scale = state.shelfScale
        let pageWidth = state.unscaledExpandedWidth - DroppyShelfMetrics.horizontalPadding * 2
        let pageHeight = state.pageHeight(state.shelfPage)
        ZStack(alignment: .top) {
            page(state.shelfPage)
                .id(state.shelfPage)
                .frame(height: pageHeight, alignment: .top)
                .transition(
                    reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                        removal: .opacity
                    )
                )
        }
        // Pages lay out at the regular size; Enlarged scales the result, so
        // every page grows alike without its own metrics.
        .frame(width: pageWidth, height: pageHeight, alignment: .top)
        .scaleEffect(scale, anchor: .top)
        .frame(width: pageWidth * scale, height: pageHeight * scale, alignment: .top)
        .padding(.top, state.shelfTopInset)
        .padding(.bottom, DroppyShelfMetrics.bottomPadding * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Settings › HUDs › Artwork tint: the player washes the shelf in the cover's colours.
        .background(ArtworkTintBackground())
        .overlay(alignment: .top) {
            if shelfSettings.navigationStyle == .regularButtons {
                WingTabs()
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.shelfPage)
        .overlay(alignment: .bottom) {
            // The notch banner can't unfurl while the shelf is open, so results
            // and errors from the pages surface here instead.
            if let notification = state.activeNotification {
                ShelfToast(notification: notification)
                    .id(notification.id)
                    .padding(.horizontal, DroppyShelfMetrics.horizontalPadding)
                    .padding(.bottom, DS.Space.md)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else if let hud = state.hud {
                ShelfLevelBand(hud: hud)
                    .padding(.horizontal, DroppyShelfMetrics.horizontalPadding)
                    .padding(.bottom, DS.Space.md)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .animation(reduceMotion ? nil : state.hudStyle(for: hud.kind).animation.animation, value: hud.value)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.snap, value: state.activeNotification?.id)
        .animation(reduceMotion ? nil : DS.Motion.snap, value: state.hud == nil)
        .background(pageShortcuts)
    }

    @ViewBuilder
    private func page(_ page: ShelfPage) -> some View {
        switch page {
        case .home: HomePage()
        case .tray: TrayPage()
        case .widgets: WidgetsPage()
        case .calendar: CalendarPage()
        }
    }

    /// ⌘1…⌘4 jump between pages while the shelf is open, and ⌘? opens the
    /// guide on the page in front of you.
    private var pageShortcuts: some View {
        Group {
            ForEach(Array(ShelfPage.allCases.enumerated()), id: \.element.id) { index, page in
                Button("") { state.select(page) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("") {
                UserGuideWindowController.shared.show(topic: UserGuideWindowController.topic(for: state.shelfPage))
            }
            .keyboardShortcut("?", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// A compact banner along the bottom of the open shelf.
private struct ShelfToast: View {
    let notification: DroppyNotification
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: notification.iconSystemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DS.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(notification.title)
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .help(notification.title)
                if !notification.message.isEmpty {
                    Text(notification.message)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .help(notification.message)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Space.sm)
            if let title = notification.actionTitle {
                DroppyPillButton(title, tone: .accent) {
                    DroppyAudio.playTick()
                    notification.action?()
                    dismiss()
                }
            }
            DroppyIconButton("xmark", size: 22, help: "Dismiss") { dismiss() }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        // `.contain`, not `.combine`: combining swallowed the action and
        // Dismiss buttons, so VoiceOver could read the toast but not act on it.
        .accessibilityElement(children: .contain)
        .onHover { AppState.shared.holdNotification($0) }
    }

    private func dismiss() {
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { state.activeNotification = nil }
    }
}

// MARK: - Navigation

/// The row floating under the open shelf: the glass navigation bar (Home,
/// Tray, Widgets) in "Floating bar" style, then round glass buttons — the
/// Calendar, the page's own buttons (✕, ↗, ↻…) and the user's favorites.
/// In "Regular buttons" style the bar moves into the notch wings and only
/// the round buttons stay here.
public struct LanePill: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @ObservedObject private var accessories = ShelfAccessoryCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        HStack(spacing: DroppyShelfMetrics.floatingButtonSpacing) {
            if shelfSettings.navigationStyle == .floatingBar {
                FloatingNavBar()
            }
            if state.showsCalendarFloatingButton {
                FloatingGlassButton(icon: ShelfPage.calendar.iconName, help: "Tasks & Calendar (⌘4)",
                                    isSelected: state.shelfPage == .calendar) {
                    state.select(state.shelfPage == .calendar ? .home : .calendar)
                }
            }
            ForEach(accessories.visible) { accessory in
                FloatingGlassButton(icon: accessory.icon, help: accessory.help) { accessory.action() }
                    .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.6).combined(with: .opacity)))
            }
            ForEach(state.shelfFavorites) { favorite in
                FloatingGlassButton(help: favorite.title, tint: favorite.tint) { favorite.run() } label: {
                    FavoriteGlyph(favorite: favorite, size: DroppyShelfMetrics.floatingButton * 0.53)
                }
            }
        }
        .frame(height: DroppyShelfMetrics.lanePillHeight)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: accessories.visible.map(\.id))
    }
}

/// Translucent grey glass, as the reference draws its navigation capsule.
struct NavGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.white.opacity(0.07)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.6))
    }
}

/// One capsule with house / tray / grid; the page on screen gets a lighter disc.
struct FloatingNavBar: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    @State private var hovered: ShelfPage?

    static let lanes: [ShelfPage] = [.home, .tray, .widgets]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.lanes) { lane in segment(lane) }
        }
        .padding(2)
        .frame(width: DroppyShelfMetrics.navBarWidth, height: DroppyShelfMetrics.lanePillHeight)
        .background(NavGlass(shape: Capsule()))
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.shelfPage)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: hovered)
    }

    private func segment(_ lane: ShelfPage) -> some View {
        let isActive = state.shelfPage == lane
        let count = lane == .tray ? state.shelfItems.count : 0
        // Clicking Home again while it's showing opens its customisation, like
        // tapping the current tab twice; otherwise it only switches pages.
        let customizes = lane == .home && isActive && !state.isCustomizingHome
        return Button {
            if customizes { state.beginCustomizingHome() } else { state.select(lane) }
        } label: {
            Image(systemName: lane.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.8))
                .frame(width: DroppyShelfMetrics.navSegmentWidth, height: DroppyShelfMetrics.navSegmentHeight)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .matchedGeometryEffect(id: "lane", in: indicator)
                    } else if hovered == lane {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 8, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 12, minHeight: 12)
                            .background(Capsule().fill(Color.white))
                            .offset(x: 3, y: -3)
                            .transition(DS.Motion.transition(reduceMotion, .scale.combined(with: .opacity)))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .onHover { inside in
            if inside { hovered = lane } else if hovered == lane { hovered = nil }
        }
        .help(customizes ? "Customize Home" : "\(lane.title) (⌘\((ShelfPage.allCases.firstIndex(of: lane) ?? 0) + 1))")
        .contextMenu {
            if lane == .home {
                Button { state.beginCustomizingHome() } label: {
                    Label("Customize Home…", systemImage: "square.grid.2x2")
                }
                .disabled(state.isCustomizingHome)
            }
            if lane == .widgets {
                Button { state.beginRearrangingWidgets() } label: {
                    Label("Rearrange Widgets…", systemImage: "hand.draw")
                }
            }
        }
        .accessibilityLabel(count > 0 ? "\(lane.title), \(count == 1 ? "1 item" : "\(count) items")" : lane.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // Only Home offers it; an unconditional action listed a dead
        // "Customize Home" on Tray and Widgets too.
        .accessibilityActions {
            if lane == .home {
                Button("Customize Home") { state.beginCustomizingHome() }
            }
        }
    }
}

/// A round grey-glass button beside the navigation bar.
struct FloatingGlassButton<Label: View>: View {
    var help: String
    var isSelected = false
    /// The widget's own colour. Settings › Shelf › Favorites › Floating button
    /// style › Colored fills the circle with it; nil keeps the glass.
    var tint: Color?
    let action: () -> Void
    @ViewBuilder let label: Label
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var isHovered = false

    init(help: String, isSelected: Bool = false, tint: Color? = nil,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
        self.label = label()
    }

    private var isColored: Bool { shelfSettings.floatingButtonStyle == .colored && tint != nil }

    var body: some View {
        let side = DroppyShelfMetrics.floatingButton
        Button(action: action) {
            label
                .frame(width: side, height: side)
                .background {
                    if isColored, let tint {
                        Circle().fill(tint)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
                    } else {
                        NavGlass(shape: Circle())
                    }
                }
                .overlay(Circle().fill(Color.white.opacity(isSelected ? 0.2 : (isHovered ? 0.08 : 0))))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension FloatingGlassButton where Label == AnyView {
    init(icon: String, help: String, isSelected: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.init(help: help, isSelected: isSelected, tint: tint, action: action) {
            AnyView(FloatingButtonSymbol(icon: icon, tint: tint))
        }
    }
}

/// A floating button's symbol, painted for the chosen style: the widget's own
/// colour on glass, the icon colour on a colored circle, or plain white.
struct FloatingButtonSymbol: View {
    let icon: String
    var tint: Color?
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: DroppyShelfMetrics.floatingButton * 0.4, weight: .semibold))
            .foregroundStyle(Self.color(style: shelfSettings.floatingButtonStyle, tint: tint,
                                        lightIcons: shelfSettings.floatingButtonLightIcons))
    }

    /// Glass keeps the widget's colour; Colored uses the icon colour on the
    /// filled circle; Monochrome is always white.
    nonisolated static func color(style: FloatingButtonStyle, tint: Color?, lightIcons: Bool) -> Color {
        switch style {
        case .glass: tint ?? .white.opacity(0.92)
        case .colored: tint == nil ? .white.opacity(0.92) : (lightIcons ? .white : .black.opacity(0.85))
        case .monochrome: .white.opacity(0.92)
        }
    }
}

/// A favorite's icon: the widget's symbol, the app's icon, or Shortcuts'.
struct FavoriteGlyph: View {
    let favorite: ShelfFavorite
    var size: CGFloat = 16
    /// Settings ignores the chosen style in its own previews.
    var stylized = true
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        switch favorite.kind {
        case .droplet:
            let symbol = state.droplets.first { $0.id == favorite.value }?.iconSystemName ?? "square.grid.2x2"
            Image(systemName: symbol)
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(stylized
                    ? FloatingButtonSymbol.color(style: shelfSettings.floatingButtonStyle, tint: favorite.tint,
                                                 lightIcons: shelfSettings.floatingButtonLightIcons)
                    : DropletPalette.tint(for: favorite.value))
        case .app:
            Image(nsImage: FileIcon.image(for: favorite.value))
                .resizable()
                .interpolation(.high)
                .frame(width: size + 2, height: size + 2)
        case .shortcut:
            if let icon = AppIcon.image(bundleID: "com.apple.shortcuts") {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: size + 2, height: size + 2)
            } else {
                Image(systemName: "square.2.layers.3d.fill")
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .foregroundStyle(.pink)
            }
        }
    }
}

/// "Regular buttons": the page tabs sit in the notch wings — Home and Tray on
/// the left, Widgets and Calendar on the right. Without a notch they share
/// a row at the top of the shelf.
struct WingTabs: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandDisplayID) private var displayID
    @Namespace private var indicator
    @State private var hovered: ShelfPage?

    var body: some View {
        let notch = state.notchHeight(on: displayID)
        HStack(spacing: DS.Space.xs) {
            tab(.home)
            tab(.tray)
            Spacer(minLength: notch > 0 ? state.hardwareNotchWidth(on: displayID) + 24 : 12)
            tab(.widgets)
            tab(.calendar)
        }
        .padding(.horizontal, DroppyShelfMetrics.horizontalPadding)
        .frame(height: notch > 0 ? notch : DroppyShelfMetrics.wingTabRow)
        .animation(reduceMotion ? nil : DS.Motion.fluid, value: state.shelfPage)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: hovered)
    }

    private func tab(_ page: ShelfPage) -> some View {
        let isActive = state.shelfPage == page
        let count = page == .tray ? state.shelfItems.count : 0
        let customizes = page == .home && isActive && !state.isCustomizingHome
        return Button {
            if customizes { state.beginCustomizingHome() } else { state.select(page) }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: page.iconName).font(.system(size: 11.5, weight: .semibold))
                if count > 0 {
                    Text("\(count)").font(.system(size: 10.5, weight: .bold).monospacedDigit())
                }
            }
            .foregroundStyle(.white.opacity(isActive ? 1 : 0.7))
            .padding(.horizontal, count > 0 ? 8 : 0)
            .frame(minWidth: DroppyShelfMetrics.wingTab, minHeight: DroppyShelfMetrics.wingTab - 4)
            .background {
                if isActive {
                    Capsule().fill(Color.white.opacity(0.18)).matchedGeometryEffect(id: "wingTab", in: indicator)
                } else if hovered == page {
                    Capsule().fill(Color.white.opacity(0.08))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .onHover { inside in
            if inside { hovered = page } else if hovered == page { hovered = nil }
        }
        .help(customizes ? "Customize Home" : "\(page.title) (⌘\((ShelfPage.allCases.firstIndex(of: page) ?? 0) + 1))")
        .contextMenu {
            if page == .home {
                Button { state.beginCustomizingHome() } label: {
                    Label("Customize Home…", systemImage: "square.grid.2x2")
                }
                .disabled(state.isCustomizingHome)
            }
            if page == .widgets {
                Button { state.beginRearrangingWidgets() } label: {
                    Label("Rearrange Widgets…", systemImage: "hand.draw")
                }
            }
        }
        .accessibilityLabel(count > 0 ? "\(page.title), \(count == 1 ? "1 item" : "\(count) items")" : page.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // Same as the floating bar: only Home offers it.
        .accessibilityActions {
            if page == .home {
                Button("Customize Home") { state.beginCustomizingHome() }
            }
        }
    }
}

// MARK: - Quick actions

/// The tiles the notch unfolds into while a file drag hovers it (Keep plus
/// the Quick Actions chosen in Settings › General). Whichever tile is under
/// the pointer lights up and gets the drop.
public struct QuickActionsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(state.quickActions.enumerated()), id: \.element.id) { index, action in
                tile(action, index: index)
            }
        }
        .padding(.top, state.islandTopInset)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ action: QuickAction, index: Int) -> some View {
        let isHovered = state.hoveredQuickAction == action
        let last = state.quickActions.count - 1
        return VStack(spacing: 8) {
            Image(systemName: action.iconName)
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: reduceMotion ? false : isHovered)
            Text(action.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHovered ? .isSelected : [])
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: index == 0 ? 26 : 14,
                bottomTrailingRadius: index == last ? 26 : 14,
                topTrailingRadius: 14,
                style: .continuous
            )
            .fill(isHovered ? NotchPalette.tileHover : NotchPalette.tile)
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - HUD

/// Volume / brightness readout that spreads into the notch wings: icon and
/// label on the left of the notch, the meter and the value on the right.
/// Its look follows Settings › Sound (volume) or › Display (brightness).
public struct IslandHUDView: View {
    public let hud: IslandHUD
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandDisplayID) private var displayID

    public init(hud: IslandHUD) {
        self.hud = hud
    }

    public var body: some View {
        HStack(spacing: 8) {
            HUDLabel(hud: hud, maxLabelWidth: max(state.hudWing(on: displayID) - 14 - 18 - 8 - 6, 20))
            Spacer(minLength: state.notchHeight(on: displayID) > 0 ? state.hardwareNotchWidth(on: displayID) : 12)
            HUDMeter(hud: hud, width: state.hudStyle(for: hud.kind).showPercentage ? 64 : 92)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : state.hudStyle(for: hud.kind).animation.animation, value: hud.value)
        .accessibilityElement(children: .combine)
    }
}

/// The speaker (or output device) symbol, and "Sound" / "Display" / "Muted"
/// or the device's name, unless the label is hidden.
struct HUDLabel: View {
    let hud: IslandHUD
    var maxLabelWidth: CGFloat = 140
    /// Settings previews pass their own; the notch reads the setting.
    var style: LevelHUDStyle? = nil
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    private var resolved: LevelHUDStyle { style ?? state.hudStyle(for: hud.kind) }

    /// "Show device" only applies to volume, and only once the output is known.
    private var device: IslandHUD.Device? {
        hud.kind == .volume && resolved.leading == .device ? hud.device : nil
    }

    private var title: String {
        if hud.isMuted { return "Muted" }
        return device?.name ?? hud.kind.label
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let device {
                    // A slash over the device reads as muted without losing which one.
                    Image(systemName: device.symbol)
                        .overlay {
                            if hud.isMuted {
                                Image(systemName: "line.diagonal").font(.system(size: 15, weight: .bold)).rotationEffect(.degrees(90))
                            }
                        }
                } else {
                    Image(systemName: hud.kind.iconName(for: hud.value, isMuted: hud.isMuted))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 18)
            if !resolved.hideLabel {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxLabelWidth, alignment: .leading)
                    .fixedSize(horizontal: device == nil, vertical: false)
            }
        }
        .foregroundStyle(.white)
    }
}

/// A slim meter in the chosen style (white, accent or decibel), and the level
/// as a number if percentages are on. Muted keeps the level visible but
/// greyed, so it's clear where sound comes back.
struct HUDMeter: View {
    let hud: IslandHUD
    var width: CGFloat = 88
    /// Settings previews pass their own; the notch reads the setting.
    var style: HUDMeterStyle? = nil
    var showPercentage: Bool? = nil
    /// The level the Decibel colour follows, when it isn't the bar's own
    /// (the Settings tile keeps its length but shows the live colour).
    var colorLevel: Double? = nil
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        let setting = state.hudStyle(for: hud.kind)
        let style = style ?? setting.meter
        // Resolved here, at draw time, so a new accent retints the next HUD.
        let fill = hud.isMuted
            ? Color.white.opacity(0.35)
            : style.color(for: colorLevel ?? hud.value, accent: themeSettings.accentColor.color, custom: state.hudCustomColor(for: hud.kind))
        let glow: CGFloat = hud.isMuted || style == .white ? 0 : (style == .decibel ? 7 : 4)
        // The empty part of the track carries a hint of the fill's colour.
        let track = hud.isMuted || style == .white ? Color.white.opacity(0.16) : fill.opacity(0.22)
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule()
                        .fill(fill)
                        .frame(width: max(geo.size.width * hud.value, hud.value > 0 ? 6 : 0))
                        .shadow(color: fill.opacity(glow > 0 ? 0.7 : 0), radius: glow)
                }
            }
            .frame(width: width, height: 6)
            if showPercentage ?? setting.showPercentage {
                Text("\(Int((hud.value * 100).rounded()))")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(hud.isMuted ? Color.white.opacity(0.45) : .white)
                    .contentTransition(.numericText())
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(hud.kind.accessibilityName)
        .accessibilityValue(hud.isMuted ? "Muted" : "\(Int((hud.value * 100).rounded())) percent")
    }
}

/// The level while the shelf is open: the island can't turn into the HUD
/// then, so the same readout sits in a band along the shelf's bottom.
struct ShelfLevelBand: View {
    let hud: IslandHUD

    var body: some View {
        HStack(spacing: DS.Space.md) {
            HUDLabel(hud: hud, maxLabelWidth: 180)
            Spacer(minLength: DS.Space.sm)
            HUDMeter(hud: hud, width: 140)
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .allowsHitTesting(false)
    }
}
