import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The modifiers every Tama shortcut shares. ⌘⇧ collides with Save As
/// (⌘⇧S), Chrome's inspector (⌘⇧C) and the bookmarks bar (⌘⇧B), so ⌃⌥ is the default.
public enum ShortcutModifier: String, CaseIterable, Identifiable, Sendable {
    case controlOption, optionCommand, commandShift

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .controlOption: "⌃ ⌥"
        case .optionCommand: "⌥ ⌘"
        case .commandShift: "⌘ ⇧"
        }
    }
    var carbonFlags: UInt32 {
        switch self {
        case .controlOption: UInt32(controlKey | optionKey)
        case .optionCommand: UInt32(optionKey | cmdKey)
        case .commandShift: UInt32(cmdKey | shiftKey)
        }
    }
}

/// A key plus modifiers, as Carbon registers it. Stored in UserDefaults as
/// "keyCode:modifiers" (Carbon flags), or "none" when the shortcut is cleared.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public var keyCode: Int
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    public var modifiers: UInt32

    public init(keyCode: Int, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2, let key = Int(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        self.init(keyCode: key, modifiers: mods)
    }

    var storage: String { "\(keyCode):\(modifiers)" }

    /// From a key event, e.g. while recording.
    public init(event: NSEvent) {
        var mods: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        self.init(keyCode: Int(event.keyCode), modifiers: mods)
    }

    public var hasModifier: Bool { modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 }

    /// Function keys work alone; anything else needs ⌃, ⌥ or ⌘, or it would
    /// swallow ordinary typing.
    public var isValidGlobal: Bool { hasModifier || Self.functionKeys.contains(keyCode) }

    public var modifierSymbols: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    public var keyName: String { Self.name(for: keyCode) }

    /// "⌃⌥Space".
    public var display: String { modifierSymbols + keyName }

    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func name(for keyCode: Int) -> String { names[keyCode] ?? "Key \(keyCode)" }
}

/// Every global shortcut Tama registers. Each one is recordable in
/// Settings; its default is the shared modifier (`shortcutModifier`, ⌃⌥ unless
/// changed in an older build) plus its letter.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case toggleIsland, toggleBasket, toggleLiveActivity, snipToTray, toggleClipboard, openPlayer, ring
    /// Settings › Clipboard › Paste shortcut: opens the clipboard ready to
    /// paste, so a clip goes straight into the app you came from. None by default.
    case pasteFromClipboard
    /// Settings › HUDs › Keyboard backlight; no shortcut until one is recorded.
    case keyboardBacklightUp, keyboardBacklightDown
    /// Settings › Basket › Basket Switcher; no shortcut until one is recorded.
    case basketSwitcher
    /// Settings › Droplets › Element Capture: one per capture mode, none by default.
    case captureArea, captureWindow, captureFullscreen, captureElement, captureOCR
    /// Settings › Droplets › Window Snap: one per layout, none by default.
    case snapLeftHalf, snapRightHalf, snapTopHalf, snapBottomHalf
    case snapLeftThird, snapCenterThird, snapRightThird, snapLeftTwoThirds, snapRightTwoThirds
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case snapCenter, snapMaximize, snapNextDisplay, snapPreviousDisplay, snapBringToFront
    /// Voice Transcribe › Quick Record: start or stop a visible recording. None by default.
    case quickRecord
    /// The floating Thunderstorm launcher.
    case thunderstorm
    /// Menu Bar Manager: show or hide the hidden section. None by default.
    case menuBarToggle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toggleIsland: "Toggle the island"
        case .toggleBasket: "Toggle Floating Basket"
        case .toggleLiveActivity: "Toggle Live Activity HUD"
        case .snipToTray: "Quick Snip to Tray"
        case .toggleClipboard: "Open the clipboard"
        case .pasteFromClipboard: "Paste from the clipboard"
        case .openPlayer: "Open the player"
        case .ring: "Ring at the pointer"
        case .keyboardBacklightUp: "Brighten keyboard"
        case .keyboardBacklightDown: "Dim keyboard"
        case .basketSwitcher: "Basket Switcher"
        case .captureArea: "Capture area"
        case .captureWindow: "Capture window"
        case .captureFullscreen: "Capture full screen"
        case .captureElement: "Capture element"
        case .captureOCR: "Capture text (OCR)"
        case .quickRecord: "Quick Record"
        case .thunderstorm: "Open Thunderstorm"
        case .menuBarToggle: "Show or hide the hidden section"
        default: SnapLayout(shortcut: self)?.title ?? rawValue
        }
    }

    /// nil: the action starts without a shortcut.
    var defaultKeyCode: Int? {
        switch self {
        case .toggleIsland: kVK_Space
        case .toggleBasket: kVK_ANSI_B
        case .toggleLiveActivity: kVK_ANSI_L
        case .snipToTray: kVK_ANSI_S
        case .toggleClipboard: kVK_ANSI_C
        case .openPlayer: kVK_ANSI_M
        case .ring: kVK_ANSI_R
        case .thunderstorm: kVK_ANSI_T
        default: nil
        }
    }

    /// UserDefaults key of the recorded combo.
    public var defaultsKey: String { "shortcut.\(rawValue)" }

    public static var defaultsKeys: [String] { allCases.map(\.defaultsKey) }

    /// Where Settings › Keyboard Shortcuts lists it.
    public var group: ShortcutGroup {
        switch self {
        case .toggleIsland, .toggleLiveActivity, .openPlayer, .ring: .general
        case .toggleBasket, .basketSwitcher, .toggleClipboard, .pasteFromClipboard: .workspace
        case .keyboardBacklightUp, .keyboardBacklightDown: .huds
        case .snipToTray, .captureArea, .captureWindow, .captureFullscreen, .captureElement, .captureOCR: .capture
        case .quickRecord, .thunderstorm, .menuBarToggle: .tools
        default: .windowSnap
        }
    }

    /// The droplet the shortcut belongs to; it's registered only while that droplet is on.
    public var dropletID: String? {
        switch self {
        case .ring: "ring"
        case .captureArea, .captureWindow, .captureFullscreen, .captureElement, .captureOCR: "snipper"
        case .quickRecord: "voiceTranscribe"
        case .thunderstorm: "thunderstorm"
        case .menuBarToggle: "menuBar"
        default: SnapLayout(shortcut: self) != nil ? "windowSnapper" : nil
        }
    }
}

