import Foundation

/// Why Tama's clock work is standing down. Sleep and screen-off arrive as
/// separate notifications and overlap freely — closing a lid sends both, and
/// they are not answered in a fixed order — so the last one to end is the one
/// that wakes the pollers, the way `ModalOwners` holds the shelf open.
struct DormancyReasons: Equatable {
    enum Reason: Hashable {
        /// `NSWorkspace.willSleepNotification` — the Mac is going to sleep.
        case systemSleep
        /// `NSWorkspace.screensDidSleepNotification` — the screen went off
        /// while the Mac stayed awake.
        case displaySleep
    }

    private var active: Set<Reason> = []

    /// Nothing Tama draws can be seen.
    var isDormant: Bool { !active.isEmpty }

    mutating func set(_ dormant: Bool, reason: Reason) {
        if dormant { active.insert(reason) } else { active.remove(reason) }
    }
}
