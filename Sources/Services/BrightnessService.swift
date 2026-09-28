import AppKit
import CoreGraphics
import IOKit
import IOKit.graphics

/// Reads and sets the built-in display's brightness for the brightness HUD.
/// macOS has no public API for this: the private DisplayServices framework is
/// what Control Center uses and works on Apple Silicon; IOKit's display
/// parameter is the fallback for Intel Macs where DisplayServices is missing.
@MainActor
public final class BrightnessService {
    public static let shared = BrightnessService()

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightness: GetBrightness?
    private var setBrightness: SetBrightness?
    private var poll: Timer?

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        }
        if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightness = unsafeBitCast(symbol, to: SetBrightness.self)
        }
    }

    /// The built-in panel, or the main display when the lid is closed.
    public var builtInDisplay: CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// 0…1, or nil when the display doesn't expose a readable brightness.
    public var brightness: Double? {
        brightness(on: builtInDisplay) ?? Self.ioKitBrightness()
    }

    /// A display's brightness through DisplayServices: the built-in panel and
    /// Apple's own external displays (Studio Display, Pro Display XDR).
    public func brightness(on display: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0, value.isFinite else { return nil }
        return Double(value)
    }

    public var canSetBrightness: Bool { setBrightness != nil && brightness != nil }

    public func canSetBrightness(on display: CGDirectDisplayID) -> Bool {
        setBrightness != nil && brightness(on: display) != nil
    }

    public func setBrightness(_ value: Double) {
        setBrightness(value, on: builtInDisplay)
    }

    public func setBrightness(_ value: Double, on display: CGDirectDisplayID) {
        guard let setBrightness else { return }
        let clamped = min(max(value, 0), 1)
        _ = setBrightness(display, Float(clamped))
        lastSet[display] = (clamped, Date())
        noteOwnChange()
    }

    /// The level to step from. The panel fades towards a new value, so while a
    /// scroll is in flight the last target beats a mid-fade read-back.
    public var level: Double? { level(on: builtInDisplay) ?? brightness }

    public func level(on display: CGDirectDisplayID) -> Double? {
        if let last = lastSet[display], Date().timeIntervalSince(last.at) < 0.5 { return last.value }
        return brightness(on: display)
    }

    private var lastSet: [CGDirectDisplayID: (value: Double, at: Date)] = [:]

    /// The brightness keys fade the panel over a few frames, so reading once
    /// right after the key shows the old value. Follow it until it settles.
    public func presentHUD() {
        guard HUDSettings.shared.showBrightnessHUD, let first = brightness else { return }
        noteOwnChange()
        AppState.shared.showHUD(.brightness, value: first)
        poll?.invalidate()
        lastShown = first
        ticks = 0
        poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { BrightnessService.shared.followBrightness() }
        }
    }

    private var lastShown: Double = 0
    private var ticks = 0

    private func followBrightness() {
        ticks += 1
        if let now = brightness, abs(now - lastShown) > 0.001 {
            lastShown = now
            AppState.shared.showHUD(.brightness, value: now)
        }
        if ticks >= 10 {
            poll?.invalidate()
            poll = nil
        }
    }

    // MARK: Automatic brightness HUD

    /// Watches the built-in panel for changes nobody pressed a key for
    /// (ambient light, Control Center, another app) and shows the HUD for
    /// them. There's no change notification, so it's sampled every two seconds
    /// while the setting is on.
    private var autoWatch: Timer?
    /// Where the panel was when the HUD last had nothing to say.
    private var baseline: Double?
    /// A key, scroll or slider here moved it; the HUD for that is already up.
    private var ownChangeAt: Date?
    private var isFollowingAutoChange = false

    private func noteOwnChange() {
        ownChangeAt = Date()
        baseline = nil
    }

    public func syncAutoWatch() {
        // A screen that is off has no brightness worth following, and the HUD
        // that would report it isn't on screen either.
        let wanted = HUDSettings.shared.automaticBrightnessHUD && HUDSettings.shared.showBrightnessHUD && getBrightness != nil
            && !PowerStateService.shared.isDormant
        if wanted, autoWatch == nil {
            baseline = brightness(on: builtInDisplay)
            let timer = Timer(timeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { BrightnessService.shared.sampleAutomaticChange() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            autoWatch = timer
        } else if !wanted {
            autoWatch?.invalidate()
            autoWatch = nil
        }
    }

    private func sampleAutomaticChange() {
        // DisplayServices only: with no readable panel (lid closed on a third-
        // party screen) the IOKit fallback would walk the registry every tick
        // for a value that is never going to move on its own.
        guard let now = brightness(on: builtInDisplay) else { return }
        if let ownChangeAt, Date().timeIntervalSince(ownChangeAt) < 2 {
            baseline = now
            return
        }
        guard let baseline else {
            self.baseline = now
            return
        }
        // Ambient changes creep; wait for a visible step, then follow it.
        let threshold = isFollowingAutoChange ? 0.004 : 0.03
        if abs(now - baseline) > threshold {
            isFollowingAutoChange = true
            self.baseline = now
            AppState.shared.showHUD(.brightness, value: now)
        } else {
            isFollowingAutoChange = false
        }
    }

    private static func ioKitBrightness() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            var value: Float = 0
            let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
            IOObjectRelease(service)
            if result == kIOReturnSuccess { return Double(value) }
        }
        return nil
    }
}
