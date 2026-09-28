import SwiftUI
import UniformTypeIdentifiers

/// The island itself. The panel behind it is just a transparent canvas; this
/// view is one persistent black shape that morphs between modes, the way the
/// Dynamic Island does. It runs on exactly two clocks:
///
/// - **Shape** — size, corner radius and notch ears, animated together as one
///   `IslandGeometry` value on one spring. Nothing else moves the outline.
/// - **Content** — only the layer for the current mode is mounted. It rides the
///   shape's spring: incoming content starts small and blurred and grows with
///   the shape, outgoing content shrinks and blurs back into the notch.
///
/// Everything is pinned to the top edge, so the island grows down and out of the
/// notch instead of zooming from its centre.
public struct DynamicIslandView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var clipboardSettings = ClipboardSettings.shared
    @ObservedObject private var generalSettings = GeneralSettings.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The HUD and banner keep their last value while they animate out.
    @State private var lastHUD: IslandHUD?
    @State private var lastNotification: DroppyNotification?
    /// The outline on screen. It trails `geometry` on two springs, one per
    /// axis (see `morph`); nil until the first change, when it is `geometry`.
    @State private var shown: IslandGeometry?
    /// All Displays: the screen a mirror stands in for; nil is the live island.
    private let displayID: CGDirectDisplayID?

    public init(displayID: CGDirectDisplayID? = nil) {
        self.displayID = displayID
    }

    private var isLive: Bool { displayID == nil }
    private var notchHeight: CGFloat { state.notchHeight(on: displayID) }
    private var mode: IslandMode { state.islandMode(on: displayID) }
    private var geometry: IslandGeometry { state.islandGeometry(on: displayID) }
    private var outline: IslandGeometry { shown ?? geometry }

    /// The one clock: opening is a touch slower than closing.
    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        return mode.isOpen ? DS.Motion.morphOpen : DS.Motion.morphClose
    }

    /// The lane pill is a separate object under the shelf: it only appears once
    /// the shelf has nearly landed (otherwise it floats, blurred, under a shape
    /// that is still growing) and leaves at once when the shelf closes.
    private var lanePillMotion: Animation? {
        guard !reduceMotion else { return nil }
        return showsLanePill ? DS.Motion.morphOpen.delay(0.14) : DS.Motion.morphClose.speed(1.6)
    }

    private var showsLanePill: Bool { isLive && state.showsLanePill }

    public var body: some View {
        VStack(spacing: DroppyShelfMetrics.lanePillGap) {
            island
                .overlay(alignment: .topTrailing) {
                    // Multi Live Activities: a second activity in its own circle.
                    SecondaryActivityPill(displayID: displayID)
                        .alignmentGuide(.trailing) { $0[.leading] - DroppyShelfMetrics.secondaryActivityGap }
                }
            LanePill()
                .modifier(IslandLayer(isVisible: showsLanePill, reduceMotion: reduceMotion))
                .animation(lanePillMotion, value: showsLanePill)
            Spacer(minLength: 0)
        }
        .padding(.top, state.islandTopOffset(on: displayID))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: mode)
        .onChange(of: geometry) { old, new in morph(from: old, to: new) }
        .ignoresSafeArea()
        .environment(\.islandDisplayID, displayID)
        .onChange(of: state.hud) { _, hud in if let hud { lastHUD = hud } }
        .onChange(of: state.activeNotification?.id) { _, _ in
            if let notification = state.activeNotification { lastNotification = notification }
        }
    }

    // MARK: - The morphing shape

    /// Width and height ride separate springs, so the shape stretches sideways
    /// then drops when it opens, and lifts then narrows when it closes.
    private func morph(from old: IslandGeometry, to new: IslandGeometry) {
        guard !reduceMotion else {
            shown = new
            return
        }
        var next = shown ?? old
        let opening = new.size.height > old.size.height + 0.5
            || (new.size.height >= old.size.height - 0.5 && new.size.width > old.size.width + 0.5)
        let (widthMotion, heightMotion) = opening
            ? (DS.Motion.islandWidthOpen, DS.Motion.islandHeightOpen)
            : (DS.Motion.islandWidthClose, DS.Motion.islandHeightClose)
        withAnimation(widthMotion) {
            next.size.width = new.size.width
            shown = next
        }
        withAnimation(heightMotion) {
            next.size.height = new.size.height
            next.cornerRadius = new.cornerRadius
            next.earRadius = new.earRadius
            shown = next
        }
    }

    /// Settings › Accessibility: the resting island is hidden (right-click
    /// menu, or Hold to reveal). Anything else it shows still appears.
    /// Settings › HUDs can hide it on this screen too — a switched-off
    /// display, fullscreen with "Hide all", Mission Control — resting or
    /// showing a level; and without "Show when idle" an external display's
    /// island fades out while nothing is live on it.
    private var isHidden: Bool {
        if mode == .resting && state.isRestingSurfaceHidden { return true }
        if (mode == .resting || mode == .hud) && state.isSurfaceSuppressed(on: displayID) { return true }
        return state.isIdleHidden(on: displayID)
    }

    private var island: some View {
        layers
            .frame(width: outline.size.width, height: outline.size.height, alignment: .top)
            .liquidGlass(
                cornerRadius: outline.cornerRadius,
                showBorder: generalSettings.islandStyle == .floatingPill,
                // On a notch only the open shelf glows; the resting notch stays
                // pure black so it reads as the hardware.
                isHovered: isLive && state.isIslandHovered && (notchHeight == 0 || mode == .shelf),
                isNotchAttached: generalSettings.islandStyle == .notchAttached && notchHeight > 0,
                earRadius: outline.earRadius,
                solidTop: notchHeight,
                isResting: mode == .resting
            )
            .opacity(isHidden ? 0 : 1)
            .animation(reduceMotion ? nil : DS.Motion.fluid, value: isHidden)
            .allowsHitTesting(!isHidden)
            .onDrop(of: DragDropService.acceptedTypes, delegate: IslandDropDelegate(state: state))
            .contextMenu { IslandContextMenu() }
    }

    // MARK: - Content layers
    //
    // Every layer stays mounted at its own final size and is shown or hidden by
    // `IslandLayer` on the same spring as the shape. (Insertion transitions were
    // tried and SwiftUI dropped them here — content just popped in, sharp.)
    // Because no layer resizes with the shape, the shape reveals it instead of
    // it reflowing mid-morph.

    private var layers: some View {
        ZStack(alignment: .top) {
            IslandCompactView()
                .frame(width: state.islandCompactSize(on: displayID).width,
                       height: state.islandCompactSize(on: displayID).height)
                .modifier(IslandLayer(isVisible: mode == .resting, reduceMotion: reduceMotion))

            ShelfView()
                .frame(width: state.islandExpandedSize.width, height: state.islandExpandedSize.height)
                .modifier(IslandLayer(isVisible: mode == .shelf, reduceMotion: reduceMotion))

            QuickActionsView()
                .frame(width: state.islandQuickActionsSize.width, height: state.islandQuickActionsSize.height)
                .modifier(IslandLayer(isVisible: mode == .dropTarget, reduceMotion: reduceMotion))

            if let hud = state.hud ?? lastHUD {
                IslandHUDView(hud: hud)
                    .frame(width: state.islandHUDSize(on: displayID).width,
                           height: state.islandHUDSize(on: displayID).height)
                    .modifier(IslandLayer(isVisible: mode == .hud, reduceMotion: reduceMotion))
            }

            if let notification = state.activeNotification ?? lastNotification {
                NotchNotificationHUDView(notification: notification)
                    .frame(width: state.islandNotificationSize(on: displayID).width,
                           height: state.islandNotificationSize(on: displayID).height)
                    .id(notification.id)
                    .modifier(IslandLayer(isVisible: mode == .notification, reduceMotion: reduceMotion))
            }
        }
    }
}

