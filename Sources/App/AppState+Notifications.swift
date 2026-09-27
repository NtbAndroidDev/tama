import SwiftUI
import Combine

// The notch banner.

extension AppState {
    // MARK: - Notification HUD
    public func showNotification(appName: String, title: String, message: String, icon: String = "bell.badge.fill",
                                 actionTitle: String? = nil, action: (@MainActor @Sendable () -> Void)? = nil,
                                 dismissTitle: String? = nil, duration: TimeInterval = 4.5) {
        let notif = DroppyNotification(appName: appName, title: title, message: message, iconSystemName: icon,
                                       actionTitle: actionTitle, action: action, dismissTitle: dismissTitle)
        present(notif, duration: duration)
    }

    /// Puts a prepared banner up (Notification HUD's mirrored ones come this way).
    public func present(_ notification: DroppyNotification, duration: TimeInterval) {
        withAnimation(DroppyLayout.springAnimation) {
            self.activeNotification = notification
        }
        lastNotificationDuration = duration
        scheduleNotificationDismiss(after: duration)
    }

    func scheduleNotificationDismiss(after delay: TimeInterval) {
        notificationDismiss?.cancel()
        guard let id = activeNotification?.id else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeNotification?.id == id else { return }
            withAnimation(DroppyLayout.springAnimation) { self.activeNotification = nil }
        }
        notificationDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Keeps a banner up while the pointer rests on it, so its action can be reached.
    public func holdNotification(_ isHovering: Bool) {
        if isHovering {
            notificationDismiss?.cancel()
        } else {
            scheduleNotificationDismiss(after: activeNotification?.isMirrored == true ? min(lastNotificationDuration, 3) : 2)
        }
    }
}
