import AppKit
import SwiftUI
import Combine
import IOKit.pwr_mgt

/// Shows the lock-screen status row, the player and the volume/brightness
/// controls while the screen is locked, plays the lock and unlock sounds, and
/// keeps the display awake for a while if asked (Settings › Lock screen).
///
/// Windows moved into a `SystemSpace` at the top absolute level draw above the
/// lock screen, like the notch itself. Separate panels, so nothing ever
/// covers the login field: the status row lets every click through, and the
/// player and controls only take clicks inside their own cards (the player
/// none when idle). None can become key, so typing always reaches the
/// password field.
@MainActor
public final class LockScreenWindowController {
    public static let shared = LockScreenWindowController()

    private var rowPanel: NSPanel?
    private var playerPanel: NSPanel?
    private var controlsPanel: NSPanel?
    private var space: SystemSpace?
    private var isLocked = false
    private var isScreensaverRunning = false
    private var cancellables = Set<AnyCancellable>()
    private let keepAwake = LockScreenKeepAwake()

    private init() {}

    public func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenWindowController.shared.setLocked(true) }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenWindowController.shared.setLocked(false) }
        }
        center.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenWindowController.shared.setScreensaver(true) }
        }
        center.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenWindowController.shared.setScreensaver(false) }
        }
        // The idle player mustn't swallow clicks where it would be.
        MediaService.shared.$currentTrack
            .map(\.hasTrack)
            .removeDuplicates()
            .sink { [weak self] hasTrack in self?.playerPanel?.ignoresMouseEvents = !hasTrack }
            .store(in: &cancellables)
        settingsChanged()
    }

    /// Called when a lock-screen setting changes.
    public func settingsChanged() {
        // Weather runs whenever it's switched on, not only while locked: the
        // Location prompt has to appear while the user can answer it, and the
        // first lock shouldn't wait on a network round trip.
        if LockScreenSettings.shared.isEnabled && LockScreenSettings.shared.showsWeather && LockScreenSettings.shared.showsStatusRow {
            WeatherService.shared.start(for: "lockScreen")
        } else {
            WeatherService.shared.stop(for: "lockScreen")
        }
        if isLocked {
            if LockScreenSettings.shared.isEnabled {
                show(animated: false)
                keepAwake.begin(minutes: LockScreenSettings.shared.keepAwake)
            } else {
                hide(animated: false)
                keepAwake.end()
            }
        }
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        guard LockScreenSettings.shared.isEnabled else { return hide(animated: false) }
        if LockScreenSettings.shared.sounds {
            LockSound.play(locked ? LockScreenSettings.shared.lockSound : LockScreenSettings.shared.unlockSound, locking: locked)
        }
        if locked {
            isScreensaverRunning = false
            show(animated: LockScreenSettings.shared.animation)
            keepAwake.begin(minutes: LockScreenSettings.shared.keepAwake)
        } else {
            keepAwake.end()
            hide(animated: LockScreenSettings.shared.animation)
        }
    }

    /// Keep visible during screensaver: the panels rise above it; otherwise
    /// they step aside while it runs and come back when it stops.
    private func setScreensaver(_ running: Bool) {
        isScreensaverRunning = running
        guard isLocked, LockScreenSettings.shared.isEnabled else { return }
        if running && !LockScreenSettings.shared.duringScreensaver {
            hide(animated: false)
        } else {
            show(animated: false)
        }
    }

    /// loginwindow draws the lock screen itself at window levels 2001–2004, so
    /// `.screenSaver` (1000) leaves the panels buried under it and nothing shows
    /// on lock. The top of the range clears both that and the screensaver's own
    /// 1000; whether the panels stay up during the screensaver is decided by
    /// showing or hiding them in `setScreensaver`, not by the level.
    private var panelLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    }

    private func show(animated: Bool) {
        if isScreensaverRunning && !LockScreenSettings.shared.duringScreensaver { return }
        // The lock screen draws its clock and login on the main display.
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        if space == nil { space = SystemSpace() }

        if LockScreenSettings.shared.showsHeadphones { HeadphoneBatteryService.shared.start(for: "lockScreen") }
        WeatherService.shared.refresh()

        // Under the system clock, which sits about a fifth of the way down.
        if LockScreenSettings.shared.showsStatusRow {
            let rowHeight: CGFloat = LockScreenStatusRow.height(for: LockScreenSettings.shared.widgetStyle)
            let rowFrame = NSRect(x: frame.minX, y: frame.maxY - frame.height * 0.19 - rowHeight / 2,
                                  width: frame.width, height: rowHeight)
            rowPanel = place(rowPanel, frame: rowFrame, animated: animated) {
                makePanel(LockScreenStatusRow(), frame: rowFrame, clickThrough: true)
            }
        } else {
            remove(&rowPanel)
        }

        // Clear of the user picture and password field at the bottom.
        var nextY = frame.minY + 150
        if LockScreenSettings.shared.showsPlayer {
            let size = LockScreenPlayer.size
            let playerFrame = NSRect(x: frame.midX - size.width / 2, y: nextY, width: size.width, height: size.height)
            playerPanel = place(playerPanel, frame: playerFrame, animated: animated) {
                makePanel(LockScreenPlayer(), frame: playerFrame, clickThrough: !MediaService.shared.currentTrack.hasTrack)
            }
            nextY += size.height + 10
        } else {
            remove(&playerPanel)
        }

        if LockScreenSettings.shared.volumeSlider || LockScreenSettings.shared.brightnessSlider {
            let size = LockScreenControls.size
            let controlsFrame = NSRect(x: frame.midX - size.width / 2, y: nextY, width: size.width, height: size.height)
            controlsPanel = place(controlsPanel, frame: controlsFrame, animated: animated) {
                makePanel(LockScreenControls(), frame: controlsFrame, clickThrough: false)
            }
        } else {
            remove(&controlsPanel)
        }
    }

    private func hide(animated: Bool) {
        HeadphoneBatteryService.shared.stop(for: "lockScreen")
        // Dropped rather than kept ordered out, so their views stop updating.
        for panel in [rowPanel, playerPanel, controlsPanel].compactMap({ $0 }) {
            if animated && !DS.Motion.reduceMotion {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    panel.animator().alphaValue = 0
                }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
            } else {
                panel.orderOut(nil)
            }
        }
        rowPanel = nil
        playerPanel = nil
        controlsPanel = nil
    }

    private func remove(_ panel: inout NSPanel?) {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Moves an existing panel into place, or makes one — fading it in when
    /// Lock/unlock animation is on.
    private func place(_ existing: NSPanel?, frame: NSRect, animated: Bool, make: () -> NSPanel) -> NSPanel {
        if let existing {
            existing.setFrame(frame, display: false)
            existing.level = panelLevel
            existing.alphaValue = 1
            existing.orderFrontRegardless()
            return existing
        }
        let panel = make()
        if animated && !DS.Motion.reduceMotion {
            panel.alphaValue = 0
            // Rise a little as it fades in.
            var start = frame
            start.origin.y -= 14
            panel.setFrame(start, display: false)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }
        return panel
    }

    private func makePanel<Content: View>(_ content: Content, frame: NSRect, clickThrough: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = clickThrough
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        // Fixed-size panel; see FloatingBasketController for why.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        space?.add(panel)
        return panel
    }
}

/// Settings › Lock screen › Keep awake: holds the display on for a while after
/// locking (so the lock-screen widgets stay visible), released on unlock.
@MainActor
final class LockScreenKeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    /// 0 is Off, -1 as long as it's locked.
    func begin(minutes: Int) {
        end()
        guard minutes != 0 else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Tama Lock Screen Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        guard minutes > 0 else { return }
        let timer = Timer(timeInterval: TimeInterval(minutes * 60), repeats: false) { _ in
            Task { @MainActor [weak self] in self?.end() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func end() {
        timer?.invalidate()
        timer = nil
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
