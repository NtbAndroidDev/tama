import AppKit
import Combine

/// A countdown timer and a stopwatch. Both are date-based, so sleep and menu
/// tracking can't make them drift, and both show in the notch while running.
@MainActor
public final class TimerService: ObservableObject {
    public static let shared = TimerService()

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case timer = "Timer", stopwatch = "Stopwatch"
        public var id: String { rawValue }
    }

    @Published public var mode: Mode = .timer
    /// Length the timer starts from, in seconds.
    @Published public var duration: TimeInterval = 5 * 60
    @Published public private(set) var isRunning = false
    /// Timer: seconds left. Stopwatch: seconds elapsed.
    @Published public private(set) var displaySeconds: TimeInterval = 5 * 60
    @Published public private(set) var laps: [TimeInterval] = []

    private var endDate: Date?
    private var startDate: Date?
    /// Stopwatch time banked before the current run.
    private var banked: TimeInterval = 0
    private var ticker: Timer?
    /// A paused countdown whose time left was adjusted back to exactly its
    /// length still counts as started.
    private var isPausedMidRun = false

    private init() {}

    public var hasStarted: Bool { isRunning || isPausedMidRun || (mode == .timer ? displaySeconds != duration : displaySeconds > 0) }

    public func setDuration(_ seconds: TimeInterval) {
        duration = max(seconds, 1)
        if !isRunning, mode == .timer { displaySeconds = duration }
    }

    /// The ±1 minute buttons. Before the timer starts they change its length;
    /// once it has started (running or paused) they add to or take from the
    /// time left, never below a second, instead of starting over.
    public func adjust(by delta: TimeInterval) {
        guard mode == .timer else { return }
        guard hasStarted else {
            return setDuration(min(max(duration + delta, 60), 24 * 3600))
        }
        let current = isRunning ? max(endDate?.timeIntervalSinceNow ?? displaySeconds, 0) : displaySeconds
        let left = min(max(current + delta, 1), 24 * 3600)
        if isRunning { endDate = Date().addingTimeInterval(left) }
        displaySeconds = left
        publishActivity()
    }

    public func toggle() { isRunning ? pause() : start() }

    public func start() {
        guard !isRunning else { return }
        switch mode {
        case .timer:
            if displaySeconds <= 0 { displaySeconds = duration }
            endDate = Date().addingTimeInterval(displaySeconds)
        case .stopwatch:
            startDate = Date()
        }
        isRunning = true
        isPausedMidRun = false
        let ticker = Timer(timeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in TimerService.shared.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        tick()
    }

    public func pause() {
        guard isRunning else { return }
        tick()
        // tick() skips sub-second changes; the paused time must be exact.
        if mode == .timer, let endDate { displaySeconds = max(endDate.timeIntervalSinceNow, 0) }
        if mode == .stopwatch { banked = displaySeconds }
        stopTicking()
        isPausedMidRun = mode == .timer
        publishActivity()
    }

    public func reset() {
        stopTicking()
        isPausedMidRun = false
        banked = 0
        laps = []
        displaySeconds = mode == .timer ? duration : 0
        LiveActivityCenter.shared.end("timer")
    }

    public func switchMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        reset()
        self.mode = mode
        displaySeconds = mode == .timer ? duration : 0
    }

    public func lap() {
        guard mode == .stopwatch, isRunning else { return }
        laps.insert(displaySeconds, at: 0)
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        endDate = nil
        startDate = nil
    }

    private func tick() {
        switch mode {
        case .timer:
            guard let endDate else { return }
            let left = max(endDate.timeIntervalSinceNow, 0)
            // The countdown shows whole seconds; the ticker runs at 4 Hz so the
            // flip lands on time, but only the flip republishes.
            guard left <= 0 || Int(left.rounded(.up)) != Int(displaySeconds.rounded(.up)) else { return }
            displaySeconds = left
            // finish() posts the "Timer finished" activity; publishing after it
            // would see a reset timer and end that activity straight away.
            if left <= 0 { return finish() }
        case .stopwatch:
            guard let startDate else { return }
            displaySeconds = banked + Date().timeIntervalSince(startDate)
        }
        publishActivity()
    }

    private func finish() {
        stopTicking()
        isPausedMidRun = false
        displaySeconds = 0
        LiveActivityCenter.shared.post(LiveActivity(
            id: "timer", icon: "bell.fill", tint: DS.Palette.warning, trailing: .text("0:00"),
            priority: .urgent, label: "Timer finished", expiresAt: Date().addingTimeInterval(8)
        ))
        let length = Self.format(duration)
        AppState.shared.showNotification(appName: "Timer", title: "Time's up", message: "\(length) timer finished",
                                         actionTitle: "Again", action: { TimerService.shared.start() })
        SystemNotifier.post(title: "Time's up", body: "\(length) timer finished")
        if GeneralSettings.shared.soundEffects { NSSound(named: "Glass")?.play() }
        displaySeconds = duration
    }

    /// While running (or paused mid-way) the notch shows the time.
    private func publishActivity() {
        guard hasStarted else { return LiveActivityCenter.shared.end("timer") }
        LiveActivityCenter.shared.post(LiveActivity(
            id: "timer",
            icon: mode == .timer ? "timer" : "stopwatch",
            tint: isRunning ? DS.Palette.warning : .white.opacity(0.6),
            trailing: .text(Self.format(displaySeconds, compact: true)),
            priority: .ambient,
            label: "\(mode.rawValue) \(Self.format(displaySeconds))\(isRunning ? "" : " · paused")"
        ))
    }

    public nonisolated static func format(_ seconds: TimeInterval, compact: Bool = false, tenths: Bool = false) -> String {
        let value = max(seconds, 0)
        // Work in whole tenths: (2.3 * 10) is 22.999… in binary and showed ".2".
        let totalTenths = Int((value * 10 + 1e-6).rounded(.down))
        let whole = tenths ? totalTenths / 10 : Int(value.rounded(.up))
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        var text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if compact, h > 0 { text = String(format: "%dh%02d", h, m) }
        if tenths { text += String(format: ".%d", totalTenths % 10) }
        return text
    }
}
