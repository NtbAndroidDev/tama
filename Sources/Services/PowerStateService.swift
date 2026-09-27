import AppKit

/// What the Mac's power state means for Tama's background work.
///
/// Nothing Tama draws can be seen while the screen is off or the Mac is on
/// its way into sleep, so the pollers that exist only to keep the notch current
/// stand down until it comes back. A Mac shut in a bag still dark-wakes —
/// hundreds of times an hour when a Bluetooth device keeps nudging it — and
/// each dark wake runs whatever timers are due, so a poller that ignores this
/// turns into Apple Events, EventKit fetches and spawned tools with the lid
/// closed. The pollers with a start/stop of their own are told through
/// `applyDormancy`; the rest skip their tick while `isDormant` holds and are
/// caught up in `refreshAfterWake`.
///
/// A locked screen is deliberately *not* dormant: Tama draws its own lock
/// screen, and the media, battery and calendar behind it have to stay current.
@MainActor
public final class PowerStateService: ObservableObject {
    public static let shared = PowerStateService()

    /// Nothing is on screen to keep current.
    @Published public private(set) var isDormant = false

    private var reasons = DormancyReasons() {
        didSet {
            guard reasons.isDormant != isDormant else { return }
            isDormant = reasons.isDormant
            applyDormancy()
        }
    }

    private var observers: [NSObjectProtocol] = []

    private init() {}

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let map: [(NSNotification.Name, DormancyReasons.Reason, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
        ]
        for (name, reason, entering) in map {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    PowerStateService.shared.reasons.set(entering, reason: reason)
                }
            })
        }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        reasons = DormancyReasons()
    }

    /// Each of these decides for itself; they all read `isDormant` from their
    /// own `sync`, so this only has to ask them to look again.
    private func applyDormancy() {
        JiggleService.shared.syncIdleWatch()
        ScreenStateService.shared.sync()
        BrightnessService.shared.syncAutoWatch()
        AgentActivityService.shared.syncPolling()
        if !isDormant { refreshAfterWake() }
    }

    /// Coming back, the notch would otherwise show whatever was true when the
    /// screen went off until each poller's next tick came round — up to ten
    /// seconds of a stale player. Ask for one round now instead.
    private func refreshAfterWake() {
        MediaService.shared.refreshNow()
        BatteryService.shared.refreshNow()
        HeadphoneBatteryService.shared.refreshNow()
        SystemMonitorService.shared.refreshMetrics()
        BetterDisplayService.shared.refresh()
        TaskAlertService.shared.tick()
        MeetingService.shared.tick()
        WeatherService.shared.refresh()
        // Something else may have disabled sleep while we were out; and a
        // Lid-Closed session of ours must not survive unnoticed.
        SleepBlockerService.shared.refreshSystemSleepStatus()
    }
}
