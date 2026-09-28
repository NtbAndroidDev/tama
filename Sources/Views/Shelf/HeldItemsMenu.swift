import AppKit
import SwiftUI

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String? = nil, image: NSImage? = nil, keyEquivalent: String = "",
         handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
        if let image {
            self.image = image
        } else if let symbol {
            self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // AppKit calls menu actions on the main thread.
    @objc @MainActor private func fire() {
        handler()
    }
}

extension NSMenu {
    @discardableResult
    func add(_ title: String, symbol: String? = nil, image: NSImage? = nil, enabled: Bool = true,
             handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title, symbol: symbol, image: image, handler: handler)
        item.isEnabled = enabled
        addItem(item)
        return item
    }

    @discardableResult
    func addSubmenu(_ title: String, symbol: String? = nil, build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        let submenu = NSMenu(title: title)
        build(submenu)
        item.submenu = submenu
        addItem(item)
        return item
    }

    /// Pops the menu at the pointer (for buttons without an AppKit view).
    @MainActor func popUpAtPointer() {
        NSApp.activate(ignoringOtherApps: true)
        popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// The Shelf and Basket context menu. It acts on the whole selection when the
/// clicked file is part of it, and says how many files each action will touch
/// ("Compress (3)").
@MainActor
enum HeldItemsMenu {
    struct Context {
        var items: [ShelfItem]
        var surface: HeldSurface
        /// Opens Tama's own preview for a single file.
        var onPreview: ((ShelfItem) -> Void)?
        /// Opens the folder browser for a folder.
        var onBrowseFolder: ((ShelfItem) -> Void)?
        /// Called after actions that consume the selection.
        var clearSelection: () -> Void = {}
    }

    static func build(_ context: Context) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items = context.items
        guard let first = items.first else { return menu }
        let state = AppState.shared
        let n = items.count
        let count = n > 1 ? " (\(n))" : ""
        let ids = Set(items.map(\.id))
        let urls = items.map(\.url)

        // Look and open.
        if n == 1, let preview = context.onPreview {
            menu.add("Preview", symbol: "eye.fill") { preview(first) }
        }
        menu.add("Quick Look\(count)", symbol: "eye") { QuickLookService.shared.preview(urls) }
        if n == 1, first.isDirectory, let browse = context.onBrowseFolder {
            menu.add("Browse Folder", symbol: "folder.badge.gearshape") { browse(first) }
        }
        menu.add("Open\(count)", symbol: "arrow.up.forward.app") { items.forEach { $0.openFile() } }
        menu.addSubmenu("Open With…", symbol: "square.and.arrow.up.on.square") { sub in
            let apps = FileOperations.applications(for: items)
            for app in apps.prefix(14) {
                // A copy: the menu resizes its icon, and the cached one is shared.
                let icon = FileIcon.image(for: app).copy() as? NSImage ?? NSImage()
                icon.size = NSSize(width: 16, height: 16)
                sub.add(FileOperations.appName(app), image: icon) { FileOperations.open(items, with: app) }
            }
            if !apps.isEmpty { sub.addItem(.separator()) }
            sub.add("Other…") { FileOperations.openWithPicker(items) }
        }
        menu.add("Reveal in Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        menu.add("Copy\(count)", symbol: "doc.on.doc") { FileOperations.copyToPasteboard(items) }
        menu.add(n == 1 ? "Copy Path" : "Copy Paths", symbol: "text.quote") { FileOperations.copyPaths(items) }

        menu.addItem(.separator())

        // Where it goes.
        menu.addSubmenu("Move to…", symbol: "folder.badge.plus") { sub in
            let fm = FileManager.default
            for directory in [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory] {
                guard let folder = fm.urls(for: directory, in: .userDomainMask).first else { continue }
                sub.add(fm.displayName(atPath: folder.path), symbol: "folder") { FileOperations.move(items, to: folder) }
            }
            sub.addItem(.separator())
            sub.add("Choose Folder…", symbol: "ellipsis.circle") { FileOperations.moveWithPicker(items) }
        }
        menu.add("Save to Downloads\(count)", symbol: "arrow.down.circle") { FileOperations.saveCopies(items) }
        // The system's own Share submenu (Mail, Messages, Notes, AirDrop…).
        menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
        menu.add("AirDrop", symbol: "dot.radiowaves.left.and.right") { TrayActions.airDrop(urls) }
        menu.add("Tama Quickshare", symbol: "drop.fill") { QuickshareService.shared.upload(urls) }
        menu.add("Share Link…", symbol: "qrcode") {
            state.pendingShare = items
            state.open(.tray)
            NotchWindowController.shared.focusPanel()
        }
        menu.add("iCloud Drive", symbol: "icloud.and.arrow.up") { QuickActionRunner.send(.iCloud, urls: urls) }
        menu.add("Mail", symbol: "envelope") { QuickActionRunner.send(.mail, urls: urls) }
        menu.add("Messages", symbol: "message") { QuickActionRunner.send(.messages, urls: urls) }
        menu.add("Send with LocalSend", symbol: "dot.radiowaves.left.and.right") { QuickActionRunner.send(.localSend, urls: urls) }

        menu.addItem(.separator())

        // Make something new.
        let formats = FileConverter.commonTargets(for: urls)
        if !formats.isEmpty {
            menu.addSubmenu("Convert\(count)", symbol: "arrow.triangle.2.circlepath") { sub in
                for format in formats {
                    sub.add("Convert to \(format)") { ConvertActions.convert(items, to: format) }
                }
            }
        }
        let compressible = items.filter { FileCompressor.canCompress($0.url) }
        if !compressible.isEmpty {
            menu.addSubmenu("Compress\(compressible.count > 1 ? " (\(compressible.count))" : "")",
                            symbol: "arrow.down.right.and.arrow.up.left") { sub in
                for level in CompressionLevel.allCases {
                    sub.add(level.title) {
                        CompressActions.compress(compressible, level: level)
                        context.clearSelection()
                    }
                }
                if n == 1, FileCompressor.kind(of: first.url) == .video {
                    sub.addItem(.separator())
                    sub.add("Target Size…", symbol: "scalemass") { CompressActions.compressToTargetSize(first) }
                }
            }
        }
        menu.add("Create ZIP\(count)", symbol: "doc.zipper") {
            state.createArchive(of: items, into: context.surface)
            context.clearSelection()
        }
        menu.add("Create Folder\(count)", symbol: "folder.badge.plus") {
            FileOperations.createFolder(from: items)
            context.clearSelection()
        }
        if ReadAloudService.shared.isSpeaking {
            menu.add("Stop Reading", symbol: "speaker.slash") { ReadAloudService.shared.stop() }
        } else if n == 1, ReadAloudService.canRead(first.url) {
            menu.add("Read Aloud", symbol: "speaker.wave.2") { ReadAloudService.shared.speak(fileAt: first.url) }
        }
        let readable = items.filter { OCRService.canRead($0.url) }
        if !readable.isEmpty {
            menu.add("Extract Text\(readable.count > 1 ? " (\(readable.count))" : "")", symbol: "text.viewfinder") {
                FileOperations.extractText(readable)
            }
        }
        let images = items.filter(\.isImage)
        if !images.isEmpty {
            menu.add("Remove Background\(images.count > 1 ? " (\(images.count))" : "")", symbol: "person.crop.rectangle") {
                BackgroundRemovalActions.run(images)
            }
            if n == 1 {
                menu.add("Edit Screenshot", symbol: "pencil.tip.crop.circle") {
                    CaptureEditorWindowController.shared.open(contentsOf: first.url)
                }
            }
        }

        menu.addItem(.separator())

        // Organise.
        if n == 1 {
            menu.add("Rename…", symbol: "pencil") { FileOperations.renameWithPrompt(first) }
        }
        let pinned = state.allPinned(ids)
        menu.add(pinned ? "Unpin\(count)" : "Pin\(count)", symbol: pinned ? "pin.slash" : "pin") { state.togglePin(ids) }
        menu.addSubmenu("Tags", symbol: "tag") { sub in
            for board in state.pinboards {
                let item = sub.add(board.name, image: tagDot(board.color)) { state.toggleTag(board.name, on: ids) }
                let tagged = items.filter { $0.tags.contains(board.name) }.count
                item.state = tagged == n ? .on : (tagged > 0 ? .mixed : .off)
            }
            if !state.pinboards.isEmpty { sub.addItem(.separator()) }
            sub.add("New Tag…", symbol: "plus") { newTag(on: ids) }
        }
        switch context.surface {
        case .shelf:
            if TraySettings.shared.twoStacks {
                let target = items.allSatisfy { $0.stack == 1 } ? 0 : 1
                menu.add("Move to Stack \(target + 1)\(count)", symbol: "square.stack") { state.moveToStack(ids, stack: target) }
            }
            if BasketSettings.shared.mode == .multi, state.baskets.count > 1 {
                menu.addSubmenu("Move to Basket\(count)", symbol: "basket") { sub in
                    for basket in state.baskets {
                        sub.add("\(basket.colorName) Basket (\(basket.items.count))", image: tagDot(basket.color)) {
                            state.moveToBasket(ids, basketID: basket.id)
                        }
                    }
                    sub.addItem(.separator())
                    sub.add("New Basket", symbol: "plus") { state.moveToBasket(ids, basketID: state.spawnBasket(nearPointer: false)) }
                }
            } else {
                menu.add("Move to Basket\(count)", symbol: "basket") { state.moveToBasket(ids, basketID: state.primaryBasketID) }
            }
        case .basket(let basketID):
            if BasketSettings.shared.secondBucket {
                let target = items.allSatisfy { $0.stack == 1 } ? 0 : 1
                menu.add(target == 1 ? "Move to Second Bucket\(count)" : "Move to Main Bucket\(count)", symbol: "tray.2") {
                    state.moveToStack(ids, stack: target)
                }
            }
            if BasketSettings.shared.mode == .multi, state.baskets.count > 1 {
                menu.addSubmenu("Move to Basket", symbol: "basket") { sub in
                    for basket in state.baskets where basket.id != basketID {
                        sub.add("\(basket.colorName) Basket (\(basket.items.count))", image: tagDot(basket.color)) {
                            state.moveToBasket(ids, basketID: basket.id)
                        }
                    }
                }
            }
            menu.add("Move to Shelf\(count)", symbol: "arrow.up.to.line") {
                state.moveToShelf(ids)
                context.clearSelection()
            }
        }

        menu.addItem(.separator())
        menu.add("Remove from \(context.surface.name)\(count)", symbol: "trash") {
            state.removeHeldItemsWithUndo(ids: ids)
            context.clearSelection()
        }
        return menu
    }

    static func tagDot(_ color: Color) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image
    }

    private static func newTag(on ids: Set<UUID>) {
        let alert = NSAlert()
        alert.messageText = "New Tag"
        alert.informativeText = "Assign this tag to items to find them quickly. Tags are shared with the clipboard's boards."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Tag name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Tag")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let state = AppState.shared
        state.setModal(true, owner: "heldItems.newTag")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        state.setModal(false, owner: "heldItems.newTag")
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
        _ = state.addPinboard(named: name)
        state.toggleTag(name, on: ids)
    }
}
