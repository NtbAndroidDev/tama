import SwiftUI

/// Pomodoro, laid out like the reference: a ruler to set the length, then
/// Start Timer, the ambient-sound mute, the Focus/Break switch and the big
/// orange time. Running, the controls become pause and stop.
struct PomodoroConsoleView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var pomodoroClock = PomodoroClock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isIdle: Bool { !state.isPomodoroActive && !state.pomodoroHasStarted }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            if isIdle {
                RulerSlider(minutes: Binding(get: { state.pomodoroRulerMinutes },
                                             set: { state.pomodoroRulerMinutes = $0 }),
                            range: state.isPomodoroWorkCycle ? 1...180 : 1...60)
                    .transition(DS.Motion.transition(reduceMotion, .opacity))
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Space.md) {
                if isIdle { idleControls } else { runningControls }
                Spacer(minLength: DS.Space.sm)
                RulerClock(seconds: state.pomodoroSecondsRemaining,
                           caption: isIdle ? nil : (state.isPomodoroWorkCycle ? "Focus" : "Break"))
            }
            if !isIdle { Spacer(minLength: 0) }
            momentum
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isIdle)
    }

    /// Momentum: finished focus sessions today and the day-by-day streak.
    @ViewBuilder
    private var momentum: some View {
        if state.pomodoroShowsMomentum, let summary = state.pomodoroMomentum.summary(on: Date()) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Palette.warning)
                    .accessibilityHidden(true)
                Text(summary)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Momentum: finished focus sessions. Best streak: \(state.pomodoroMomentum.bestStreak) days.")
            .accessibilityLabel("Momentum: \(summary)")
            .transition(DS.Motion.transition(reduceMotion, .opacity))
        }
    }

    @ViewBuilder
    private var idleControls: some View {
        RulerStartButton {
            state.startPomodoro()
            DroppyAudio.playTick()
        }
        RulerRoundButton(state.pomodoroAmbientEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         help: state.pomodoroAmbientEnabled
                            ? "Ambient sound: \(state.pomodoroAmbient.title) (click to mute)"
                            : "Ambient sound is off (click to turn on)") {
            state.pomodoroAmbientEnabled.toggle()
            DroppyAudio.playTick()
        }
        .contextMenu {
            ForEach(AmbientSoundService.Sound.allCases) { sound in
                Button {
                    state.pomodoroAmbientSound = sound.rawValue
                    state.pomodoroAmbientEnabled = true
                } label: {
                    if sound == state.pomodoroAmbient { Label(sound.title, systemImage: "checkmark") } else { Text(sound.title) }
                }
            }
        }
        RulerRoundButton(state.isPomodoroWorkCycle ? "brain.head.profile" : "cup.and.saucer.fill",
                         help: state.isPomodoroWorkCycle
                            ? "Focus session (click for a break)"
                            : "Break (click for a focus session)") {
            state.setPomodoroCycle(work: !state.isPomodoroWorkCycle)
            DroppyAudio.playTick()
        }
    }

    @ViewBuilder
    private var runningControls: some View {
        RulerRoundButton(state.isPomodoroActive ? "pause.fill" : "play.fill", orange: true,
                         help: state.isPomodoroActive ? "Pause" : "Resume") {
            state.isPomodoroActive ? state.pausePomodoro() : state.startPomodoro()
            DroppyAudio.playTick()
        }
        RulerRoundButton("xmark", help: "Stop and reset") {
            state.resetPomodoro()
            DroppyAudio.playTick()
        }
        if state.pomodoroAmbientEnabled || state.isPomodoroWorkCycle {
            RulerRoundButton(state.pomodoroAmbientEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             help: state.pomodoroAmbientEnabled ? "Mute ambient sound" : "Play ambient sound") {
                state.pomodoroAmbientEnabled.toggle()
                DroppyAudio.playTick()
            }
        }
    }
}
