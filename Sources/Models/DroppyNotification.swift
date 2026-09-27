import SwiftUI

public struct DroppyNotification: Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let title: String
    public let message: String
    public let iconSystemName: String
    public let actionTitle: String?
    /// Runs when the action button is pressed; the banner closes afterwards.
    public let action: (@MainActor @Sendable () -> Void)?
    /// A labelled dismiss button ("OK") in place of the ✕.
    public let dismissTitle: String?
    public let timestamp: Date
    /// A notification mirrored from another app (Notification HUD): drawn
    /// with that app's real icon, no buttons but its reply.
    public let sourceBundleID: String?
    public let isMirrored: Bool
    
    public init(
        id: UUID = UUID(),
        appName: String,
        title: String,
        message: String,
        iconSystemName: String = "bell.badge.fill",
        actionTitle: String? = nil,
        action: (@MainActor @Sendable () -> Void)? = nil,
        dismissTitle: String? = nil,
        sourceBundleID: String? = nil,
        isMirrored: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.message = message
        self.iconSystemName = iconSystemName
        self.actionTitle = actionTitle
        self.action = action
        self.dismissTitle = dismissTitle
        self.timestamp = Date()
        self.sourceBundleID = sourceBundleID
        self.isMirrored = isMirrored
    }
}
