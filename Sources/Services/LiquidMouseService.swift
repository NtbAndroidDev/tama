import AppKit
import Combine
import CoreGraphics
import IOKit.hid

/// A scroll-wheel tap on its own thread. Notched mouse-wheel events are
/// swallowed and replayed as a stream of small pixel scrolls that ease out,
/// so a plain mouse glides like a trackpad. Trackpads and Magic Mouse already
/// scroll continuously and pass through untouched; "reverse" flips only the
/// wheel, so natural scrolling can stay on for the trackpad.
final class LiquidScrollTap: @unchecked Sendable {
    struct Axis: Equatable {
        /// Invert this axis on a notched wheel only.
        var reverse = false
        /// Multiplies the distance of every notch.
        var speed = 1.0
        var curve: ScrollCurve = .balanced
    }

    struct Config: Equatable {
        var smooth = true
        /// Momentum instead of a fixed glide per notch: notches add velocity
        /// that decays, so quick flicks carry on like a trackpad.
        var liquid = false
        /// Seconds a single notch takes to settle.
        var glide = 0.35
        var vertical = Axis()
        var horizontal = Axis()

        var reversesAny: Bool { vertical.reverse || horizontal.reverse }
    }

    /// Marks the events this tap posts, so it lets them through on the way back.
    private static let marker: Int64 = 0x4452_4F50
    /// Pixels one wheel line scrolls at speed 1.
    private static let pixelsPerLine = 38.0
    private static let frameInterval = 1.0 / 120

    private let lock = NSLock()
    private var _config = Config()
    var config: Config {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set { lock.lock(); _config = newValue; lock.unlock() }
    }

    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var timer: CFRunLoopTimer?

    /// One notch being played out along its curve.
    private struct Impulse {
        var distance: Double
        var start: CFAbsoluteTime
        var duration: Double
        var curve: ScrollCurve
        var emitted = 0.0
    }

    // Touched only on the tap thread.
    private var impulsesX: [Impulse] = [], impulsesY: [Impulse] = []
    private var velocityX = 0.0, velocityY = 0.0
    private var lastNotchX: CFAbsoluteTime = 0, lastNotchY: CFAbsoluteTime = 0
    private var residualX = 0.0, residualY = 0.0
    private var lastFrame: CFAbsoluteTime = 0
    private var isGliding = false
    var isRunning: Bool { thread != nil }

    /// Returns false when macOS refuses the tap (Accessibility not granted).
    func start() -> Bool {
        guard thread == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var created = false
        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                callback: liquidTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            // One repeating frame timer, parked far in the future while idle.
            let timer = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, Self.frameInterval, 0, 0) { [weak self] _ in
                self?.frame()
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self.port = port
            self.runLoop = loop
            self.timer = timer
            created = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Tama LiquidMouse tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if created { self.thread = thread }
        return created
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let timer { CFRunLoopTimerInvalidate(timer) }
        if let runLoop { CFRunLoopStop(runLoop) }
        port = nil
        runLoop = nil
        timer = nil
        thread = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS also disables the tap when Accessibility is revoked; turning
            // it back on then would hold up every scroll event in the session.
            if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker,
              // Trackpads and Magic Mouse scroll continuously already.
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
        else { return Unmanaged.passUnretained(event) }

        let config = config
        guard config.smooth || config.reversesAny else { return Unmanaged.passUnretained(event) }

        // ⌘/⌥/⌃-scroll zooms or does something app-specific; leave it notched.
        let modified = !event.flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        guard config.smooth, !modified else {
            Self.flip(event, vertical: config.vertical.reverse, horizontal: config.horizontal.reverse)
            return Unmanaged.passUnretained(event)
        }

        // The fixed-point deltas already include the system's wheel acceleration.
        var lineY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var lineX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if lineY == 0, lineX == 0 {
            lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        }
        // Shift turns a vertical wheel sideways, as apps would; the horizontal
        // settings then apply.
        if event.flags.contains(.maskShift), lineX == 0 {
            lineX = lineY
            lineY = 0
        }
        let now = CFAbsoluteTimeGetCurrent()
        if lineY != 0 {
            let axis = config.vertical
            add(lineY * Self.pixelsPerLine * axis.speed * (axis.reverse ? -1 : 1), axis: axis, config: config,
                impulses: &impulsesY, velocity: &velocityY, lastNotch: &lastNotchY, now: now)
        }
        if lineX != 0 {
            let axis = config.horizontal
            add(lineX * Self.pixelsPerLine * axis.speed * (axis.reverse ? -1 : 1), axis: axis, config: config,
                impulses: &impulsesX, velocity: &velocityX, lastNotch: &lastNotchX, now: now)
        }

        if !isGliding, let timer {
            isGliding = true
            lastFrame = now
            CFRunLoopTimerSetNextFireDate(timer, lastFrame)
        }
        return nil
    }

