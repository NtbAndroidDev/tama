import SwiftUI
import AppKit

/// Voice Transcribe › External Recorder: the recorder in a small floating
/// glass window instead of the expanded island. It stays up while recording
/// (so a recording is always on screen) and can be dragged anywhere.
@MainActor
final class VoiceRecorderPanelController: NSObject {
    static let shared = VoiceRecorderPanelController()

    private var panel: NSPanel?

    private override init() { super.init() }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                let size = ToolWindowMetrics.recorderSize
                panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 24))
            }
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        // A running recording keeps its window: it's the visible indicator.
        if VoiceTranscribeService.shared.phase == .recording { return }
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = ToolWindowMetrics.recorderSize
        let panel = RecorderPanel(
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
        let host = NSHostingView(rootView: FloatingRecorderView())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

private final class RecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FloatingRecorderView: View {
    @ObservedObject private var voice = VoiceTranscribeService.shared

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            HStack {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
                Spacer()
                if voice.phase != .recording {
                    DroppyIconButton("xmark", size: 20, help: "Close the recorder") {
                        VoiceRecorderPanelController.shared.close()
                    }
                }
            }
            VoiceRecorderView(isFloating: true)
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
