import AppKit
import ServiceManagement

/// Opens Tama when the user logs in, through the system's Login Items.
/// The switch reads the real registration, so it stays right if the user
/// removes Tama in System Settings › General › Login Items. It is re-read
/// whenever Tama comes to the front, since that's where approval happens.
@MainActor
public final class LaunchAtLoginService: ObservableObject {
    public static let shared = LaunchAtLoginService()

    /// Registered, whether or not the user has approved it yet. The switch
    /// shows this, so turning it off unregisters a pending approval too.
    @Published public private(set) var isEnabled = false
    /// Registered, but the user still has to allow it in Login Items.
    @Published public private(set) var needsApproval = false
    @Published public private(set) var lastError: String?
    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LaunchAtLoginService.shared.refresh() }
        }
    }

    public func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    public func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