    /// Momentum time constant: a longer tail than the glide, like a trackpad fling.
    private static func momentumTau(_ glide: Double) -> Double { max(glide, 0.12) * 0.9 + 0.12 }

    private func add(_ distance: Double, axis: Axis, config: Config, impulses: inout [Impulse],
                     velocity: inout Double, lastNotch: inout CFAbsoluteTime, now: CFAbsoluteTime) {
        // A notch against the glide cancels it instead of fighting it.
        let remaining = velocity + impulses.reduce(0) { $0 + ($1.distance - $1.emitted) }
        if remaining != 0, (remaining > 0) != (distance > 0) {
            impulses.removeAll()
            velocity = 0
        }
        if config.liquid {
            // Travel `distance` in total over an exponential decay; notches in
            // quick succession build up speed.
            let tau = Self.momentumTau(config.glide)
            let boost = now - lastNotch < 0.12 ? 1.25 : 1
            velocity += distance * boost / tau
        } else {
            impulses.append(Impulse(distance: distance, start: now, duration: max(config.glide, 0.08), curve: axis.curve))
        }
        lastNotch = now
    }

    private func frame() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(max(now - lastFrame, Self.frameInterval / 2), 0.05)
        lastFrame = now
        let tau = Self.momentumTau(config.glide)

        let stepY = advance(&impulsesY, velocity: &velocityY, now: now, dt: dt, tau: tau)
        let stepX = advance(&impulsesX, velocity: &velocityX, now: now, dt: dt, tau: tau)

        let totalY = stepY + residualY
        let totalX = stepX + residualX
        let pixelsY = totalY.rounded(.towardZero)
        let pixelsX = totalX.rounded(.towardZero)
        residualY = totalY - pixelsY
        residualX = totalX - pixelsX

        if pixelsY != 0 || pixelsX != 0,
           let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: Int32(pixelsY), wheel2: Int32(pixelsX), wheel3: 0) {
            scroll.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            scroll.post(tap: .cgSessionEventTap)
        }

        if impulsesY.isEmpty, impulsesX.isEmpty, velocityY == 0, velocityX == 0, let timer {
            isGliding = false
            residualX = 0
            residualY = 0
            CFRunLoopTimerSetNextFireDate(timer, .greatestFiniteMagnitude)
        }
    }

    /// Pixels to scroll this frame on one axis: each notch follows its curve,
    /// momentum decays exponentially.
    private func advance(_ impulses: inout [Impulse], velocity: inout Double,
                         now: CFAbsoluteTime, dt: Double, tau: Double) -> Double {
        var step = 0.0
        for i in impulses.indices {
            let progress = min(max((now - impulses[i].start) / impulses[i].duration, 0), 1)
            let target = impulses[i].distance * impulses[i].curve.value(at: progress)
            step += target - impulses[i].emitted
            impulses[i].emitted = target
        }
        impulses.removeAll { now - $0.start >= $0.duration }
        if velocity != 0 {
            step += velocity * dt
            velocity *= exp(-dt / tau)
            if abs(velocity) < 6 { velocity = 0 }
        }
        return step
    }

    private static func flip(_ event: CGEvent, vertical: Bool, horizontal: Bool) {
        if vertical {
            for field in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1] {
                event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
            }
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                      value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        }
        if horizontal {
            for field in [CGEventField.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2] {
                event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
            }
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,
                                      value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        }
    }
}

private func liquidTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<LiquidScrollTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

// MARK: - Service

/// LiquidMouse: smooth scrolling and a separate scroll direction for a plain
/// mouse wheel. Runs while the Droplet is on and either switch is, and needs
/// Accessibility to change scroll events.
@MainActor
public final class LiquidMouseService: ObservableObject {
    public static let shared = LiquidMouseService()

