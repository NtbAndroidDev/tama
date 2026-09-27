import SwiftUI
import AppKit
import Combine

/// The island is drawn inside a canvas much larger than the island itself, so the
/// spring has room to overshoot without the window clipping it. Everything outside
/// the island shape must stay invisible to the mouse, or the canvas would swallow
/// clicks meant for the menu bar and the desktop behind it.
@MainActor
final class IslandHostingView: NSHostingView<DynamicIslandView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let state = AppState.shared
        let size = state.islandSize
        let top = state.islandTopOffset
        let island = NSRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - top,
            width: size.width,
            height: size.height
        ).insetBy(dx: -4, dy: -4)

        var hit = island.contains(point)
        if !hit, state.showsLanePill {
            let pill = state.lanePillSize
            let pillRect = NSRect(
                x: (bounds.width - pill.width) / 2,
                y: island.minY + 4 - DroppyShelfMetrics.lanePillGap - pill.height,
                width: pill.width,
                height: pill.height
            ).insetBy(dx: -6, dy: -6)
            hit = pillRect.contains(point)
        }
        guard hit else { return nil }
        return super.hitTest(point)
    }
}

/// Plain container between the panel and SwiftUI. With an NSHostingView as the
/// window's content view, SwiftUI takes part in sizing the window itself; while
/// the canvas resizes over the notch that feedback loops until AppKit aborts
/// ("more Update Constraints in Window passes than there are views"). Behind a
/// plain NSView the hosting view just follows the container's bounds.
///
/// It also reports pointer movement over the canvas. The global monitor only
/// hears events bound for *other* apps, so once the pointer is over Tama's own
/// window it goes quiet — hover then fired late or not at all, and differently
/// depending on which side the pointer came from.
final class IslandCanvasView: NSView {
    var onPointerMoved: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { onPointerMoved?() }
    override func mouseEntered(with event: NSEvent) { onPointerMoved?() }
    override func mouseExited(with event: NSEvent) { onPointerMoved?() }
}

public final class DroppyNotchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Prevent macOS from pushing the panel down underneath the notch and menu bar
        return frameRect
    }
}

@MainActor
public final class NotchWindowController: NSObject {
    public static let shared = NotchWindowController()
    
    public private(set) var panel: DroppyNotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragMonitors: [Any] = []
    /// Drag pasteboard generation at mouse-down; a newer one means a drag began.
    private var dragBaseline = 0
    /// Whether the current drag carries files (nil = not checked yet).
    private var dragHasFiles: Bool?
    private var collapseTimer: Timer?
    private var openWork: DispatchWorkItem?
    /// Set when the pointer scrolls or clicks on the resting notch, so hover
    /// doesn't unfold the shelf underneath a volume scroll or a double-click.
    /// Cleared once the pointer leaves the island.
    private var suppressHoverOpen = false
    private var interactionMonitor: Any?
    private var lastPointer: NSPoint?
    private var lastPointerIslandSize: CGSize?
    /// Whether the pointer has been over the shelf since it opened. A shelf
    /// opened from the keyboard or a menu closed on the first stray mouse move,
    /// before the pointer could even reach it.
    private var pointerVisitedShelf = false
    /// Whether the pointer was outside the island the last time it actually
    /// moved. Switching pages resizes the shelf, so a stationary pointer can
    /// end up outside a rect that moved away from under it — that must not
    /// count as having left.
    private var pointerWasOutside = false
    /// Keeps the island out of the Space-switch slide; see `SystemSpace`.
    private var systemSpace: SystemSpace?
    /// All Displays: a look-alike resting island on every screen the live one
    /// isn't on, keyed by display ID.
    private var mirrors: [CGDirectDisplayID: NSPanel] = [:]
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let panel = Self.makePanel()
        panel.acceptsMouseMovedEvents = true

        let hostingView = Self.makeHostingView()
        let canvas = IslandCanvasView(frame: panel.contentLayoutRect)
        canvas.onPointerMoved = { [weak self] in self?.handleMouseMoved() }
        hostingView.frame = canvas.bounds
        canvas.addSubview(hostingView)
        panel.contentView = canvas

