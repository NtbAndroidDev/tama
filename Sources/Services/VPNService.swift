import Foundation
import SystemConfiguration
import SwiftUI

/// A connected VPN in the notch wings, with how long the session has run when
/// Tama saw it start.
///
/// Two signals, since neither sees every VPN: tunnel interfaces (utun / ppp /
/// ipsec) holding an IPv4 address in the dynamic store catch WireGuard,
/// Tailscale and friends even when they aren't the primary route; `scutil --nc`
/// names the VPNs configured in System Settings. The idle utun interfaces macOS
/// keeps for iCloud and Continuity carry no IPv4 address, so they don't count.
/// Driven by SCDynamicStore change notifications rather than polling.
@MainActor
public final class VPNService {
    public static let shared = VPNService()

    struct Status: Equatable, Sendable {
        var name: String
        var interface: String?
        var address: String?
    }

    private static let activityID = "vpn"

    private var store: SCDynamicStore?
    private var current: Status?
    private var connectedAt: Date?
    /// False for a VPN that was already up when Tama first looked: its real
    /// start is unknown, so the wings show "On" rather than a made-up length.
    private var connectedAtIsExact = false
    private var hasProbed = false
    private var pendingCheck: DispatchWorkItem?
    private var probing = false
    private var recheck = false
    private var ticker: Timer?

    private init() {}

    public func start() {
        apply(enabled: AppState.shared.showVPNStatus)
    }

    public func apply(enabled: Bool) {
        if enabled {
            watch()
            scheduleCheck(after: 0)
        } else {
            ticker?.invalidate()
            ticker = nil
            // Forget the session so turning it back on doesn't announce stale transitions.
            current = nil
            connectedAt = nil
            connectedAtIsExact = false
            hasProbed = false
            LiveActivityCenter.shared.end(Self.activityID)
        }
    }

    // MARK: Watching

    private func watch() {
        guard store == nil else { return }
        let callback: SCDynamicStoreCallBack = { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { VPNService.shared.scheduleCheck(after: 0.6) }
            }
        }
        guard let store = SCDynamicStoreCreate(nil, "Tama.VPN" as CFString, callback, nil) else { return }
        let patterns = [
            "State:/Network/Interface/[^/]+/IPv4",
            "State:/Network/Service/[^/]+/IPv4",
            "State:/Network/Global/IPv4",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
    }

    /// Network changes arrive in bursts while a tunnel comes up; wait for it to settle.
    private func scheduleCheck(after delay: TimeInterval) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func check() {
        guard AppState.shared.showVPNStatus else { return }
        guard !probing else { recheck = true; return }
        probing = true
        Task {
            let status = await Task.detached(priority: .utility) { Self.probe() }.value
            probing = false
            update(status)
            if recheck {
                recheck = false
                check()
            }
        }
    }

    private func update(_ status: Status?) {
        guard AppState.shared.showVPNStatus else { return }
        let previous = current
        let wasFirstProbe = !hasProbed
        hasProbed = true
        current = status

        switch (previous, status) {
        case (nil, let now?):
            connectedAt = Date()
            connectedAtIsExact = !wasFirstProbe
            if !wasFirstProbe {
                var details = [now.interface, now.address].compactMap { $0 }.joined(separator: " · ")
                if details.isEmpty { details = "Secure tunnel is up." }
                AppState.shared.showNotification(appName: "VPN", title: "VPN connected — \(now.name)", message: details)
            }
        case (let was?, nil):
            let duration = connectedAtIsExact ? connectedAt.map { Self.format(Date().timeIntervalSince($0)) } : nil
            connectedAt = nil
            connectedAtIsExact = false
            AppState.shared.showNotification(
                appName: "VPN", title: "VPN disconnected",
                message: duration.map { "\(was.name) · session \($0)" } ?? was.name
            )
        default:
            break
        }

        if status == nil {
            ticker?.invalidate()
            ticker = nil
            LiveActivityCenter.shared.end(Self.activityID)
        } else {
            postActivity()
            if ticker == nil, connectedAtIsExact {
                ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    MainActor.assumeIsolated { VPNService.shared.tick() }
                }
            }
        }
    }

    // MARK: Activity

    /// Only re-posts while the wings can actually show the timer, so a VPN
    /// left on all day doesn't re-render the notch every second for nothing.
    private func tick() {
        let live = LiveActivityCenter.shared
        guard current != nil, !AppState.shared.isIslandExpanded,
              live.top(.urgent) == nil, live.top(.ambient)?.id == Self.activityID else { return }
        postActivity()
    }

    private func postActivity() {
        guard let current, let connectedAt else { return }
        LiveActivityCenter.shared.post(LiveActivity(
            id: Self.activityID,
            icon: "lock.shield.fill",
            tint: DS.Palette.success,
            trailing: .text(connectedAtIsExact ? Self.format(Date().timeIntervalSince(connectedAt)) : "On"),
            priority: .ambient,
            label: "VPN connected · \(current.name)"
        ))
    }

    /// m:ss under an hour, then h:mm.
    private static func format(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        if seconds < 3600 {
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    // MARK: Probe (off the main thread)

    nonisolated private static func probe() -> Status? {
        let named = connectedServiceName()
        let tunnel = tunnelInterface()
        if let named {
            return Status(name: named, interface: tunnel?.name, address: tunnel?.address)
        }
        if let tunnel {
            return Status(name: tunnel.name, interface: nil, address: tunnel.address)
        }
        return nil
    }

    /// A tunnel interface with a routable IPv4 address, preferring the primary one.
    nonisolated private static func tunnelInterface() -> (name: String, address: String?)? {
        guard let store = SCDynamicStoreCreate(nil, "Tama.VPNProbe" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/[^/]+/IPv4" as CFString) as? [String]
        else { return nil }
        let prefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wg"]
        let primary = (SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any])?["PrimaryInterface"] as? String

        var found: [(name: String, address: String?)] = []
        for key in keys {
            let parts = key.split(separator: "/")
            guard parts.count >= 4 else { continue }
            let name = String(parts[3])
            guard prefixes.contains(where: name.hasPrefix),
                  let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let addresses = value["Addresses"] as? [String] else { continue }
            let routable = addresses.first { !$0.hasPrefix("169.254.") }
            guard let routable else { continue }
            found.append((name, routable))
        }
        return found.first { $0.name == primary } ?? found.first
    }

    /// The first "(Connected)" VPN listed by `scutil --nc list`, by its display name.
    nonisolated private static func connectedServiceName() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--nc", "list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.split(separator: "\n") where line.contains("(Connected)") {
            // Dial-up modems show up here too; they aren't VPNs.
            guard !line.contains("[PPP:Modem]") else { continue }
            guard let open = line.firstIndex(of: "\""),
                  let close = line[line.index(after: open)...].firstIndex(of: "\"") else { continue }
            let name = line[line.index(after: open)..<close]
            if !name.isEmpty { return String(name) }
        }
        return nil
    }
}
