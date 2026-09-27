import SwiftUI

/// Notification banner that unfurls from the notch, with an optional action.
public struct NotchNotificationHUDView: View {
    public let notification: DroppyNotification
    @ObservedObject private var state = AppState.shared
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
        .onHover { AppState.shared.holdNotification($0) }
    }
    @ViewBuilder
    private var banner: some View {
        if notification.isMirrored { mirrored } else { droppyBanner }
    }

    /// A mirrored macOS notification, like the reference: the app's real
    /// icon, app name over a bold title and the preview, "now" on the right,
    /// and no buttons but Reply. A click opens the app.
    private var mirrored: some View {
        HStack(spacing: DS.Space.lg) {
            Group {
                if let icon = AppIcon.image(bundleID: notification.sourceBundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.accent))
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.appName)
                    .font(DS.Typo.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                Text(notification.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                if !notification.message.isEmpty {
                    Text(notification.message)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.sm)
            VStack(alignment: .trailing, spacing: DS.Space.sm) {
                Text("now")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
                if let title = notification.actionTitle {
                    DroppyPillButton(title, tone: .tonal) {
                        DroppyAudio.playTick()
                        notification.action?()
                        dismiss()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let bundleID = notification.sourceBundleID,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(notification.sourceBundleID == nil ? "" : "Opens \(notification.appName)")
        .accessibilityAction(named: notification.actionTitle ?? "Dismiss") {
            // The unnamed fallback only dismisses; it must not run an action
            // the banner never offered.
            if notification.actionTitle != nil { notification.action?() }
            dismiss()
        }
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
