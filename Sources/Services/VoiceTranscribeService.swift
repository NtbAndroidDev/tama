import AppKit
import AVFoundation
import Speech

/// A finished voice note: the .m4a on disk plus what was said in it.
public struct VoiceRecording: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let date: Date
    public var duration: TimeInterval
    public var transcript: String
    public let localeID: String
    /// Settings › Recordings › Delete audio after transcription removed the
    /// .m4a; the text stays. Optional so older saved lists still decode.
    public var audioDeleted: Bool?

    @MainActor public var url: URL { VoiceTranscribeService.recordingsDirectory.appendingPathComponent(fileName) }
    public var title: String { (fileName as NSString).deletingPathExtension }
    public var hasAudio: Bool { audioDeleted != true }

    public var wordCount: Int { VoiceTranscribeService.wordCount(transcript) }
}

/// Voice Transcribe: records the microphone to AAC while streaming the same
/// audio into Speech, on-device when the locale supports it. Also transcribes
/// dropped audio and video files.
@MainActor
public final class VoiceTranscribeService: ObservableObject {
    public static let shared = VoiceTranscribeService()

    public enum Phase: Equatable, Sendable {
        case idle, starting, recording
        /// Audio stopped; waiting for Speech to finalize the last words (live transcription).
        case finishing
        /// A whole file goes through Speech: a dropped file, a recording just
        /// stopped (live transcription off) or a saved one being re-transcribed.
        case transcribingFile
    }

    public enum Access: Sendable {
        case granted, denied, notDetermined
        /// Running outside an app bundle with the usage description, where
        /// touching the API would crash instead of prompting.
        case unavailable
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var transcript = ""
    @Published public private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0…1, oldest first; drawn as the waveform.
    @Published public private(set) var levels: [Float] = Array(repeating: 0, count: VoiceTranscribeService.levelHistory)
    @Published public private(set) var recents: [VoiceRecording] = []
    @Published public private(set) var playingID: UUID?
    @Published public private(set) var micAccess: Access = .notDetermined
    @Published public private(set) var speechAccess: Access = .notDetermined
    /// Something went wrong that the user should see; cleared on the next action.
    @Published public var message: String?
    /// The recording the transcript on screen belongs to, if any.
    @Published public private(set) var currentRecordingID: UUID?
    /// Name of the file being (or last) transcribed, when the text came from a file.
    @Published public private(set) var sourceFileName: String?
    /// 0…1 while a file is transcribed ("Transcribing… 40%").
    @Published public private(set) var progress: Double = 0
    /// The "Transcription · N words" card is up (off with Skip result window).
    @Published public var showsResult = false
    /// The saved recording a file transcription writes its text into.
    @Published public private(set) var transcriptionTargetID: UUID?
    @Published public var localeID: String {
        didSet {
            UserDefaults.standard.set(localeID, forKey: Self.localeKey)
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        }
    }
    @Published public private(set) var recognizer: SFSpeechRecognizer?

    public static let levelHistory = 28
    private static let localeKey = "voiceTranscribeLocale"
    private static let recentsKey = "voiceTranscribeRecents"
    private static let recentsLimit = 5

    private var engine: AVAudioEngine?
    private var sink: CaptureSink?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var ticker: Timer?
    private var configObserver: NSObjectProtocol?
    private var finishTimeout: DispatchWorkItem?

    // Recognition runs as a chain of tasks; each one's text lives under its
    // generation number so late finals from an earlier task land in order.
    private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    private var segments: [Int: String] = [:]
    private var nextGeneration = 0
    private var sessionFirstGeneration = 0
    private var currentGeneration = -1
    private var taskStartedAt = Date()
    private var quickFailures = 0

    private var player: AVAudioPlayer?
    private let playerDelegate = PlayerDelegate()

