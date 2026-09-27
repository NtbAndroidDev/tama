import AppKit

/// "Grab, jiggle, drop." Watches file drags anywhere on screen and brings the
/// floating Basket (Settings › Basket):
/// - a side-to-side shake mid-drag (Shake sensitivity sets how hard);
/// - Instant appear: any file drag, after a short delay;
/// - Drag shortcut: holding the recorded modifiers while dragging.
/// In Multi-Basket mode a shake while a Basket is already out spawns another.
/// Auto-hide puts the Baskets away once they've been idle for a while.
@MainActor
public final class JiggleService {
    public static let shared = JiggleService()

    private var monitors: [Any] = []
    private var dragChangeCount = 0
    private var detector = ShakeDetector()
    /// The current drag carries files and has been seen as such.
    private var isFileDrag = false
    private var instantWork: DispatchWorkItem?
    private var lastSpawn = Date.distantPast
    private var idleTimer: Timer?
    private var idleSeconds: TimeInterval = 0

    private init() {}

    public func start() {
        stop()
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            Task { @MainActor in JiggleService.shared.beginGesture() }
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
            let dx = event.deltaX
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            Task { @MainActor in JiggleService.shared.track(dx: dx, flags: flags) }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in JiggleService.shared.endGesture() }
        }
        monitors = [down, drag, up].compactMap { $0 }
        syncIdleWatch()
    }

    /// The auto-hide countdown only means something while a Basket is on screen
    /// and the setting is on. It used to be started at launch and left running
    /// for the life of the process: two wake-ups a second, for ever, to find
    /// there was nothing to hide. It also stands down while the screen is off.
    /// Whether the countdown is armed right now.
    var isWatchingIdle: Bool { idleTimer != nil }

    public func syncIdleWatch() {
        let state = AppState.shared
        let wanted = state.basketAutoHide && state.isBasketVisible && !PowerStateService.shared.isDormant
        if wanted, idleTimer == nil {
            idleSeconds = 0
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in JiggleService.shared.tickAutoHide() }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
        } else if !wanted {
            idleTimer?.invalidate()
            idleTimer = nil
            idleSeconds = 0
        }
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// Settings › Basket › Shake sensitivity, 0…1, onto the recognizer.
    static func detector(sensitivity: Double) -> ShakeDetector {
        let s = min(max(sensitivity, 0), 1)
        var d = ShakeDetector()
        d.minimumTravel = CGFloat(34 - 26 * s)          // 34 pt … 8 pt legs
        d.window = 0.5 + 0.4 * s                         // 0.5 s … 0.9 s
        d.requiredReversals = s < 0.25 ? 4 : (s > 0.8 ? 2 : 3)
        return d
    }

    /// "Gentle" … "Sensitive", for the slider's pill.
    static func sensitivityLabel(_ value: Double) -> String {
        switch value {
        case ..<0.2: "Firm"
        case ..<0.4: "Relaxed"
        case ..<0.6: "Balanced"
        case ..<0.8: "Responsive"
        default: "Sensitive"
        }
    }

    private func beginGesture() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        detector = Self.detector(sensitivity: AppState.shared.basketShakeSensitivity)
        isFileDrag = false
        instantWork?.cancel()
    }

    private func endGesture() {
        instantWork?.cancel()
        instantWork = nil
        isFileDrag = false
    }

    private func track(dx: CGFloat, flags: UInt) {
        let state = AppState.shared
        if !isFileDrag, isDraggingFiles {
            isFileDrag = true
            scheduleInstantAppear()
        }
        guard isFileDrag else { return }

        // Drag shortcut: the recorded modifiers are down.
        let wanted = UInt(max(state.basketDragModifiers, 0))
        if wanted != 0, flags & wanted == wanted, !state.isBasketVisible {
            summon()
            return
        }

        guard state.jiggleToOpenBasket, abs(dx) > 1 else { return }
        let now = Date()
        guard detector.record(dx: dx, at: now) else { return }
        detector.fire(at: now)
        if !state.isBasketVisible {
            summon()
        } else if state.basketMode == .multi, !FloatingBasketController.shared.isPointerOverBasket,
                  now.timeIntervalSince(lastSpawn) > 1 {
            // Multi-Basket: jiggling while a basket is open spawns another.
            lastSpawn = now
            state.spawnBasket()
        }
    }

    /// Instant appear: the Basket comes after the delay unless the drag ended.
    private func scheduleInstantAppear() {
        let state = AppState.shared
        guard state.basketInstantAppear, !state.isBasketVisible else { return }
        // Tiles dragged out of Tama itself don't count.
        guard TrayActions.internalDragSource == nil else { return }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 != 0, !AppState.shared.isBasketVisible else { return }
                JiggleService.shared.summon()
            }
        }
        instantWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(max(state.basketInstantDelay, 0), 2), execute: work)
    }

    private func summon() {
        AppState.shared.showBasket(nearPointer: true)
        idleSeconds = 0
        DroppyAudio.playDropSuccess()
    }

    /// Auto-hide: no drag, the pointer away from every Basket, nothing modal.
    private func tickAutoHide() {
        let state = AppState.shared
        guard state.basketAutoHide, state.isBasketVisible else {
            idleSeconds = 0
            return
        }
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        if dragging || state.isModalPresented || FloatingBasketController.shared.isPointerOverBasket {
            idleSeconds = 0
            return
        }
        idleSeconds += 0.5
        if idleSeconds >= max(state.basketAutoHideDelay, 0.5) {
            idleSeconds = 0
            state.isBasketVisible = false
        }
    }

    /// A drag session carrying files has started since the mouse went down.
    private var isDraggingFiles: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount else { return false }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.types?.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")) == true
    }
}