    /// UserDefaults keys, shared with the console's @AppStorage.
    public enum Keys {
        public static let smooth = "liquidMouseSmooth"
        /// Vertical axis (the keys predate per-axis settings).
        public static let reverse = "liquidMouseReverse"
        public static let speed = "liquidMouseSpeed"
        public static let curve = "liquidMouseCurveV"
        public static let reverseHorizontal = "liquidMouseReverseH"
        public static let speedHorizontal = "liquidMouseSpeedH"
        public static let curveHorizontal = "liquidMouseCurveH"
        public static let glide = "liquidMouseGlide"
        public static let liquidMode = "liquidMouseLiquidMode"

        public static let all = [smooth, reverse, speed, curve, reverseHorizontal, speedHorizontal,
                                 curveHorizontal, glide, liquidMode]

        public static func reverse(_ axis: ScrollAxis) -> String { axis == .vertical ? reverse : reverseHorizontal }
        public static func speed(_ axis: ScrollAxis) -> String { axis == .vertical ? speed : speedHorizontal }
        public static func curve(_ axis: ScrollAxis) -> String { axis == .vertical ? curve : curveHorizontal }
    }

    @Published public private(set) var hasPermission = AXIsProcessTrusted()
    @Published public private(set) var isActive = false

    private let tap = LiquidScrollTap()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Called once at launch; from then on the tap follows the settings.
    public func start() {
        guard !started else { return }
        started = true
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.smooth: false, Keys.reverse: false, Keys.speed: 1.0, Keys.glide: 0.35,
            // One "reverse" used to flip both axes; horizontal starts from it.
            Keys.reverseHorizontal: defaults.bool(forKey: Keys.reverse), Keys.speedHorizontal: 1.0,
            Keys.curve: ScrollCurve.balanced.rawValue, Keys.curveHorizontal: ScrollCurve.balanced.rawValue,
            Keys.liquidMode: false,
        ])
        AppState.shared.$droplets
            .map { $0.first(where: { $0.id == "liquidMouse" })?.isEnabled ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        // Granting Accessibility in System Settings doesn't notify; look again on return.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPermission() }
            .store(in: &cancellables)
        apply()
    }

    public func refreshPermission() {
        let granted = AXIsProcessTrusted()
        if granted != hasPermission { hasPermission = granted }
        // A revoked grant leaves the tap in place but dead; take it down.
        if !granted, isActive {
            tap.stop()
            isActive = false
        }
        apply()
    }

    public func requestPermission() {
        PermissionService.shared.request(.accessibility)
        refreshPermission()
    }

    private var isDropletEnabled: Bool {
        AppState.shared.droplets.first(where: { $0.id == "liquidMouse" })?.isEnabled ?? false
    }

    private func apply() {
        let defaults = UserDefaults.standard
        func axis(_ axis: ScrollAxis) -> LiquidScrollTap.Axis {
            LiquidScrollTap.Axis(
                reverse: defaults.bool(forKey: Keys.reverse(axis)),
                speed: defaults.double(forKey: Keys.speed(axis)),
                curve: ScrollCurve(rawValue: defaults.string(forKey: Keys.curve(axis)) ?? "") ?? .balanced
            )
        }
        let config = LiquidScrollTap.Config(
            smooth: defaults.bool(forKey: Keys.smooth),
            liquid: defaults.bool(forKey: Keys.liquidMode),
            glide: defaults.double(forKey: Keys.glide),
            vertical: axis(.vertical),
            horizontal: axis(.horizontal)
        )
        tap.config = config
        let wanted = started && isDropletEnabled && (config.smooth || config.reversesAny)
        if wanted, !isActive {
            hasPermission = AXIsProcessTrusted()
            guard hasPermission else { return }
            if tap.start() { isActive = true } else { hasPermission = false }
        } else if !wanted, isActive {
            tap.stop()
            isActive = false
        }
    }

    public func shutdown() {
        tap.stop()
        isActive = false
    }

    /// "Restore the balanced preset for this direction".
    public static func restoreBalanced(_ axis: ScrollAxis) {
        let defaults = UserDefaults.standard
        defaults.set(ScrollCurve.balanced.rawValue, forKey: Keys.curve(axis))
        defaults.set(1.0, forKey: Keys.speed(axis))
    }
}

public enum ScrollAxis: String, CaseIterable, Identifiable, Sendable {
    case vertical, horizontal
    public var id: String { rawValue }
    public var title: String { self == .vertical ? "Vertical" : "Horizontal" }
}

