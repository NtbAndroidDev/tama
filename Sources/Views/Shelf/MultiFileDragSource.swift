import SwiftUI
import AppKit

/// An AppKit drag source for files: the "N selected" / "Drag all" chips and
/// every Shelf and Basket tile use it, so all drags out follow Settings ›
/// General › Protect originals (copy only) and report whether another app
/// took the drop.
class FileDragSourceView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var surface: TrayActions.DragSurface = .tray
    /// true when another app took the files (a drop back on Tama doesn't count).
    var onEnded: ((Bool) -> Void)?

    func beginFileDrag(with event: NSEvent) {
        let files = urls()
        guard !files.isEmpty else { return }
        let origin = convert(event.locationInWindow, from: nil)
        let items = files.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = FileIcon.image(for: url)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: origin.x - 20 + offset, y: origin.y - 20 - offset, width: 40, height: 40), contents: icon)
            return item
        }
        DroppyAudio.playTick()
        TrayActions.internalDragSource = surface
        beginDraggingSession(with: items, event: event, source: self)
    }

    // Settings › General › Protect originals (on by default): copy only,
    // so Finder can't move the user's originals out of their folder when
    // the drop lands on the same volume. Off offers a move to other apps.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        let protects = UserDefaults.standard.object(forKey: "protectOriginals") as? Bool ?? true
        if context == .outsideApplication, !protects {
            return [.copy, .move]
        }
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Any drop on our own targets has been handled by now.
        TrayActions.internalDragSource = nil
        let ontoDroppy = TrayActions.isOverDroppy(screenPoint)
        if operation.contains(.move), !ontoDroppy {
            // The files now live elsewhere; their Tray entries point at nothing.
            MainActor.assumeIsolated { AppState.shared.pruneMissingShelfItems() }
        }
        onEnded?(operation != [] && !ontoDroppy)
    }
}

/// Put it behind a label with `.overlay`; it has no click behaviour of its own.
struct MultiFileDragSource: NSViewRepresentable {
    let urls: () -> [URL]
    var surface: TrayActions.DragSurface = .tray
    var onEnded: ((Bool) -> Void)? = nil
    /// The tooltip: SwiftUI's `.help` on the label can't reach through this view.
    var help: String = ""

    func makeNSView(context: Context) -> SourceView {
        let view = SourceView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SourceView, context: Context) {
        view.urls = urls
        view.surface = surface
        view.onEnded = onEnded
        view.toolTip = help.isEmpty ? nil : help
    }

    final class SourceView: FileDragSourceView {
        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            beginFileDrag(with: event)
        }
    }
}

/// Everything a file tile does with the pointer, in AppKit: click to select
/// (the count tells a double click), drag the file (or the selection) out
/// with the Protect originals policy, right-click for the context menu, and
/// hover. SwiftUI's `onDrag` can't say copy-only or report the outcome.
struct TileInteraction: NSViewRepresentable {
    var urls: () -> [URL]
    var surface: TrayActions.DragSurface
    var onClick: (Int) -> Void
    var onHover: (Bool) -> Void
    var menu: () -> NSMenu?
    var onDragEnded: (Bool) -> Void
    /// The tooltip (SwiftUI's `.help` can't reach through this view).
    var help: String = ""

    func makeNSView(context: Context) -> TileView {
        let view = TileView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: TileView, context: Context) {
        view.urls = urls
        view.surface = surface
        view.onClick = onClick
        view.onHover = onHover
        view.menuProvider = menu
        view.onEnded = onDragEnded
        view.toolTip = help.isEmpty ? nil : help
    }

    final class TileView: FileDragSourceView {
        var onClick: (Int) -> Void = { _ in }
        var onHover: (Bool) -> Void = { _ in }
        var menuProvider: () -> NSMenu? = { nil }
        private var downEvent: NSEvent?
        private var didDrag = false
        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        // The shelf panel doesn't take key focus on the first click.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                showMenu(event)
                return
            }
            downEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let down = downEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 16 else { return }
            didDrag = true
            beginFileDrag(with: down)
        }

        override func mouseUp(with event: NSEvent) {
            defer { downEvent = nil }
            guard downEvent != nil, !didDrag else { return }
            onClick(event.clickCount)
        }

        override func rightMouseDown(with event: NSEvent) {
            showMenu(event)
        }

        private func showMenu(_ event: NSEvent) {
            guard let menu = menuProvider() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func accessibilityIsIgnored() -> Bool { true }
    }
}
