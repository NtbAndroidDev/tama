import SwiftUI

/// Notification banner that unfurls from the notch, with an optional action.
public struct NotchNotificationHUDView: View {
    public let notification: DroppyNotification
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var hud = NotificationHUDService.shared
    @State private var isHovered = false
    @Environment(\.islandDisplayID) private var displayID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(notification: DroppyNotification) {
        self.notification = notification
    }

    public var body: some View {
        banner
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, topInset)
            .padding(.bottom, DS.Space.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            AppState.shared.holdNotification(hovering)
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { isHovered = hovering }
        }
    }
    @ViewBuilder
    private var banner: some View {
        if notification.isMirrored { mirrored } else { droppyBanner }
    }

    /// A mirrored macOS notification, like the reference: the app's real
    /// icon, app name over a bold title and the preview, "now" on the right,
    /// and no buttons but Reply. A click opens the app (or, for a burst from
    /// several apps, the Notifications console); hovering swaps "now" for ✕.
    private var mirrored: some View {
        HStack(spacing: DS.Space.lg) {
            mirroredIcon
                .frame(width: 36, height: 36)
                .overlay(alignment: .topTrailing) { queueBadge }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // With previews off the title already is the app's name.
                if notification.title != notification.appName {
                    Text(notification.appName)
                        .font(DS.Typo.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
                Text(notification.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                if !notification.message.isEmpty {
                    Text(notification.message)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .help([notification.title, notification.message].filter { !$0.isEmpty }.joined(separator: "\n"))
            Spacer(minLength: DS.Space.sm)
            VStack(alignment: .trailing, spacing: DS.Space.sm) {
                ZStack(alignment: .trailing) {
                    Text("now")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .opacity(isHovered ? 0 : 1)
                    DroppyIconButton("xmark", size: 20, help: "Dismiss") { dismiss() }
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                }
                if let title = notification.actionTitle {
                    DroppyPillButton(title, tone: .tonal) {
                        DroppyAudio.playTick()
                        notification.action?()
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.surface1)
                .opacity(isHovered ? 1 : 0)
        )
        .padding(.horizontal, -DS.Space.sm)
        .contentShape(Rectangle())
        .onTapGesture { openSource() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(openHint)
        .accessibilityAction(named: notification.actionTitle ?? "Dismiss") {
            // The unnamed fallback only dismisses; it must not run an action
            // the banner never offered.
            if notification.actionTitle != nil { notification.action?() }
            dismiss()
        }
    }

    @ViewBuilder
    private var mirroredIcon: some View {
        if let icon = AppIcon.image(bundleID: notification.sourceBundleID) {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: notification.sourceBundleID == nil ? "square.stack.fill" : "bell.badge.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.accent))
        }
    }

    /// "+2" on the icon while more notifications wait behind this one.
    @ViewBuilder
    private var queueBadge: some View {
        if hud.pendingCount > 0 {
            Text("+\(hud.pendingCount)")
                .font(DS.Typo.numericSmall)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(DS.accent))
                .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.5))
                .offset(x: 6, y: -5)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var accessibilityText: String {
        var parts = [notification.appName, notification.title, notification.message].filter { !$0.isEmpty }
        if parts.count > 1, parts[0] == parts[1] { parts.remove(at: 0) }
        if hud.pendingCount > 0 { parts.append("\(hud.pendingCount) more waiting") }
        return parts.joined(separator: ", ")
    }

    private var openHint: String {
        notification.sourceBundleID == nil ? "Opens the Notifications widget" : "Opens \(notification.appName)"
    }

    private func openSource() {
        if let bundleID = notification.sourceBundleID {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            NotificationHUDService.shared.openConsole()
        }
        dismiss()
    }

    private var droppyBanner: some View {
        HStack(spacing: DS.Space.lg) {
            ZStack {
                Circle().fill(DS.accent)
                Image(systemName: notification.iconSystemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.xs) {
                    Text(notification.appName.uppercased())
                        .font(DS.Typo.micro)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                    Text("now")
                        .font(DS.Typo.micro)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Text(notification.title)
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .help(notification.title)
                if !notification.message.isEmpty {
                    Text(notification.message)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.sm)

            if let title = notification.actionTitle {
                DroppyPillButton(title, tone: .accent) {
                    DroppyAudio.playTick()
                    notification.action?()
                    dismiss()
                }
            }

            if let dismissTitle = notification.dismissTitle {
                DroppyPillButton(dismissTitle, tone: .tonal) {
                    DroppyAudio.playTick()
                    dismiss()
                }
            } else {
                DroppyIconButton("xmark", size: 22, help: "Dismiss") {
                    dismiss()
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { state.activeNotification = nil }
    }

    private var topInset: CGFloat {
        let notch = AppState.shared.notchHeight(on: displayID)
        return notch > 0 ? notch + DS.Space.xs : DS.Space.sm
    }
}
