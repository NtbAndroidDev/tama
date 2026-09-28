import SwiftUI
import AppKit

public struct LockScreenLiveActivityView: View {
    /// Observed directly: AppState holds this service but doesn't forward its changes.
    @ObservedObject private var mediaServiceUpdates = MediaService.shared
    // High Alert isn't observed here: AppState forwards its on/off flips, and
    // the service's once-a-second countdown would redraw this whole view.
    @ObservedObject private var systemMonitorUpdates = SystemMonitorService.shared
    @ObservedObject var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @ObservedObject private var pomodoroClock = PomodoroClock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: DS.Space.xl) {
            // Top Bar: Dismiss & Activity Mode Switcher
            HStack {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                    Text("Live Activity")
                        .font(DS.Typo.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                
                Spacer()
                
                // Mode Switcher Pills
                HStack(spacing: DS.Space.xxs) {
                    ForEach(LiveActivityMode.allCases) { mode in
                        // Full names don't fit three-up in the 480pt card.
                        DroppyChip(mode.shortTitle, isSelected: state.liveActivityMode == mode) {
                            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { state.liveActivityMode = mode }
                            DroppyAudio.playTick()
                        }
                        .help("\(mode.rawValue) (Tab to switch)")
                    }
                }
                .padding(DS.Space.xxs)
                .background(Capsule().fill(DS.Palette.surfaceSunken))
                
                Spacer()
                
                DroppyIconButton("xmark", size: 24, tone: .tonal, help: "Close (Esc)") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { state.isLiveActivityPresented = false }
                    DroppyAudio.playTick()
                }
            }
            .padding(.horizontal, DS.Space.xs)
            
            // Hero Large Time & Date Lock Screen Header
            // The clock has minute precision, so it only needs to redraw once a minute.
            TimelineView(.everyMinute) { context in
                VStack(spacing: DS.Space.xxs) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 56, weight: .thin, design: .rounded))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .monospacedDigit()
                        .shadow(color: DS.accent.opacity(0.35), radius: 18, y: 4)

                    Text(context.date.formatted(Date.FormatStyle().weekday(.wide).month(.wide).day()))
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            
            // Live Activity Dynamic Card Content
            Group {
                switch state.liveActivityMode {
                case .mediaAndFocus:
                    mediaAndFocusCard
                case .systemTelemetry:
                    telemetryCard
                case .pomodoroCountdown:
                    pomodoroRingCard
                }
            }
            .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.98))))
            
            // Bottom Quick Utilities Bar
            HStack(spacing: 16) {
                // Battery Indicator
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: state.systemMonitor.batteryIconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state.systemMonitor.isCharging ? DS.Palette.success : DS.Palette.textSecondary)
                    Text(state.systemMonitor.hasBattery ? "\(state.systemMonitor.batteryLevel)%" : "AC")
                        .font(DS.Typo.numeric)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .padding(.horizontal, DS.Space.md)
                .frame(height: 26)
                .background(Capsule().fill(DS.Palette.surface2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery")
                .accessibilityValue(state.systemMonitor.hasBattery
                    ? "\(state.systemMonitor.batteryLevel) percent\(state.systemMonitor.isCharging ? ", charging" : "")"
                    : "On power adapter")
                
                // Sleep Blocker Toggle
                Button {
                    state.sleepBlocker.toggleIndefinite()
                    DroppyAudio.playTick()
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(state.sleepBlocker.isAwakeActive ? DS.Palette.warning : DS.Palette.textSecondary)
                        Text(state.sleepBlocker.isAwakeActive ? "Staying awake" : "Sleep as usual")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(.horizontal, DS.Space.md)
                    .frame(height: 26)
                    .background(Capsule().fill(state.sleepBlocker.isAwakeActive ? DS.Palette.warning.opacity(0.18) : DS.Palette.surface2))
                    .contentShape(Capsule())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help(state.sleepBlocker.isAwakeActive ? "Let your Mac sleep again" : "Keep your Mac awake")
                .accessibilityLabel("High Alert")
                .accessibilityValue(state.sleepBlocker.isAwakeActive ? "On" : "Off")
                
                Spacer()
                
                // Open Dynamic Island shortcut
                Button {
                    state.isLiveActivityPresented = false
                    state.setIslandExpanded(true)
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Open the shelf")
                            .font(DS.Typo.caption)
                    }
                    .accessibilityElement(children: .combine)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.lg)
                    .frame(height: 26)
                    .background(Capsule().fill(DS.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help("Close the Live Activity and open the shelf")
            }
            .padding(.top, DS.Space.xs)
        }
        .padding(DS.Space.xl)
        .frame(width: 480)
        .liquidGlass(cornerRadius: DS.Radius.xl + 4, showBorder: true, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .background(
            HStack {
                Button("") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                        state.isLiveActivityPresented = false
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                        switch state.liveActivityMode {
                        case .mediaAndFocus: state.liveActivityMode = .systemTelemetry
                        case .systemTelemetry: state.liveActivityMode = .pomodoroCountdown
                        case .pomodoroCountdown: state.liveActivityMode = .mediaAndFocus
                        }
                        DroppyAudio.playTick()
                    }
                }
                .keyboardShortcut(.tab, modifiers: [])
                
                Button("") {
                    state.mediaService.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            // Keyboard-only: VoiceOver otherwise found three unlabeled buttons here.
            .accessibilityHidden(true)
        )
    }
    
    // MARK: - Subcards
    
    private var mediaAndFocusCard: some View {
        HStack(spacing: 16) {
            // Album Art
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [DS.accent, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))

                if let artwork = state.mediaService.currentTrack.artworkImage {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Palette.hairlineStrong, lineWidth: 1)
            )
            .shadow(color: DS.accent.opacity(0.35), radius: 10, y: 4)
            
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    let title = state.mediaService.trackTitle
                    Text(title.isEmpty ? "Not playing" : title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(title.isEmpty ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                        .optionalHelp(title)
                    
                    if !title.isEmpty {
                        Text(state.mediaService.artist)
                            .font(DS.Typo.body)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                // Same deterministic bars as the notch; held still under Reduce Motion.
                WaveBars(isPlaying: state.mediaService.isPlaying && !reduceMotion, bars: 7, height: 18, barWidth: 3)
                    // The panel stays mounted after it's ordered out; don't tick behind it.
                    .environment(\.isIslandLayerVisible, state.isLiveActivityPresented)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                
                // Transport Buttons
                HStack(spacing: DS.Space.lg) {
                    Button {
                        state.mediaService.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.textPrimary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DroppyPressStyle())
                    .help("Previous track")
                    .accessibilityLabel("Previous track")
                    
                    Button {
                        state.mediaService.togglePlayPause()
                    } label: {
                        Image(systemName: state.mediaService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.accent)
                            .contentShape(Circle())
                    }
                    .buttonStyle(DroppyPressStyle())
                    .help(state.mediaService.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .accessibilityLabel(state.mediaService.isPlaying ? "Pause" : "Play")
                    
                    Button {
                        state.mediaService.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.textPrimary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DroppyPressStyle())
                    .help("Next track")
                    .accessibilityLabel("Next track")
                }
            }
            
            Spacer()
        }
        .padding(DS.Space.lg)
        .dsSurface(1, radius: DS.Radius.lg)
    }
    
    private var telemetryCard: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: 16) {
                // CPU Gauge
                VStack(spacing: DS.Space.xs) {
                    Text("CPU")
                        .font(DS.Typo.caption.weight(.bold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    
                    ZStack {
                        Circle()
                            .stroke(DS.Palette.track, lineWidth: 5)
                            .frame(width: 54, height: 54)
                        Circle()
                            .trim(from: 0, to: state.systemMonitor.cpuUsage)
                            .stroke(DS.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(state.systemMonitor.cpuUsage * 100))%")
                            .font(DS.Typo.numeric)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU")
                .accessibilityValue("\(Int(state.systemMonitor.cpuUsage * 100)) percent")
                
                // Memory Gauge
                VStack(spacing: DS.Space.xs) {
                    Text("RAM")
                        .font(DS.Typo.caption.weight(.bold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    
                    ZStack {
                        Circle()
                            .stroke(DS.Palette.track, lineWidth: 5)
                            .frame(width: 54, height: 54)
                        Circle()
                            .trim(from: 0, to: state.systemMonitor.memoryUsage)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(state.systemMonitor.memoryUsage * 100))%")
                            .font(DS.Typo.numeric)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Memory")
                .accessibilityValue("\(Int(state.systemMonitor.memoryUsage * 100)) percent")
                
                // Battery Gauge
                VStack(spacing: DS.Space.xs) {
                    Text("BATTERY")
                        .font(DS.Typo.caption.weight(.bold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    
                    ZStack {
                        Circle()
                            .stroke(DS.Palette.track, lineWidth: 5)
                            .frame(width: 54, height: 54)
                        Circle()
                            .trim(from: 0, to: CGFloat(state.systemMonitor.batteryLevel) / 100.0)
                            .stroke(DS.Palette.success, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))
                        Text(state.systemMonitor.hasBattery ? "\(state.systemMonitor.batteryLevel)%" : "AC")
                            .font(DS.Typo.numeric)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery")
                .accessibilityValue(state.systemMonitor.hasBattery ? "\(state.systemMonitor.batteryLevel) percent" : "On power adapter")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DS.Space.lg)
        .dsSurface(1, radius: DS.Radius.lg)
    }
    
    /// Says what Start will do: begin, resume focus, or resume the break.
    private var pomodoroStatusText: String {
        switch (state.isPomodoroActive, state.pomodoroHasStarted, state.isPomodoroWorkCycle) {
        case (true, _, true): "Focus timer is running in the notch."
        case (true, _, false): "Break is running. Step away for a bit."
        case (false, false, _): "Press Start to begin a \(pomodoroSettings.workMinutes)-minute focus session."
        case (false, true, true): "Focus paused. Press Start to resume."
        case (false, true, false): "Break paused. Press Start to resume."
        }
    }

    private var pomodoroRingCard: some View {
        HStack(spacing: 18) {
            // Dial Ring
            ZStack {
                Circle()
                    .stroke(DS.Palette.track, lineWidth: 6)
                    .frame(width: 76, height: 76)
                
                let progress = 1.0 - (Double(state.pomodoroSecondsRemaining) / Double(max(state.pomodoroCycleSeconds, 1)))
                Circle()
                    .trim(from: 0, to: max(0.01, progress))
                    .stroke(
                        state.isPomodoroWorkCycle ? NotchPalette.calendarRed : DS.Palette.success,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 1) {
                    Text(state.formattedPomodoroTime)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(state.isPomodoroWorkCycle ? "FOCUS" : "BREAK")
                        .font(DS.Typo.micro)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.isPomodoroWorkCycle ? "Focus time left" : "Break time left")
            .accessibilityValue(state.formattedPomodoroTime)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(state.isPomodoroWorkCycle ? "Deep focus session" : "Rest & recharge")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                Text(pomodoroStatusText)
                    .font(DS.Typo.label)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    Button {
                        if state.isPomodoroActive {
                            state.pausePomodoro()
                        } else {
                            state.startPomodoro()
                        }
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: state.isPomodoroActive ? "pause.fill" : "play.fill")
                                .accessibilityHidden(true)
                            Text(state.isPomodoroActive ? "Pause" : "Start")
                        }
                        .font(DS.Typo.labelStrong)
                        .padding(.horizontal, DS.Space.md)
                        .frame(height: 24)
                        .background(Capsule().fill(state.isPomodoroActive ? DS.Palette.warning : DS.accent))
                        .foregroundStyle(.white)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(DroppyPressStyle(scale: 0.95))
                    .help(state.isPomodoroActive ? "Pause the Pomodoro timer" : "Start the Pomodoro timer")
                    
                    DroppyPillButton("Reset", tone: .plain, help: "Reset the Pomodoro timer") {
                        state.resetPomodoro()
                    }
                }
            }
            
            Spacer()
        }
        .padding(DS.Space.lg)
        .dsSurface(1, radius: DS.Radius.lg)
    }
}

private extension LiveActivityMode {
    var shortTitle: String {
        switch self {
        case .mediaAndFocus: "Media"
        case .systemTelemetry: "System"
        case .pomodoroCountdown: "Focus"
        }
    }
}
