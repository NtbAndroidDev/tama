import SwiftUI

/// Timer & Stopwatch droplet, in the ruler style Pomodoro and High Alert use:
/// the ruler sets the countdown, Start Timer runs it, and the big orange time
/// sits on the right. The time keeps showing in the notch's wings while it
/// runs, so the shelf can be closed.
struct TimerConsoleView: View {
    @ObservedObject private var timer = TimerService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xxs) {
                ForEach(TimerService.Mode.allCases) { mode in
                    DroppyChip(mode.rawValue, isSelected: timer.mode == mode) {
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { timer.switchMode(mode) }
                        DroppyAudio.playTick()
                    }
                }
                // Switching resets, so it waits until the current run is reset.
                .disabled(timer.hasStarted)
                .optionalHelp(timer.hasStarted ? "Reset to switch modes" : nil)
                Spacer()
            }

            if timer.mode == .timer {
                if timer.hasStarted {
                    Spacer(minLength: 0)
                } else {
                    RulerSlider(minutes: Binding(get: { max(Int(timer.duration / 60), 1) },
                                                 set: { timer.setDuration(TimeInterval($0 * 60)) }),
                                range: 1...1440)
                }
            } else {
                laps
            }

            HStack(spacing: DS.Space.md) {
                controls
                Spacer(minLength: DS.Space.sm)
                RulerClock(text: TimerService.format(timer.displaySeconds, tenths: timer.mode == .stopwatch),
                           caption: timer.hasStarted ? timer.mode.rawValue : nil)
                    .accessibilityLabel("\(timer.mode.rawValue) \(TimerService.format(timer.displaySeconds))")
            }
            if timer.mode == .timer, timer.hasStarted { Spacer(minLength: 0) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: timer.mode)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: timer.hasStarted)
    }

    @ViewBuilder
    private var controls: some View {
        if !timer.hasStarted {
            RulerStartButton(title: timer.mode == .timer ? "Start timer" : "Start") {
                timer.start()
                DroppyAudio.playTick()
            }
        } else {
            RulerRoundButton(timer.isRunning ? "pause.fill" : "play.fill", orange: true,
                             help: timer.isRunning ? "Pause" : "Resume") {
                timer.toggle()
                DroppyAudio.playTick()
            }
            RulerRoundButton("xmark", help: "Reset") {
                timer.reset()
                DroppyAudio.playTick()
            }
            if timer.mode == .stopwatch {
                RulerRoundButton("flag.fill", help: "Lap") {
                    timer.lap()
                    DroppyAudio.playTick()
                }
                    .disabled(!timer.isRunning)
            } else {
                RulerRoundButton("minus", help: "Remove a minute") {
                    timer.adjust(by: -60)
                    DroppyAudio.playTick()
                }
                RulerRoundButton("plus", help: "Add a minute") {
                    timer.adjust(by: 60)
                    DroppyAudio.playTick()
                }
            }
        }
    }

    private var laps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.sm) {
                ForEach(Array(timer.laps.enumerated()), id: \.offset) { index, time in
                    VStack(spacing: 1) {
                        Text("Lap \(timer.laps.count - index)")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(TimerService.format(time, tenths: true))
                            .foregroundStyle(RulerMetrics.orange.opacity(0.9))
                    }
                    .font(DS.Typo.caption.monospacedDigit())
                    .padding(.horizontal, DS.Space.md).padding(.vertical, 5)
                    .background(Capsule().fill(DS.Palette.surface1))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(height: RulerMetrics.height)
        .overlay {
            if timer.laps.isEmpty {
                Text("Laps appear here")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }
}
