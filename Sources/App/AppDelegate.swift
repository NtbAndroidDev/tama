import SwiftUI
import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup Windows
        NotchWindowController.shared.setup()
        FloatingBasketController.shared.setup()
        LiveActivityWindowController.shared.setup()
        LockScreenWindowController.shared.start()
        ClipboardWindowController.shared.setup()

        // Sleep and screen-off: the pollers that only feed the notch stand
        // down while nothing can be seen, and everything is refreshed on wake.
        // Started before them, so each one starts in the right state.
        PowerStateService.shared.start()
        // Shake a file drag anywhere to summon the Basket.
        JiggleService.shared.start()
        // Follow app switches so Window Snap targets the app, not Tama.
        WindowSnapService.shared.start()
        // Finder › Services: Add to Shelf / Basket, Extract Text, Send to Scratchpad.
        ServicesProvider.install()
        // Settings › General › Automation › Tracked folders.
        TrackedFolderService.shared.sync()

        // Live activities for the resting notch.
        MeetingService.shared.start()
        // Tasks & Calendar: due alerts, the event progress ring, the next-event wing.
        TaskAlertService.shared.start()
        // Lid-Closed High Alert that didn't finish cleanly left system sleep off.
        SleepBlockerService.shared.checkLeftoverLidMode()
        BatteryService.shared.start()
        VPNService.shared.start()
        // Volume / brightness keys → notch HUD.
        MediaKeyMonitor.shared.start()
        // Settings › HUDs: fullscreen / Mission Control, the notch cover, the
        // system HUDs (Caps Lock, recording, Focus, offline), desktop sliders,
        // automatic brightness and BetterDisplay.
        ScreenStateService.shared.start()
        NotchCoverController.shared.start()
        CapsLockService.shared.sync()
        RecordingIndicatorService.shared.sync()
        FocusModeService.shared.sync()
        ConnectivityService.shared.start()
        DesktopSliderController.shared.sync()
        BrightnessService.shared.syncAutoWatch()
        BetterDisplayService.shared.refresh()
        DownloadWatcher.shared.apply(enabled: AppState.shared.showDownloadActivity)
        // Keystroke sounds and per-app volumes follow their Droplets' settings.
        MecheyService.shared.start()
        AppAudioService.shared.start()
        // Smooth mouse scrolling and meeting controls follow their Droplets.
        LiquidMouseService.shared.start()
        MeetingControlService.shared.start()
        // Notification HUD and Agents follow their Droplets' switches.
        NotificationHUDService.shared.sync()
        AgentActivityService.shared.sync()
        // Menu Bar Manager's status items follow its Droplet.
        MenuBarManagerService.shared.start()
        // LocalSend's receiver and discovery follow its Droplet.
        LocalSendService.shared.start()
        // Settings › Accessibility › Show tooltips.
        DroppyDiagnostics.applyTooltipPreference(AppState.shared.showTooltips)
        DroppyLog.info("App", "Launched \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
        
        // Menu bar item and Dock icon follow Settings, live.
        applyPresenceSettings()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in (AppState.shared.showInMenuBar, AppState.shared.showInDock) }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPresenceSettings() }
            .store(in: &cancellables)
        
        // Setup Global Keyboard Shortcuts (⌘+Shift+Space, ⌘+Shift+B, ⌘+Shift+L, Esc)
        GlobalShortcutService.shared.startMonitoring()
        
        // Settings › Accessibility: right-click / hold-to-reveal monitors.
        IslandVisibilityService.shared.sync()
        // First run: the welcome tour (replayable from Settings › About).
        OnboardingWindowController.shared.showIfNeeded()
        // After an update: What's New (Settings › About can show it again).
        WhatsNewController.shared.showIfUpdated()
        // After a crash: the report macOS wrote, to copy (never to send).
        CrashReportService.shared.checkForRecentCrash()

        // Setup Basket visibility listener
        AppState.shared.$isBasketVisible
            .receive(on: RunLoop.main)
            .sink { visible in
                FloatingBasketController.shared.setVisible(visible)
            }
            .store(in: &cancellables)
    }
    
    /// tama:// links (Alfred, scripts); see URLSchemeHandler.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLSchemeHandler.handle(url) }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Settings › Clipboard › Clear history on quit, before the last save.
        AppState.shared.clearClipboardOnQuitIfNeeded()
        AppState.shared.flushPersistence()
        // Lid-Closed High Alert turned system sleep off; put it back (this asks
        // for the administrator password once more).
        if SleepBlockerService.shared.isAwakeActive, SleepBlockerService.shared.activeMode == .lidClosed {
            SleepBlockerService.shared.restoreSystemSleep(synchronously: true)
        }
        AmbientSoundService.shared.stop()
        MecheyService.shared.shutdown()
        LiquidMouseService.shared.shutdown()
        AppAudioService.shared.shutdown()
        MediaRemoteAdapterProcess.shared.stop()
        // TermiNotch's shells get a hang-up, and remember their folder.
        TermiNotchSessions.shared.terminateAll()
        NotchfaceCamera.shared.stop()
    }

    private func applyPresenceSettings() {
        let state = AppState.shared
        if state.showInMenuBar, statusItem == nil {
            setupStatusItem()
        } else if !state.showInMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        let policy: NSApplication.ActivationPolicy = state.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Clicking the Dock icon, or relaunching, opens Settings. `flag` can't be
    /// trusted here: the island panels are always on screen, so it stays true
    /// even when Settings is the only window the user could mean.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.showWindow()
        return true
    }

    /// Tama's silhouette for the menu bar: the orb, with its eyes knocked out
    /// of the fill. Drawn rather than taken from SF Symbols, so the menu bar
    /// carries the same face as the app icon. Template, so macOS tints it for
    /// light, dark and a highlighted menu.
    private static func menuBarGlyph() -> NSImage {
        let pt: CGFloat = 18
        let image = NSImage(size: NSSize(width: pt, height: pt), flipped: false) { rect in
            let orb = rect.insetBy(dx: pt * 0.1, dy: pt * 0.1)
            let path = NSBezierPath(ovalIn: orb)
            let eyeW = orb.width * 0.17, eyeH = orb.height * 0.25
            for dx in [-0.215, 0.215] as [CGFloat] {
                path.appendOval(in: NSRect(x: orb.midX + orb.width * dx - eyeW / 2,
                                           y: orb.midY - eyeH / 2 + orb.height * 0.05,
                                           width: eyeW, height: eyeH))
            }
            // Even-odd, so the eyes are holes and the tint shows through them.
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarGlyph()
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Shelf", action: #selector(toggleIsland), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Keep Shelf Open", action: #selector(togglePinNotch), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Toggle Live Activity HUD", action: #selector(toggleLiveActivity), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Now Playing", action: #selector(openMedia), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Tray", action: #selector(openShelf), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Widgets", action: #selector(openDroplets), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Tasks & Calendar", action: #selector(openCalendar), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "Open Clipboard", action: #selector(openClipboard), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Snip to Tray", action: #selector(triggerQuickSnip), keyEquivalent: "S"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Toggle Floating Basket", action: #selector(toggleBasket), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Notch/Island", action: #selector(revealIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Tama Guide", action: #selector(openUserGuide), keyEquivalent: "?"))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Tama", action: #selector(quitApp), keyEquivalent: "q"))
        
        // Target ourselves: with no key window the responder chain may not reach
        // the delegate, and validateMenuItem is what keeps the checkmarks right.
        for entry in menu.items where entry.action != nil { entry.target = self }
        item.menu = menu
        self.statusItem = item
    }
    
    @objc private func toggleIsland() {
        AppState.shared.toggleIsland()
    }
    
    @objc private func toggleLiveActivity() {
        AppState.shared.isLiveActivityPresented.toggle()
    }
    
    @objc private func togglePinNotch() {
        let state = AppState.shared
        state.isIslandPinned.toggle()
        // Pinning a closed shelf would do nothing visible; open it so it stays open.
        if state.isIslandPinned, !state.isIslandExpanded { state.setIslandExpanded(true) }
        DroppyAudio.playTick()
    }
    
    @objc private func openShelf() {
        openPage(.tray)
    }
    
    @objc private func openMedia() {
        openPage(.home)
    }
    
    /// Opens a shelf page and gives it the keyboard, so ⌘1–⌘4 and Esc work
    /// straight away.
    private func openPage(_ page: ShelfPage) {
        AppState.shared.open(page)
        NotchWindowController.shared.focusPanel()
    }

    @objc private func openClipboard() {
        AppState.shared.showClipboard()
    }
    
    @objc private func openDroplets() {
        openPage(.widgets)
    }

    @objc private func openCalendar() {
        openPage(.calendar)
    }
    
    @objc private func triggerQuickSnip() {
        TrayActions.snipToTray()
    }
    
    @objc private func toggleBasket() {
        AppState.shared.isBasketVisible.toggle()
    }
    
    @objc private func revealIsland() {
        IslandVisibilityService.shared.reveal()
    }

    @objc private func openUserGuide() {
        UserGuideWindowController.shared.show()
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.showWindow()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuItemValidation {
    /// Menu items reflect the live state each time the menu opens.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let state = AppState.shared
        switch menuItem.action {
        case #selector(toggleIsland):
            menuItem.title = state.isIslandExpanded ? "Close Shelf" : "Open Shelf"
        case #selector(togglePinNotch):
            menuItem.state = state.isIslandPinned ? .on : .off
        case #selector(toggleLiveActivity):
            menuItem.state = state.isLiveActivityPresented ? .on : .off
        case #selector(toggleBasket):
            menuItem.state = state.isBasketVisible ? .on : .off
        case #selector(openClipboard):
            // Settings › Clipboard › Clipboard locations › Menu bar.
            menuItem.isHidden = !(state.clipboardEnabled && state.clipboardInMenuBar)
        case #selector(revealIsland):
            // Only there while the island is hidden from its right-click menu.
            menuItem.isHidden = !state.isIslandHidden
        default:
            break
        }
        return true
    }
}
