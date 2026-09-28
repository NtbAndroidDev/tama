import SwiftUI

/// Settings › Droplets › Pomodoro: cycle lengths, ambient sound and Momentum.
@MainActor
public final class PomodoroSettings: SettingsStore {
    public static let shared = PomodoroSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "pomodoroWorkMinutes", "pomodoroBreakMinutes", "pomodoroAmbientEnabled",
        "pomodoroAmbientSound", "pomodoroAmbientVolume", "pomodoroFocusShortcuts",
        "pomodoroKeepVisible", "pomodoroHoverOpens", "pomodoroMomentum", "pomodoroSessionsToday",
        "pomodoroMomentumDay", "pomodoroStreakDays", "pomodoroBestStreak"
    ]

    @AppStorage("pomodoroWorkMinutes") public var workMinutes: Int = 25 {
        didSet { AppState.shared.syncIdlePomodoro() }
    }
    @AppStorage("pomodoroBreakMinutes") public var breakMinutes: Int = 5 {
        didSet { AppState.shared.syncIdlePomodoro() }
    }
    /// Pomodoro › ambient sound: synthesised noise while a focus cycle runs.
    @AppStorage("pomodoroAmbientEnabled") public var ambientEnabled: Bool = false {
        didSet { AppState.shared.syncPomodoroAmbient() }
    }
    @AppStorage("pomodoroAmbientSound") public var ambientSound: String = AmbientSoundService.Sound.brown.rawValue {
        didSet { AppState.shared.syncPomodoroAmbient() }
    }
    @AppStorage("pomodoroAmbientVolume") public var ambientVolume: Double = 0.5 {
        didSet { AmbientSoundService.shared.setVolume(ambientVolume) }
    }
    /// Runs the "Tama Focus On/Off" Shortcuts as focus cycles start and stop.
    @AppStorage("pomodoroFocusShortcuts") public var focusShortcuts: Bool = false
    /// The running Pomodoro outranks music and the Tray in the resting wings.
    @AppStorage("pomodoroKeepVisible") public var keepVisible: Bool = true {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Hovering the resting timer opens the shelf straight onto Pomodoro.
    @AppStorage("pomodoroHoverOpens") public var hoverOpens: Bool = true
    /// Pomodoro › Momentum: finished focus sessions and the day-by-day streak.
    @AppStorage("pomodoroMomentum") public var showsMomentum: Bool = true
    @AppStorage("pomodoroSessionsToday") public var sessionsToday: Int = 0
    @AppStorage("pomodoroMomentumDay") public var momentumDay: String = ""
    @AppStorage("pomodoroStreakDays") public var streakDays: Int = 0
    @AppStorage("pomodoroBestStreak") public var bestStreak: Int = 0

    private init() { super.init(keys: Self.keys) }
}
