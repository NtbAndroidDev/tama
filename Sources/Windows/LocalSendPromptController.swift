import SwiftUI
import AppKit

/// LocalSend's "Incoming requests" prompt: a small floating glass window near
/// the top of the active screen, asking to accept or decline a transfer. It
/// times out (declines) after a minute.
@MainActor
final class LocalSendPromptController: NSObject {
    static let shared = LocalSendPromptController()

    private var panel: NSPanel?

    private override init() { super.init() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = ToolWindowMetrics.localSendPromptSize
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 16))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = ToolWindowMetrics.localSendPromptSize
        let panel = PromptPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: LocalSendPromptView())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LocalSendPromptView: View {
    @ObservedObject private var service = LocalSendService.shared

    var body: some View {
        Group {
            if let request = service.incoming {
                LocalSendIncomingCard(request: request)
            } else {
                Color.clear
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(DS.Palette.hairline))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The request itself: who, what, and Decline / Accept. Shared by the
/// floating prompt and the LocalSend console.
struct LocalSendIncomingCard: View {
    let request: LocalSendService.IncomingRequest
    @ObservedObject private var service = LocalSendService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: LocalSendDeviceType.symbol(type: request.sender.deviceType, model: request.sender.deviceModel))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LocalSendConsoleView.tint.opacity(0.85)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(request.sender.alias)
                        .font(DS.Typo.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if service.isFavorite(request.sender.fingerprint) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).help("Favorite")
                        .accessibilityLabel("Favorite")
                }
            }
            if let message = request.message {
                Text(message)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(names)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.sm) {
                Spacer(minLength: 0)
                DroppyPillButton("Decline", systemName: "xmark", tone: .tonal, help: "Decline (Esc)") { service.decide(false) }
                    .keyboardShortcut(.cancelAction)
                DroppyPillButton(request.message == nil ? "Accept" : "Copy",
                                 systemName: request.message == nil ? "checkmark" : "doc.on.doc", tone: .accent,
                                 help: request.message == nil ? "Accept and receive (↩)" : "Copy the message (↩)") {
                    service.decide(true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var subtitle: String {
        if request.message != nil { return "sent you a message" }
        let size = ByteCountFormatter.string(fromByteCount: request.totalBytes, countStyle: .file)
        return "wants to send \(request.files.count) file\(request.files.count == 1 ? "" : "s") · \(size)"
    }

    private var names: String {
        let shown = request.files.prefix(3).map(\.fileName).joined(separator: ", ")
        let more = request.files.count - 3
        return more > 0 ? "\(shown) and \(more) more" : shown
    }
}