    /// Length of the file being transcribed, for the progress.
    private var fileDuration: TimeInterval = 0
    private var fileStartedAt = Date()
    private var progressTicker: Timer?
    /// Settings › Show recording icon in menu bar.
    private var statusItem: NSStatusItem?

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.localeKey)
        let initial = saved ?? Self.defaultLocaleID()
        localeID = initial
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: initial))
        loadRecents()
        refreshAccess()
    }

    // MARK: Locales

    /// Speech's own spelling of the user's locale, or English when Speech can't do it.
    private static func defaultLocaleID() -> String {
        let supported = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        if let match = supported.first(where: { $0.replacingOccurrences(of: "_", with: "-") == current }) { return match }
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return supported.first { $0.hasPrefix(language + "-") } ?? "en-US"
    }

    /// The current locale, Vietnamese and US English first, then everything else Speech supports.
    public var pinnedLocales: [String] {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        var pinned: [String] = []
        for id in [Self.defaultLocaleID(), "vi-VN", "en-US"] where supported.contains(id) && !pinned.contains(id) {
            pinned.append(id)
        }
        return pinned
    }

    public var otherLocales: [String] {
        let pinned = Set(pinnedLocales)
        return SFSpeechRecognizer.supportedLocales().map(\.identifier)
            .filter { !pinned.contains($0) }
            .sorted { Self.displayName($0) < Self.displayName($1) }
    }

    public static func displayName(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    public var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    /// Where Speech will run with the chosen engine, or nil when the engine
    /// can't handle this language (On-device only without a local model).
    public var effectiveOnDevice: Bool? {
        switch VoiceSettings.shared.engine {
        case .auto: isOnDevice
        case .onDevice: isOnDevice ? true : nil
        case .server: false
        }
    }

    nonisolated public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    // MARK: Permissions

    public func refreshAccess() {
        micAccess = Self.microphoneAccess()
        speechAccess = Self.speechAccess()
    }

    static func microphoneAccess() -> Access {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func speechAccess() -> Access {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else { return .unavailable }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Built outside the main actor: Speech calls back on its own queue.
    nonisolated static func requestSpeechAuthorization() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }
    }

    public static func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    public static func openSpeechSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
    }

    private func ensureSpeechAccess() async {
        refreshAccess()
        if speechAccess == .notDetermined {
            await Self.requestSpeechAuthorization()
            refreshAccess()
        }
    }

    // MARK: Recording

    /// The Quick Record shortcut: shows the recorder (inline in the island, or
    /// the floating panel) and starts recording, or stops the one running.
    /// Recording is never hidden: the recorder, the notch activity and the
    /// menu bar icon all show it.
    public func quickRecord() {
        if phase == .recording { return stopRecording() }
        presentRecorder()
        if phase == .idle {
            showsResult = false
            Task { await startRecording() }
        }
    }

    /// Brings the recorder on screen where Settings says.
    public func presentRecorder() {
        // With the shelf switched off there's no inline recorder to open.
        if VoiceSettings.shared.floatingRecorder || !ShelfSettings.shared.isEnabled {
            VoiceRecorderPanelController.shared.show()
        } else {
            let state = AppState.shared
            state.open(.widgets)
            state.activeDropletID = "voiceTranscribe"
        }
    }

    public func toggleRecording() {
        switch phase {
        case .idle: Task { await startRecording() }
        case .recording: stopRecording()
        case .transcribingFile: cancelFileTranscription()
        case .starting, .finishing: break
        }
    }

    public func startRecording() async {
        guard phase == .idle else { return }
        phase = .starting
        message = nil
        stopPlayback()
        showsResult = false
        refreshAccess()
        if micAccess == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshAccess()
        }
        guard micAccess == .granted else {
            phase = .idle
            message = micAccess == .unavailable
                ? "Recording needs the Tama app bundle."
                : "Tama can't hear the microphone."
            return
        }
        await ensureSpeechAccess()
        do {
            try beginCapture()
        } catch {
            teardownCapture()
            if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
            recordingURL = nil
            phase = .idle
            message = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    private func beginCapture() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw VoiceError.noInput }
        // AAC tops out at 48 kHz, and Speech only needs mono.
        let rate = min(inputFormat.sampleRate, 48_000)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
        else { throw VoiceError.noInput }

        let url = Self.recordingsDirectory.appendingPathComponent("\(Self.fileStamp()).m4a")
        recordingURL = url
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let sink = try CaptureSink(input: inputFormat, output: outputFormat, file: file, onLevel: Self.levelHandler())
        self.sink = sink
        self.engine = engine

        segments = [:]
        tasks = [:]
        transcript = ""
        sourceFileName = nil
        currentRecordingID = nil
        quickFailures = 0
        sessionFirstGeneration = nextGeneration
        currentGeneration = -1
        levels = Array(repeating: 0, count: Self.levelHistory)
        // Live transcription streams as you talk; otherwise the saved file is
        // transcribed after Stop, with progress.
        if speechAccess == .granted, VoiceSettings.shared.liveTranscription, effectiveOnDevice != nil {
            startRecognitionTask()
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: Self.tapBlock(sink))
        engine.prepare()
        try engine.start()

        // A headset plugged in mid-recording invalidates the tap's format.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let service = VoiceTranscribeService.shared
                guard service.phase == .recording else { return }
                service.stopRecording()
                service.message = "The audio input changed, so recording stopped."
            }
        }

        startedAt = Date()
        elapsed = 0
        phase = .recording
        let ticker = Timer(timeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in VoiceTranscribeService.shared.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        publishActivity()
        updateStatusItem()
        if GeneralSettings.shared.soundEffects { NSSound(named: "Tink")?.play() }
    }

    public func stopRecording() {
        guard phase == .recording else { return }
        tick()
        teardownCapture()
        LiveActivityCenter.shared.end("voiceTranscribe")
        removeStatusItem()
        phase = .finishing
        if GeneralSettings.shared.soundEffects { NSSound(named: "Pop")?.play() }
        guard tasks[currentGeneration] != nil else { return finishSession() }
        // Speech normally finalizes within a second; don't hang on it forever.
        let work = DispatchWorkItem { VoiceTranscribeService.shared.finishSession() }
        finishTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func teardownCapture() {
        ticker?.invalidate()
        ticker = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        sink?.swapRequest(nil)?.endAudio()
        // Releasing the file is what writes the AAC trailer.
        sink?.closeFile()
        sink = nil
        levels = Array(repeating: 0, count: Self.levelHistory)
    }

    private func finishSession() {
        guard phase == .finishing else { return }
        finishTimeout?.cancel()
        finishTimeout = nil
        phase = .idle
        guard let url = recordingURL else { return }
        recordingURL = nil
        guard elapsed >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let recording = VoiceRecording(id: UUID(), fileName: url.lastPathComponent, date: startedAt ?? Date(),
                                       duration: elapsed, transcript: transcript, localeID: localeID)
        currentRecordingID = recording.id
        recents.insert(recording, at: 0)
        trimRecents()
        saveRecents()
        if !transcript.isEmpty {
            // Live transcription already has the text.
            transcriptionFinished(for: recording.id)
        } else if speechAccess == .granted, !VoiceSettings.shared.liveTranscription {
            retranscribe(recording)
        }
    }

    private func tick() {
        guard phase == .recording, let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        publishActivity()
        updateStatusItem()
        // Server recognition stops after about a minute, so hand over to a
        // fresh task well before that. On-device has no hard cap but still
        // gets slower with very long requests.
        let limit: TimeInterval = isOnDevice ? 180 : 50
        if currentGeneration >= sessionFirstGeneration, speechAccess == .granted,
           Date().timeIntervalSince(taskStartedAt) > limit {
            startRecognitionTask()
        }
    }

    private func publishActivity() {
        LiveActivityCenter.shared.post(LiveActivity(
            id: "voiceTranscribe", icon: "mic.fill", tint: DS.Palette.danger,
            trailing: .text(TimerService.format(elapsed, compact: true)), priority: .ambient,
            label: "Recording \(TimerService.format(elapsed))"
        ))
    }

    private func pushLevel(_ level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    // MARK: Recognition

    private func startRecognitionTask() {
        guard let recognizer, recognizer.isAvailable, let sink else {
            if recognizer?.isAvailable == false { message = "Speech recognition is unavailable right now." }
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        let generation = nextGeneration
        nextGeneration += 1
        currentGeneration = generation
        taskStartedAt = Date()
        tasks[generation] = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(generation))
        // Swapping between two buffers means no audio is lost at the seam.
        sink.swapRequest(request)?.endAudio()
    }

    private func configure(_ request: SFSpeechRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = effectiveOnDevice ?? true
    }

    private func handleResult(generation: Int, text: String?, isFinal: Bool, failed: Bool, processed: TimeInterval? = nil) {
        guard generation >= sessionFirstGeneration else { return }
        if let text { segments[generation] = text }
        if phase == .transcribingFile, let processed, fileDuration > 0 {
            progress = max(progress, min(processed / fileDuration, 0.99))
        }
        let ended = isFinal || failed
        if ended { tasks[generation] = nil }
        rebuildTranscript()

        guard generation == currentGeneration, ended else { return }
        switch phase {
        case .recording:
            // The task ended on its own (a pause, a server limit); keep listening.
            quickFailures = failed && Date().timeIntervalSince(taskStartedAt) < 2 ? quickFailures + 1 : 0
            if quickFailures < 3 {
                startRecognitionTask()
            } else {
                message = "Speech recognition keeps failing; recording continues without text."
            }
        case .finishing:
            finishSession()
        case .transcribingFile:
            stopProgressTicker()
            progress = 1
            phase = .idle
            let target = transcriptionTargetID
            transcriptionTargetID = nil
            if transcript.isEmpty {
                message = failed ? "Couldn't transcribe this audio." : "No speech detected in this recording."
            } else if let target, let index = recents.firstIndex(where: { $0.id == target }) {
                recents[index].transcript = transcript
                saveRecents()
                transcriptionFinished(for: target)
            } else {
                transcriptionFinished(for: nil)
            }
        case .idle, .starting:
            break
        }
    }

    private func rebuildTranscript() {
        transcript = segments.keys.sorted()
            .compactMap { segments[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Late finals after the timeout still belong to the saved recording.
        if phase == .idle, let id = currentRecordingID, let index = recents.firstIndex(where: { $0.id == id }),
           recents[index].transcript != transcript {
            recents[index].transcript = transcript
            saveRecents()
        }
    }

    // MARK: Files

    public func transcribeFile(_ url: URL) {
        guard phase == .idle else { return }
        transcribe(url, target: nil, sourceName: url.lastPathComponent)
    }

    /// Runs a saved recording through Speech again (another language or
    /// engine, or it was saved without text) and stores the new text on it.
    public func retranscribe(_ recording: VoiceRecording) {
        guard phase == .idle else { return }
        guard recording.hasAudio, FileManager.default.fileExists(atPath: recording.url.path) else {
            message = "The audio of this recording was deleted."
            return
        }
        currentRecordingID = recording.id
        transcribe(recording.url, target: recording.id, sourceName: nil)
    }

    private func transcribe(_ url: URL, target: UUID?, sourceName: String?) {
        stopPlayback()
        message = nil
        showsResult = false
        phase = .starting
        Task {
            let asset = AVURLAsset(url: url)
            let tracks = try? await asset.loadTracks(withMediaType: .audio)
            guard let tracks, !tracks.isEmpty else {
                phase = .idle
                message = "\(url.lastPathComponent) has no audio to transcribe."
                return
            }
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            await ensureSpeechAccess()
            guard speechAccess == .granted else {
                phase = .idle
                message = "Transcribing needs Speech Recognition access."
                return
            }
            guard let recognizer, recognizer.isAvailable else {
                phase = .idle
                message = "Speech recognition is unavailable for \(Self.displayName(localeID))."
                return
            }
            guard effectiveOnDevice != nil else {
                phase = .idle
                message = "\(Self.displayName(localeID)) has no on-device model. Pick another language, or allow the server engine in Settings."
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            configure(request)
            segments = [:]
            tasks = [:]
            transcript = ""
            if target == nil { currentRecordingID = nil }
            transcriptionTargetID = target
            sourceFileName = sourceName
            fileDuration = duration.isFinite ? duration : 0
            progress = 0
            sessionFirstGeneration = nextGeneration
            let generation = nextGeneration
            nextGeneration += 1
            currentGeneration = generation
            taskStartedAt = Date()
            fileStartedAt = Date()
            phase = .transcribingFile
            startProgressTicker()
            tasks[generation] = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(generation))
        }
    }

    public func cancelFileTranscription() {
        guard phase == .transcribingFile else { return }
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        // Late callbacks from the cancelled task are ignored from here on.
        sessionFirstGeneration = nextGeneration
        stopProgressTicker()
        transcriptionTargetID = nil
        phase = .idle
    }

    /// Speech's partial results carry timestamps, but not always early on;
    /// until they do, an estimate from elapsed time (capped below 100%) keeps
    /// the percentage moving. The larger of the two is shown.
    private func startProgressTicker() {
        stopProgressTicker()
        let ticker = Timer(timeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in VoiceTranscribeService.shared.estimateProgress() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        progressTicker = ticker
    }

    private func stopProgressTicker() {
        progressTicker?.invalidate()
        progressTicker = nil
    }

    private func estimateProgress() {
        guard phase == .transcribingFile else { return stopProgressTicker() }
        // On-device Speech handles roughly 3–5× real time; a conservative guess.
        let expected = max(fileDuration / 3, 1.5)
        let estimate = min(Date().timeIntervalSince(fileStartedAt) / expected, 1) * 0.95
        progress = max(progress, estimate)
    }

    /// Text is ready: copy it straight away (Skip result window) or show the
    /// result card, and apply Delete audio after transcription.
    private func transcriptionFinished(for recordingID: UUID?) {
        let state = AppState.shared
        if let recordingID, VoiceSettings.shared.retention == .deleteAudio,
           let index = recents.firstIndex(where: { $0.id == recordingID }), recents[index].hasAudio {
            if playingID == recordingID { stopPlayback() }
            try? FileManager.default.removeItem(at: recents[index].url)
            recents[index].audioDeleted = true
            saveRecents()
        }
        guard !transcript.isEmpty else { return }
        if VoiceSettings.shared.skipResult {
            copy(transcript)
            showsResult = false
        } else {
            showsResult = true
            // The shelf closed while it worked: say it's ready, with a Copy button.
            let onScreen = VoiceRecorderPanelController.shared.isVisible
                || (state.isIslandExpanded && state.shelfPage == .widgets && state.activeDropletID == "voiceTranscribe")
            if !onScreen {
                let text = transcript
                state.showNotification(appName: "Voice Transcribe", title: "Transcription ready",
                                       message: Self.preview(text), icon: "waveform.badge.mic",
                                       actionTitle: "Copy", action: { VoiceTranscribeService.shared.copy(text) })
            }
        }
    }

    // MARK: Actions

    public var currentRecording: VoiceRecording? {
        currentRecordingID.flatMap { id in recents.first { $0.id == id } }
    }

    /// Puts a saved recording's text up on the result card.
    public func show(_ recording: VoiceRecording) {
        guard phase == .idle, !recording.transcript.isEmpty else { return }
        segments = [:]
        transcript = recording.transcript
        currentRecordingID = recording.id
        sourceFileName = nil
        showsResult = true
    }

    public func clear() {
        guard phase == .idle else { return }
        showsResult = false
        segments = [:]
        transcript = ""
        currentRecordingID = nil
        sourceFileName = nil
        message = nil
    }

    public func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        AppState.shared.showNotification(appName: "Voice Transcribe", title: "Text Copied", message: Self.preview(text))
    }

    /// Copies into a temporary folder so the Tray keeps its own file, which
    /// survives this recording rolling off the recent list.
    public func addToTray(_ recording: VoiceRecording) {
        guard recording.hasAudio, let copy = Self.temporaryCopy(of: recording.url) else {
            message = "The recording file is missing."
            return
        }
        AppState.shared.addShelfItems([ShelfItem(url: copy)])
        AppState.shared.showNotification(appName: "Voice Transcribe", title: "Added to Tray", message: recording.fileName)
    }

    public func saveTranscriptToTray(_ text: String, name: String) {
        guard !text.isEmpty else { return }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("\(name).txt")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            message = "Couldn't save the transcript: \(error.localizedDescription)"
            return
        }
        AppState.shared.addShelfItems([ShelfItem(url: url)])
        AppState.shared.showNotification(appName: "Voice Transcribe", title: "Transcript in Tray", message: url.lastPathComponent)
    }

    /// Base name for the transcript on screen.
    public var transcriptName: String {
        if let currentRecording { return currentRecording.title }
        if let sourceFileName { return "\((sourceFileName as NSString).deletingPathExtension) transcript" }
        return "Transcript \(Self.fileStamp())"
    }

    public func delete(_ recording: VoiceRecording) {
        if playingID == recording.id { stopPlayback() }
        try? FileManager.default.removeItem(at: recording.url)
        recents.removeAll { $0.id == recording.id }
        if currentRecordingID == recording.id { currentRecordingID = nil }
        saveRecents()
    }

    // MARK: Menu bar indicator

    /// A red mic with the time in the menu bar while recording; click to stop.
    /// Also shown when the island is hidden, so a recording is always visible.
    private func updateStatusItem() {
        guard phase == .recording, VoiceSettings.shared.menuBarIcon || AppState.shared.isIslandHidden else {
            return removeStatusItem()
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = StatusItemTarget.shared
            item.button?.action = #selector(StatusItemTarget.stop)
            item.button?.toolTip = "Voice Transcribe is recording. Click to stop."
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            image?.isTemplate = false
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
            statusItem = item
        }
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: " " + TimerService.format(elapsed, compact: true),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.systemRed]
        )
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: Playback

    public func togglePlayback(_ recording: VoiceRecording) {
        if playingID == recording.id { return stopPlayback() }
        stopPlayback()
        guard phase == .idle, recording.hasAudio else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: recording.url)
            player.delegate = playerDelegate
            player.play()
            self.player = player
            playingID = recording.id
        } catch {
            message = "Couldn't play \(recording.fileName)."
        }
    }

    public func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
    }

    fileprivate func playbackFinished() {
        player = nil
        playingID = nil
    }

    // MARK: Persistence

    /// Beside the Tray folder rather than inside it: the Tray deletes any
    /// folder it doesn't list at launch, and these outlive the Tray.
    static var recordingsDirectory: URL {
        let dir = AppState.trayStorageDirectory.deletingLastPathComponent()
            .appendingPathComponent("Voice Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey),
              let saved = try? JSONDecoder().decode([VoiceRecording].self, from: data) else { return }
        recents = saved.filter { !$0.hasAudio || FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    /// Only with Settings › Recordings › Keep the last 5; otherwise recordings
    /// stay until deleted.
    private func trimRecents() {
        guard VoiceSettings.shared.retention == .lastFive, recents.count > Self.recentsLimit else { return }
        for old in recents[Self.recentsLimit...] {
            if playingID == old.id { stopPlayback() }
            try? FileManager.default.removeItem(at: old.url)
        }
        recents.removeLast(recents.count - Self.recentsLimit)
    }

    // MARK: Helpers

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Voice \(formatter.string(from: Date()))"
    }

    private static func temporaryCopy(of url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func preview(_ text: String) -> String {
        text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    // These closures run on audio and Speech queues, so they are built in a
    // nonisolated context; closures formed on the main actor would inherit
    // its isolation and trap when called elsewhere.

    nonisolated private static func tapBlock(_ sink: CaptureSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.consume(buffer) }
    }

    nonisolated private static func levelHandler() -> @Sendable (Float) -> Void {
        { level in Task { @MainActor in VoiceTranscribeService.shared.pushLevel(level) } }
    }

    nonisolated private static func resultHandler(_ generation: Int) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            let processed = result?.bestTranscription.segments.last.map { $0.timestamp + $0.duration }
            Task { @MainActor in
                VoiceTranscribeService.shared.handleResult(generation: generation, text: text, isFinal: isFinal,
                                                           failed: failed, processed: processed)
            }
        }
    }
}

