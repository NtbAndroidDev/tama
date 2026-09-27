import AppKit
import Combine

/// Menu Bar Manager: folds menu bar icons away behind Tama's own status
/// items, with no Accessibility access, event taps or pointer monitoring.
///
/// It is the separator technique: a divider status item sits left of a
/// toggle (chevron) item. Everything the user ⌘-drags to the left of the
/// divider is pushed off the screen when the divider's length grows to
/// `collapsedLength`, and comes back when it shrinks. An optional second
/// divider further left makes an always-hidden section that only an
/// Option-click (or the menu) reveals. Positions are remembered by macOS
/// through each item's `autosaveName`.
@MainActor
public final class MenuBarManagerService: NSObject, ObservableObject {
    public static let shared = MenuBarManagerService()

    /// The hidden section is on screen.
    @Published public private(set) var isRevealed = false
    /// The always-hidden section is on screen too.
    @Published public private(set) var isAlwaysHiddenRevealed = false
    @Published public private(set) var isRunning = false
    /// A divider sits right of the toggle, so collapsing would hide the toggle
    /// itself. Nothing collapses until the layout is fixed or reset.
    @Published public private(set) var isMisordered = false

    private var toggleItem: NSStatusItem?
    private var hiddenDivider: NSStatusItem?
    private var alwaysDivider: NSStatusItem?
    private var rehideWork: DispatchWorkItem?
    private var appObserver: NSObjectProtocol?
    private var dropletSink: AnyCancellable?

    static let collapsedLength: CGFloat = 10_000
    static let dividerLength: CGFloat = 14
    static let toggleName = "TamaMenuBarToggle"
    static let hiddenName = "TamaMenuBarHidden"
    static let alwaysName = "TamaMenuBarAlwaysHidden"

    private override init() { super.init() }

    /// Follows the droplet's switch from now on.
    public func start() {
        dropletSink = AppState.shared.$droplets
            .map { $0.first { $0.id == "menuBar" }?.isEnabled ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.apply(enabled: enabled) }
    }

    private var isEnabled: Bool {
        AppState.shared.droplets.first { $0.id == "menuBar" }?.isEnabled ?? false
    }

    /// Settings changed: redraw and re-lay-out.
    public func sync() {
        apply(enabled: isEnabled)
    }

    private func apply(enabled: Bool) {
        guard enabled else { return teardown() }
        let state = AppState.shared
        // Created right to left: each new item lands left of the previous one.
        if toggleItem == nil {
            toggleItem = makeItem(Self.toggleName, length: NSStatusItem.variableLength)
            hiddenDivider = makeItem(Self.hiddenName, length: Self.dividerLength)
            // Start folded, once AppKit has placed the new items.
            DispatchQueue.main.async { [weak self] in self?.hide() }
        }
        if state.menuBarAlwaysHidden, alwaysDivider == nil {
            alwaysDivider = makeItem(Self.alwaysName, length: Self.dividerLength)
        } else if !state.menuBarAlwaysHidden, let item = alwaysDivider {
            NSStatusBar.system.removeStatusItem(item)
            alwaysDivider = nil
            isAlwaysHiddenRevealed = false
        }
        isRunning = true
        observeAppSwitches()
        layout()
    }