/// The sections of Settings › Keyboard Shortcuts.
public enum ShortcutGroup: String, CaseIterable, Sendable {
    case general = "General", workspace = "Basket & Clipboard", huds = "HUDs", capture = "Element Capture"
    case windowSnap = "Window Snap", tools = "Tools", widgets = "Widget shortcuts"
}

/// Anything that can hold a recorded shortcut: one of the fixed actions, or
/// "open this droplet's console" for any droplet (per-widget shortcuts).
public enum ShortcutSlot: Hashable, Sendable, Identifiable {
    case action(ShortcutAction)
    case droplet(String)

    public var id: String { defaultsKey }

    public var defaultsKey: String {
        switch self {
        case .action(let action): action.defaultsKey
        case .droplet(let id): Self.dropletKey(id)
        }
    }

    public static func dropletKey(_ id: String) -> String { "shortcut.droplet.\(id)" }

    /// Every per-widget key, for Reset / Export.
    public static var dropletDefaultsKeys: [String] { AppState.defaultDroplets.map { dropletKey($0.id) } }

    @MainActor public var title: String {
        switch self {
        case .action(let action): action.title
        case .droplet(let id):
            "Open \(AppState.defaultDroplets.first { $0.id == id }?.name ?? id)"
        }
    }

    /// Every slot there is: the fixed actions, then one per droplet.
    public static var all: [ShortcutSlot] {
        ShortcutAction.allCases.map(ShortcutSlot.action) + AppState.defaultDroplets.map { .droplet($0.id) }
    }
}

/// System-wide shortcuts. They are Carbon hot keys: they work without
/// Accessibility / Input Monitoring access and are consumed, so the frontmost
/// app never sees them. Esc is watched with event monitors, since it must stay
/// available to other apps.
@MainActor
public final class GlobalShortcutService: ObservableObject {
    public static let shared = GlobalShortcutService()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?

    /// The modifiers older builds shared across every shortcut. Now only the
    /// base of each shortcut's default.
    public static let modifierKey = "shortcutModifier"
    public var modifier: ShortcutModifier {
        ShortcutModifier(rawValue: UserDefaults.standard.string(forKey: Self.modifierKey) ?? "") ?? .controlOption
    }
    /// Shortcuts another app already holds.
    @Published public private(set) var failedSlots: [ShortcutSlot] = []
    public var failedActions: [ShortcutAction] {
        failedSlots.compactMap { if case .action(let action) = $0 { action } else { nil } }
    }
    /// Bumped whenever a combo changes, so views showing combos redraw.
    @Published public private(set) var revision = 0
    /// What is registered now, to skip re-registering on unrelated defaults changes.
    private var registered: [ShortcutSlot: KeyCombo] = [:]
    private var registeredRing: Bool?
    /// While a recorder listens, the hot keys are off so pressing the current
    /// combo records it instead of firing it.
    private var isSuspended = false

