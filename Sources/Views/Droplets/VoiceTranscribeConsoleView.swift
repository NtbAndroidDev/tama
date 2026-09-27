import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Voice Transcribe droplet, laid out like the reference: idle is the list of
/// recordings over a big red record button; recording is a red live waveform
/// with the time and a stop ring; then "Transcribing… N%"; then a
/// "Transcription · N words" card with Close and Copy. Recording keeps going,
/// and shows in the notch and the menu bar, when the shelf closes.
public struct VoiceTranscribeConsoleView: View {
    public init() {}

    public var body: some View {
        VoiceRecorderView()
    }
}

/// The recorder itself, shared by the island console and the floating
/// recorder panel (Settings › External Recorder).
struct VoiceRecorderView: View {
    var isFloating = false
    @ObservedObject private var voice = VoiceTranscribeService.shared
    @ObservedObject private var state = AppState.shared
    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tint = Color(red: 0.93, green: 0.36, blue: 0.33)

    private enum Screen: Equatable { case idle, busy, recording, transcribing, result }

    private var screen: Screen {
        switch voice.phase {
        case .recording: return .recording
        case .starting, .finishing: return .busy
        case .transcribingFile: return .transcribing
        case .idle: return voice.showsResult && !voice.transcript.isEmpty ? .result : .idle
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            switch screen {
            case .idle: idleScreen
            case .busy: busyScreen
            case .recording: recordingScreen
            case .transcribing: transcribingScreen
            case .result: resultScreen
            }
            messageRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: screen)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: voice.message)
        .onAppear { voice.refreshAccess() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard voice.phase == .idle else { return false }
            DragDropService.shared.handleDrop(providers: providers) { items in
                guard let first = items.first else { return }
                voice.transcribeFile(first.url)
            }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay(Text("Drop audio or video to transcribe").font(DS.Typo.labelStrong).foregroundStyle(DS.accent))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Idle

    private var idleScreen: some View {
        VStack(spacing: DS.Space.sm) {
            header
            if voice.recents.isEmpty {
                DroppyEmptyState(systemName: "waveform", title: "No recordings yet",
                                 subtitle: "Press record and start talking, or drop an audio or video file here.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(voice.recents) { recording in
                            RecordingRow(recording: recording, isPlaying: voice.playingID == recording.id)
                            if recording.id != voice.recents.last?.id {
                                Rectangle().fill(DS.Palette.hairline).frame(height: 0.5).padding(.leading, DS.Space.sm)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            accessOrRecord
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            // In the island the page header already names the Droplet.
            if isFloating {
                Text("Voice Transcribe")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: DS.Space.sm)
            localeMenu
            DroppyIconButton("doc.badge.plus", size: 24, tone: .tonal, help: "Transcribe an audio or video file") {
                pickFile()
            }
        }
    }

    private var localeMenu: some View {
        Menu {
            ForEach(voice.pinnedLocales, id: \.self) { localeButton($0) }
            if !voice.otherLocales.isEmpty {
                Divider()
                ForEach(voice.otherLocales, id: \.self) { localeButton($0) }
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: engineSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(VoiceTranscribeService.displayName(voice.localeID))
                    .font(DS.Typo.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(.horizontal, DS.Space.sm)
            .frame(height: 22)
            .frame(maxWidth: 150)
            .background(Capsule().fill(DS.Palette.surface2))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(engineHelp)
        .accessibilityLabel("Language: \(VoiceTranscribeService.displayName(voice.localeID))")
        .accessibilityHint(engineHelp)
    }

    private var engineSymbol: String {
        switch voice.effectiveOnDevice {
        case .some(true): "cpu"
        case .some(false): "globe"
        case .none: "exclamationmark.triangle"
        }
    }

    private var engineHelp: String {
        switch voice.effectiveOnDevice {
        case .some(true): "Recognized on this Mac"
        case .some(false): "Recognized by Apple's servers"
        case .none: "No on-device model for this language; allow the server engine in Settings"
        }
    }

    private func localeButton(_ id: String) -> some View {
        Button {
            voice.localeID = id
        } label: {
            if id == voice.localeID {
                Label(VoiceTranscribeService.displayName(id), systemImage: "checkmark")
            } else {
                Text(VoiceTranscribeService.displayName(id))
            }
        }
    }

    @ViewBuilder
    private var accessOrRecord: some View {
        if voice.micAccess == .denied {
            accessCard(title: "Microphone access is off",
                       detail: "Allow Tama under Privacy & Security › Microphone. You can still transcribe files.",
                       action: VoiceTranscribeService.openMicrophoneSettings)
        } else if voice.micAccess == .unavailable {
            accessCard(title: "Recording isn't available here",
                       detail: "The microphone only works when Tama runs from Tama.app. You can still transcribe files.",
                       action: nil)
        } else {
            BigRecordButton { voice.toggleRecording() }
                .padding(.bottom, 2)
        }
    }

    // MARK: Recording

    private var recordingScreen: some View {
        VStack(spacing: DS.Space.md) {
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.md) {
                LiveWaveform(levels: voice.levels, tint: Self.tint)
                    .frame(height: 30)
                Text(TimerService.format(voice.elapsed))
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Self.tint)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Recording, \(TimerService.format(voice.elapsed))")
                StopRingButton { voice.stopRecording() }
            }
            .padding(.horizontal, DS.Space.md)
            if state.voiceLiveTranscription, !voice.transcript.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(voice.transcript)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 60)
                .padding(.horizontal, DS.Space.md)
            }
            Spacer(minLength: 0)
        }
    }

    private var busyScreen: some View {
        VStack(spacing: DS.Space.sm) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text(voice.phase == .finishing ? "Finishing…" : "Starting…")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .frame(maxHeight: .infinity)
    }

    // MARK: Transcribing

    private var transcribingScreen: some View {
        VStack(spacing: DS.Space.xs) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text("Transcribing…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.top, DS.Space.xs)
            Text("\(Int((voice.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(DS.Palette.textSecondary)
                .contentTransition(.numericText())
            if let name = voice.sourceFileName {
                Text(name)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            DroppyPillButton("Cancel", tone: .tonal, help: "Stop transcribing this file") {
                voice.cancelFileTranscription()
            }
            .padding(.top, DS.Space.sm)
        }
        .frame(maxHeight: .infinity)
        .animation(DS.Motion.respecting(reduceMotion, .linear(duration: 0.3)), value: voice.progress)
    }

    // MARK: Result

    private var resultScreen: some View {
        VStack(spacing: DS.Space.sm) {
            VStack(spacing: 1) {
                Text("Transcription")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                let words = VoiceTranscribeService.wordCount(voice.transcript)
                Text("\(words) \(words == 1 ? "word" : "words")")
                    .font(DS.Typo.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView(.vertical, showsIndicators: false) {
                Text(voice.transcript)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.md)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface1))
            HStack(spacing: DS.Space.sm) {
                Button("Close") { voice.showsResult = false }
                    .buttonStyle(ResultPillStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                    .help("Back to recordings (Esc)")
                DroppyIconButton("doc.text", size: 26, tone: .tonal, help: "Save the transcript to the Tray") {
                    voice.saveTranscriptToTray(voice.transcript, name: voice.transcriptName)
                }
                Spacer(minLength: 0)
                Button {
                    voice.copy(voice.transcript)
                    DroppyAudio.playCopySuccess()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(ResultPillStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy the transcript (⌘C)")
            }
        }
    }

    // MARK: Messages

    /// Errors get their own row, so they stay visible in every state.
    @ViewBuilder
    private var messageRow: some View {
        if let message = voice.message {
            HStack(spacing: DS.Space.sm) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.warning)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if voice.speechAccess == .denied {
                    DroppyPillButton("Open Settings", systemName: "gear", tone: .tonal,
                                     help: "Open Speech Recognition in System Settings") {
                        VoiceTranscribeService.openSpeechSettings()
                    }
                }
                DroppyIconButton("xmark", size: 20, help: "Dismiss") { voice.message = nil }
            }
            .transition(DS.Motion.transition(reduceMotion, .opacity))
        }
    }

    private func accessCard(title: String, detail: String, action: (() -> Void)?) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "mic.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Palette.danger)
                .frame(width: 34, height: 34)
                .background(Circle().fill(DS.Palette.danger.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                Text(detail).font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let action {
                DroppyPillButton("Open Settings", systemName: "gear", tone: .accent,
                                 help: "Open Microphone in System Settings", action: action)
            }
        }
        .frame(height: 50)
    }

    // MARK: Files

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Keep the island open while the panel has focus, or this console unmounts.
        state.setModal(true, owner: "voiceTranscribe.console")
        defer { state.setModal(false, owner: "voiceTranscribe.console") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voice.transcribeFile(url)
    }
}

// MARK: - Pieces

/// The reference's idle control: a red disc inside a grey ring.
private struct BigRecordButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            DroppyAudio.playTick()
            action()
        }) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 3)
                Circle().fill(VoiceRecorderView.tint).padding(6)
            }
            .frame(width: 50, height: 50)
            .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { hovering in withAnimation(DS.Motion.hover) { isHovered = hovering } }
        .help("Start recording")
        .accessibilityLabel("Start recording")
    }
}

