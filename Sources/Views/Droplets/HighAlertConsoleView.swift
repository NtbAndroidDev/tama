import SwiftUI

/// High Alert, laid out like the reference: the ruler sets how long, the gear
/// cycles Screen / System / Lid Closed, ∞ keeps awake until stopped. Running,
/// a stop button, the mode pill and the time left.
struct HighAlertConsoleView: View {
    // Observed directly: AppState doesn't forward the service's changes.
    @ObservedObject private var blocker = SleepBlockerService.shared
    @ObservedObject private var state = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if blocker.isAwakeActive {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    RulerRoundButton("stop.fill", orange: true, help: "Stop keeping awake") {
                        blocker.disable()
                        DroppyAudio.playTick()
                    }
                    RulerRoundButton(blocker.activeMode.icon, title: blocker.activeMode.title,
                                     help: blocker.activeMode.summary) {}
                        .allowsHitTesting(false)
                    Spacer(minLength: 8)
                    if blocker.remainingSeconds > 0 {
                        RulerClock(seconds: blocker.remainingSeconds, caption: "High Alert")
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("High Alert")
                                .font(DS.Typo.title)
                                .foregroundStyle(RulerMetrics.orange.opacity(0.9))
                            Image(systemName: "infinity")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(RulerMetrics.orange)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("High Alert, running indefinitely")
                    }
                }
                statusLine
                Spacer(minLength: 0)
            } else {
                RulerSlider(minutes: $state.highAlertMinutes, range: 5...1440)
                HStack(spacing: 10) {
                    RulerStartButton(title: blocker.isAuthorizing ? "Authorizing…" : "Start timer") {
                        blocker.enable(durationSeconds: state.highAlertMinutes * 60, mode: state.highAlertMode)
                        DroppyAudio.playTick()
                    }
                    .disabled(blocker.isAuthorizing)
                    RulerRoundButton(state.highAlertMode.icon,
                                     help: "\(state.highAlertMode.summary). Click to switch to \(state.highAlertMode.next.title).") {
                        state.highAlertMode = state.highAlertMode.next
                        DroppyAudio.playTick()
                    }
                    RulerRoundButton("infinity", help: "Keep awake indefinitely") {
                        blocker.enable(durationSeconds: 0, mode: state.highAlertMode)
                        DroppyAudio.playTick()
                    }
                    .disabled(blocker.isAuthorizing)
                    Spacer(minLength: 8)
                    RulerClock(seconds: state.highAlertMinutes * 60)
                }
                statusLine
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: blocker.isAwakeActive)
        .onAppear { blocker.refreshSystemSleepStatus() }
    }

    /// "System sleep enabled · Sleep Now", or the lid-closed warning.
    private var statusLine: some View {
        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(blocker.isSystemSleepDisabled ? DS.Palette.warning : DS.Palette.success)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            // The longer notes don't fit one line; the tooltip has them whole.
            Text(statusText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(statusText)
            Spacer(minLength: DS.Space.xs)
            Button("Sleep now") {
                blocker.sleepNow()
            }
            .buttonStyle(DroppyPressStyle(scale: 0.95))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(RulerMetrics.orange.opacity(0.9))
            .help("Put your Mac to sleep")
        }
    }

    private var statusText: String {
        if blocker.isSystemSleepDisabled {
            return "System sleep disabled — closing the lid won't sleep your Mac"
        }
        if !blocker.isAwakeActive, state.highAlertMode == .lidClosed {
            return "Lid Closed asks for your password and turns system sleep off until it stops"
        }
        return "System sleep enabled"
    }
}
