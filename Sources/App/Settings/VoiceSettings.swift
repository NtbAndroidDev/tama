import SwiftUI

/// Settings › Droplets › Voice Transcribe.
@MainActor
public final class VoiceSettings: SettingsStore {
    public static let shared = VoiceSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "voiceLiveTranscription", "voiceEngine", "voiceSkipResult", "voiceMenuBarIcon",
        "voiceRetention", "voiceFloatingRecorder"
    ]

    /// Stream text while recording; off transcribes the whole file after Stop, with progress.
    @AppStorage("voiceLiveTranscription") public var liveTranscription: Bool = false
    @AppStorage("voiceEngine") public var engine: VoiceEngine = .auto
    /// Copy the text as soon as it's ready instead of showing the result card.
    @AppStorage("voiceSkipResult") public var skipResult: Bool = false
    /// A red mic (with the time) in the menu bar while recording; click it to stop.
    @AppStorage("voiceMenuBarIcon") public var menuBarIcon: Bool = true
    @AppStorage("voiceRetention") public var retention: VoiceRetention = .keep
    /// Quick Record opens a floating recorder instead of expanding the island.
    @AppStorage("voiceFloatingRecorder") public var floatingRecorder: Bool = false

    private init() { super.init(keys: Self.keys) }
}