// MARK: - Layer visibility

/// How content enters and leaves the island. It scales from the top edge — so
/// it comes out of, and goes back into, the notch — and is blurred in motion.
private struct IslandLayer: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool

    /// Like the Dynamic Island, content runs on its own clock, not the
    /// shape's: it arrives a beat after the shape starts growing, and leaves
    /// fast, before the shape has shrunk around it.
    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : (isVisible ? DS.Motion.islandContentIn : DS.Motion.islandContentOut)) { layer in
                layer
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.9, anchor: .top)
                    .blur(radius: isVisible || reduceMotion ? 0 : 8)
                    .opacity(isVisible ? 1 : 0)
            }
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .environment(\.isIslandLayerVisible, isVisible)
    }
}

// MARK: - Drop handling

/// A file drag over the notch unfolds the quick-action tiles; the tile under
/// the pointer takes the drop. With the Tray page already open, files go
/// straight into the tray instead.
@MainActor
private struct IslandDropDelegate: DropDelegate {
    let state: AppState

    private var dropsStraightIntoTray: Bool {
        state.isIslandExpanded && state.shelfPage == .tray
    }

    /// A Tray tile dropped back onto the open Tray page is a no-op, not a re-add.
    private var isTrayTileOverTray: Bool {
        dropsStraightIntoTray && TrayActions.internalDragSource == .tray
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Settings › Shelf › The Shelf is off: no drop tiles either.
        ShelfSettings.shared.isEnabled && !isTrayTileOverTray && info.hasItemsConforming(to: DragDropService.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard ShelfSettings.shared.isEnabled, !dropsStraightIntoTray else { return }
        DroppyAudio.playTick()
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.morphOpen)) { state.isDragHovering = true }
        updateHover(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if !dropsStraightIntoTray { updateHover(info) }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.morphClose)) {
            state.isDragHovering = false
            state.hoveredQuickAction = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard ShelfSettings.shared.isEnabled, !isTrayTileOverTray else { return false }
        let action = dropsStraightIntoTray ? .keep : (state.hoveredQuickAction ?? .keep)
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.morphClose)) {
            state.isDragHovering = false
            state.hoveredQuickAction = nil
        }
        let providers = info.itemProviders(for: DragDropService.acceptedTypes)
        DragDropService.shared.handleDrop(providers: providers) { items in
            perform(action, with: items)
        }
        return true
    }

    /// Maps the pointer to one of the tiles under the notch. Mirrors the
    /// QuickActionsView layout (12pt inset, 10pt gaps); a pointer in a gap
    /// goes to the nearer tile, so the split falls mid-gap.
    private func updateHover(_ info: DropInfo) {
        let size = state.islandQuickActionsSize
        let inset: CGFloat = 12
        let spacing: CGFloat = 10
        let actions = state.quickActions
        let x = info.location.x - inset
        let width = size.width - inset * 2
        let tileWidth = (width - spacing * CGFloat(actions.count - 1)) / CGFloat(actions.count)
        guard info.location.y > state.islandTopInset - 6, tileWidth > 0 else {
            state.hoveredQuickAction = nil
            return
        }
        let slot = (x + spacing / 2) / (tileWidth + spacing)
        let index = min(max(Int(slot.rounded(.down)), 0), actions.count - 1)
        if state.hoveredQuickAction != actions[index] {
            state.hoveredQuickAction = actions[index]
        }
    }

    private func perform(_ action: QuickAction, with items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        // Settings › Shelf › Open tray after drop; off, the wings' count shows it.
        QuickActionRunner.perform(action, items: items,
                                  from: .island(openTray: ShelfSettings.shared.openTrayAfterDrop || dropsStraightIntoTray))
    }
}