    private func teardown() {
        rehideWork?.cancel()
        for item in [toggleItem, hiddenDivider, alwaysDivider].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(item)
        }
        toggleItem = nil
        hiddenDivider = nil
        alwaysDivider = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        isRunning = false
        isRevealed = false
        isAlwaysHiddenRevealed = false
        isMisordered = false
    }

    private func makeItem(_ name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = name
        if let button = item.button {
            button.target = self
            button.action = #selector(itemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        return item
    }

    // MARK: Showing and hiding

    public func toggle() {
        isRevealed ? hide() : reveal()
    }

    /// Shows the hidden section; with `all`, the always-hidden one as well.
    public func reveal(all: Bool = false) {
        guard isRunning else { return }
        isRevealed = true
        isAlwaysHiddenRevealed = all && alwaysDivider != nil
        layout()
        scheduleRehide()
    }

    public func hide() {
        guard isRunning else { return }
        rehideWork?.cancel()
        isRevealed = false
        isAlwaysHiddenRevealed = false
        layout()
    }

    private func layout() {
        guard let toggleItem, let hiddenDivider else { return }
        let showsDividers = AppState.shared.menuBarShowDividers
        let open = showsDividers ? Self.dividerLength : 0
        // Only fold when every divider is still left of what it must not hide.
        isMisordered = !Self.isOrdered(left: hiddenDivider, right: toggleItem)
            || alwaysDivider.map { !Self.isOrdered(left: $0, right: hiddenDivider) } ?? false
        if isMisordered {
            hiddenDivider.length = Self.dividerLength
            alwaysDivider?.length = Self.dividerLength
        } else {
            hiddenDivider.length = isRevealed ? open : Self.collapsedLength
            alwaysDivider?.length = isAlwaysHiddenRevealed ? open : Self.collapsedLength
        }
        drawToggle()
        drawDivider(hiddenDivider, visible: isMisordered || (isRevealed && showsDividers))
        if let alwaysDivider {
            drawDivider(alwaysDivider, visible: isMisordered || (isAlwaysHiddenRevealed && showsDividers), dotted: true)
        }
    }

    /// Screen order of two items. Unknown (not yet placed) counts as ordered;
    /// a folded divider is measured by its right edge.
    private static func isOrdered(left: NSStatusItem, right: NSStatusItem) -> Bool {
        guard let leftFrame = left.button?.window?.frame, let rightFrame = right.button?.window?.frame,
              leftFrame.width > 0, rightFrame.width > 0 else { return true }
        return leftFrame.maxX <= rightFrame.minX + 1
    }

    private func drawToggle() {
        guard let button = toggleItem?.button else { return }
        let state = AppState.shared
        let symbol = state.menuBarToggleIcon.symbol(revealed: isRevealed)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isRevealed ? "Hide menu bar items" : "Show hidden menu bar items")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        image?.isTemplate = state.menuBarIconTemplate
        button.image = image
        button.contentTintColor = state.menuBarIconTemplate ? nil : NSColor(state.accentColor.color)
        button.toolTip = isMisordered
            ? "Tama's divider is right of this icon. ⌘-drag it back to the left, or reset the layout in Settings."
            : "Click to show or hide menu bar items. Option-click for the always-hidden ones too."
    }

    private func drawDivider(_ item: NSStatusItem, visible: Bool, dotted: Bool = false) {
        guard let button = item.button else { return }
        button.image = visible ? Self.dividerImage(dotted: dotted) : nil
        button.toolTip = dotted ? "Always Hidden: items left of this stay hidden until Option-click."
                                : "Hidden: ⌘-drag items left of this divider to hide them."
    }

    private static func dividerImage(dotted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            if dotted {
                for i in 0..<4 {
                    NSBezierPath(ovalIn: NSRect(x: rect.midX - 1, y: 1.5 + CGFloat(i) * 4, width: 2, height: 2)).fill()
                }
            } else {
                NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 1, width: 1.5, height: 14),
                             xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Rehide

    private func scheduleRehide() {
        rehideWork?.cancel()
        let state = AppState.shared
        guard state.menuBarAutoRehide else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRevealed else { return }
            // The pointer is up in the menu bar, probably using a revealed item: wait.
            if Self.pointerInMenuBar() { return self.scheduleRehide() }
            self.hide()
        }
        rehideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(state.menuBarRehideDelay, 2), execute: work)
    }

    /// A one-off read of the pointer position (no monitoring).
    private static func pointerInMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        return point.y >= screen.visibleFrame.maxY
    }

    private func observeAppSwitches() {
        guard appObserver == nil else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let service = MenuBarManagerService.shared
                if service.isRevealed, AppState.shared.menuBarRehideOnAppSwitch { service.hide() }
            }
        }
    }

    // MARK: Clicks

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            return showMenu(from: sender)
        }
        if event?.modifierFlags.contains(.option) == true {
            // Option-click: everything, including the always-hidden section.
            return isAlwaysHiddenRevealed ? hide() : reveal(all: true)
        }
        toggle()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let toggleTitle = isRevealed ? "Hide Menu Bar Items" : "Show Hidden Items"
        menu.addItem(withTitle: toggleTitle, action: #selector(menuToggle), keyEquivalent: "").target = self
        if alwaysDivider != nil {
            menu.addItem(withTitle: "Show Always-Hidden Items", action: #selector(menuRevealAll), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reset Layout", action: #selector(menuReset), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Menu Bar Manager Settings…", action: #selector(menuSettings), keyEquivalent: "").target = self
        // Attach just for this click, so plain clicks keep reaching the action.
        toggleItem?.menu = menu
        button.performClick(nil)
        toggleItem?.menu = nil
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuRevealAll() { reveal(all: true) }
    @objc private func menuReset() { resetLayout() }
    @objc private func menuSettings() {
        SettingsNavigator.shared.open(.droplets)
        SettingsNavigator.shared.openDropletID = "menuBar"
        SettingsWindowController.shared.showWindow()
    }

    // MARK: Reset

    /// Forgets where the items were dragged and puts them back in their
    /// starting order: toggle rightmost, then the dividers to its left.
    public func resetLayout() {
        let defaults = UserDefaults.standard
        let names = [Self.toggleName, Self.hiddenName, Self.alwaysName]
        teardown()
        for name in names {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
            defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        }
        // A fresh run loop turn, so the status bar has dropped the old items.
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }
}
