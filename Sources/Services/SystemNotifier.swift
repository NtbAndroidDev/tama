import Foundation
import UserNotifications

/// Posts macOS notifications (Notification Center) for events worth seeing
/// even when the notch isn't in view, such as the end of a Pomodoro cycle.
@MainActor
public enum SystemNotifier {
    /// UNUserNotificationCenter traps outside an app bundle (`swift run`).
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    public static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