/// How one wheel notch plays out over the glide: position (0…1) against time (0…1).
public enum ScrollCurve: String, CaseIterable, Identifiable, Sendable {
    case linear, balanced
    case easeInCubic, easeOutCubic, easeInOutCubic
    case easeInQuartic, easeOutQuartic, easeInOutQuartic
    case softStart, stableFluid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .balanced: "Balanced"
        case .easeInCubic: "Ease In Cubic"
        case .easeOutCubic: "Ease Out Cubic"
        case .easeInOutCubic: "Ease In Out Cubic"
        case .easeInQuartic: "Ease In Quartic"
        case .easeOutQuartic: "Ease Out Quartic"
        case .easeInOutQuartic: "Ease In Out Quartic"
        case .softStart: "Soft Start"
        case .stableFluid: "Stable & Fluid"
        }
    }

    public var summary: String {
        switch self {
        case .linear: "Constant speed from start to stop, with no easing."
        case .balanced: "Quick to respond, then settles smoothly. The default for both directions."
        case .easeInCubic: "Starts gently and speeds up toward the end."
        case .easeOutCubic: "Jumps ahead at once and coasts to a long, gentle stop."
        case .easeInOutCubic: "Gentle at both ends with a faster middle."
        case .easeInQuartic: "A very soft start that finishes quickly."
        case .easeOutQuartic: "Snappiest response, with the longest glide out."
        case .easeInOutQuartic: "Pronounced easing at both ends; the middle moves fastest."
        case .softStart: "Soft start, then an even glide — good for reading long pages."
        case .stableFluid: "Stable and fluid: steady, predictable motion that stops smoothly."
        }
    }

    /// Progress along the notch's distance at time `x`, both 0…1.
    public func value(at x: Double) -> Double {
        let t = min(max(x, 0), 1)
        switch self {
        case .linear: return t
        case .balanced: return 1 - pow(1 - t, 2)
        case .easeInCubic: return t * t * t
        case .easeOutCubic: return 1 - pow(1 - t, 3)
        case .easeInOutCubic: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .easeInQuartic: return t * t * t * t
        case .easeOutQuartic: return 1 - pow(1 - t, 4)
        case .easeInOutQuartic: return t < 0.5 ? 8 * pow(t, 4) : 1 - pow(-2 * t + 2, 4) / 2
        case .softStart: return 1 - cos(t * .pi / 2)
        case .stableFluid: return sin(t * .pi / 2)
        }
    }
}

// MARK: - External mouse detection

/// Whether a mouse other than the built-in trackpad is connected, from the
/// HID devices IOKit lists. Only device properties are read; nothing is
/// opened or monitored, so no Input Monitoring access is involved.
@MainActor
public final class ExternalMouseMonitor: ObservableObject {
    public static let shared = ExternalMouseMonitor()

    /// Product names of the connected external mice, de-duplicated.
    @Published public private(set) var mice: [String] = []

    private var manager: IOHIDManager?

    private init() {}

    public var hasExternalMouse: Bool { !mice.isEmpty }

    public func start() {
        if manager == nil {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [String: Any] = [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            // Plug and unplug; delivered on the main run loop.
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
                MainActor.assumeIsolated { ExternalMouseMonitor.shared.refresh() }
            }, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in
                MainActor.assumeIsolated { ExternalMouseMonitor.shared.refresh() }
            }, nil)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            self.manager = manager
        }
        refresh()
    }

    public func refresh() {
        guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            if !mice.isEmpty { mice = [] }
            return
        }
        var names: [String] = []
        for device in devices {
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "").lowercased()
            let builtIn = (IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? Bool) ?? false
            guard Self.isExternalMouse(product: product, transport: transport, builtIn: builtIn) else { continue }
            let name = product.isEmpty ? "Mouse" : product
            if !names.contains(name) { names.append(name) }
        }
        names.sort()
        if names != mice { mice = names }
    }

    /// Trackpads (built-in on SPI/FIFO, or a Magic Trackpad) and virtual
    /// pointing devices don't count.
    nonisolated static func isExternalMouse(product: String, transport: String, builtIn: Bool) -> Bool {
        guard !builtIn, !["spi", "fifo", "i2c", ""].contains(transport) else { return false }
        return !product.localizedCaseInsensitiveContains("trackpad")
    }
}
