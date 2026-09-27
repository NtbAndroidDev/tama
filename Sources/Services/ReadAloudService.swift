import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Read Aloud: speaks a clip, a note or a text file with the system voice
/// (AVSpeechSynthesizer, on-device). One thing at a time; asking again
/// while it talks stops it. The notch shows a live activity while it reads.
@MainActor
final class ReadAloudService: NSObject, ObservableObject {
    static let shared = ReadAloudService()

    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private static let activityID = "readAloud"
    /// Long texts are cut here, so a stray 10 MB log isn't read for hours.
    static let maxCharacters = 20_000

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        if isSpeaking { stop(); return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: String(trimmed.prefix(Self.maxCharacters)))
        // The voice of the text's language when macOS can tell, else the system's.
        if let language = NSLinguisticTagger.dominantLanguage(for: trimmed),
           let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        isSpeaking = true
        LiveActivityCenter.shared.post(LiveActivity(
            id: Self.activityID, icon: "speaker.wave.2.fill", tint: .white, trailing: .spinner,
            priority: .ambient, label: "Reading aloud"))
        synthesizer.speak(utterance)
    }

    /// Reads a plain-text, Markdown, RTF or source file.
    func speak(fileAt url: URL) {
        let task = Task.detached(priority: .userInitiated) { () -> String? in
            if let rtf = try? NSAttributedString(url: url, options: [:], documentAttributes: nil), !rtf.string.isEmpty,
               ["rtf", "rtfd", "doc", "docx", "html", "htm"].contains(url.pathExtension.lowercased()) {
                return rtf.string
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        Task {
            guard let text = await task.value else {
                AppState.shared.showNotification(appName: "Read Aloud", title: "Can't read this file",
                                                 message: "Only text documents can be read aloud.", icon: "speaker.slash.fill")
                return
            }
            speak(text)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finished()
    }

    private func finished() {
        isSpeaking = false
        LiveActivityCenter.shared.end(Self.activityID)
    }

    /// Files Read Aloud can open.
    nonisolated static func canRead(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .sourceCode)
            || ["doc", "docx", "rtfd"].contains(url.pathExtension.lowercased())
    }
}

extension ReadAloudService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in ReadAloudService.shared.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in ReadAloudService.shared.finished() }
    }
}