private enum VoiceError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone is available." }
}

/// Everything the audio thread touches, behind one lock: the tap runs off the
/// main thread, and the recognition request is swapped as tasks are chained.
private final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let converter: AVAudioConverter?
    private let output: AVAudioFormat
    private let onLevel: @Sendable (Float) -> Void
    private var lastLevelPost: CFTimeInterval = 0

    init(input: AVAudioFormat, output: AVAudioFormat, file: AVAudioFile, onLevel: @escaping @Sendable (Float) -> Void) throws {
        self.output = output
        self.file = file
        self.onLevel = onLevel
        if input == output {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else { throw VoiceError.noInput }
            converter.downmix = true
            self.converter = converter
        }
    }

    /// Installs `request` as the one buffers go to and returns the previous one.
    @discardableResult
    func swapRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = self.request
        self.request = request
        return old
    }

    func closeFile() {
        lock.lock()
        file = nil
        lock.unlock()
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let mono = convert(buffer) else { return }
        lock.lock()
        try? file?.write(from: mono)
        request?.append(mono)
        lock.unlock()

        let now = CACurrentMediaTime()
        guard now - lastLevelPost > 0.05 else { return }
        lastLevelPost = now
        onLevel(Self.level(of: mono))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        // The converter calls back synchronously on this thread, once per
        // chunk it wants; hand over this buffer exactly once.
        let pending = PendingBuffer(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            guard let next = pending.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    /// RMS mapped from a -50…0 dB window onto 0…1, which is where speech sits.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return min(max((db + 50) / 50, 0), 1)
    }
}

private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

@MainActor
private final class StatusItemTarget: NSObject {
    static let shared = StatusItemTarget()
    @objc func stop() { VoiceTranscribeService.shared.stopRecording() }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in VoiceTranscribeService.shared.playbackFinished() }
    }
}

extension PermissionService {
    /// Voice Transcribe's two permissions, in Settings' terms.
    static func voiceStatus(microphone: Bool) -> Status {
        let access = microphone ? VoiceTranscribeService.microphoneAccess() : VoiceTranscribeService.speechAccess()
        switch access {
        case .granted: return .granted
        case .notDetermined: return .notDetermined
        // Unbundled builds can't prompt; Settings is the only way forward.
        case .denied, .unavailable: return .denied
        }
    }

    func requestVoice(microphone: Bool) {
        let status = Self.voiceStatus(microphone: microphone)
        guard status == .notDetermined else {
            if microphone { VoiceTranscribeService.openMicrophoneSettings() } else { VoiceTranscribeService.openSpeechSettings() }
            return
        }
        Task {
            if microphone {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                await VoiceTranscribeService.requestSpeechAuthorization()
            }
            PermissionService.shared.refresh()
            VoiceTranscribeService.shared.refreshAccess()
        }
    }
}
