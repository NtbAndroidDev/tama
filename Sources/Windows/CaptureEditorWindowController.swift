import SwiftUI
import AppKit
import Carbon.HIToolbox
import ImageIO

/// A panel that takes key focus (text annotations need typing) while
/// floating over whatever was just captured.
final class CaptureEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Opens screenshot editor windows. Each capture gets its own window, so a
/// second snip never throws away edits on the first.
@MainActor
public final class CaptureEditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = CaptureEditorWindowController()

    private struct Session {
        let panel: CaptureEditorPanel
        let model: CaptureEditorModel
    }

    private var sessions: [ObjectIdentifier: Session] = [:]
    private var keyMonitor: Any?

    private override init() {
        super.init()
    }

    /// Opens any image for annotation. `sourceURL` names the result and lets the
    /// original file be read at full resolution.
    public func open(image: NSImage, sourceURL: URL?) {
        open(image: image, sourceURL: sourceURL, delivery: nil)
    }

    func open(image: NSImage, sourceURL: URL?, delivery: CaptureDelivery?) {
        guard let cgImage = Self.fullResolutionImage(image, sourceURL: sourceURL) else {
            AppState.shared.showNotification(appName: "Capture", title: "Can't edit this image",
                                             message: "The image couldn't be decoded.")
            return
        }
        let pixelScale = image.size.width > 0 ? CGFloat(cgImage.width) / image.size.width : 1
        let document = CaptureDocument(original: cgImage, pixelScale: pixelScale.rounded(), sourceURL: sourceURL)
        let model = CaptureEditorModel(document: document, delivery: delivery)

        let panel = CaptureEditorPanel(
            contentRect: initialFrame(for: document),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = sourceURL?.lastPathComponent ?? "Screenshot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 820, height: 420)
        panel.backgroundColor = NSColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)
        // Dark chrome regardless of the system appearance, like the rest of Tama.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        let host = NSHostingView(rootView: CaptureEditorView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        model.window = panel
        model.onClose = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.close(panel)
        }
        sessions[ObjectIdentifier(panel)] = Session(panel: panel, model: model)
        installKeyMonitor()

        panel.center()
        // Tama is an LSUIElement agent: it has to activate itself before its window can take keys.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DroppyAudio.playSnip()
    }

    /// Opens an image file, e.g. from the Tray.
    public func open(contentsOf url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            AppState.shared.showNotification(appName: "Capture", title: "Can't edit this file",
                                             message: url.lastPathComponent)
            return
        }
        open(image: image, sourceURL: url)
    }

    // MARK: Window lifecycle

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session = sessions[ObjectIdentifier(sender)] else { return true }
        session.model.requestDiscard()
        return false
    }

    private func close(_ panel: CaptureEditorPanel) {
        sessions[ObjectIdentifier(panel)] = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        // Drop the SwiftUI tree now so the model (and its temp files) go with it.
        panel.contentView = nil
        if sessions.isEmpty, let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func initialFrame(for document: CaptureDocument) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let chrome = CGSize(width: 56, height: 46 * 2 + 56)
        let points = CGSize(width: document.imageSize.width / document.pixelScale,
                            height: document.imageSize.height / document.pixelScale)
        let maxSize = CGSize(width: visible.width * 0.82, height: visible.height * 0.85)
        let fit = min(1, (maxSize.width - chrome.width) / points.width, (maxSize.height - chrome.height) / points.height)
        let width = min(max(points.width * fit + chrome.width, 820), maxSize.width)
        let height = min(max(points.height * fit + chrome.height, 460), maxSize.height)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    // MARK: Keyboard

    /// Tama has no menu bar to route ⌘-shortcuts, and single-key tool
    /// switching must not fire while typing, so keys are handled here.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window,
                  let session = self.sessions[ObjectIdentifier(window)],
                  window.attachedSheet == nil else { return event }
            return self.handle(event, model: session.model) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, model: CaptureEditorModel) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = Int(event.keyCode)

        if model.textEdit != nil {
            // The text field owns typing, Return and Esc; only ⌘-shortcuts that
            // make sense mid-edit get through.
            if flags.contains(.command) && key == "s" { model.save(); return true }
            return false
        }

        if flags.contains(.command) {
            switch key {
            case "z": flags.contains(.shift) ? model.redo() : model.undo(); return true
            case "c": model.copy(); return true
            case "s": model.save(); return true
            case "w": model.requestDiscard(); return true
            case "=", "+": model.zoomIn(); return true
            case "-": model.zoomOut(); return true
            case "0": model.zoomToFit(); return true
            case "1": model.zoomToActualSize(); return true
            default: return false
            }
        }

        switch code {
        case kVK_Escape:
            if model.tool == .crop { model.cancelCrop() }
            else if model.selectedID != nil { model.selectedID = nil }
            else { model.requestDiscard() }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.tool == .crop { model.tool = .select } else { model.finish() }
            return true
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelection()
            return true
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            guard model.selectedID != nil else { return false }
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            let dx: CGFloat = code == kVK_LeftArrow ? -step : code == kVK_RightArrow ? step : 0
            let dy: CGFloat = code == kVK_UpArrow ? -step : code == kVK_DownArrow ? step : 0
            model.nudgeSelection(dx: dx * model.document.pixelScale, dy: dy * model.document.pixelScale)
            return true
        default:
            break
        }

        guard flags.isDisjoint(with: [.command, .control, .option]), key.count == 1,
              let tool = CaptureTool.allCases.first(where: { $0.shortcut.map(String.init) == key }) else {
            if key == "?" || key == "/" {
                model.showsShortcuts.toggle()
                return true
            }
            return false
        }
        model.tool = tool
        DroppyAudio.playTick()
        return true
    }

    // MARK: Image loading

    /// The largest bitmap available: the file itself when there is one, since
    /// an NSImage may only hold a downscaled representation.
    private static func fullResolutionImage(_ image: NSImage, sourceURL: URL?) -> CGImage? {
        if let sourceURL,
           let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            return cg
        }
        let best = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let cg = best?.cgImage { return cg }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
