import SwiftUI

/// Settings › Droplets › Meetings.
@MainActor
public final class MeetingSettings: SettingsStore {
    public static let shared = MeetingSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "meetingPauseMedia", "meetingResumeMedia", "meetingPauseTrigger", "meetingCallHUD",
        "meetingMicLevel"
    ]

    /// Meetings › Pause media when a meeting starts (or, see the trigger, when the mic goes live).
    @AppStorage("meetingPauseMedia") public var pauseMedia: Bool = true
    @AppStorage("meetingResumeMedia") public var resumeMedia: Bool = true
    @AppStorage("meetingPauseTrigger") public var pauseTrigger: MeetingPauseTrigger = .callStarts
    /// Meetings › Show active call HUD: phone, elapsed time and the mic level in the notch.
    @AppStorage("meetingCallHUD") public var callHUD: Bool = true {
        didSet { MeetingControlService.shared.refreshCallActivity() }
    }
    @AppStorage("meetingMicLevel") public var micLevel: Bool = true {
        didSet { MeetingControlService.shared.refreshCallActivity() }
    }

    private init() { super.init(keys: Self.keys) }
}
