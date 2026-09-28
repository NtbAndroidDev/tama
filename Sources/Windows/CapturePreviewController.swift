import SwiftUI
import AppKit

/// The card a fresh screenshot leaves in the corner: a glass "Screenshot /
/// Quick actions" card with the capture inset in a well and five round
/// buttons (edit, copy, save, read text, pin). It stays a few seconds, longer
/// while hovered, and the image can be dragged straight into another app.
@MainActor
public final class CapturePreviewController {
    public static let shared = CapturePreviewController()

    /// How long an untouched preview stays up.
    static let lifetime: TimeInterval = 6

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    let model = CapturePreviewModel()

    private init() {}

    /// Shows `url` in the corner. `copied` adds the "Copied" pill.
    public func show(url: URL, copied: Bool) {
        guard CaptureSettings.shared.showsPreview, let image = NSImage(contentsOf: url) else { return }
        model.url = url
        model.image = image
        model.copied = copied
        model.isHovered = false
        model.isReading = false

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = Self.size(for: image)
        let pointer = NSEvent.mouseLocation
        let visible = (NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = Self.origin(for: size, on: visible, pointer: pointer,
                                 placement: CaptureSettings.shared.previewPlacement)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        scheduleDismiss()
    }

    public func dismiss() {
        dismissWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 0 }) {
            Task { @MainActor in
                panel.orderOut(nil)
                self.model.image = nil
            }
        }
    }

    /// Restarts the countdown; hovering holds it.
    func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isHovered, !self.model.isReading else { return }
            self.dismiss()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }

    /// Where the card sits. Closest Corner puts it in the screen corner the
    /// pointer is nearest, so it doesn't cover what was just captured.
    nonisolated static func origin(for size: CGSize, on visible: NSRect, pointer: NSPoint,
                                   placement: CapturePreviewPlacement) -> NSPoint {
        let margin = CaptureMetrics.previewMargin
        let left = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        let right = visible.maxX - size.width - margin
        let top = visible.maxY - size.height - margin
        switch placement {
        case .bottomRight:
            return NSPoint(x: right, y: left.y)
        case .closestCorner:
            return NSPoint(x: pointer.x >= visible.midX ? right : left.x,
                           y: pointer.y >= visible.midY ? top : left.y)
        }
    }

    static func wellHeight(for image: NSImage) -> CGFloat {
        let inner = CaptureMetrics.previewWidth - CaptureMetrics.previewPadding * 2
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 0.6
        return min(max(inner * aspect, CaptureMetrics.previewWellMin), CaptureMetrics.previewWellMax)
    }

    private static func size(for image: NSImage) -> CGSize {
        let m = CaptureMetrics.self
        let height = m.previewPadding * 2 + m.previewHeader + m.previewSpacing * 2 + wellHeight(for: image) + m.previewButton
        return CGSize(width: m.previewWidth, height: height)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: CaptureMetrics.previewWidth, height: 320),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: CapturePreviewView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

@MainActor
final class CapturePreviewModel: ObservableObject {
    @Published var url: URL?
    @Published var image: NSImage?
    @Published var copied = false
    @Published var isHovered = false
    @Published var isReading = false
}

private struct CapturePreviewView: View {
    @ObservedObject var model: CapturePreviewModel
    @ObservedObject private var state = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var controller: CapturePreviewController { .shared }
    private let shape = RoundedRectangle(cornerRadius: CaptureMetrics.previewRadius, style: .continuous)