/// White ring around a red rounded square: stop.
private struct StopRingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            DroppyAudio.playTick()
            action()
        }) {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(VoiceRecorderView.tint)
                    .frame(width: 16, height: 16)
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help("Stop recording")
        .accessibilityLabel("Stop recording")
    }
}

/// Levels so far as red bars from the left, the rest of the strip as dots.
private struct LiveWaveform: View {
    let levels: [Float]
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let slots = max(Int(geo.size.width / 5), 1)
            // The newest level sits at the right end of the filled run.
            let filled = levels.drop { $0 == 0 }.suffix(slots)
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<slots, id: \.self) { index in
                    if index < filled.count {
                        let level = CGFloat(filled[filled.startIndex + index])
                        Capsule()
                            .fill(tint)
                            .frame(width: 3, height: max(geo.size.height * level, 4))
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 2.5, height: 2.5)
                            .frame(width: 3)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .animation(DS.Motion.respecting(reduceMotion, .linear(duration: 0.08)), value: levels)
        }
        .accessibilityHidden(true)
    }
}

/// Close (grey capsule) and Copy (white pill) on the result card.
private struct ResultPillStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.headline)
            .foregroundStyle(prominent ? Color.black : DS.Palette.textPrimary)
            .padding(.horizontal, prominent ? 26 : 16)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? Color.white : DS.Palette.surface3))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(DS.Motion.snap, value: configuration.isPressed)
    }
}

