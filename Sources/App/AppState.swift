import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Island UI State
    @Published public var isIslandExpanded: Bool = false
    @Published public var isIslandHovered: Bool = false
    @Published public var isIslandPinned: Bool = false
    /// Any Basket is on screen. Turning it on with none open opens one.
    @Published public var isBasketVisible: Bool = false {
        didSet {
            guard isBasketVisible != oldValue else { return }
            basketVisibilityChanged()
        }
    }
    @Published public var activeNotification: DroppyNotification? = nil
    /// How long the banner on screen was meant to stay (for re-arming after hover).
    var lastNotificationDuration: TimeInterval = 4.5
    @Published public var isLiveActivityPresented: Bool = false
    /// A sheet is up over the island; auto-collapse would tear it down mid-task.
    /// Read-only: it is derived from `modalOwners`, so write through
    /// `setModal(_:owner:)` instead of assigning it.
    @Published public private(set) var isModalPresented: Bool = false
    /// Who currently has a modal up; `isModalPresented` mirrors it (`ModalOwners`).
    private var modalOwners = ModalOwners()
    @Published public var liveActivityMode: LiveActivityMode = .mediaAndFocus

    // MARK: Shelf
    // The open shelf shows one page at a time; the lane pill under it switches.
    @Published public var shelfPage: ShelfPage = .home {
        didSet {
            guard shelfPage != oldValue else { return }
            if shelfPage != .home { isOutputPickerOpen = false }
            if shelfPage != .home { playerPanel = .none }
            if shelfPage != .home { homeDraft = nil }
            // Rearranging is only drawn on the Widgets page, but it also holds
            // the shelf open. Left set, a page switch (the bar, the calendar
            // button, ⌘1–⌘4) parked the shelf open with nothing on screen
            // explaining why and no way for it to close itself.
            if shelfPage != .widgets { isRearrangingWidgets = false }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// Audio output list folded out under the player.
    @Published public var isOutputPickerOpen: Bool = false {
        didSet {
            guard isOutputPickerOpen != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// Lyrics or Playing Next open beside the player (the shelf widens).
    @Published public var playerPanel: PlayerPanel = .none {
        didSet {
            guard playerPanel != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// Droplet currently opened on the Widgets page (nil = the widget row).
    @Published public var activeDropletID: String? = nil {
        didSet {
            guard activeDropletID != oldValue else { return }
            dropletConsoleHeight = nil
            // The console going away takes its fields with it, and a focused
            // one never reports losing focus.
            clearEditing(withPrefix: "droplet.")
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    // MARK: Home layout
    // The home page holds one or two widgets side by side: the player and/or
    // Droplets that have a card. Customising edits a draft that only replaces
    // `homeWidgets` once it's confirmed.

    /// What the home page shows, in order. Persisted as `homeWidgets`.
    @Published public var homeWidgets: [String] = [HomeWidget.media] {
        didSet {
            guard homeWidgets != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// The layout being customised; nil while the home page isn't in edit mode.
    @Published public var homeDraft: [String]? = nil {
        didSet {
            guard homeDraft != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    public var isCustomizingHome: Bool { homeDraft != nil }

    /// Widgets that can go on the home page right now: the player, Droplets
    /// that are switched on and have a card, and the calendar.
    public var availableHomeWidgets: [String] {
        [HomeWidget.weather, HomeWidget.media]
            + droplets.filter { $0.isEnabled && HomeWidget.cardDroplets.contains($0.id) }.map(\.id)
            + [HomeWidget.battery, HomeWidget.calendar]
    }

    /// The home page's widgets as drawn: the draft while customising, dropping
    /// any whose Droplet has since been switched off.
    public var visibleHomeWidgets: [String] {
        let available = Set(availableHomeWidgets)
        if let homeDraft { return homeDraft.filter(available.contains) }
        let saved = homeWidgets.filter(available.contains)
        return saved.isEmpty ? [HomeWidget.media] : saved
    }

    /// The plain full player, with its lyrics / queue / output panels. Any
    /// other layout draws cards.
    public var showsFullPlayer: Bool {
        !isCustomizingHome && visibleHomeWidgets == [HomeWidget.media]
    }

    /// Two cards side by side need the wide shelf.
    /// Customising too: the picker's row of widgets plus cancel/confirm
    /// doesn't fit the regular width.
    public var isHomeWide: Bool {
        shelfPage == .home && (visibleHomeWidgets.count > 1 || isCustomizingHome)
    }

    public func beginCustomizingHome() {
        guard ShelfSettings.shared.isEnabled else { return }
        if !isIslandExpanded { open(.home) }
        withAnimation(DS.Motion.fluid) {
            shelfPage = .home
            isOutputPickerOpen = false
            playerPanel = .none
            homeDraft = visibleHomeWidgets
        }
        DroppyAudio.playTick()
    }

    /// Adds or removes a widget in the draft. A third one takes the place of
    /// the second, so the first stays put.
    public func toggleHomeWidget(_ id: String) {
        guard var draft = homeDraft else { return }
        if let index = draft.firstIndex(of: id) {
            draft.remove(at: index)
        } else if draft.count >= HomeWidget.limit {
            draft[draft.count - 1] = id
        } else {
            draft.append(id)
        }
        withAnimation(DS.Motion.fluid) { homeDraft = draft }
        DroppyAudio.playTick()
    }

    public func commitHomeCustomization() {
        guard let draft = homeDraft, !draft.isEmpty else { return }
        withAnimation(DS.Motion.fluid) {
            homeWidgets = draft
            homeDraft = nil
        }
        DroppyAudio.playTick()
    }

    public func cancelHomeCustomization() {
        guard homeDraft != nil else { return }
        withAnimation(DS.Motion.fluid) { homeDraft = nil }
        DroppyAudio.playTick()
    }

    /// A file drag is hovering the notch: the island shows the quick-action tiles.
    @Published public var isDragHovering: Bool = false {
        didSet {
            guard isDragHovering != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }
    @Published public var hoveredQuickAction: QuickAction? = nil

    /// A file drag is closing in on the resting notch but hasn't reached it yet:
    /// the notch leans towards it a little before the tiles unfold.
    @Published public var isDragNear: Bool = false

    /// Files dropped on the Tama Cloud / Convert tiles, waiting for the Tray page.
    @Published public var pendingShare: [ShelfItem]? = nil
    @Published public var pendingConvert: [ShelfItem]? = nil

    /// Volume / brightness HUD shown in the notch wings.
    @Published public var hud: IslandHUD? = nil
    var hudDismiss: DispatchWorkItem?
    /// Held items whose files are being moved or copied off the main thread.
    /// Their old paths vanish mid-way, so the missing-file prune leaves them be.
    var heldItemsInFileWork: Set<UUID> = []
    var shelfReset: DispatchWorkItem?

    /// The clipboard docks at the bottom of the screen, separate from the notch.
    @Published public var isClipboardVisible: Bool = false {
        didSet { if !isClipboardVisible { isClipboardPasteMode = false } }
    }
    /// The clipboard was opened with the paste shortcut: picking a clip pastes
    /// it into the app underneath, whatever "Paste into the previous app" says.
    @Published public var isClipboardPasteMode: Bool = false
    @Published public var pinboards: [Pinboard] = [] {
        didSet { persistPinboards() }
    }

    /// Height of the page area of the open shelf, resolved against live state.
    public func pageHeight(_ page: ShelfPage) -> CGFloat {
        switch page {
        case .home where !showsFullPlayer:
            return isCustomizingHome ? HomeWidget.editPageHeight : HomeWidget.cardHeight
        case .home:
            let outputs = CGFloat(AudioOutputService.shared.devices.count)
            let player = DroppyShelfMetrics.playerHeight
            return isOutputPickerOpen
                ? player + PlayerMetrics.outputPickerTop + outputs * PlayerMetrics.outputRowPitch
                : player
        case .tray: return DroppyShelfMetrics.trayPageHeight
        case .widgets:
            if let id = activeDropletID {
                return dropletConsoleHeight ?? DroppyShelfMetrics.consoleHeight(for: id)
            }
            return isRearrangingWidgets ? widgetsGridHeight : DroppyShelfMetrics.widgetsPageHeight
        case .calendar: return DroppyShelfMetrics.calendarPageHeight
        }
    }

    // Data collections
    @Published public var shelfItems: [ShelfItem] = []
    /// The floating Baskets, each with its own files (see AppState+Basket).
    @Published public var baskets: [Basket] = []
    /// Settings › Shelf › Two Stacks: the stack the Tray shows and drops land in.
    @Published public var activeTrayStack: Int = 0
    /// The Tray shows only files with this tag; nil shows all.
    @Published public var trayTagFilter: String? = nil
    @Published public var clipboardItems: [ClipboardItem] = []
    @Published public var droplets: [DropletModel] = []
    
    // Media & System
    @Published public var mediaService = MediaService.shared
    @Published public var sleepBlocker = SleepBlockerService.shared
    @Published public var systemMonitor = SystemMonitorService.shared
    
    // Active Droplet states
    @Published public var isPomodoroActive: Bool = false
    /// Lives on `PomodoroClock`: it changes every second, and a write here
    /// would redraw every view that observes AppState.
    public var pomodoroSecondsRemaining: Int {
        get { PomodoroClock.shared.secondsRemaining }
        set { if PomodoroClock.shared.secondsRemaining != newValue { PomodoroClock.shared.secondsRemaining = newValue } }
    }
    @Published public var isPomodoroWorkCycle: Bool = true
    var pomodoroTimer: Timer?

    /// A console asking for more room than the standard one (a long note).
    @Published public var dropletConsoleHeight: CGFloat? = nil {
        didSet {
            guard dropletConsoleHeight != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// When the running cycle ends; the countdown is derived from it so sleep
    /// and menu tracking can't make the timer drift.
    var pomodoroEndDate: Date?
    /// A cycle has been started and not reset — paused still counts.
    var pomodoroHasStarted = false
    /// Length of the current cycle, for progress rings.
    public var pomodoroCycleSeconds: Int {
        let settings = PomodoroSettings.shared
        return (isPomodoroWorkCycle ? settings.workMinutes : settings.breakMinutes) * 60
    }

    @Published public var quickMathExpression: String = ""
    /// A text field in the shelf is being typed into (e.g. Calendar's New
    /// Task), so the pointer drifting off mustn't close it and lose the text.
    /// Read-only: it is derived from `editingOwners`, so write through
    /// `setEditing(_:owner:)` instead of assigning it.
    @Published public private(set) var isEditingText = false
    /// Which fields are being typed into; `isEditingText` mirrors it.
    private var editingOwners = EditingOwners()

    // Preferences are not here: they live in the settings stores under
    // App/Settings (`ShelfSettings`, `HUDSettings`…). See SettingsStore.swift.

    /// The Widgets page is in rearrange mode (drag icons to reorder).
    @Published public var isRearrangingWidgets: Bool = false {
        didSet {
            guard isRearrangingWidgets != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    /// The tags clips can carry, in the order they were made.
    @Published public var clipboardTags: [ClipTag] = [] {
        didSet { persistClipboardTags() }
    }

    // MARK: Island visibility

    /// Hidden from the island's right-click menu; not persisted, so a relaunch
    /// always brings the island back.
    @Published public var isIslandHidden: Bool = false {
        didSet {
            guard isIslandHidden != oldValue else { return }
            IslandVisibilityService.shared.sync()
            onIslandFrameChange?(isIslandExpanded)
        }
    }
    /// The hold-to-reveal modifiers are down right now.
    @Published public var isHoldRevealing: Bool = false

    /// The resting island is drawn invisible and lets clicks through. HUDs,
    /// banners and an open shelf still show, so feedback is never lost.
    public var isRestingSurfaceHidden: Bool {
        (isIslandHidden || GeneralSettings.shared.holdToReveal) && !isHoldRevealing
    }

    // MARK: Media

    /// Music has been paused long enough for Auto-hide preview to fold the wings.
    @Published public var isMediaAutoHidden: Bool = false {
        didSet {
            guard isMediaAutoHidden != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }
    var mediaAutoHideWork: DispatchWorkItem?
    /// The pointer is over the player or media card, where a sideways swipe skips.
    public var isPointerOverMediaWidget = false

    public var onIslandFrameChange: ((Bool) -> Void)?

    /// Something that shapes the island changed: the panel re-fits it.
    public func islandFrameChanged() {
        onIslandFrameChange?(isIslandExpanded)
    }
    
    /// Follow Mouse and All Displays: the screen the live island is on. Only
    /// `NotchWindowController` moves it, and only while the island rests; it
    /// isn't published, the controller redraws after changing it.
    public var pointerScreenID: CGDirectDisplayID?

    /// The screen a display ID names; nil means the live island's screen.
    public func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return getTargetScreen() ?? NSScreen.main }
        return NSScreen.screens.first { $0.displayID == displayID }
    }

    public func getTargetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }
        
        switch DisplaySettings.shared.displayTargetMode {
        case .main:
            return screens.first ?? NSScreen.main
            
        case .builtIn:
            // Clamshell mode has no built-in screen; fall back to the main one.
            return screens.first(where: \.isBuiltIn) ?? screens.first ?? NSScreen.main

        case .external:
            // Prefer an external screen that is the main one, then any external.
            return screens.first(where: { !$0.isBuiltIn }) ?? screens.first ?? NSScreen.main
            
        case .active, .all:
            // The live island's screen, not the pointer's: an open shelf keeps
            // its notch geometry and hit rect while the pointer strays.
            if let id = pointerScreenID, let screen = screens.first(where: { $0.displayID == id }) {
                return screen
            }
            let mouseLoc = NSEvent.mouseLocation
            if let mouseScreen = screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
                return mouseScreen
            }
            return NSScreen.main ?? screens.first
        }
    }
    
    var persistence = Set<AnyCancellable>()
    /// Pending auto-dismiss of the notch banner.
    var notificationDismiss: DispatchWorkItem?

    private init() {
        migrateSettings()
        pinboards = Self.loadPinboards()
        clipboardTags = Self.loadClipboardTags()
        if let page = ShelfSettings.shared.defaultPage.page { shelfPage = page }
        pomodoroSecondsRemaining = PomodoroSettings.shared.workMinutes * 60
        loadDefaultDroplets()
        restorePersistedState()
        setupClipboardMonitoring()
        // Files trashed or moved in Finder leave the Tray even while the shelf
        // is closed, so the wing count and share actions never see dead files.
        // Half a minute is soon enough at rest (a stat per held file each
        // tick); opening the shelf checks at once, below.
        let prune = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                let state = AppState.shared
                guard !state.shelfItems.isEmpty || state.baskets.contains(where: { !$0.items.isEmpty }) else { return }
                state.pruneMissingShelfItems()
                state.pruneExpiredShelfItems()
            }
        }
        prune.tolerance = 5
        RunLoop.main.add(prune, forMode: .common)
        $isIslandExpanded
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in
                // Deferred a turn: the published value lands after this runs.
                DispatchQueue.main.async { AppState.shared.pruneMissingShelfItems() }
            }
            .store(in: &persistence)
        observeSettings().store(in: &persistence)
        observeMenuTracking().store(in: &persistence)
        observeDropletSwitches().store(in: &persistence)
        observeMediaAutoHide().store(in: &persistence)
        // The island's size depends on whether anything is live, so re-render
        // (and resize the panel) when the set of live activities changes.
        LiveActivityCenter.shared.$activities
            .map { $0.map(\.id) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &persistence)
        // Music starting or stopping and High Alert grow or fold the resting
        // wings, but those services' changes aren't ours: without this the shape
        // kept its old size until something of AppState's own (a hover) changed.
        // Only the flips are forwarded — scrubber ticks would redraw everything.
        // Merged, not combined: combineLatest stayed silent until music had
        // changed once, so High Alert alone never resized the wings.
        mediaService.$currentTrack
            .map(\.hasTrack)
            .removeDuplicates()
            .dropFirst()
            .merge(with: sleepBlocker.$isAwakeActive.removeDuplicates().dropFirst())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &persistence)
    }

    // MARK: - Modals

    /// Marks a modal as up or gone for one owner. The island stays open while
    /// any owner still has one, so a Basket closing its preview can't pull the
    /// protection out from under the Tray's.
    ///
    /// `owner` identifies the surface, not the sheet: one per view or service,
    /// and one per instance where a surface can be on screen more than once
    /// (each floating Basket passes its own id).
    public func setModal(_ presented: Bool, owner: String) {
        modalOwners.set(presented, owner: owner)
        guard modalOwners.isPresenting != isModalPresented else { return }
        isModalPresented = modalOwners.isPresenting
    }

    /// An open menu counts as a modal.
    ///
    /// A context menu ("Customize Home…", the Tray's held-item actions) is an
    /// `NSMenu` drawn well outside the island, so the pointer reaching for it
    /// reads as having left — and auto-collapse used to pull the shelf out
    /// from under the menu before it could be clicked. AppKit tells us when
    /// any menu starts and stops tracking, which covers every menu at once.
    private func observeMenuTracking() -> AnyCancellable {
        let center = NotificationCenter.default
        let began = center.publisher(for: NSMenu.didBeginTrackingNotification).map { _ in true }
        let ended = center.publisher(for: NSMenu.didEndTrackingNotification).map { _ in false }
        return began.merge(with: ended)
            .receive(on: RunLoop.main)
            .sink { [weak self] isTracking in
                self?.setModal(isTracking, owner: "appkit.menu")
            }
    }

    /// Drops every owner whose name starts with `prefix`. A surface that goes
    /// away with a sheet still up (a Basket closed from its own close button)
    /// would otherwise hold the island open for good.
    public func clearModals(withPrefix prefix: String) {
        modalOwners.clear(withPrefix: prefix)
        guard modalOwners.isPresenting != isModalPresented else { return }
        isModalPresented = modalOwners.isPresenting
    }

    /// Runs `body` with a modal registered to `owner`, clearing it however
    /// `body` leaves — the shape almost every NSOpenPanel / NSAlert call wants.
    public func withModal<T>(_ owner: String, _ body: () -> T) -> T {
        setModal(true, owner: owner)
        defer { setModal(false, owner: owner) }
        return body()
    }

    // MARK: - Typing

    /// Marks a shelf text field as focused or left, for one field.
    ///
    /// Owner-tracked for the same reason modals are: a console holds a search
    /// box and an editor, and moving between them used to clear the flag while
    /// the person was still typing — the pointer resting outside then closed
    /// the shelf and took the draft with it.
    public func setEditing(_ editing: Bool, owner: String) {
        editingOwners.set(editing, owner: owner)
        guard editingOwners.isPresenting != isEditingText else { return }
        isEditingText = editingOwners.isPresenting
    }

    /// Drops every field whose name starts with `prefix`. A focused field that
    /// is dismantled never reports losing focus, so the surface that owned it
    /// clears its own prefix as it goes.
    public func clearEditing(withPrefix prefix: String) {
        editingOwners.clear(withPrefix: prefix)
        guard editingOwners.isPresenting != isEditingText else { return }
        isEditingText = editingOwners.isPresenting
    }

    public func toggleIsland() {
        setIslandExpanded(!isIslandExpanded)
        if isIslandExpanded { NotchWindowController.shared.focusPanel() }
    }
    
    public func setIslandExpanded(_ expanded: Bool) {
        guard isIslandExpanded != expanded else { return }
        // Settings › Shelf › The Shelf is off: nothing opens it.
        guard !expanded || ShelfSettings.shared.isEnabled else { return }
        shelfReset?.cancel()
        shelfReset = nil
        withAnimation(expanded ? DroppyLayout.expandSpring : DroppyLayout.collapseSpring) {
            isIslandExpanded = expanded
        }
        if !expanded {
            // Nothing in a closed shelf can be typed into, and a field torn
            // down with the focus in it never reports losing it.
            clearEditing(withPrefix: "")
            // The shelf reopens on the page picked in Settings. Reset it only
            // once it has faded out — doing it now would animate a page swap
            // inside a shelf that is busy closing.
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isIslandExpanded else { return }
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) {
                    self.isOutputPickerOpen = false
                    self.playerPanel = .none
                    self.activeDropletID = nil
                    self.homeDraft = nil
                    self.isRearrangingWidgets = false
                    if let page = ShelfSettings.shared.defaultPage.page { self.shelfPage = page }
                }
            }
            shelfReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        onIslandFrameChange?(expanded)
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }
    
    // MARK: - Shelf pages

    /// Opens the shelf on a page, expanding the island if needed.
    public func open(_ page: ShelfPage) {
        guard isIslandExpanded else {
            // The shelf isn't on screen yet, so there is no page swap to animate.
            shelfPage = page
            setIslandExpanded(true)
            return
        }
        withAnimation(DS.Motion.fluid) { shelfPage = page }
    }

    public func select(_ page: ShelfPage) {
        guard page != shelfPage else { return }
        withAnimation(DS.Motion.fluid) { shelfPage = page }
        DroppyAudio.playTick()
    }

    public func toggleClipboard() {
        guard isClipboardVisible || clipboardIsAvailable() else { return }
        isClipboardVisible.toggle()
        DroppyAudio.playTick()
    }

    public func showClipboard() {
        guard clipboardIsAvailable() else { return }
        if !isClipboardVisible { isClipboardVisible = true }
    }

    /// Settings › Clipboard › Paste shortcut. Opens the clipboard in paste
    /// mode; picking a clip drops it straight into the app you came from.
    public func openClipboardToPaste() {
        guard clipboardIsAvailable() else { return }
        isClipboardPasteMode = true
        if !isClipboardVisible {
            isClipboardVisible = true
            DroppyAudio.playTick()
        }
    }

    // MARK: - HUD

    /// Shows a level in the notch wings. With the shelf open the island stays
    /// the shelf (it outranks the HUD) and the shelf shows the level in its
    /// bottom band instead — the macOS HUD may be hidden, so there must be one.
    public func showHUD(_ kind: IslandHUD.Kind, value: Double, isMuted: Bool = false, device: IslandHUD.Device? = nil) {
        let wasHidden = hud == nil
        let next = IslandHUD(kind: kind, value: min(max(value, 0), 1), isMuted: isMuted, device: device)
        // The same level again (a key held at the top, the listener echoing our
        // own change) only keeps the HUD up; it doesn't redraw every observer.
        if next != hud {
            withAnimation(wasHidden && !isIslandExpanded ? DS.Motion.morphOpen : nil) {
                hud = next
            }
        }
        if wasHidden && !isIslandExpanded { onIslandFrameChange?(false) }
        scheduleHUDDismiss(after: min(max(hudStyle(for: kind).duration, 0.5), 5))
    }

    /// Settings › HUDs › Keep HUD while hovered: a pointer resting on the
    /// level keeps it up; it goes a moment after the pointer leaves.
    private func scheduleHUDDismiss(after delay: TimeInterval) {
        hudDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if HUDSettings.shared.keepHUDWhileHovered, self.isIslandHovered, self.hud != nil {
                self.scheduleHUDDismiss(after: 0.4)
                return
            }
            withAnimation(DS.Motion.morphClose) { self.hud = nil }
            self.onIslandFrameChange?(self.isIslandExpanded)
        }
        hudDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