    var body: some View {
        VStack(spacing: CaptureMetrics.previewSpacing) {
            header
            well
            actions
        }
        .padding(CaptureMetrics.previewPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.25)
            }
            .clipShape(shape)
        )
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if model.isHovered {
                Button { controller.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.85))
                .help("Close")
                .accessibilityLabel("Close preview")
                .offset(x: -6, y: -6)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: model.isHovered)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: model.copied)
        .onHover { hovering in
            model.isHovered = hovering
            if !hovering { controller.scheduleDismiss() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Quick actions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if model.copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.success)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(DS.Palette.success.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(DS.Palette.success.opacity(0.45), lineWidth: 1))
                    .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.85).combined(with: .opacity)))
            }
        }
        .frame(height: CaptureMetrics.previewHeader)
    }

    private var well: some View {
        let wellShape = RoundedRectangle(cornerRadius: CaptureMetrics.previewWellRadius, style: .continuous)
        return ZStack {
            wellShape.fill(Color.white.opacity(0.06))
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
                    .onDrag { NSItemProvider(contentsOf: model.url) ?? NSItemProvider() }
                    .onTapGesture(count: 2) { edit() }
                    .help("Double-click to edit · drag into any app")
                    .accessibilityLabel("Screenshot")
                    .accessibilityHint("Double-click to edit, or drag into any app")
                    .accessibilityAddTraits(.isImage)
            }
        }
        .frame(height: model.image.map(CapturePreviewController.wellHeight(for:)) ?? CaptureMetrics.previewWellMin)
        .overlay(wellShape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            // Ours only: keep the capture in the Tray.
            if model.isHovered {
                Button(action: keep) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .contentShape(Circle())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.85))
                .help("Keep in Tray")
                .accessibilityLabel("Keep in Tray")
                .padding(8)
                .transition(.opacity)
            }
        }
        .contextMenu {
            Button("Edit in Screenshot Editor", action: edit)
            Button("Copy", action: copy)
            Button("Save to \(ScreenCaptureService.folderURL.lastPathComponent)", action: save)
            Button("Keep in Tray", action: keep)
            Button("Pin to Screen", action: pin)
            Divider()
            Button("Close") { controller.dismiss() }
        }
    }

    private var actions: some View {
        HStack {
            round("pencil", help: "Edit", action: edit)
            Spacer(minLength: 0)
            round("doc.on.doc", help: "Copy", action: copy)
            Spacer(minLength: 0)
            round("square.and.arrow.down", help: "Save to \(ScreenCaptureService.folderURL.lastPathComponent)", action: save)
            Spacer(minLength: 0)
            round(model.isReading ? "hourglass" : "text.viewfinder",
                  help: model.isReading ? "Reading text…" : "Read text (OCR)", action: readText)
            Spacer(minLength: 0)
            round("pin.fill", help: "Pin to screen", tint: Color(red: 1, green: 0.3, blue: 0.3), action: pin)
        }
    }

    private func round(_ symbol: String, help: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        PreviewRoundButton(symbol: symbol, help: help, tint: tint, action: action)
    }

    // MARK: Actions

    private func edit() {
        guard let image = model.image else { return }
        CaptureEditorWindowController.shared.open(image: image, sourceURL: model.url)
        controller.dismiss()
    }

    private func copy() {
        guard let image = model.image else { return }
        NSPasteboard.general.clearContents()
        if let url = model.url, let data = try? Data(contentsOf: url), url.pathExtension.lowercased() == "png" {
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            NSPasteboard.general.writeObjects([image])
        }
        DroppyAudio.playCopySuccess()
        model.copied = true
    }

    private func save() {
        guard let url = model.url, let saved = ScreenCaptureService.saveToFolder(url) else { return }
        DroppyAudio.playDropSuccess()
        AppState.shared.showNotification(appName: "Capture", title: "Saved", message: "\(saved.lastPathComponent) in \(saved.deletingLastPathComponent().lastPathComponent)",
                                         actionTitle: "Reveal", action: { NSWorkspace.shared.activateFileViewerSelecting([saved]) })
    }

    private func keep() {
        guard let url = model.url else { return }
        AppState.shared.addShelfItems([ShelfItem(name: url.lastPathComponent, url: url, fileExtension: url.pathExtension.uppercased())])
        DroppyAudio.playDropSuccess()
        AppState.shared.showNotification(appName: "Tama Shelf", title: "Screenshot Held", message: "\(url.lastPathComponent) added to the Tray",
                                         actionTitle: "Show", action: { AppState.shared.open(.tray) })
        controller.dismiss()
    }

    private func pin() {
        guard let image = model.image else { return }
        PinnedScreenshotController.shared.pin(image: image, url: model.url)
        controller.dismiss()
    }

    private func readText() {
        guard let image = model.image, !model.isReading,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        model.isReading = true
        Task {
            await ScreenCaptureService.shared.readText(cgImage)
            CapturePreviewController.shared.model.isReading = false
            CapturePreviewController.shared.scheduleDismiss()
        }
    }
}

