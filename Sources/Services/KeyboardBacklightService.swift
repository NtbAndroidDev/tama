import Foundation
import ObjectiveC

/// Reads and sets the keyboard backlight for the keyboard-brightness HUD.
/// There's no public API: CoreBrightness's `KeyboardBrightnessClient` (what
/// Control Center uses) is loaded at runtime, and every call goes through
/// `responds(to:)`, so a macOS without it just reports "unavailable" and the
/// HUD and keys are left to macOS.
@MainActor
public final class KeyboardBacklightService {
    public static let shared = KeyboardBacklightService()

    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let client: NSObject?
    private let keyboardID: UInt64
    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    /// The last level set here, so held keys step from the target rather
    /// than a value the backlight is still fading towards.
    private var lastSet: (value: Double, at: Date)?

    private init() {
        let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")
        guard bundle?.load() == true,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil
            keyboardID = 0
            return
        }
        let client = type.init()
        let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        var id: UInt64 = 1
        if client.responds(to: copySelector) {
            let copy = unsafeBitCast(client.method(for: copySelector), to: CopyIDs.self)
            if let first = (copy(client, copySelector)?.takeRetainedValue() as? [NSNumber])?.first {
                id = first.uint64Value
            }
        }
        let usable = client.responds(to: Self.getSelector) && client.responds(to: Self.setSelector)
        self.client = usable ? client : nil
        self.keyboardID = id
    }

    public var isAvailable: Bool { brightness != nil }

    /// 0…1, or nil without a backlit keyboard or the private client.
    public var brightness: Double? {
        guard let client else { return nil }
        let get = unsafeBitCast(client.method(for: Self.getSelector), to: GetLevel.self)
        let value = Double(get(client, Self.getSelector, keyboardID))
        return value.isFinite && value >= 0 ? min(value, 1) : nil
    }

    /// The level to step from.
    public var level: Double? {
        if let lastSet, Date().timeIntervalSince(lastSet.at) < 0.5 { return lastSet.value }
        return brightness
    }

    public func setBrightness(_ value: Double) {
        guard let client else { return }
        let clamped = min(max(value, 0), 1)
        let set = unsafeBitCast(client.method(for: Self.setSelector), to: SetLevel.self)
        _ = set(client, Self.setSelector, Float(clamped), keyboardID)
        lastSet = (clamped, Date())
    }

    /// One press of a backlight key or shortcut: a sixteenth up or down (a
    /// quarter of that with ⌥⇧), with the HUD. Returns false when there's no
    /// backlight to step.
    @discardableResult
    public func step(up: Bool, fine: Bool = false) -> Bool {
        guard let current = level else { return false }
        let step = fine ? MediaKeyMonitor.fineStep : MediaKeyMonitor.coarseStep
        let target = MediaKeyMonitor.steppedVolume(current, by: up ? step : -step, step: step)
        setBrightness(target)
        if AppState.shared.showKeyboardBrightnessHUD {
            AppState.shared.showHUD(.keyboard, value: target)
        }
        return true
    }

    // MARK: Shortcuts (Settings › HUDs › Keyboard backlight)

    private var holdTimer: Timer?

    /// A shortcut went down: one step now, then more while it's held.
    public func beginHold(up: Bool) {
        endHold()
        guard step(up: up) else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { _ in
            MainActor.assumeIsolated { _ = KeyboardBacklightService.shared.step(up: up) }
        }
        timer.fireDate = Date().addingTimeInterval(0.4)
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    public func endHold() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    /// The backlight keys changed the level in macOS's hands: show where it landed.
    public func presentHUD() {
        guard AppState.shared.showKeyboardBrightnessHUD else { return }
        // The backlight fades; read once it has moved.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let now = KeyboardBacklightService.shared.brightness else { return }
            AppState.shared.showHUD(.keyboard, value: now)
        }
    }
}