    /// Read from the persisted list rather than AppState: the defaults change
    /// fires while `droplets` is still publishing its old value.
    static var isRingEnabled: Bool { isDropletOn("ring") }

    /// For droplets that start switched on: off only once listed as disabled.
    static func isDropletOn(_ id: String) -> Bool {
        !(UserDefaults.standard.stringArray(forKey: "disabledDroplets") ?? []).contains(id)
    }

    /// Like `isDropletOn`, but honours droplets that ship switched off
    /// (Mechey, Menu Bar Manager): those need to be listed as enabled.
    static func isDropletEnabled(_ id: String) -> Bool {
        let defaults = UserDefaults.standard
        if (defaults.stringArray(forKey: "enabledDroplets") ?? []).contains(id) { return true }
        if (defaults.stringArray(forKey: "disabledDroplets") ?? []).contains(id) { return false }
        return AppState.defaultDroplets.first { $0.id == id }?.isEnabled ?? false
    }

    // MARK: Combos

    /// The combo an action fires on; nil when cleared.
    public func combo(for action: ShortcutAction) -> KeyCombo? { combo(for: .action(action)) }

    public func combo(for slot: ShortcutSlot) -> KeyCombo? {
        guard let stored = UserDefaults.standard.string(forKey: slot.defaultsKey) else {
            return defaultCombo(for: slot)
        }
        if stored == "none" { return nil }
        return KeyCombo(storage: stored) ?? defaultCombo(for: slot)
    }

    /// Per-widget shortcuts start empty.
    public func defaultCombo(for slot: ShortcutSlot) -> KeyCombo? {
        if case .action(let action) = slot { return defaultCombo(for: action) }
        return nil
    }

    public func defaultCombo(for action: ShortcutAction) -> KeyCombo? {
        // The clipboard opens on ⇧⌘Space, like the reference — unless the
        // shared modifier is ⌘⇧, where that's the island's own shortcut.
        if action == .toggleClipboard, modifier != .commandShift {
            return KeyCombo(keyCode: kVK_Space, modifiers: UInt32(cmdKey | shiftKey))
        }
        return action.defaultKeyCode.map { KeyCombo(keyCode: $0, modifiers: modifier.carbonFlags) }
    }

    /// "⌃⌥C", or nil when the action has no shortcut.
    public func display(for action: ShortcutAction) -> String? {
        combo(for: action)?.display
    }

    /// Records a combo. Returns the action that already uses it, without
    /// changing anything, so the recorder can say so.
    @discardableResult
    public func setCombo(_ combo: KeyCombo?, for action: ShortcutAction) -> ShortcutAction? {
        if case .action(let owner) = setCombo(combo, for: .action(action)) { return owner }
        return nil
    }

    /// Records a combo for any slot. Returns the slot that already uses it,
    /// without changing anything.
    @discardableResult
    public func setCombo(_ combo: KeyCombo?, for slot: ShortcutSlot) -> ShortcutSlot? {
        if let combo, let owner = ShortcutSlot.all.first(where: { $0 != slot && self.combo(for: $0) == combo }) {
            return owner
        }
        UserDefaults.standard.set(combo?.storage ?? "none", forKey: slot.defaultsKey)
        reregisterIfNeeded()
        return nil
    }

    public func resetCombo(for action: ShortcutAction) { resetCombo(for: .action(action)) }

    public func resetCombo(for slot: ShortcutSlot) {
        UserDefaults.standard.removeObject(forKey: slot.defaultsKey)
        reregisterIfNeeded()
    }

