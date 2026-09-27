import SwiftUI
import Combine

// The Pomodoro droplet's focus / break cycle, its ambient sound and the
// optional Focus mode through Shortcuts.

/// The Pomodoro countdown, apart from AppState so its once-a-second tick only
/// redraws the views that show the time. They observe this directly.
@MainActor
public final class PomodoroClock: ObservableObject {
    public static let shared = PomodoroClock()
    @Published public var secondsRemaining: Int = 25 * 60
    private init() {}
}

/// The running Pomodoro time as text, observing only the clock.
struct PomodoroTimeText: View {
    @ObservedObject private var clock = PomodoroClock.shared

    var body: some View {
        Text(String(format: "%02d:%02d", clock.secondsRemaining / 60, clock.secondsRemaining % 60))
    }
}

extension AppState {
    // MARK: - Pomodoro Droplet Timer
    public func startPomodoro() {
        SystemNotifier.requestAuthorization()
        isPomodoroActive = true
        pomodoroHasStarted = true
        pomodoroEndDate = Date().addingTimeInterval(TimeInterval(max(pomodoroSecondsRemaining, 1)))
        pomodoroTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickPomodoro() }
        }
        // Common modes: keep counting while a menu is open or a drag is in flight.
        RunLoop.main.add(timer, forMode: .common)
        pomodoroTimer = timer
        syncPomodoroAmbient()
        if isPomodoroWorkCycle { runFocusShortcut(on: true) }
    }

    func tickPomodoro() {
        guard isPomodoroActive, let end = pomodoroEndDate else { return }
        let remaining = Int(end.timeIntervalSinceNow.rounded(.up))
        if remaining > 0 {
            if remaining != pomodoroSecondsRemaining { pomodoroSecondsRemaining = remaining }
            return
        }
        // The focus cycle just ran out, so it counts towards Momentum.
        if isPomodoroWorkCycle { recordPomodoroSession() }
        isPomodoroWorkCycle.toggle()
        pomodoroSecondsRemaining = pomodoroCycleSeconds
        pomodoroEndDate = Date().addingTimeInterval(TimeInterval(pomodoroCycleSeconds))
        let title = isPomodoroWorkCycle ? "Break Finished!" : "Focus Time Completed!"
        let message = isPomodoroWorkCycle
            ? "Time to focus for \(pomodoroWorkMinutes) minutes."
            : "Take a well-deserved \(pomodoroBreakMinutes) minute break."
        showNotification(appName: "Pomodoro", title: title, message: message)
        SystemNotifier.post(title: title, body: message)
        if soundEffects { NSSound(named: "Glass")?.play() }
        syncPomodoroAmbient()
        runFocusShortcut(on: isPomodoroWorkCycle)
    }

    public func pausePomodoro() {
        if let end = pomodoroEndDate {
            pomodoroSecondsRemaining = max(Int(end.timeIntervalSinceNow.rounded(.up)), 0)
        }
        pomodoroEndDate = nil
        let wasActive = isPomodoroActive
        isPomodoroActive = false
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        syncPomodoroAmbient()
        if wasActive && isPomodoroWorkCycle { runFocusShortcut(on: false) }
    }

    public func resetPomodoro() {
        pausePomodoro()
        pomodoroHasStarted = false
        isPomodoroWorkCycle = true
        pomodoroSecondsRemaining = pomodoroWorkMinutes * 60
    }

    /// Before starting: pick which cycle the ruler sets and Start begins.
    public func setPomodoroCycle(work: Bool) {
        guard !isPomodoroActive, !pomodoroHasStarted, work != isPomodoroWorkCycle else { return }
        isPomodoroWorkCycle = work
        pomodoroSecondsRemaining = pomodoroCycleSeconds
    }

    /// The ruler's value: the length of the cycle Start begins.
    public var pomodoroRulerMinutes: Int {
        get { isPomodoroWorkCycle ? pomodoroWorkMinutes : pomodoroBreakMinutes }
        set {
            if isPomodoroWorkCycle { pomodoroWorkMinutes = newValue } else { pomodoroBreakMinutes = newValue }
        }
    }

    /// A stopped timer that hasn't started its cycle follows the new length;
    /// a paused one keeps where it was.
    func syncIdlePomodoro() {
        guard !isPomodoroActive, !pomodoroHasStarted else { return }
        pomodoroSecondsRemaining = pomodoroCycleSeconds
    }

    public var formattedPomodoroTime: String {
        let mins = pomodoroSecondsRemaining / 60
        let secs = pomodoroSecondsRemaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: Momentum

    /// Pomodoro › Momentum: finished focus sessions today and the day streak.
    public var pomodoroMomentum: PomodoroMomentum {
        get {
            PomodoroMomentum(sessionsToday: pomodoroSessionsToday, day: pomodoroMomentumDay,
                             streakDays: pomodoroStreakDays, bestStreak: pomodoroBestStreak)
        }
        set {
            pomodoroSessionsToday = newValue.sessionsToday
            pomodoroMomentumDay = newValue.day
            pomodoroStreakDays = newValue.streakDays
            pomodoroBestStreak = newValue.bestStreak
        }
    }

    /// One focus session finished. Only whole cycles count, so a session that
    /// was reset or paused away doesn't inflate the streak.
    func recordPomodoroSession() {
        let before = pomodoroMomentum
        let after = before.recording(Date())
        pomodoroMomentum = after
        guard pomodoroShowsMomentum, after.streakDays > before.currentStreak(on: Date()), after.streakDays > 1 else { return }
        showNotification(appName: "Pomodoro", title: "\(after.streakDays)-day streak",
                         message: "That's \(after.streakDays) days in a row with a finished focus session.",
                         icon: "flame.fill")
    }

    public func resetPomodoroMomentum() {
        pomodoroMomentum = PomodoroMomentum()
    }

    // MARK: Ambient sound

    public var pomodoroAmbient: AmbientSoundService.Sound {
        AmbientSoundService.Sound(rawValue: pomodoroAmbientSound) ?? .brown
    }

    /// Plays while a focus cycle runs with ambient sound on; quiet otherwise.
    func syncPomodoroAmbient() {
        if pomodoroAmbientEnabled, isPomodoroActive, isPomodoroWorkCycle {
            AmbientSoundService.shared.play(pomodoroAmbient, volume: pomodoroAmbientVolume)
        } else {
            AmbientSoundService.shared.stop()
        }
    }

    // MARK: Focus mode

    static let focusOnShortcut = "Tama Focus On"
    static let focusOffShortcut = "Tama Focus Off"

    /// macOS has no public API to switch Focus, so two user-made Shortcuts do it.
    func runFocusShortcut(on: Bool) {
        guard pomodoroFocusShortcuts, ShortcutsLibrary.isAvailable else { return }
        let name = on ? Self.focusOnShortcut : Self.focusOffShortcut
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var failed = false
            do {
                try process.run()
                process.waitUntilExit()
                failed = process.terminationStatus != 0
            } catch {
                failed = true
            }
            guard failed else { return }
            await MainActor.run {
                AppState.shared.showNotification(
                    appName: "Pomodoro", title: "Couldn't run \u{201C}\(name)\u{201D}",
                    message: "Create it in Shortcuts with a Set Focus action.",
                    icon: "exclamationmark.triangle.fill", actionTitle: "Open Shortcuts",
                    action: {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    })
            }
        }
    }
}
