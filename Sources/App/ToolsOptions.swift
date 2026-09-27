import Foundation

/// Voice Transcribe › Engine. Only Apple's Speech framework is available; these
/// choose where it may run.
public enum VoiceEngine: String, CaseIterable, Identifiable, Sendable {
    /// On this Mac when the language has an on-device model, Apple's servers otherwise.
    case auto
    /// Never leaves the Mac; languages without an on-device model can't be used.
    case onDevice
    /// Lets Speech use Apple's servers even when an on-device model exists.
    case server

    public var id: Self { self }

    public var title: String {
        switch self {
        case .auto: "Auto (best available)"
        case .onDevice: "On-device only"
        case .server: "Server allowed"
        }
    }

    public var detail: String {
        switch self {
        case .auto: "Uses the on-device model when your language has one, Apple's servers otherwise."
        case .onDevice: "Audio never leaves this Mac. Languages without an on-device model can't be transcribed."
        case .server: "Apple's servers may be used for any language; usually a little more accurate, needs internet."
        }
    }
}

/// Voice Transcribe › Recordings: what happens to the audio files.
public enum VoiceRetention: String, CaseIterable, Identifiable, Sendable {
    case keep
    case lastFive
    case deleteAudio

    public var id: Self { self }

    public var title: String {
        switch self {
        case .keep: "Keep until deleted"
        case .lastFive: "Keep the last 5"
        case .deleteAudio: "Delete audio after transcription"
        }
    }

    public var detail: String {
        switch self {
        case .keep: "Recordings are kept until you delete them."
        case .lastFive: "Older recordings are deleted as new ones come in."
        case .deleteAudio: "Audio is deleted right after transcription; the text stays in the list."
        }
    }
}

/// Menu Bar Manager › the toggle item's icon.
public enum MenuBarToggleIcon: String, CaseIterable, Identifiable, Sendable {
    case chevron, dot, ellipsis, eye, drop

    public var id: Self { self }

    public var title: String {
        switch self {
        case .chevron: "Chevron"
        case .dot: "Dot"
        case .ellipsis: "Ellipsis"
        case .eye: "Eye"
        case .drop: "Drop"
        }
    }

    /// The symbol while the hidden section is folded away, and while it's shown.
    public func symbol(revealed: Bool) -> String {
        switch self {
        case .chevron: revealed ? "chevron.right" : "chevron.left"
        case .dot: revealed ? "circle" : "circle.fill"
        case .ellipsis: revealed ? "ellipsis.circle.fill" : "ellipsis.circle"
        case .eye: revealed ? "eye" : "eye.slash"
        case .drop: revealed ? "drop" : "drop.fill"
        }
    }
}