    /// Settings › Keyboard Shortcuts › Reset all shortcuts.
    public func resetAll() {
        for slot in ShortcutSlot.all { UserDefaults.standard.removeObject(forKey: slot.defaultsKey) }
        reregisterIfNeeded()
    }

    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterHotKeys()
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerHotKeys()
    }

    private struct HotKey {
        let slot: ShortcutSlot
        /// Registered only while this is true, so a disabled feature doesn't hold the key.
        var isAvailable: @MainActor () -> Bool = { true }
        var onRelease: (@MainActor () -> Void)?
        let fire: @MainActor () -> Void

        init(slot: ShortcutSlot, isAvailable: @escaping @MainActor () -> Bool = { true },
             onRelease: (@MainActor () -> Void)? = nil, fire: @escaping @MainActor () -> Void) {
            self.slot = slot
            self.isAvailable = isAvailable
            self.onRelease = onRelease
            self.fire = fire
        }

        init(action: ShortcutAction, isAvailable: @escaping @MainActor () -> Bool = { true },
             onRelease: (@MainActor () -> Void)? = nil, fire: @escaping @MainActor () -> Void) {
            self.init(slot: .action(action), isAvailable: isAvailable, onRelease: onRelease, fire: fire)
        }
    }

    /// The fixed actions; per-widget ones are added by `currentHotKeys()`.
    private let actionHotKeys: [HotKey] = [
        HotKey(action: .toggleIsland) { AppState.shared.toggleIsland() },
        HotKey(action: .toggleBasket) {
            AppState.shared.isBasketVisible.toggle()
            DroppyAudio.playTick()
        },
        HotKey(action: .basketSwitcher) { BasketSwitcher.show() },
        HotKey(action: .toggleLiveActivity) {
            AppState.shared.isLiveActivityPresented.toggle()
            DroppyAudio.playTick()
        },
        HotKey(action: .snipToTray) { TrayActions.snipToTray() },
        HotKey(action: .toggleClipboard) { AppState.shared.toggleClipboard() },
        HotKey(action: .pasteFromClipboard) { AppState.shared.openClipboardToPaste() },
        HotKey(action: .openPlayer) {
            AppState.shared.open(.home)
            NotchWindowController.shared.focusPanel()
            DroppyAudio.playTick()
        },
        // Hold to open, release to fire: needs the key-up, unlike the others.
        HotKey(action: .ring,
               isAvailable: { GlobalShortcutService.isRingEnabled },
               onRelease: { RingWindowController.shared.hotKeyReleased() }) {
            RingWindowController.shared.hotKeyPressed()
        },
        // Press to step the backlight, hold to keep stepping.
        HotKey(action: .keyboardBacklightUp,
               onRelease: { KeyboardBacklightService.shared.endHold() }) {
            KeyboardBacklightService.shared.beginHold(up: true)
        },
        HotKey(action: .keyboardBacklightDown,
               onRelease: { KeyboardBacklightService.shared.endHold() }) {
            KeyboardBacklightService.shared.beginHold(up: false)
        },
    ] + CaptureMode.allCases.map { mode in
        HotKey(action: mode.shortcutAction, isAvailable: { GlobalShortcutService.isDropletOn("snipper") }) {
            ScreenCaptureService.shared.capture(mode)
        }
    } + SnapLayout.allCases.map { layout in
        HotKey(action: layout.shortcutAction, isAvailable: { GlobalShortcutService.isDropletOn("windowSnapper") }) {
            WindowSnapService.shared.perform(layout, fromShortcut: true)
        }
    } + [
        HotKey(action: .quickRecord, isAvailable: { GlobalShortcutService.isDropletOn("voiceTranscribe") }) {
            VoiceTranscribeService.shared.quickRecord()
        },
        HotKey(action: .thunderstorm, isAvailable: { GlobalShortcutService.isDropletOn("thunderstorm") }) {
            ThunderstormLauncherController.shared.toggle()
        },
        HotKey(action: .menuBarToggle, isAvailable: { GlobalShortcutService.isDropletEnabled("menuBar") }) {
            MenuBarManagerService.shared.toggle()
        },
    ]

    /// What `registerHotKeys` registered, in order: IDs are the array index.
    private var hotKeys: [HotKey] = []

    /// The fixed actions plus one "open its console" key per droplet.
    private func currentHotKeys() -> [HotKey] {
        actionHotKeys + AppState.defaultDroplets.map { droplet in
            let id = droplet.id
            return HotKey(slot: .droplet(id), isAvailable: { GlobalShortcutService.isDropletEnabled(id) }) {
                GlobalShortcutService.openDroplet(id)
            }
        }
    }

    /// A per-widget shortcut: opens the droplet's console in the shelf, or
    /// closes the shelf when that console is already up.
    static func openDroplet(_ id: String) {
        let state = AppState.shared
        guard let droplet = state.droplets.first(where: { $0.id == id }), droplet.isEnabled else { return }
        if state.isIslandExpanded, state.shelfPage == .widgets, state.activeDropletID == id {
            state.setIslandExpanded(false)
            return
        }
        state.open(.widgets)
        state.activeDropletID = id
        NotchWindowController.shared.focusPanel()
        DroppyAudio.playTick()
    }

    private init() {}

    public func startMonitoring() {
        stopMonitoring()
        registerHotKeys()
        // Re-register when a shortcut, the base modifier or the Ring changes.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { GlobalShortcutService.shared.reregisterIfNeeded() }
        }

        // Esc while another app is frontmost (needs Accessibility; harmless without it).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            Task { @MainActor [weak self] in
                _ = self?.handleEscape(keyCode: keyCode)
            }
        }

        // Esc while the notch or clipboard panel has focus. Only a fallback:
        // Settings sheets, the Live Activity HUD and a field being edited
        // (search, rename, new task) keep Esc for themselves.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window is DroppyNotchPanel || event.window is ClipboardPanel else { return event }
            if let editor = event.window?.firstResponder as? NSTextView, editor.isFieldEditor { return event }
            if let handled = self?.handleEscape(keyCode: event.keyCode), handled {
                return nil // consume event
            }
            return event
        }
    }

    public func stopMonitoring() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        unregisterHotKeys()
    }

    private func wantedCombos(_ keys: [HotKey]) -> [ShortcutSlot: KeyCombo] {
        var result: [ShortcutSlot: KeyCombo] = [:]
        for hotKey in keys where hotKey.isAvailable() {
            if let combo = combo(for: hotKey.slot) { result[hotKey.slot] = combo }
        }
        return result
    }

    /// Every slot's combo as last seen, to tell views when one changed.
    private var knownCombos: [ShortcutSlot: KeyCombo?] = [:]

    private func reregisterIfNeeded() {
        let combos = Dictionary(uniqueKeysWithValues: ShortcutSlot.all.map { ($0, combo(for: $0)) })
        if combos != knownCombos {
            knownCombos = combos
            revision &+= 1
        }
        guard !isSuspended, eventHandler != nil || !hotKeyRefs.isEmpty || registeredRing != nil else { return }
        guard registered != wantedCombos(currentHotKeys()) || registeredRing != Self.isRingEnabled else { return }
        unregisterHotKeys()
        registerHotKeys()
    }

    private func unregisterHotKeys() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        registered = [:]
        registeredRing = nil
    }

    // MARK: Hot keys

    private static let signature: OSType = 0x4452_5059 // 'DRPY'

    private func registerHotKeys() {
        guard !isSuspended else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == GlobalShortcutService.signature else { return status }
            let index = Int(hotKeyID.id)
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalShortcutService.shared.fire(index, released: released) }
            }
            return noErr
        }, specs.count, &specs, nil, &eventHandler)

        hotKeys = currentHotKeys()
        let wanted = wantedCombos(hotKeys)
        var failed: [ShortcutSlot] = []
        for (index, hotKey) in hotKeys.enumerated() {
            guard let combo = wanted[hotKey.slot] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            if RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                hotKeyRefs.append(ref)
            } else {
                failed.append(hotKey.slot)
            }
        }
        registered = wanted
        registeredRing = Self.isRingEnabled
        failedSlots = failed
    }

    private func fire(_ index: Int, released: Bool) {
        guard hotKeys.indices.contains(index) else { return }
        if released {
            hotKeys[index].onRelease?()
        } else {
            hotKeys[index].fire()
        }
    }

    // MARK: Escape

    private func handleEscape(keyCode: UInt16) -> Bool {
        guard keyCode == UInt16(kVK_Escape) else { return false }
        if RingWindowController.shared.isVisible {
            RingWindowController.shared.close()
            return true
        }
        if AppState.shared.isClipboardVisible {
            AppState.shared.isClipboardVisible = false
            return true
        }
        // A preview, sampler or capture over the shelf takes Esc for itself;
        // collapsing here would tear it down mid-task.
        if AppState.shared.isCustomizingHome {
            AppState.shared.cancelHomeCustomization()
            return true
        }
        // Step back one level at a time: a console, lyrics/up-next or the
        // output picker closes first, the shelf only on the next Esc.
        let s = AppState.shared
        if s.isIslandExpanded, !s.isModalPresented {
            let back = DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)
            if s.shelfPage == .home, s.isOutputPickerOpen {
                withAnimation(back) { s.isOutputPickerOpen = false }
                return true
            }
            if s.shelfPage == .home, s.playerPanel != .none {
                withAnimation(back) { s.playerPanel = .none }
                return true
            }
            if s.shelfPage == .tray, s.pendingConvert != nil {
                withAnimation(back) { s.pendingConvert = nil }
                return true
            }
            if s.shelfPage == .widgets, s.activeDropletID != nil {
                withAnimation(back) { s.activeDropletID = nil }
                return true
            }
        }
        if AppState.shared.isIslandExpanded, !AppState.shared.isModalPresented {
            AppState.shared.setIslandExpanded(false)
            return true
        }
        return false
    }
}