// MARK: - Context menu

private struct IslandContextMenu: View {
    /// " (⌃⌥C)" for an action's shortcut, or nothing when it has none.
    private func keys(_ action: ShortcutAction) -> String {
        GlobalShortcutService.shared.display(for: action).map { " (\($0))" } ?? ""
    }
    // High Alert isn't observed here: AppState forwards its on/off flips, and
    // the service's once-a-second countdown would redraw this whole view.
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var clipboardSettings = ClipboardSettings.shared
    @ObservedObject private var generalSettings = GeneralSettings.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared

    var body: some View {
        Button {
            state.toggleIsland()
        } label: {
            Label((state.isIslandExpanded ? "Close Shelf" : "Open Shelf") + keys(.toggleIsland), systemImage: "rectangle.topthird.inset.filled")
        }

        Divider()

        // The pages and their edit modes live in one submenu, so the top level
        // stays short enough to read at a glance.
        Menu {
            ForEach(ShelfPage.allCases) { page in
                Button {
                    state.open(page)
                    NotchWindowController.shared.focusPanel()
                } label: {
                    Label(page == .tray ? "Tray (\(state.shelfItems.count))" : page.title, systemImage: page.iconName)
                }
            }

            Divider()

            Button { state.beginCustomizingHome() } label: {
                Label("Customize Home…", systemImage: "square.grid.2x2")
            }
            .disabled(state.isCustomizingHome || !shelfSettings.isEnabled)
            Button { state.beginRearrangingWidgets() } label: {
                Label("Rearrange Widgets…", systemImage: "hand.draw")
            }
            .disabled(!shelfSettings.isEnabled)
        } label: {
            Label("Pages", systemImage: "square.grid.2x2")
        }
        // Settings › Clipboard › Clipboard locations › Shelf right-click menu.
        if clipboardSettings.isEnabled && clipboardSettings.inShelfMenu {
            Button { state.toggleClipboard() } label: {
                Label("Open Clipboard\(keys(.toggleClipboard))", systemImage: "doc.on.clipboard")
            }
        }
        Button { state.isBasketVisible.toggle() } label: {
            Label((state.isBasketVisible ? "Hide Basket" : "Show Basket") + keys(.toggleBasket), systemImage: "basket")
        }
        Button { TrayActions.snipToTray() } label: {
            Label("Snip to Tray\(keys(.snipToTray))", systemImage: "camera.viewfinder")
        }

        Divider()

        // Everything that toggles a mode rather than opening something.
        Menu {
            Button {
                state.isIslandPinned.toggle()
                // Pinning a closed shelf would do nothing visible; open it so it stays open.
                if state.isIslandPinned, !state.isIslandExpanded { state.setIslandExpanded(true) }
            } label: {
                Label(state.isIslandPinned ? "Unpin Shelf" : "Keep Shelf Open", systemImage: state.isIslandPinned ? "pin.slash" : "pin")
            }
            Button { state.isLiveActivityPresented.toggle() } label: {
                Label((state.isLiveActivityPresented ? "Hide Live Activity" : "Show Live Activity") + keys(.toggleLiveActivity), systemImage: "sparkles.tv")
            }
            Button { state.sleepBlocker.toggleIndefinite() } label: {
                Label(state.sleepBlocker.isAwakeActive ? "Stop High Alert" : "High Alert (Keep Awake)", systemImage: "cup.and.saucer.fill")
            }

            if !state.shelfItems.isEmpty {
                Divider()
                Button(role: .destructive) { state.clearTrayWithUndo() } label: {
                    Label("Clear Tray (\(state.shelfItems.count))", systemImage: "trash")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }

        Divider()

        if generalSettings.rightClickToHide {
            Button { IslandVisibilityService.shared.hide() } label: {
                Label(generalSettings.islandStyle == .notchAttached && state.notchHeight > 0 ? "Hide Notch" : "Hide Island",
                      systemImage: "eye.slash")
            }
        }
        // The guide opens on the page you are looking at, so the menu answers
        // "what is this?" about what is actually on screen.
        Button { UserGuideWindowController.shared.show(topic: UserGuideWindowController.topic(for: state.shelfPage)) } label: {
            Label("Tama Guide", systemImage: "text.book.closed")
        }
        Button { SettingsWindowController.shared.showWindow() } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        Button("Quit Tama") { NSApplication.shared.terminate(nil) }
    }
}

/// The screen the island being drawn belongs to (nil: the live island), so
/// nested views read that screen's notch rather than the live one's.
private struct IslandDisplayIDKey: EnvironmentKey {
    static let defaultValue: CGDirectDisplayID? = nil
}

extension EnvironmentValues {
    var islandDisplayID: CGDirectDisplayID? {
        get { self[IslandDisplayIDKey.self] }
        set { self[IslandDisplayIDKey.self] = newValue }
    }
}