        self.panel = panel
        CaptureExclusion.register(panel)
        setupObservers()
        ShelfGestureService.shared.start()
    }

    private static func makePanel() -> DroppyNotchPanel {
        let contentRect = NSRect(x: 0, y: 0, width: DroppyLayout.compactWidth, height: DroppyLayout.compactHeight)
        let panel = DroppyNotchPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar: at .statusBar the bar's glass paints over the wings
        // and turns them grey instead of notch black.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private static func makeHostingView(displayID: CGDirectDisplayID? = nil) -> IslandHostingView {
        let hostingView = IslandHostingView(rootView: DynamicIslandView(displayID: displayID))
        hostingView.wantsLayer = true
        // The expanded stack stays mounted at full size even while the island is
        // resting, so it can cross-fade during the morph. Without this, AppKit
        // turns that content size into window constraints, and the moment the
        // canvas is smaller than the stack the constraint system throws.
        hostingView.sizingOptions = []
        // The canvas deliberately sits over the notch and menu bar. If SwiftUI
        // tracked the safe area there, every canvas resize would change the
        // insets, which re-lays out, which changes them again — AppKit aborts
        // that loop with an "Update Constraints in Window" exception.
        hostingView.safeAreaRegions = []
        hostingView.layer?.masksToBounds = true
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
    }

    private func setupObservers() {
        guard let panel else { return }
        updateWindowPosition(expanded: false)
        panel.orderFrontRegardless()
        systemSpace = SystemSpace()
        systemSpace?.add(panel)
        
        setupMouseTracking()
        
        // Listen to island expand/collapse state changes
        AppState.shared.onIslandFrameChange = { [weak self] expanded in
            self?.updateWindowPosition(expanded: expanded)
            if !expanded, let panel = self?.panel, panel.isKeyWindow { panel.resignKey() }
        }
        
        // The island reshapes without the pointer moving (hotkeys, banners,
        // Live Activities); re-check click-through once the change lands.
        AppState.shared.objectWillChange
            .sink { [weak self] _ in self?.cachedIslandRect = nil }
            .store(in: &cancellables)
        AppState.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.cachedIslandRect = nil
                self?.updateMousePassThrough()
                self?.rearmAutoCollapseIfNeeded()
            }
            .store(in: &cancellables)

        AppState.shared.$isIslandExpanded
            .removeDuplicates()
            // Fires before the change: a pointer on the notch as it opens counts.
            .sink { [weak self] expanded in
                guard let self else { return }
                self.pointerVisitedShelf = expanded && self.isOverIsland(NSEvent.mouseLocation)
            }
            .store(in: &cancellables)

        // Listen to notification changes to resize window dynamically
        AppState.shared.$activeNotification
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateWindowPosition(expanded: AppState.shared.isIslandExpanded)
            }
            .store(in: &cancellables)
            
        // Listen to media playback state changes (deduplicated to prevent scrubber ticks from triggering window moves)
        AppState.shared.mediaService.$currentTrack
            .map { "\($0.title.isEmpty)" }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateWindowPosition(expanded: AppState.shared.isIslandExpanded)
            }
            .store(in: &cancellables)
            
        // Listen to shelf items count transitions (empty <-> non-empty)
        AppState.shared.$shelfItems
            .map { $0.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateWindowPosition(expanded: AppState.shared.isIslandExpanded)
            }
            .store(in: &cancellables)
            
        // A running timer or High Alert grows the resting notch's wings too.
        AppState.shared.$isPomodoroActive
            .combineLatest(SleepBlockerService.shared.$isAwakeActive)
            .map { $0 || $1 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowPosition(expanded: AppState.shared.isIslandExpanded)
            }
            .store(in: &cancellables)

        // A live activity appearing or ending grows or folds the wings.
        LiveActivityCenter.shared.$activities
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowPosition(expanded: AppState.shared.isIslandExpanded)
            }
            .store(in: &cancellables)

        // Listen to multi-monitor and display resolution changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.cachedIslandRect = nil
                // A display that went away can't keep the live island.
                let state = AppState.shared
                if let id = state.pointerScreenID, !NSScreen.screens.contains(where: { $0.displayID == id }) {
                    state.pointerScreenID = nil
                }
                self.updateWindowPosition(expanded: state.isIslandExpanded)
                // The notch size is read from the screen, not published: redraw the
                // shape for the new (or remaining) display.
                AppState.shared.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Opening or closing changes which screens may take the live island.
        AppState.shared.$isIslandExpanded.map { _ in () }
            .merge(with: AppState.shared.$isDragHovering.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncMirrors() }
            .store(in: &cancellables)

        // Picking another Target Display in Settings has to move the canvas right
        // away; @AppStorage has no publisher of its own, so watch the default.
        UserDefaults.standard.publisher(for: \.displayTargetMode)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Start on the screen being used, not wherever the island last was.
                let mouse = NSEvent.mouseLocation
                AppState.shared.pointerScreenID = NSScreen.screens
                    .first { NSMouseInRect(mouse, $0.frame, false) }?.displayID
                self.screenDidChange()
            }
            .store(in: &cancellables)
    }
    
    /// The panel never resizes with the island. It is a fixed transparent canvas
    /// big enough for anything the island can become; the morph lives entirely
    /// in SwiftUI. Resizing it mid-morph moved the hosting view's origin, and
    /// SwiftUI animated that too — the island dropped below the menu bar and
    /// slid back up on every open. The canvas now only moves between screens,
    /// and only ever grows (for an unusually tall shelf).
    public func updateWindowPosition(expanded: Bool) {
        syncCanvas()
    }

    public func syncCanvas() {
        applyCanvas()
    }

    /// The island's size reads the target screen's notch, which AppState can't
    /// observe: redraw the shape for the new screen, then move the canvas.
    private func screenDidChange() {
        AppState.shared.objectWillChange.send()
        syncCanvas()
    }

    /// Room for the largest shape plus the lane pill and a margin, so the canvas
    /// stays put through every normal state change.
    private static let canvasFloor = CGSize(width: 720, height: 560)

    private func applyCanvas() {
        // Any move of the live island changes which screens need a mirror.
        defer { syncMirrors() }
        guard let panel = self.panel,
              let screen = AppState.shared.getTargetScreen() ?? NSScreen.main ?? NSScreen.screens.first
        else { return }

        let target = canvasFrame(on: screen)
        let current = panel.frame

        let fitsInside = target.width <= current.width + 0.5
            && target.height <= current.height + 0.5
            // Equal top edges, not just "at least as high": a display stacked
            // above or below the old one shares its midX and would be skipped.
            && abs(current.maxY - target.maxY) < 0.5
            && abs(current.midX - target.midX) < 0.5

        guard !fitsInside else { return }
        let grown = current.width > 1
            ? NSRect(
                x: target.midX - max(target.width, current.width) / 2,
                y: target.maxY - max(target.height, current.height),
                width: max(target.width, current.width),
                height: max(target.height, current.height)
            )
            : target
        // Only a different screen moves the origin; a same-screen grow keeps the
        // top edge where it is, so SwiftUI's top-pinned content does not shift.
        setFrameWithoutAnimation(panel, grown)
    }

    // MARK: - All Displays
    // The live island is one panel that follows the pointer between screens.
    // Every other screen gets a mirror: the same SwiftUI island in a panel that
    // ignores the mouse, drawn with its own screen's notch (or pill). Mirrors
    // stay up while the shelf is open — they just keep resting, since an open
    // shelf or drop tiles only belong on the screen being used.

    private func syncMirrors() {
        let state = AppState.shared
        guard state.displayTargetMode == .all, NSScreen.screens.count > 1 else {
            mirrors.values.forEach { $0.orderOut(nil) }
            mirrors.removeAll()
            return
        }
        let live = state.getTargetScreen().flatMap(\.displayID)
        // Settings › HUDs › Hide on external displays / Per-display visibility.
        let targets = state.surfaceScreens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let id = screen.displayID, id != live else { return nil }
            return (id, screen)
        }
        let wanted = Set(targets.map(\.0))
        // The pointer crossing to another screen swaps which one is live, so
        // the mirror it leaves behind is exactly the one the old screen needs.
        // Re-point that panel rather than build a fresh island: a new hosting
        // view lays out its whole SwiftUI graph from scratch, which was most of
        // what a screen crossing cost.
        var spares = mirrors.filter { !wanted.contains($0.key) }.map(\.value)
        mirrors = mirrors.filter { wanted.contains($0.key) }
        for (id, screen) in targets {
            let mirror: NSPanel
            if let existing = mirrors[id] {
                mirror = existing
            } else if let spare = spares.popLast() {
                retarget(spare, to: id)
                mirror = spare
            } else {
                mirror = makeMirror(for: id)
            }
            mirrors[id] = mirror
            let frame = canvasFrame(on: screen)
            if mirror.frame != frame { setFrameWithoutAnimation(mirror, frame) }
            if !mirror.isVisible {
                mirror.orderFrontRegardless()
                systemSpace?.add(mirror)
            }
        }
        spares.forEach { $0.orderOut(nil) }
    }

    private func retarget(_ mirror: NSPanel, to displayID: CGDirectDisplayID) {
        let host = mirror.contentView?.subviews.lazy.compactMap { $0 as? IslandHostingView }.first
        host?.rootView = DynamicIslandView(displayID: displayID)
    }

    private func makeMirror(for displayID: CGDirectDisplayID) -> NSPanel {
        let panel = Self.makePanel()
        panel.ignoresMouseEvents = true
        let canvas = NSView(frame: panel.contentLayoutRect)
        // `retarget` finds this view again to point it at another screen.
        let hostingView = Self.makeHostingView(displayID: displayID)
        hostingView.frame = canvas.bounds
        canvas.addSubview(hostingView)
        panel.contentView = canvas
        CaptureExclusion.register(panel)
        return panel
    }

    private func setFrameWithoutAnimation(_ panel: NSPanel, _ frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(frame, display: false, animate: false)
        }
    }

    private func canvasFrame(on screen: NSScreen) -> NSRect {
        let needed = AppState.shared.islandCanvasSize
        let size = CGSize(
            width: max(needed.width, Self.canvasFloor.width),
            height: max(needed.height, Self.canvasFloor.height)
        )
        let frame = screen.frame
        return NSRect(
            x: frame.origin.x + (frame.width - size.width) / 2,
            y: frame.origin.y + frame.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Where the island shape actually sits on screen — the canvas is much larger,
    /// so hover tests have to use this, not the panel frame. While the shelf is
    /// open the rect reaches down over the lane pill so moving to it never closes it.
    /// The live island's screen rect, cached: every pointer move asks for it,
    /// and working it out walks the screens and the notch geometry. Cleared
    /// on any AppState change and on display changes.
    private var cachedIslandRect: NSRect?

    private func currentIslandRect() -> NSRect? {
        if let cachedIslandRect { return cachedIslandRect }
        guard let screen = AppState.shared.getTargetScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let rect = islandScreenRect(on: screen)
        cachedIslandRect = rect
        return rect
    }

    private func islandScreenRect(on screen: NSScreen) -> NSRect {
        let state = AppState.shared
        let size = state.islandSize
        let top = state.islandTopOffset
        let frame = screen.frame
        let pill = state.showsLanePill
            ? DroppyShelfMetrics.lanePillGap + DroppyShelfMetrics.lanePillHeight
            : 0
        // The navigation row can be wider than a narrow shelf (the player
        // alone plus four favorites); cover it so moving onto it never closes.
        let width = max(size.width, state.showsLanePill ? state.lanePillSize.width : 0)
        return NSRect(
            x: frame.origin.x + (frame.width - width) / 2,
            y: frame.origin.y + frame.height - size.height - top - pill,
            width: width,
            height: size.height + pill
        )
    }

    private func setupMouseTracking() {
        // Global monitors call back on the main thread. This one hears every
        // pointer move on the Mac, so it runs in place rather than as a Task each.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }

        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
            self?.handleRestingInteraction()
            return event
        }

        dragMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                Task { @MainActor in self?.beginDragWatch() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                Task { @MainActor in self?.handleDragMoved() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                Task { @MainActor in self?.endDragWatch() }
            },
        ].compactMap { $0 }
    }

    // MARK: - Drag pre-hover
    // A file drag heading for the resting notch makes it lean out a little
    // before the drop tiles unfold, so the target feels magnetic.

    /// How close (in points) a file drag has to be before the notch reacts.
    private static let dragProximity: CGFloat = 80

    private func beginDragWatch() {
        dragBaseline = NSPasteboard(name: .drag).changeCount
        dragHasFiles = nil
        setDragNear(false)
    }

    /// Follow Mouse and All Displays: the live island moves to whichever
    /// screen the pointer is on.
    private func followPointerScreen(_ mouse: NSPoint) {
        let state = AppState.shared
        guard state.displayTargetMode.followsPointer,
              // An open shelf or drop tiles stay on their screen until they close.
              !state.isIslandExpanded, !state.isDragHovering,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              // A display switched off in Settings › HUDs doesn't take the island.
              state.allowsSurface(on: screen),
              let id = screen.displayID,
              id != state.pointerScreenID
        else { return }
        state.pointerScreenID = id
        // A hover-open timed on the old screen mustn't fire on the new one.
        openWork?.cancel()
        openWork = nil
        syncCanvas()
        // Notch or no notch comes from the new screen; reshape the island.
        AppState.shared.objectWillChange.send()
    }

    private func handleDragMoved() {
        // A file drag heading for another screen's notch brings the island along.
        followPointerScreen(NSEvent.mouseLocation)
        let state = AppState.shared
        guard !state.isIslandExpanded, !state.isDragHovering, !isHiddenAtRest,
              let rect = currentIslandRect()
        else { return setDragNear(false) }

        let mouse = NSEvent.mouseLocation
        let dx = max(rect.minX - mouse.x, 0, mouse.x - rect.maxX)
        let dy = max(rect.minY - mouse.y, 0, mouse.y - rect.maxY)
        let isNear = hypot(dx, dy) < Self.dragProximity

        // Only look at the pasteboard once the pointer is actually close.
        setDragNear(isNear && isDraggingFiles)
        updateMousePassThrough(mouse)
    }

    private func endDragWatch() {
        dragHasFiles = nil
        setDragNear(false)
        updateMousePassThrough()
        // A plain click in another app closes the shelf. Acting on mouse-up and
        // only when no drag began keeps a file drag from Finder into the open
        // Tray working.
        let state = AppState.shared
        if state.isIslandExpanded, state.canAutoCollapse,
           NSPasteboard(name: .drag).changeCount == dragBaseline,
           !isOverIsland(NSEvent.mouseLocation) {
            state.setIslandExpanded(false)
        }
    }

    /// `hitTest` returning nil only makes AppKit drop a click; it doesn't hand
    /// it to the window below. The canvas sits above almost everything, so it
    /// swallowed clicks on whatever lay under it — even system privacy prompts.
    /// Let the whole panel ignore the mouse unless the pointer is on the island,
    /// or a file drag is closing in on it.
    private func updateMousePassThrough(_ mouse: NSPoint = NSEvent.mouseLocation) {
        guard let panel, let rect = currentIslandRect() else { return }
        // A hidden resting island lets everything through; right-click and
        // hold-to-reveal are heard by IslandVisibilityService instead.
        if isHiddenAtRest {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        let reach: CGFloat = AppState.shared.isDragNear || AppState.shared.isDragHovering ? Self.dragProximity : 10
        let ignores = !NSMouseInRect(mouse, rect.insetBy(dx: -reach, dy: -reach), false)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    /// Settings › Accessibility hid the island and nothing is showing in it,
    /// or Settings › HUDs hides it on this screen (switched-off display,
    /// fullscreen, Mission Control) while it rests or shows a level.
    private var isHiddenAtRest: Bool {
        let state = AppState.shared
        let mode = state.islandMode
        if state.isRestingSurfaceHidden && mode == .resting { return true }
        return (mode == .resting || mode == .hud) && state.isSurfaceSuppressed(on: nil)
    }

    /// Settings › HUDs changed which screens may carry the island: move the
    /// live one off a screen that no longer may, and redo the mirrors.
    public func surfaceRulesChanged() {
        let state = AppState.shared
        if state.displayTargetMode.followsPointer,
           let current = state.getTargetScreen(), !state.allowsSurface(on: current) {
            let mouse = NSEvent.mouseLocation
            let allowed = state.surfaceScreens
            let next = allowed.first { NSMouseInRect(mouse, $0.frame, false) } ?? allowed.first
            state.pointerScreenID = next?.displayID
        }
        cachedIslandRect = nil
        screenDidChange()
        updateMousePassThrough()
    }

    private func setDragNear(_ isNear: Bool) {
        if AppState.shared.isDragNear != isNear {
            AppState.shared.isDragNear = isNear
        }
    }

    private var isDraggingFiles: Bool {
        if let dragHasFiles { return dragHasFiles }
        let pasteboard = NSPasteboard(name: .drag)
        // The drag session may not have written the pasteboard yet — check again next event.
        guard pasteboard.changeCount != dragBaseline else { return false }
        let hasFiles = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        dragHasFiles = hasFiles
        return hasFiles
    }
    
    private func handleRestingInteraction() {
        guard !AppState.shared.isIslandExpanded,
              let rect = currentIslandRect(),
              NSMouseInRect(NSEvent.mouseLocation, rect, false) else { return }
        suppressHoverOpen = true
        openWork?.cancel()
        openWork = nil
    }

    /// Whether a screen point is over the island as it's drawn right now.
    public func isOverIsland(_ point: NSPoint) -> Bool {
        guard let rect = currentIslandRect() else { return false }
        return NSMouseInRect(point, rect.insetBy(dx: -10, dy: -10), false)
    }

    /// Gives the panel keyboard focus (⌘1–⌘4, Esc) without activating Tama.
    public func focusPanel() {
        panel?.makeKey()
    }

    private func handleMouseMoved() {
        guard self.panel != nil else { return }
        let mouseLoc = NSEvent.mouseLocation
        // The second report of a move already handled (global monitor plus
        // tracking area), with nothing changed since: skip even the screen walk.
        if mouseLoc == lastPointer, let cached = cachedIslandRect, cached.size == lastPointerIslandSize { return }
        followPointerScreen(mouseLoc)
        guard let islandRect = currentIslandRect() else { return }
        // The global monitor and the canvas tracking area both report the same
        // move; handle each position once.
        guard mouseLoc != lastPointer || islandRect.size != lastPointerIslandSize else { return }
        lastPointer = mouseLoc
        lastPointerIslandSize = islandRect.size

        updateMousePassThrough(mouseLoc)

        // A drag cancelled while still over the island (Esc, or the source app
        // calling it off) never reaches the drop delegate's `dropExited`, so
        // the island would keep showing the drop tiles and refuse to collapse.
        // A move with no button held means the drag is definitely over.
        if AppState.shared.isDragHovering, NSEvent.pressedMouseButtons == 0 {
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.morphClose)) {
                AppState.shared.isDragHovering = false
                AppState.shared.hoveredQuickAction = nil
            }
        }

        // Hover highlighting is always live; only the automatic open/close is optional.
        let hitRect = AppState.shared.isIslandExpanded ? islandRect.insetBy(dx: -10, dy: -10) : islandRect
        let isInside = NSMouseInRect(mouseLoc, hitRect, false) && !isHiddenAtRest

        if AppState.shared.isIslandHovered != isInside {
            AppState.shared.isIslandHovered = isInside
        }
        pointerWasOutside = isInside ? false : true
        if !isInside { suppressHoverOpen = false }

        if isInside {
            collapseTimer?.invalidate()
            collapseTimer = nil
            if AppState.shared.isIslandExpanded { pointerVisitedShelf = true }
            // The setting only governs opening; leaving closes a shelf either way.
            // Settings › Pomodoro › Hover opens the timer: the running timer in
            // the wings opens straight onto Pomodoro, even without Auto-expand.
            let hoversTimer = AppState.shared.pomodoroHoverOpens && AppState.shared.isPomodoroActive
                && RestingSlot.ordered().first == .pomodoro
            if AppState.shared.expandOnHover || hoversTimer, !AppState.shared.isIslandExpanded, openWork == nil, !suppressHoverOpen {
                // A short dwell, so sweeping past the menu bar doesn't pop it open.
                let work = DispatchWorkItem { [weak self] in
                    self?.openWork = nil
                    guard AppState.shared.isIslandHovered else { return }
                    if hoversTimer, AppState.shared.isPomodoroActive {
                        AppState.shared.shelfPage = .widgets
                        AppState.shared.activeDropletID = "pomodoro"
                    }
                    // Deliberately not focused: a pointer brushing the notch
                    // mustn't take the keys from whatever is being typed in.
                    // A click on the shelf gives it focus.
                    AppState.shared.setIslandExpanded(true)
                }
                openWork = work
                let delay = hoversTimer ? min(AppState.shared.hoverOpenDelay, 0.15) : AppState.shared.hoverOpenDelay
                DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0), execute: work)
            }
        } else {
            openWork?.cancel()
            openWork = nil
            if AppState.shared.isIslandExpanded, pointerVisitedShelf { scheduleAutoCollapse() }
        }
    }

    private func scheduleAutoCollapse() {
        // Settings › Shelf › Auto-collapse off: only a click elsewhere or Esc closes it.
        guard collapseTimer == nil, AppState.shared.autoCollapse else { return }

        collapseTimer = Timer.scheduledTimer(
            withTimeInterval: AppState.shared.autoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let rect = self.currentIslandRect() else { return }
                defer { self.collapseTimer = nil }
                guard AppState.shared.autoCollapse, AppState.shared.canAutoCollapse else { return }

                let stillInside = NSMouseInRect(NSEvent.mouseLocation, rect.insetBy(dx: -10, dy: -10), false)
                if !stillInside {
                    AppState.shared.setIslandExpanded(false)
                }
            }
        }
    }

    /// Arms the countdown again once whatever was holding the shelf open lets
    /// go — a sheet dismissed, a pin removed, a task field left. The pointer
    /// may well be parked far from the notch and never move again, so waiting
    /// for the next mouse-moved event would leave the shelf open for good.
    private func rearmAutoCollapseIfNeeded() {
        let state = AppState.shared
        // Only when the pointer had already left of its own accord: the shelf
        // growing or shrinking under a pointer that is standing still is the
        // island moving away, not the person leaving.
        guard collapseTimer == nil, state.isIslandExpanded, state.autoCollapse,
              state.canAutoCollapse, pointerVisitedShelf, pointerWasOutside,
              let rect = currentIslandRect(),
              !NSMouseInRect(NSEvent.mouseLocation, rect.insetBy(dx: -10, dy: -10), false)
        else { return }
        scheduleAutoCollapse()
    }
}

private extension UserDefaults {
    /// KVO-visible mirror of the `displayTargetMode` @AppStorage key; the
    /// property name must match the key for UserDefaults to emit changes.
    @objc dynamic var displayTargetMode: String? { string(forKey: "displayTargetMode") }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