/// One of the card's round quick-action buttons; it brightens under the pointer.
private struct PreviewRoundButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: CaptureMetrics.previewButton, height: CaptureMetrics.previewButton)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.18 : 0.1)))
                .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.2 : 0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(DroppyPressStyle(scale: 0.9))
        .animation(DS.Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Pinned screenshots

/// Pin: a screenshot in its own floating, resizable, always-on-top window.
/// Any number can be pinned; each closes on its own.
@MainActor
final class PinnedScreenshotController: NSObject, NSWindowDelegate {
    static let shared = PinnedScreenshotController()

    private var panels: [NSPanel] = []

    private override init() { super.init() }

    func pin(image: NSImage, url: URL?) {
        let size = Self.initialSize(for: image)
        let visible = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(panels.count % 6) * 24
        let frame = NSRect(x: visible.midX - size.width / 2 + offset, y: visible.midY - size.height / 2 - offset,
                           width: size.width, height: size.height)
        let panel = PinnedScreenshotPanel(contentRect: frame,
                                          styleMask: [.borderless, .resizable, .nonactivatingPanel, .fullSizeContentView],
                                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentAspectRatio = size
        panel.minSize = Self.minimumSize(for: size)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        let host = NSHostingView(rootView: PinnedScreenshotView(image: image, url: url) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.close(panel)
        })
        host.sizingOptions = []
        panel.contentView = host
        CaptureExclusion.register(panel)
        panels.append(panel)
        panel.orderFrontRegardless()
        DroppyAudio.playTick()
    }

    func close(_ panel: NSPanel) {
        panels.removeAll { $0 === panel }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === panel }
    }

    private static func initialSize(for image: NSImage) -> CGSize {
        let w = max(image.size.width, 1), h = max(image.size.height, 1)
        let fit = min(1, CaptureMetrics.pinLongestSide / max(w, h))
        return CGSize(width: (w * fit).rounded(), height: (h * fit).rounded())
    }

    private static func minimumSize(for size: CGSize) -> CGSize {
        let shortest = max(min(size.width, size.height), 1)
        let factor = CaptureMetrics.pinMinSide / shortest
        return CGSize(width: size.width * min(factor, 1), height: size.height * min(factor, 1))
    }
}

/// Borderless but key-capable, so Esc and ⌘W close it once clicked.
private final class PinnedScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { closePin() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
            closePin()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func closePin() {
        MainActor.assumeIsolated { PinnedScreenshotController.shared.close(self) }
    }
}

private struct PinnedScreenshotView: View {
    let image: NSImage
    let url: URL?
    let close: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel("Pinned screenshot")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(isHovered ? 0.35 : 0.12), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(DroppyPressStyle(scale: 0.85))
                    .help("Close pinned screenshot")
                    .accessibilityLabel("Close pinned screenshot")
                    .padding(6)
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) { CaptureEditorWindowController.shared.open(image: image, sourceURL: url) }
            .contextMenu {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    DroppyAudio.playCopySuccess()
                }
                Button("Edit in Screenshot Editor") { CaptureEditorWindowController.shared.open(image: image, sourceURL: url) }
                Divider()
                Button("Close Pinned Screenshot", action: close)
            }
            .help("Drag to move · drag an edge to resize · double-click to edit")
    }
}
