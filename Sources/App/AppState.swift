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
        guard shelfEnabled else { return }
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
    @AppStorage("pomodoroWorkMinutes") public var pomodoroWorkMinutes: Int = 25 {
        didSet { syncIdlePomodoro() }
    }
    @AppStorage("pomodoroBreakMinutes") public var pomodoroBreakMinutes: Int = 5 {
        didSet { syncIdlePomodoro() }
    }
    /// Pomodoro › ambient sound: synthesised noise while a focus cycle runs.
    @AppStorage("pomodoroAmbientEnabled") public var pomodoroAmbientEnabled: Bool = false {
        didSet { syncPomodoroAmbient() }
    }
    @AppStorage("pomodoroAmbientSound") public var pomodoroAmbientSound: String = AmbientSoundService.Sound.brown.rawValue {
        didSet { syncPomodoroAmbient() }
    }
    @AppStorage("pomodoroAmbientVolume") public var pomodoroAmbientVolume: Double = 0.5 {
        didSet { AmbientSoundService.shared.setVolume(pomodoroAmbientVolume) }
    }
    /// Runs the "Tama Focus On/Off" Shortcuts as focus cycles start and stop.
    @AppStorage("pomodoroFocusShortcuts") public var pomodoroFocusShortcuts: Bool = false
    /// The running Pomodoro outranks music and the Tray in the resting wings.
    @AppStorage("pomodoroKeepVisible") public var pomodoroKeepVisible: Bool = true {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// Hovering the resting timer opens the shelf straight onto Pomodoro.
    @AppStorage("pomodoroHoverOpens") public var pomodoroHoverOpens: Bool = true
    /// Pomodoro › Momentum: finished focus sessions and the day-by-day streak.
    @AppStorage("pomodoroMomentum") public var pomodoroShowsMomentum: Bool = true
    @AppStorage("pomodoroSessionsToday") public var pomodoroSessionsToday: Int = 0
    @AppStorage("pomodoroMomentumDay") public var pomodoroMomentumDay: String = ""
    @AppStorage("pomodoroStreakDays") public var pomodoroStreakDays: Int = 0
    @AppStorage("pomodoroBestStreak") public var pomodoroBestStreak: Int = 0
    /// High Alert: what it keeps awake, and the ruler's last length.
    @AppStorage("highAlertMode") public var highAlertMode: HighAlertMode = .display
    @AppStorage("highAlertMinutes") public var highAlertMinutes: Int = 60

    // MARK: Tasks & Calendar (Settings › Shelf › Tasks & Calendar)
    @AppStorage("tasksShowTasks") public var tasksShowTasks: Bool = true {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksShowEvents") public var tasksShowEvents: Bool = true {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksHideUndated") public var tasksHideUndated: Bool = false {
        didSet { CalendarService.shared.reload() }
    }
    /// Newline-separated calendar identifiers left out of the page.
    @AppStorage("tasksHiddenCalendars") public var tasksHiddenCalendars: String = "" {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksHiddenLists") public var tasksHiddenLists: String = "" {
        didSet { CalendarService.shared.reload() }
    }
    /// Where new tasks and events go; "" is the system default.
    @AppStorage("tasksDefaultList") public var tasksDefaultList: String = ""
    @AppStorage("tasksDefaultCalendar") public var tasksDefaultCalendar: String = ""
    /// Seconds a completed task stays struck through before it's cleaned up.
    @AppStorage("tasksCleanupDelay") public var tasksCleanupDelay: Int = 60
    @AppStorage("tasksDueAlerts") public var tasksDueAlerts: Bool = true {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksDueChime") public var tasksDueChime: Bool = true
    /// Minutes of warning before a task is due (0: at the due time only).
    @AppStorage("tasksHeadsUpMinutes") public var tasksHeadsUpMinutes: Int = 10
    @AppStorage("tasksEventRing") public var tasksEventRing: Bool = true {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksNextEventWing") public var tasksNextEventWing: Bool = false {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksWeekNumbers") public var tasksWeekNumbers: Bool = true
    @AppStorage("calendarLayout") public var calendarLayout: CalendarLayout = .agenda
    @AppStorage("calendarPopoutOnTop") public var calendarPopoutOnTop: Bool = true {
        didSet { CalendarPopoutController.shared.applyLevel() }
    }

    // MARK: Notes
    @AppStorage("notesAppleSync") public var notesAppleSync: Bool = false {
        didSet { if notesAppleSync { NotesStore.shared.pullFromAppleNotes() } }
    }
    @AppStorage("notesShowToolbar") public var notesShowToolbar: Bool = true
    @AppStorage("notesGrowCanvas") public var notesGrowCanvas: Bool = true

    // MARK: Phase 8b droplets (TermiNotch, Meetings, Notification HUD, Agents, Notchface)

    /// TermiNotch › Open in Terminal: the app that gets the current folder.
    @AppStorage("termiNotchTerminalApp") public var termiNotchTerminalApp: TerminalApp = .terminal
    /// TermiNotch › zsh gets the `user@host ~` / green `$` prompt after your own startup files.
    @AppStorage("termiNotchDroppyPrompt") public var termiNotchDroppyPrompt: Bool = true
    /// TermiNotch › Show TermiNotch bar: open as the one-line quick command bar.
    @AppStorage("termiNotchQuickBar") public var termiNotchQuickBar: Bool = false
    @AppStorage("termiNotchFontSize") public var termiNotchFontSize: Double = 12
    /// Meetings › Pause media when a meeting starts (or, see the trigger, when the mic goes live).
    @AppStorage("meetingPauseMedia") public var meetingPauseMedia: Bool = true
    @AppStorage("meetingResumeMedia") public var meetingResumeMedia: Bool = true
    @AppStorage("meetingPauseTrigger") public var meetingPauseTrigger: MeetingPauseTrigger = .callStarts
    /// Meetings › Show active call HUD: phone, elapsed time and the mic level in the notch.
    @AppStorage("meetingCallHUD") public var meetingCallHUD: Bool = true {
        didSet { MeetingControlService.shared.refreshCallActivity() }
    }
    @AppStorage("meetingMicLevel") public var meetingMicLevel: Bool = true {
        didSet { MeetingControlService.shared.refreshCallActivity() }
    }
    /// Notification HUD: seconds a mirrored notification stays up.
    @AppStorage("notificationHUDDuration") public var notificationHUDDuration: Double = 5
    /// Bundle IDs whose notifications are not mirrored, one per line.
    @AppStorage("notificationHUDBlockedApps") public var notificationHUDBlockedApps: String = ""
    @AppStorage("notificationHUDBurst") public var notificationHUDBurst: Bool = true
    @AppStorage("notificationHUDPreview") public var notificationHUDPreview: Bool = true
    @AppStorage("notificationHUDQuickReply") public var notificationHUDQuickReply: Bool = true
    @AppStorage("notificationHUDHideAfterReply") public var notificationHUDHideAfterReply: Bool = true
    @AppStorage("notificationHUDShowFilters") public var notificationHUDShowFilters: Bool = false
    /// Agents: which coding agents feed the notch.
    @AppStorage("agentsClaude") public var agentsClaude: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsCodex") public var agentsCodex: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsCursor") public var agentsCursor: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsShowInNotch") public var agentsShowInNotch: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsNotifyDone") public var agentsNotifyDone: Bool = true
    /// Notchface: the camera to preview (unique ID; empty = the system default).
    @AppStorage("notchfaceCamera") public var notchfaceCamera: String = ""
    @AppStorage("notchfaceMirror") public var notchfaceMirror: Bool = true
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
    public var pomodoroCycleSeconds: Int { (isPomodoroWorkCycle ? pomodoroWorkMinutes : pomodoroBreakMinutes) * 60 }
    
    @Published public var quickMathExpression: String = ""
    /// A text field in the shelf is being typed into (e.g. Calendar's New
    /// Task), so the pointer drifting off mustn't close it and lose the text.
    /// Read-only: it is derived from `editingOwners`, so write through
    /// `setEditing(_:owner:)` instead of assigning it.
    @Published public private(set) var isEditingText = false
    /// Which fields are being typed into; `isEditingText` mirrors it.
    private var editingOwners = EditingOwners()
    
    // Settings (UserDefaults backed)
    // MARK: Lock screen
    // A status row under the system clock and a player above the login field,
    // drawn while the screen is locked. Off until switched on in Settings.
    @AppStorage("lockScreenEnabled") public var lockScreenEnabled: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenShowsBattery") public var lockScreenShowsBattery: Bool = true
    @AppStorage("lockScreenShowsHeadphones") public var lockScreenShowsHeadphones: Bool = true
    /// Weather, air quality and the next sunrise/sunset; asks for Location.
    @AppStorage("lockScreenShowsWeather") public var lockScreenShowsWeather: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenShowsNextEvent") public var lockScreenShowsNextEvent: Bool = true
    @AppStorage("lockScreenShowsPlayer") public var lockScreenShowsPlayer: Bool = true {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Lock/unlock animation: the lock-screen panels fade and scale in and out.
    @AppStorage("lockScreenAnimation") public var lockScreenAnimation: Bool = true
    /// Lock & unlock sound, and which sound each one is (see `LockSound`).
    @AppStorage("lockScreenSounds") public var lockScreenSounds: Bool = false
    @AppStorage("lockScreenLockSound") public var lockScreenLockSound: String = LockSound.none
    @AppStorage("lockScreenUnlockSound") public var lockScreenUnlockSound: String = LockSound.default
    /// Volume and brightness sliders on the lock screen.
    @AppStorage("lockScreenVolumeSlider") public var lockScreenVolumeSlider: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenBrightnessSlider") public var lockScreenBrightnessSlider: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Keep the panels over the screen saver instead of hiding them under it.
    @AppStorage("lockScreenDuringScreensaver") public var lockScreenDuringScreensaver: Bool = false {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// Minutes the display is kept awake while locked (`LockKeepAwake`).
    @AppStorage("lockScreenKeepAwake") public var lockScreenKeepAwake: Int = 0 {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    /// The status widgets row under the clock.
    @AppStorage("lockScreenShowsStatusRow") public var lockScreenShowsStatusRow: Bool = true {
        didSet { LockScreenWindowController.shared.settingsChanged() }
    }
    @AppStorage("lockScreenWidgetStyle") public var lockScreenWidgetStyle: LockWidgetStyle = .inline
    @AppStorage("lockScreenWidgetLook") public var lockScreenWidgetLook: LockWidgetLook = .dark
    @AppStorage("lockScreenWidgetMaterial") public var lockScreenWidgetMaterial: LockSurfaceMaterial = .regular
    /// Lock screen media HUD material.
    @AppStorage("lockScreenMediaMaterial") public var lockScreenMediaMaterial: LockSurfaceMaterial = .dark

    @AppStorage("islandStyle") public var islandStyle: IslandStyle = .notchAttached
    /// Off by default, like the reference; existing installs are switched off
    /// once by `migrateSettings()`.
    @AppStorage("expandOnHover") public var expandOnHover: Bool = false
    @AppStorage("hapticFeedback") public var hapticFeedback: Bool = true
    @AppStorage("soundEffects") public var soundEffects: Bool = true
    /// Grace period before the island closes itself once the pointer leaves.
    /// Long enough to overshoot an edge and come back, or to reach a control
    /// that sits just outside the island; below roughly a third of a second
    /// the shelf is gone before a deliberate move can land.
    nonisolated public static let defaultAutoHideDelay: Double = 0.4
    @AppStorage("autoHideDelay") public var autoHideDelay: Double = AppState.defaultAutoHideDelay
    /// How long the pointer rests on the notch before hover opens it.
    @AppStorage("hoverOpenDelay") public var hoverOpenDelay: Double = 0.25
    @AppStorage("islandMotionStyle") public var islandMotionStyle: IslandMotionStyle = .dynamicIsland

    // MARK: Shelf (Settings › Shelf)
    /// The Shelf master switch. Off, the island never opens into the shelf;
    /// HUDs, banners and live activities still show in the notch.
    @AppStorage("shelfEnabled") public var shelfEnabled: Bool = true {
        didSet {
            if !shelfEnabled {
                cancelHomeCustomization()
                isRearrangingWidgets = false
                isIslandPinned = false
                setIslandExpanded(false)
            }
            onIslandFrameChange?(isIslandExpanded)
        }
    }
    /// Regular or Enlarged: the open shelf is scaled as a whole.
    @AppStorage("shelfSize") public var shelfSize: ShelfSize = .regular {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("shelfNavigationStyle") public var shelfNavigationStyle: ShelfNavigationStyle = .floatingBar {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// A round Calendar button beside the floating bar (the Calendar page's
    /// way in, now that the bar only holds Home, Tray and Widgets).
    @AppStorage("showCalendarButton") public var showCalendarButton: Bool = true {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// Settings › Shelf › Favorites: how the round buttons under the shelf
    /// are drawn. The size key is `FloatingButtonSize.key`, which
    /// `DroppyShelfMetrics.floatingButton` reads back.
    @AppStorage(FloatingButtonSize.key) public var floatingButtonSize: FloatingButtonSize = .regular {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("floatingButtonStyle") public var floatingButtonStyle: FloatingButtonStyle = .glass
    /// Icon and text colour on a colored floating button.
    @AppStorage("floatingButtonLightIcons") public var floatingButtonLightIcons: Bool = true
    /// Up to four favorites beside the floating bar; see `ShelfFavorite`.
    @AppStorage("shelfFavorites") public var shelfFavoritesStorage: String = "" {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// A second concurrent activity gets its own round pill beside the notch.
    @AppStorage("multiLiveActivities") public var multiLiveActivities: Bool = true
    /// Off: the shelf stays open until a click elsewhere or Esc.
    @AppStorage("autoCollapse") public var autoCollapse: Bool = true
    @AppStorage("animationSpeed") public var animationSpeed: ShelfAnimationSpeed = .human
    /// Two-finger swipes: down on the notch opens the shelf (when scrolling
    /// there isn't set to change the volume), sideways switches pages.
    @AppStorage("shelfGestures") public var shelfGestures: Bool = true
    /// Settings › Shelf › Behavior › Swipe direction: Reversed flips which way
    /// a sideways swipe moves between pages and between the Tray's two stacks.
    @AppStorage("shelfSwipeReversed") public var shelfSwipeReversed: Bool = false
    /// Dropping files on the notch opens the Tray to show them.
    @AppStorage("openTrayAfterDrop") public var openTrayAfterDrop: Bool = true

    /// The Widgets page is in rearrange mode (drag icons to reorder).
    @Published public var isRearrangingWidgets: Bool = false {
        didSet {
            guard isRearrangingWidgets != oldValue else { return }
            onIslandFrameChange?(isIslandExpanded)
        }
    }

    @AppStorage("defaultShelfPage") public var defaultShelfPage: DefaultShelfPage = .home
    @AppStorage("clipboardHistoryLimit") public var clipboardHistoryLimit: Int = 50 {
        didSet { trimClipboardHistory(undoLimit: oldValue) }
    }

    // MARK: Clipboard (Settings › Clipboard)
    /// The Clipboard manager master switch. Off, nothing is recorded and the
    /// shortcut only points at Settings.
    @AppStorage("clipboardEnabled") public var clipboardEnabled: Bool = true {
        didSet { applyClipboardEnabled() }
    }
    /// Where "Open Clipboard" appears: the menu bar item's menu and the
    /// notch's right-click menu.
    @AppStorage("clipboardInMenuBar") public var clipboardInMenuBar: Bool = true
    @AppStorage("clipboardInShelfMenu") public var clipboardInShelfMenu: Bool = true
    @AppStorage("clipboardLayout") public var clipboardLayout: ClipboardLayout = .alpha {
        didSet { if clipboardLayout != oldValue, isClipboardVisible { isClipboardVisible = false } }
    }
    /// The type-filter rail (All, Favorites, Text, Images…).
    @AppStorage("clipboardTypeFilters") public var clipboardTypeFilters: Bool = true
    /// Unstarred, unfiled clips are dropped when Tama quits.
    @AppStorage("clipboardClearOnQuit") public var clipboardClearOnQuit: Bool = false
    /// A copy repeating a clip already in history is ignored outright
    /// (off: the existing clip moves back to the front).
    @AppStorage("clipboardRejectDuplicates") public var clipboardRejectDuplicates: Bool = false
    /// Clipboard actions: tags on clips, a "Copy + Favorite" action, and
    /// the search field focused whenever the clipboard opens.
    @AppStorage("clipboardTagsEnabled") public var clipboardTagsEnabled: Bool = true
    /// Settings › Clipboard › Favorites bar: starred clips get a strip of
    /// chips above the cards, one click away wherever the search is.
    @AppStorage("clipboardFavoritesBar") public var clipboardFavoritesBar: Bool = true
    @AppStorage("clipboardCopyFavorite") public var clipboardCopyFavorite: Bool = false
    @AppStorage("clipboardAutoFocusSearch") public var clipboardAutoFocusSearch: Bool = false
    /// Paste into the app underneath (⌘V is posted); off, a pick is only copied.
    @AppStorage("clipboardPasteIntoApp") public var clipboardPasteIntoApp: Bool = true
    /// The tags clips can carry, in the order they were made.
    @Published public var clipboardTags: [ClipTag] = [] {
        didSet { persistClipboardTags() }
    }
    @AppStorage("showInMenuBar") public var showInMenuBar: Bool = true
    @AppStorage("showInDock") public var showInDock: Bool = false
    @AppStorage("accentColor") public var accentColor: DroppyAccentColor = .electricBlue
    @AppStorage("borderGlowIntensity") public var borderGlowIntensity: Double = 0.8
    @AppStorage("notchEarFilletRadius") public var notchEarFilletRadius: Double = 12.0
    @AppStorage("displayTargetMode") public var displayTargetMode: DisplayTargetMode = .main
    /// Shake a file drag to summon the Basket.
    @AppStorage("jiggleToOpenBasket") public var jiggleToOpenBasket: Bool = true
    /// A fresh screenshot leaves a thumbnail in the corner for a few seconds.
    /// Settings › Shelf › Tray & screenshots › Preview placement.
    @AppStorage("capturePreviewPlacement") public var capturePreviewPlacement: CapturePreviewPlacement = .bottomRight
    @AppStorage("showCapturePreview") public var showCapturePreview: Bool = true
    /// Show the volume HUD in the notch when scrolling over it.
    @AppStorage("showVolumeHUD") public var showVolumeHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// Two-finger scroll on the resting notch changes the volume.
    @AppStorage("scrollToChangeVolume") public var scrollToChangeVolume: Bool = true
    /// The volume keys are handled by Tama so only the notch HUD shows, not
    /// the macOS one. Needs Accessibility; without it both appear.
    @AppStorage("replaceSystemVolumeHUD") public var replaceSystemVolumeHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// How the volume HUD looks and behaves (Settings › Sound).
    @AppStorage("hudDuration") public var hudDuration: Double = 1.5
    @AppStorage("hudMeterStyle") public var hudMeterStyle: HUDMeterStyle = .accent
    @AppStorage("hudShowPercentage") public var hudShowPercentage: Bool = true
    @AppStorage("hudHideLabel") public var hudHideLabel: Bool = false
    @AppStorage("hudAnimation") public var hudAnimation: HUDAnimation = .fast
    @AppStorage("hudLeading") public var hudLeading: HUDLeading = .symbol
    /// The brightness HUD's own look (Settings › Display).
    @AppStorage("brightnessHUDDuration") public var brightnessHUDDuration: Double = 1.5
    @AppStorage("brightnessHUDMeterStyle") public var brightnessHUDMeterStyle: HUDMeterStyle = .accent
    @AppStorage("brightnessHUDShowPercentage") public var brightnessHUDShowPercentage: Bool = true
    @AppStorage("brightnessHUDHideLabel") public var brightnessHUDHideLabel: Bool = false
    @AppStorage("brightnessHUDAnimation") public var brightnessHUDAnimation: HUDAnimation = .fast
    /// The brightness keys are handled by Tama so the macOS HUD stays away.
    @AppStorage("replaceSystemBrightnessHUD") public var replaceSystemBrightnessHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// ⌥-scroll on the resting notch changes the built-in display's brightness.
    @AppStorage("scrollToChangeBrightness") public var scrollToChangeBrightness: Bool = true
    /// Brightness keys show a level readout in the notch; ⌥-scroll changes it.
    @AppStorage("showBrightnessHUD") public var showBrightnessHUD: Bool = true {
        didSet {
            MediaKeyMonitor.shared.syncInterception()
            BrightnessService.shared.syncAutoWatch()
        }
    }
    /// A connected VPN sits in the notch wings with its session time.
    @AppStorage("showVPNStatus") public var showVPNStatus: Bool = true {
        didSet { VPNService.shared.apply(enabled: showVPNStatus) }
    }
    /// Take a file off the Tray once it's been dragged out into another app.
    @AppStorage("removeOnDragOut") public var removeOnDragOut: Bool = false
    /// Drags out of the Tray and Basket only ever copy: Finder can't move the
    /// user's original out of its folder. Off allows a move (Finder's default
    /// on the same volume), and a moved file then leaves the Tray.
    @AppStorage("protectOriginals") public var protectOriginals: Bool = true
    /// Text read by OCR (the OCR droplet, a Tray preview) goes straight to the clipboard.
    @AppStorage("autoCopyOCRText") public var autoCopyOCRText: Bool = false

    // MARK: Tools (Settings › Droplets › Element Capture, Window Snap)
    /// Capture destinations. The console's checkboxes use the same keys.
    @AppStorage("snipperAutoCopy") public var captureToClipboard: Bool = true
    @AppStorage("snipperAutoTray") public var captureToTray: Bool = true
    @AppStorage("snipperSaveToFolder") public var captureToFolder: Bool = false
    /// Empty: the Desktop.
    @AppStorage("snipperFolderPath") public var captureFolderPath: String = ""
    /// "Open editor instantly": the editor takes over delivery.
    @AppStorage("snipperEditAfterCapture") public var captureOpensEditor: Bool = true
    /// Screenshots are saved at point resolution and run through the image compressor.
    @AppStorage("snipperAutoCompress") public var captureAutoCompress: Bool = false
    /// Tama's own windows are left out of its captures.
    @AppStorage("captureExcludeDroppy") public var captureExcludesDroppy: Bool = true
    @AppStorage("captureEditorDefaultZoom") public var captureEditorDefaultZoom: CaptureEditorZoomDefault = .fit
    /// A swatch name from `RGBAColor.swatches`.
    @AppStorage("captureAnnotationColor") public var captureAnnotationColor: String = "red"
    @AppStorage("captureEditorFont") public var captureEditorFont: String = CaptureFont.system.rawValue
    /// Corner radius (pt) the Beautify backdrop starts with.
    @AppStorage("screenshotRadius") public var screenshotRadius: Double = 12
    /// Flash the target zone when a snap comes from a shortcut.
    @AppStorage("windowSnapShowPreview") public var windowSnapShowPreview: Bool = true

    // MARK: Voice Transcribe (Settings › Droplets › Voice Transcribe)
    /// Stream text while recording; off transcribes the whole file after Stop, with progress.
    @AppStorage("voiceLiveTranscription") public var voiceLiveTranscription: Bool = false
    @AppStorage("voiceEngine") public var voiceEngine: VoiceEngine = .auto
    /// Copy the text as soon as it's ready instead of showing the result card.
    @AppStorage("voiceSkipResult") public var voiceSkipResult: Bool = false
    /// A red mic (with the time) in the menu bar while recording; click it to stop.
    @AppStorage("voiceMenuBarIcon") public var voiceMenuBarIcon: Bool = true
    @AppStorage("voiceRetention") public var voiceRetention: VoiceRetention = .keep
    /// Quick Record opens a floating recorder instead of expanding the island.
    @AppStorage("voiceFloatingRecorder") public var voiceFloatingRecorder: Bool = false

    // MARK: Thunderstorm launcher (Settings › Droplets › Thunderstorm)
    /// Google / DuckDuckGo / Wikipedia rows under the results.
    @AppStorage("thunderstormWebSearch") public var thunderstormWebSearch: Bool = true
    /// Ask DuckDuckGo's Instant Answer API as you type (sends the query to DuckDuckGo).
    @AppStorage("thunderstormInlineAnswers") public var thunderstormInlineAnswers: Bool = false
    /// Lock, Sleep, Restart, Eject… rows.
    @AppStorage("thunderstormSystemCommands") public var thunderstormSystemCommands: Bool = true

    // MARK: Menu Bar Manager (Settings › Droplets › Menu Bar Manager)
    @AppStorage("menuBarAlwaysHidden") public var menuBarAlwaysHidden: Bool = false {
        didSet { MenuBarManagerService.shared.sync() }
    }
    @AppStorage("menuBarAutoRehide") public var menuBarAutoRehide: Bool = true
    /// Seconds before revealed items fold away again.
    @AppStorage("menuBarRehideDelay") public var menuBarRehideDelay: Double = 10
    @AppStorage("menuBarRehideOnAppSwitch") public var menuBarRehideOnAppSwitch: Bool = false
    @AppStorage("menuBarToggleIcon") public var menuBarToggleIcon: MenuBarToggleIcon = .chevron {
        didSet { MenuBarManagerService.shared.sync() }
    }
    @AppStorage("menuBarIconTemplate") public var menuBarIconTemplate: Bool = true {
        didSet { MenuBarManagerService.shared.sync() }
    }
    /// Thin dividers mark the sections while they're shown.
    @AppStorage("menuBarShowDividers") public var menuBarShowDividers: Bool = true {
        didSet { MenuBarManagerService.shared.sync() }
    }

    // MARK: LocalSend (Settings › Droplets › LocalSend)
    /// The name other devices see; empty = this Mac's name.
    @AppStorage("localSendDeviceName") public var localSendDeviceName: String = "" {
        didSet { LocalSendService.shared.settingsChanged() }
    }
    @AppStorage("localSendReceiveMode") public var localSendReceiveMode: LocalSendReceiveMode = .anyone
    /// Announce this Mac and answer other devices' scans.
    @AppStorage("localSendVisible") public var localSendVisible: Bool = true {
        didSet { LocalSendService.shared.settingsChanged() }
    }
    /// Encrypted (HTTPS): serve with the self-signed certificate; off = plain HTTP.
    @AppStorage("localSendEncrypted") public var localSendEncrypted: Bool = true {
        didSet { LocalSendService.shared.restart() }
    }
    /// A PIN senders must type before a transfer is offered; empty = none.
    @AppStorage("localSendPIN") public var localSendPIN: String = ""
    /// Where received files go; empty = Downloads.
    @AppStorage("localSendSaveFolder") public var localSendSaveFolder: String = ""
    @AppStorage("localSendAddToShelf") public var localSendAddToShelf: Bool = true
    /// Favorites' transfers are saved without asking.
    @AppStorage("localSendQuickSaveFavorites") public var localSendQuickSaveFavorites: Bool = false

    // MARK: Diagnostics, tooltips, What's New (Settings › About / Accessibility)
    /// Write detailed logs for troubleshooting (DroppyLog).
    @AppStorage("diagnosticLogging") public var diagnosticLogging: Bool = false
    /// Show the hover help (tooltips) on Tama's own buttons.
    @AppStorage("showTooltips") public var showTooltips: Bool = true {
        didSet { DroppyDiagnostics.applyTooltipPreference(showTooltips) }
    }
    /// Droplets left out of the Settings sidebar's "Enabled Droplets" list (comma-separated ids).
    @AppStorage("sidebarHiddenDroplets") public var sidebarHiddenDroplets: String = ""
    /// Show What's New after an update.
    @AppStorage("showWhatsNew") public var showWhatsNew: Bool = true

    // MARK: Files (Settings › Shelf, Basket and General)
    /// Auto-cleanup: unpinned Shelf files leave after this long.
    @AppStorage("trayExpiry") public var trayExpiry: TrayExpiry = .never
    /// Two Stacks: the Tray holds two separate stacks of files.
    @AppStorage("trayTwoStacks") public var trayTwoStacks: Bool = false {
        didSet { if !trayTwoStacks { activeTrayStack = 0 } }
    }
    // Basket.
    /// Instant appear: any file drag shows the Basket after a short delay, no shake needed.
    @AppStorage("basketInstantAppear") public var basketInstantAppear: Bool = false
    @AppStorage("basketInstantDelay") public var basketInstantDelay: Double = 0.35
    /// Auto-hide: the Basket goes once it's been idle (no drag, pointer away) this long.
    @AppStorage("basketAutoHide") public var basketAutoHide: Bool = false
    @AppStorage("basketAutoHideDelay") public var basketAutoHideDelay: Double = 3
    /// 0 (a big, deliberate shake) … 1 (a flick is enough).
    @AppStorage("basketShakeSensitivity") public var basketShakeSensitivity: Double = 0.5
    /// Drag shortcut: modifiers (NSEvent.ModifierFlags raw value) that, held
    /// while dragging files, bring the Basket. 0 = none.
    @AppStorage("basketDragModifiers") public var basketDragModifiers: Int = 0
    @AppStorage("basketMode") public var basketMode: BasketMode = .single {
        didSet { if basketMode == .single { mergeBasketsIntoFirst() } }
    }
    /// A second bucket in each Basket for rarely used items.
    @AppStorage("basketSecondBucket") public var basketSecondBucket: Bool = false
    @AppStorage("basketLayout") public var basketLayout: BasketLayout = .grid
    // Quick Actions.
    @AppStorage("quickActionsEnabled") public var quickActionsEnabled: Bool = true {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// The tiles after Keep, comma-separated `QuickAction` raw values.
    @AppStorage("quickActionTiles") public var quickActionTilesStorage: String = QuickAction.storage(for: QuickAction.defaultTiles)
    @AppStorage("quickActionMailApp") public var quickActionMailApp: QuickActionMailApp = .systemDefault
    /// Quickshare asks before anything leaves the Mac.
    @AppStorage("quickshareConfirm") public var quickshareConfirm: Bool = true
    // Conversion.
    /// Converted files' folder; "" is Downloads.
    @AppStorage("convertDestination") public var convertDestination: String = ""
    @AppStorage("afterConvertAction") public var afterConvertAction: AfterConvertAction = .addToShelf
    // Automation.
    /// Smart Export: processed files are saved into per-type folders.
    @AppStorage("smartExportEnabled") public var smartExportEnabled: Bool = false
    /// Base folder for Smart Export; "" is Downloads › Tama.
    @AppStorage("smartExportFolder") public var smartExportFolder: String = ""
    @AppStorage("smartExportCompressed") public var smartExportCompressed: Bool = true
    @AppStorage("smartExportConverted") public var smartExportConverted: Bool = true
    @AppStorage("smartExportCutouts") public var smartExportCutouts: Bool = true
    /// Tracked folders: new files in these folders are taken in, each folder
    /// doing what its own action says (`TrackedFolderAction`).
    @AppStorage("trackedFoldersEnabled") public var trackedFoldersEnabled: Bool = false {
        didSet { TrackedFolderService.shared.sync() }
    }
    /// Newline-separated "action:path" tokens; see `TrackedFolder`.
    @AppStorage("trackedFolders") public var trackedFoldersStorage: String = "" {
        didSet { TrackedFolderService.shared.sync() }
    }
    /// The level "Add and compress" uses, since there is nobody to ask.
    @AppStorage("trackedFoldersCompressionLevel") public var trackedFoldersCompressionLevel: CompressionLevel = .medium
    // Background removal.
    @AppStorage("cutoutBackground") public var cutoutBackground: CutoutBackground = .transparent
    /// Space around the subject, as a fraction of its size (0 keeps the whole frame).
    @AppStorage("cutoutPadding") public var cutoutPadding: Double = 0
    /// Corner radius of the backdrop, as a fraction of its shorter side.
    @AppStorage("cutoutCornerRadius") public var cutoutCornerRadius: Double = 0
    @AppStorage("cutoutShadow") public var cutoutShadow: Bool = false

    // MARK: Theming
    /// Surface of the notch-attached island and shelf on screens with a notch.
    @AppStorage("notchedSurfaceStyle") public var notchedSurfaceStyle: IslandSurfaceStyle = .dynamicGlass
    /// Surface of the floating island and shelf on screens without one.
    @AppStorage("notchlessSurfaceStyle") public var notchlessSurfaceStyle: IslandSurfaceStyle = .dynamicGlass
    /// A hairline around the surface, so black stays visible on dark wallpapers.
    @AppStorage("subtleOutline") public var subtleOutline: Bool = false
    /// The outline is drawn on the resting island too, not just when it opens.
    @AppStorage("outlineInRestingState") public var outlineInRestingState: Bool = false
    /// Settings › Theming › Settings window: paint this window opaque instead
    /// of translucent glass.
    @AppStorage("solidSettingsBackground") public var solidSettingsBackground: Bool = false
    /// Tint washed over Settings and the glass surfaces: "" (default), a
    /// `TapePalette` id, or "#RRGGBB".
    @AppStorage("windowTint") public var windowTint: String = ""
    /// Meter colours for `HUDMeterStyle.custom`, per HUD: a `TapePalette` id or "#RRGGBB".
    @AppStorage("hudMeterCustomColor") public var hudMeterCustomColor: String = ""
    @AppStorage("brightnessHUDMeterCustomColor") public var brightnessHUDMeterCustomColor: String = ""

    /// Theming › Window tint, resolved.
    public var windowTintColor: Color? { TapePalette.color(for: windowTint) }
    /// Extra points between the top of the screen and the floating island pill.
    @AppStorage("mediaHUDVerticalOffset") public var mediaHUDVerticalOffset: Double = 0 {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }

    // MARK: Accessibility
    /// Adds "Hide Notch/Island" to the island's right-click menu.
    @AppStorage("rightClickToHide") public var rightClickToHide: Bool = false
    /// A right-click where the hidden island sits brings it back.
    @AppStorage("rightClickToReveal") public var rightClickToReveal: Bool = true
    /// The resting island stays hidden until the modifiers below are held.
    @AppStorage("holdToReveal") public var holdToReveal: Bool = false {
        didSet { IslandVisibilityService.shared.sync() }
    }
    @AppStorage("holdToRevealModifier") public var holdToRevealModifier: ShortcutModifier = .controlOption
    /// Tama's panels are left out of screenshots and screen sharing.
    @AppStorage("hideFromScreenshots") public var hideFromScreenshots: Bool = false {
        didSet { CaptureExclusion.apply() }
    }

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
        (isIslandHidden || holdToReveal) && !isHoldRevealing
    }
    /// Most files the Tray holds; the oldest go first.
    @AppStorage("trayCapacity") public var trayCapacity: Int = 50 {
        didSet { trimTray(reason: "Tray capacity lowered", undoCapacity: oldValue) }
    }
    /// Live activities in the resting notch.
    @AppStorage("showMeetingCountdown") public var showMeetingCountdown: Bool = true {
        didSet { MeetingService.shared.tick() }
    }
    @AppStorage("showBatteryAlerts") public var showBatteryAlerts: Bool = true {
        didSet { if !showBatteryAlerts { LiveActivityCenter.shared.end("battery") } }
    }
    /// Settings › HUDs › Media Controls › Always use built-in speakers: a
    /// device that just connected doesn't get to take the sound with it.
    @AppStorage("alwaysUseBuiltInSpeakers") public var alwaysUseBuiltInSpeakers: Bool = false
    @AppStorage("showDeviceAlerts") public var showDeviceAlerts: Bool = true {
        didSet { if !showDeviceAlerts { LiveActivityCenter.shared.end("audioDevice") } }
    }
    /// Off by default: watching ~/Downloads makes macOS ask for folder access.
    @AppStorage("showDownloadActivity") public var showDownloadActivity: Bool = false {
        didSet { DownloadWatcher.shared.apply(enabled: showDownloadActivity) }
    }

    // MARK: HUDs (Settings › HUDs)
    // Display style: which screens carry the island at all, and how it rests there.
    @AppStorage("hideOnExternalDisplays") public var hideOnExternalDisplays: Bool = false {
        didSet { surfaceRulesChanged() }
    }
    /// Off: an external display's resting island fades out while nothing is live.
    @AppStorage("showWhenIdle") public var showWhenIdle: Bool = true {
        didSet { objectWillChange.send() }
    }
    /// On: only the external displays not listed in `hiddenDisplays` show the island.
    @AppStorage("perDisplayVisibility") public var perDisplayVisibility: Bool = false {
        didSet { surfaceRulesChanged() }
    }
    /// Newline-separated `NSScreen.droppyDisplayKey`s; see `hiddenDisplayKeys`.
    @AppStorage("hiddenDisplays") public var hiddenDisplaysStorage: String = "" {
        didSet { surfaceRulesChanged() }
    }
    /// A black bar across the top of a notched display, so the notch disappears into it.
    @AppStorage("hidePhysicalNotch") public var hidePhysicalNotch: Bool = false {
        didSet { NotchCoverController.shared.sync() }
    }
    // Size: points off the standard size (see DroppyShelfMetrics' ranges).
    @AppStorage("islandHeightOffset") public var islandHeightOffset: Double = 0 {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("islandWidthOffset") public var islandWidthOffset: Double = 0 {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("notchHUDHeightOffset") public var notchHUDHeightOffset: Double = 0 {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("notchHUDWidthOffset") public var notchHUDWidthOffset: Double = 0 {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    // Behavior.
    @AppStorage("collapsedHUDScope") public var collapsedHUDScope: HUDScope = .underPointer
    @AppStorage("fullscreenBehavior") public var fullscreenBehavior: FullscreenBehavior = .show {
        didSet { ScreenStateService.shared.sync() }
    }
    @AppStorage("hideInMissionControl") public var hideInMissionControl: Bool = true {
        didSet { ScreenStateService.shared.sync() }
    }
    /// How long a finished, transient HUD (charger, device, Caps Lock…) stays.
    @AppStorage("finishedHUDLinger") public var finishedHUDLinger: Double = 3
    /// A level HUD under the pointer stays until the pointer leaves.
    @AppStorage("keepHUDWhileHovered") public var keepHUDWhileHovered: Bool = true
    @AppStorage("compactHUDPriority") public var compactHUDPriority: CompactHUDPriority = .activitiesFirst
    // System HUDs.
    @AppStorage("showKeyboardBrightnessHUD") public var showKeyboardBrightnessHUD: Bool = true {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    @AppStorage("showFileTrayHUD") public var showFileTrayHUD: Bool = true
    @AppStorage("showCapsLockHUD") public var showCapsLockHUD: Bool = true {
        didSet { CapsLockService.shared.sync() }
    }
    @AppStorage("showRecordingHUD") public var showRecordingHUD: Bool = true {
        didSet { RecordingIndicatorService.shared.sync() }
    }
    @AppStorage("showFocusHUD") public var showFocusHUD: Bool = true {
        didSet { FocusModeService.shared.sync() }
    }
    @AppStorage("showOfflineHUD") public var showOfflineHUD: Bool = true {
        didSet { ConnectivityService.shared.sync() }
    }
    // Media keys.
    /// The feedback pop when the volume keys change the level (⇧ flips it).
    @AppStorage("volumeKeySound") public var volumeKeySound: Bool = false
    @AppStorage("desktopVolumeSlider") public var desktopVolumeSlider: Bool = false {
        didSet { DesktopSliderController.shared.sync() }
    }
    @AppStorage("desktopBrightnessSlider") public var desktopBrightnessSlider: Bool = false {
        didSet { DesktopSliderController.shared.sync() }
    }
    @AppStorage("mediaKeyTarget") public var mediaKeyTarget: MediaKeyTarget = .underPointer
    /// External displays' brightness goes through BetterDisplay's HTTP API when it's running.
    @AppStorage("useBetterDisplay") public var useBetterDisplay: Bool = true {
        didSet { BetterDisplayService.shared.refresh() }
    }
    /// The brightness HUD also shows when the level changes on its own (ambient light, Control Center).
    /// Off by default: with auto-brightness on, the panel drifts all day and the HUD kept popping up.
    @AppStorage("automaticBrightnessHUD") public var automaticBrightnessHUD: Bool = false {
        didSet { BrightnessService.shared.syncAutoWatch() }
    }
    /// Tama takes the keyboard backlight keys and steps the backlight itself.
    @AppStorage("keyboardBrightnessKeys") public var keyboardBrightnessKeys: Bool = false {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }
    /// Who answers play/pause, next and previous (Media keys › Playback keys).
    @AppStorage("playbackKeysMode") public var playbackKeysMode: PlaybackKeysMode = .system {
        didSet { MediaKeyMonitor.shared.syncInterception() }
    }

    // MARK: Media (Settings › HUDs › Media, Media Controls)
    /// Now Playing master switch: off, music stays out of the resting island.
    @AppStorage("nowPlayingEnabled") public var nowPlayingEnabled: Bool = true {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// Auto-hide preview: the resting wings fade out once music has been
    /// paused for `mediaAutoHideDelay` seconds.
    @AppStorage("mediaAutoHide") public var mediaAutoHide: Bool = true {
        didSet { syncMediaAutoHide() }
    }
    @AppStorage("mediaAutoHideDelay") public var mediaAutoHideDelay: Double = 5 {
        didSet { syncMediaAutoHide() }
    }
    @AppStorage("nowPlayingDisplay") public var nowPlayingDisplay: NowPlayingDisplay = .underPointer {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// Settings › HUDs › Media › Now Playing Size: Regular or Smaller. The
    /// key is `NowPlayingSize.key`, which `PlayerMetrics` reads back.
    @AppStorage(NowPlayingSize.key) public var nowPlayingSize: NowPlayingSize = .regular {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    /// The track title and artist are written in the notch wings.
    @AppStorage("notchTrackTitle") public var notchTrackTitle: Bool = true {
        didSet { onIslandFrameChange?(isIslandExpanded) }
    }
    @AppStorage("visualizerStyle") public var visualizerStyle: VisualizerStyle = .gradient
    /// The bars follow the sound actually playing (a system audio tap).
    @AppStorage("liveAudioVisualizer") public var liveAudioVisualizer: Bool = false {
        didSet { LiveAudioLevels.shared.sync() }
    }
    /// Clicking the album art opens it large instead of the player's app.
    @AppStorage("liveAlbumArtwork") public var liveAlbumArtwork: Bool = false
    /// The open player washes the shelf with the album art's colours.
    @AppStorage("playerArtworkTint") public var playerArtworkTint: Bool = true
    /// The player's right-hand time shows what's left (off: the length).
    @AppStorage("playerShowsRemaining") public var playerShowsRemaining: Bool = true
    @AppStorage("defaultMusicApp") public var defaultMusicApp: DefaultMusicApp = .appleMusic
    /// Two-finger sideways swipe on the media widget or the wings skips tracks.
    @AppStorage("trackSwipe") public var trackSwipe: Bool = true
    @AppStorage("trackSwipeReversed") public var trackSwipeReversed: Bool = false
    /// A click on the notch opens the media widget while music plays.
    @AppStorage("notchClickOpensMedia") public var notchClickOpensMedia: Bool = false
    /// Filter media sources: apps listed in `blockedMediaSources` are ignored.
    @AppStorage("filterMediaSources") public var filterMediaSources: Bool = false
    /// Newline-separated bundle IDs; see `blockedMediaSourceIDs`.
    @AppStorage("blockedMediaSources") public var blockedMediaSourcesStorage: String = ""
    /// Private (incognito) browser windows are never picked up.
    @AppStorage("hideIncognitoMedia") public var hideIncognitoMedia: Bool = false
    /// The lyrics card opens beside the player on its own when a song has lyrics.
    @AppStorage("autoExpandLyrics") public var autoExpandLyrics: Bool = false
    /// The floating lyrics window stays above other windows.
    @AppStorage("lyricsWindowPinned") public var lyricsWindowPinned: Bool = true
    /// Apple Music droplet: a Lossless / Hi-Res badge beside the title.
    @AppStorage("audioQualityBadge") public var audioQualityBadge: Bool = true
    // The buttons either side of the transport, per source (Media widget).
    @AppStorage("musicLeftButton") public var musicLeftButton: MediaWidgetButton = .shuffle
    @AppStorage("musicRightButton") public var musicRightButton: MediaWidgetButton = .repeat
    @AppStorage("spotifyLeftButton") public var spotifyLeftButton: MediaWidgetButton = .shuffle
    @AppStorage("spotifyRightButton") public var spotifyRightButton: MediaWidgetButton = .repeat
    @AppStorage("regularLeftButton") public var regularLeftButton: MediaWidgetButton = .none
    @AppStorage("regularRightButton") public var regularRightButton: MediaWidgetButton = .none
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

    // MARK: Weather (Settings › Droplets › Weather)
    @AppStorage("weatherStyle") public var weatherStyle: WeatherStyle = .liquidGlass
    @AppStorage("weatherLocationMode") public var weatherLocationMode: WeatherLocationMode = .automatic {
        didSet { WeatherService.shared.locationSettingsChanged() }
    }
    @AppStorage("weatherPlaceName") public var weatherPlaceName: String = ""
    @AppStorage("weatherPlaceLatitude") public var weatherPlaceLatitude: Double = 0
    @AppStorage("weatherPlaceLongitude") public var weatherPlaceLongitude: Double = 0
    /// Minutes between refreshes.
    @AppStorage("weatherRefreshMinutes") public var weatherRefreshMinutes: Int = 30 {
        didSet { WeatherService.shared.intervalChanged() }
    }
    @AppStorage("weatherShowsAQI") public var weatherShowsAQI: Bool = true
    @AppStorage("weatherShowsSun") public var weatherShowsSun: Bool = true

    public var onIslandFrameChange: ((Bool) -> Void)?
    
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
        
        switch displayTargetMode {
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
        if let page = defaultShelfPage.page { shelfPage = page }
        pomodoroSecondsRemaining = pomodoroWorkMinutes * 60
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
        guard !expanded || shelfEnabled else { return }
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
                    if let page = self.defaultShelfPage.page { self.shelfPage = page }
                }
            }
            shelfReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        onIslandFrameChange?(expanded)
        if hapticFeedback {
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
            if self.keepHUDWhileHovered, self.isIslandHovered, self.hud != nil {
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
