import AppKit
import ApplicationServices

/// What the screens are doing that the island should step aside for
/// (Settings › HUDs › Behavior):
///
/// - **Fullscreen**: a screen counts as fullscreen when the frontmost app's
///   focused window reports `AXFullScreen` (Accessibility), or when an
///   ordinary window covers the whole screen, menu bar included (games,
///   borderless players). Window bounds need no permission. It's re-checked on
///   Space and app switches, and every few seconds while a rule needs it.
/// - **Mission Control / App Exposé**: the Dock announces them to
///   Accessibility clients (`AXExposeShowAllWindows`, `…ShowFrontWindows`,
///   `…Exit`). Without Accessibility access nothing is heard and the island
///   simply stays up.
@MainActor
public final class ScreenStateService: ObservableObject {
    public static let shared = ScreenStateService()

    /// Displays showing a fullscreen app right now.
    @Published public private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []
    @Published public private(set) var isMissionControlActive = false

    private var observers: [NSObjectProtocol] = []
    private var poll: Timer?
    private var dockObserver: AXObserver?
    private var dockPID: pid_t = 0
    private var missionControlFailsafe: DispatchWorkItem?

    private init() {}

    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                let isSpace = note.name == NSWorkspace.activeSpaceDidChangeNotification
                MainActor.assumeIsolated {
                    let service = ScreenStateService.shared
                    // Switching Space or app always means Mission Control is over.
                    service.setMissionControl(false)
                    service.refreshFullscreen()
                    // The fullscreen slide takes a moment to land.
                    if isSpace {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { service.refreshFullscreen() }
                    }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ScreenStateService.shared.refreshFullscreen() }
        })
        sync()
    }

    /// Starts or stops what the settings need.
    public func sync() {
        if DisplaySettings.shared.fullscreenBehavior != .show {
            // Nothing is fullscreen over a screen that is off, and the island
            // it would step aside for isn't being drawn either: the poll waits
            // until the screen comes back.
            if poll == nil, !PowerStateService.shared.isDormant {
                let timer = Timer(timeInterval: 3, repeats: true) { _ in
                    MainActor.assumeIsolated { ScreenStateService.shared.refreshFullscreen() }
                }
                timer.tolerance = 1
                RunLoop.main.add(timer, forMode: .common)
                poll = timer
            } else if PowerStateService.shared.isDormant {
                poll?.invalidate()
                poll = nil
            }
            if !PowerStateService.shared.isDormant { refreshFullscreen() }
        } else {
            poll?.invalidate()
            poll = nil
            update(fullscreen: [])
        }
        if DisplaySettings.shared.hideInMissionControl {
            watchDock()
        } else {
            unwatchDock()
            setMissionControl(false)
        }
        NotchCoverController.shared.sync()
    }

    // MARK: Fullscreen

    public func refreshFullscreen() {
        // Accessibility may have been granted since; the Dock watch needs it.
        if DisplaySettings.shared.hideInMissionControl, dockObserver == nil { watchDock() }
        guard DisplaySettings.shared.fullscreenBehavior != .show else { return }
        // Screen geometry is read here on main; the Accessibility round-trip into
        // the frontmost app and the window-list copy run on a serial background
        // queue, so a hung frontmost app can't beachball the menu-bar app.
        guard let primary = NSScreen.screens.first else { update(fullscreen: []); return }
        let screens: [ScreenProbe] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            // CG window bounds are top-left based, measured from the primary screen.
            let f = screen.frame
            return ScreenProbe(id: id, cgFrame: CGRect(x: f.minX, y: primary.frame.maxY - f.maxY,
                                                       width: f.width, height: f.height))
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.detectionQueue.async {
            let result = Self.detectFullscreenDisplays(screens: screens, frontPID: frontPID, ownPID: ownPID)
            // main.async (not a Task) keeps the results in the queue's order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // The setting may have been switched to "show" while this ran.
                    guard DisplaySettings.shared.fullscreenBehavior != .show else { return }
                    ScreenStateService.shared.update(fullscreen: result)
                }
            }
        }
    }

    private func update(fullscreen: Set<CGDirectDisplayID>) {
        guard fullscreen != fullscreenDisplays else { return }
        fullscreenDisplays = fullscreen
        islandNeedsRedraw()
    }

    private struct ScreenProbe: Sendable {
        let id: CGDirectDisplayID
        let cgFrame: CGRect
    }

    /// Serial, so results land on main in the order the checks were asked for.
    private nonisolated static let detectionQueue = DispatchQueue(label: "app.tama.screen-state", qos: .utility)

    /// Caps how long an Accessibility call into a busy app may block the queue.
    private nonisolated static let axTimeout: Float = 0.2

    private nonisolated static func detectFullscreenDisplays(screens: [ScreenProbe], frontPID: pid_t?,
                                                             ownPID: pid_t) -> Set<CGDirectDisplayID> {
        guard !screens.isEmpty else { return [] }
        var result = Set<CGDirectDisplayID>()

        // 1. The frontmost app's focused window says it's fullscreen.
        if AXIsProcessTrusted(), let frontPID, frontPID != ownPID {
            let element = AXUIElementCreateApplication(frontPID)
            AXUIElementSetMessagingTimeout(element, axTimeout)
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                let axWindow = window as! AXUIElement
                AXUIElementSetMessagingTimeout(axWindow, axTimeout)
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &value) == .success,
                   (value as? Bool) == true {
                    var positionValue: CFTypeRef?
                    var point = CGPoint.zero
                    if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
                       let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID() {
                        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
                    }
                    let probe = CGPoint(x: point.x + 20, y: point.y + 20)
                    if let screen = screens.first(where: { $0.cgFrame.contains(probe) }) {
                        result.insert(screen.id)
                    }
                }
            }
        }

        // 2. An ordinary window covering a whole screen, menu bar and all.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return result }
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            for screen in screens {
                let frame = screen.cgFrame
                if abs(bounds.minX - frame.minX) < 1, abs(bounds.minY - frame.minY) < 1,
                   abs(bounds.width - frame.width) < 1, abs(bounds.height - frame.height) < 1 {
                    result.insert(screen.id)
                }
            }
        }
        return result
    }

    // MARK: Mission Control

    private func watchDock() {
        guard dockObserver == nil, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        let pid = dock.processIdentifier
        var observer: AXObserver?
        guard AXObserverCreate(pid, dockNotificationCallback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        for name in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"] {
            AXObserverAddNotification(observer, element, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        dockObserver = observer
        dockPID = pid
    }

    private func unwatchDock() {
        guard let dockObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes)
        self.dockObserver = nil
        dockPID = 0
    }

    fileprivate func dockPosted(_ name: String) {
        switch name {
        case "AXExposeShowAllWindows", "AXExposeShowFrontWindows":
            setMissionControl(true)
        default:
            setMissionControl(false)
        }
    }

    private func setMissionControl(_ active: Bool) {
        missionControlFailsafe?.cancel()
        missionControlFailsafe = nil
        if active {
            // If the exit is ever missed, don't leave the island hidden for good.
            let work = DispatchWorkItem { ScreenStateService.shared.setMissionControl(false) }
            missionControlFailsafe = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
        }
        guard active != isMissionControlActive else { return }
        isMissionControlActive = active
        islandNeedsRedraw()
    }

    private func islandNeedsRedraw() {
        AppState.shared.objectWillChange.send()
        NotchWindowController.shared.syncCanvas()
        NotchCoverController.shared.sync()
    }
}

/// AXObserver callbacks are plain C functions; the observer is added to the
/// main run loop, so this runs on the main thread.
private func dockNotificationCallback(_ observer: AXObserver, _ element: AXUIElement,
                                      _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    let name = notification as String
    MainActor.assumeIsolated { ScreenStateService.shared.dockPosted(name) }
}