private struct RecordingRow: View {
    let recording: VoiceRecording
    let isPlaying: Bool
    @State private var isHovered = false
    /// Deleting removes the audio file for good (there's no undo), so the
    /// trash button asks for a second click first, and the menu item asks too.
    @State private var confirmsDelete = false

    private var voice: VoiceTranscribeService { .shared }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.xs)
            if isHovered {
                HStack(spacing: 2) {
                    if recording.hasAudio {
                        DroppyIconButton(isPlaying ? "pause.fill" : "play.fill", size: 22, isActive: isPlaying,
                                         help: isPlaying ? "Stop" : "Play") { voice.togglePlayback(recording) }
                        DroppyIconButton("text.bubble", size: 22, help: "Transcribe this recording") { voice.retranscribe(recording) }
                    }
                    DroppyIconButton("doc.on.doc", size: 22, help: "Copy transcript") { voice.copy(recording.transcript) }
                        .disabled(recording.transcript.isEmpty)
                    if recording.hasAudio {
                        DroppyIconButton("tray.and.arrow.down", size: 22, help: "Add recording to Tray") { voice.addToTray(recording) }
                    }
                    DroppyIconButton(confirmsDelete ? "trash.fill" : "trash", size: 22, tone: .destructive,
                                     help: confirmsDelete ? "Click again to delete this recording" : "Delete recording") {
                        if confirmsDelete {
                            voice.delete(recording)
                        } else {
                            confirmsDelete = true
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Text(TimerService.format(recording.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isHovered ? DS.Palette.surface1 : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { isHovered = hovering }
            if !hovering { confirmsDelete = false }
        }
        .onTapGesture(count: 2) { if !recording.transcript.isEmpty { voice.show(recording) } }
        .help(recording.transcript.isEmpty ? "No transcript yet" : recording.transcript)
        .contextMenu {
            Button("Show Transcription") { voice.show(recording) }
                .disabled(recording.transcript.isEmpty)
            Button("Copy Transcript") { voice.copy(recording.transcript) }
                .disabled(recording.transcript.isEmpty)
            Button("Save Transcript to Tray") { voice.saveTranscriptToTray(recording.transcript, name: recording.title) }
                .disabled(recording.transcript.isEmpty)
            if recording.hasAudio {
                Button("Transcribe Again") { voice.retranscribe(recording) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
            }
            Divider()
            Button("Delete Recording…", role: .destructive) { confirmAndDelete() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recording.date.formatted(.dateTime.weekday(.wide).hour().minute()))
        .accessibilityValue(subtitle)
        .accessibilityAction(named: "Show transcription") {
            if !recording.transcript.isEmpty { voice.show(recording) }
        }
        .accessibilityAction(named: isPlaying ? "Stop" : "Play") {
            if recording.hasAudio { voice.togglePlayback(recording) }
        }
        .accessibilityAction(named: "Copy transcript") {
            if !recording.transcript.isEmpty { voice.copy(recording.transcript) }
        }
        .accessibilityAction(named: "Delete recording") { confirmAndDelete() }
    }

    /// The context menu and VoiceOver have no second click to wait for, so they ask.
    private func confirmAndDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete this recording?"
        alert.informativeText = "The audio and its transcript are removed. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let state = AppState.shared
        // Keep the island open while the alert has focus, or this console unmounts.
        state.setModal(true, owner: "voiceTranscribe.delete")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        state.setModal(false, owner: "voiceTranscribe.delete")
        guard response == .alertFirstButtonReturn else { return }
        voice.delete(recording)
    }

    private var subtitle: String {
        let date = recording.date.formatted(.dateTime.day().month(.abbreviated).year())
        if !recording.transcript.isEmpty { return "\(date) · \(recording.transcript)" }
        return recording.hasAudio ? date : "\(date) · audio deleted"
    }
}
