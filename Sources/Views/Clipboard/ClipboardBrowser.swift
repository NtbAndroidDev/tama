import SwiftUI
import AppKit

// What both clipboard layouts share: which clips are shown (pinboard, tag,
// type and search), the selection (one clip or several), the context menu,
// the empty states and the look of a clip's source app.

/// The clipboard's filters and selection. One instance, since only one
/// clipboard window is on screen at a time; cleared whenever it closes.
@MainActor
final class ClipboardBrowser: ObservableObject {
    static let shared = ClipboardBrowser()

    /// The pinboard tab; nil is the Clipboard (all history) tab.
    @Published var board: String?
    /// The tag tab (Settings › Clipboard › Tags); exclusive with `board`.
    @Published var tag: String?
    @Published var kind: ClipFilter = .all
    @Published var query = ""
    @Published var isSearching = false
    /// The clip the keyboard is on (and the Legacy preview shows).
    @Published var selectedID: UUID?
    /// Clips picked with ⌘- or ⇧-click. Empty or one entry means a single selection.
    @Published var selection: Set<UUID> = []
    /// Where a ⇧-click range starts.
    private var anchorID: UUID?
    /// The list as it last stood. A clip deleted from its own menu, or pruned
    /// by retention, doesn't come through `handleKey`, so this is the only way
    /// to know which clip stood next to it.
    private var lastOrder: [UUID] = []

    private init() {}

    func clips(from items: [ClipboardItem]) -> [ClipboardItem] {
        let state = AppState.shared
        var result = items
        if let board { result = result.filter { $0.board == board } }
        if let tag, state.clipboardTagsEnabled { result = result.filter { $0.tags.contains(tag) } }
        // With the rail hidden there's no way to see or change the filter.
        if state.clipboardTypeFilters { result = result.filter(kind.matches) }
        if !query.isEmpty {
            result = result.filter {
                // An image clip's content is just its stored filename.
                ($0.type != .image && $0.content.localizedCaseInsensitiveContains(query))
                    || $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || ($0.ocrText?.localizedCaseInsensitiveContains(query) ?? false)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        // Favourites float to the front.
        return result.filter(\.isPinned) + result.filter { !$0.isPinned }
    }

    var isMultiSelecting: Bool { selection.count > 1 }

    /// The clips an action applies to, in list order: the multi-selection,
    /// else the selected clip.
    func targets(in list: [ClipboardItem]) -> [ClipboardItem] {
        if isMultiSelecting { return list.filter { selection.contains($0.id) } }
        return list.filter { $0.id == selectedID }
    }

    /// The clips a right-clicked clip's menu acts on: the whole selection
    /// when it's part of one, else just that clip.
    func menuTargets(for item: ClipboardItem, in list: [ClipboardItem]) -> [ClipboardItem] {
        isMultiSelecting && selection.contains(item.id) ? list.filter { selection.contains($0.id) } : [item]
    }

    /// A click: plain selects one, ⌘ adds or removes, ⇧ selects the range
    /// from the last clicked clip.
    func click(_ item: ClipboardItem, in list: [ClipboardItem], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.isEmpty, let selectedID { selection = [selectedID] }
            if selection.contains(item.id) {
                selection.remove(item.id)
                // In list order, not `Set.first`, so the focus ring lands
                // somewhere predictable rather than on a random survivor.
                if selectedID == item.id { selectedID = list.last { selection.contains($0.id) }?.id }
            } else {
                selection.insert(item.id)
                selectedID = item.id
            }
            anchorID = item.id
        } else if modifiers.contains(.shift),
                  let anchor = rangeAnchor(in: list),
                  let from = list.firstIndex(where: { $0.id == anchor }),
                  let to = list.firstIndex(where: { $0.id == item.id }) {
            selection = Set(list[min(from, to)...max(from, to)].map(\.id))
            selectedID = item.id
        } else {
            // Also the ⇧-click with nothing to range from: it used to fall
            // through every branch and the click did nothing at all.
            select(item.id)
        }
    }

    /// Where a ⇧-click range starts: the last clicked clip, else the focused
    /// one — whichever is still in the list. A clip deleted meanwhile left a
    /// dead anchor behind, and ⇧-click then silently did nothing.
    private func rangeAnchor(in list: [ClipboardItem]) -> UUID? {
        [anchorID, selectedID].compactMap { $0 }.first { id in list.contains { $0.id == id } }
    }

    /// One clip, and nothing else, selected.
    func select(_ id: UUID?) {
        selectedID = id
        selection = []
        anchorID = id
    }

    /// Steps the cursor; with `extend` (⇧) the selection grows along.
    func move(by offset: Int, in list: [ClipboardItem], extend: Bool = false) {
        guard let index = list.firstIndex(where: { $0.id == selectedID }) else {
            select(list.first?.id)
            return
        }
        let next = list[min(max(index + offset, 0), list.count - 1)].id
        if extend {
            if selection.isEmpty, let selectedID { selection = [selectedID] }
            selection.insert(next)
            selectedID = next
        } else {
            select(next)
        }
    }

    /// Keeps a selection on screen after the list changed (search, filter, delete).
    func reconcile(with list: [ClipboardItem]) {
        let ids = Set(list.map(\.id))
        defer { lastOrder = list.map(\.id) }
        selection.formIntersection(ids)
        if let anchorID, !ids.contains(anchorID) { self.anchorID = nil }
        if let selectedID, ids.contains(selectedID) { return }
        // The clip the keyboard was on has gone. Hand it to the neighbour
        // rather than the front of the list: jumping to the newest clip
        // scrolls the shelf back under them, and the next Delete would then
        // take a clip they never meant to touch.
        if let gone = selectedID, let next = FocusAfterRemoval.next(after: gone, in: lastOrder, surviving: ids) {
            selectedID = next
            return
        }
        // No neighbour to fall back on: a clip still in the selection, in list
        // order, and only then the front.
        selectedID = list.first { selection.contains($0.id) }?.id ?? list.first?.id
    }



    func showBoard(_ board: String?) {
        self.board = board
        tag = nil
    }

    func showTag(_ tag: String) {
        self.tag = tag
        board = nil
    }

    /// Everything back to the Clipboard tab, when the window closes.
    func reset() {
        query = ""
        isSearching = false
        selection = []
        anchorID = nil
    }

    /// Paste the targets and close.
    func paste(_ list: [ClipboardItem], plainText: Bool = false) {
        let items = targets(in: list)
        ClipboardWindowController.shared.paste(items, plainText: plainText)
    }
}

// MARK: - Type filter

/// The kinds the clipboard can narrow the clips down to.
enum ClipFilter: String, CaseIterable, Identifiable {
    case all, favorites, text, images, links, colors, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Clips"
        case .favorites: return "Favorites"
        case .text: return "Text"
        case .images: return "Images"
        case .links: return "Links"
        case .colors: return "Colors"
        case .files: return "Files"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .favorites: return "star.fill"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .links: return "link"
        case .colors: return "paintpalette.fill"
        case .files: return "doc.fill"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return item.isPinned
        case .text: return (item.type == .text || item.type == .code) && item.parsedColor == nil
        case .images: return item.type == .image
        case .links: return item.type == .url
        case .colors: return item.type == .color || item.parsedColor != nil
        case .files: return item.type == .file
        }
    }
}

// MARK: - Empty states

/// The reference's wording for an empty list, by why it's empty.
@MainActor
enum ClipboardEmptyState {
    static func content(browser: ClipboardBrowser, isPaused: Bool, pauseDescription: String)
        -> (icon: String, title: String, subtitle: String) {
        if !browser.query.isEmpty {
            return ("magnifyingglass", "No clipboard matches", "Try a different search.")
        }
        if let tag = browser.tag, AppState.shared.clipboardTagsEnabled {
            return ("tag", "No items with this tag", "Assign \u{201C}\(tag)\u{201D} to items to collect them here.")
        }
        if browser.board != nil {
            return ("pin", "Pinboard is empty", "Pin items to this pinboard to see them here.")
        }
        if browser.kind != .all, AppState.shared.clipboardTypeFilters {
            return (browser.kind.iconName, "No \(browser.kind.title.lowercased())",
                    browser.kind == .favorites ? "Star an item to keep it here." : "Things you copy will appear here.")
        }
        if isPaused {
            return ("pause.circle", "Clipboard is paused", "\(pauseDescription). New copies aren't being saved.")
        }
        return ("doc.on.clipboard", "Clipboard is empty", "Copied items will appear here.")
    }
}

// MARK: - Context menu

/// The right-click menu of a clip, or of a multi-selection when the clicked
/// clip is part of one (bulk Paste, Copy, Favorite, Pinboard, Tag, Delete).
struct ClipMenu: View {
    let item: ClipboardItem
    /// The clips the menu acts on (just `item`, or the whole selection).
    let targets: [ClipboardItem]
    var onRename: (() -> Void)?

    @ObservedObject private var state = AppState.shared

    private var ids: Set<UUID> { Set(targets.map(\.id)) }
    private var isBulk: Bool { targets.count > 1 }
    private var isTextLike: Bool { targets.contains { $0.type != .image && $0.type != .file } }

    var body: some View {
        Button { ClipboardWindowController.shared.paste(targets) } label: {
            Label(isBulk ? "Paste \(targets.count) Items" : "Paste", systemImage: "arrow.down.doc")
        }
        if isTextLike {
            Button { ClipboardWindowController.shared.paste(targets, plainText: true) } label: {
                Label("Paste as Plain Text", systemImage: "textformat")
            }
        }
        Button {
            if state.copyClipboardItems(targets) { DroppyAudio.playCopySuccess() }
        } label: { Label(isBulk ? "Copy \(targets.count) Items" : "Copy", systemImage: "doc.on.doc") }
        if state.clipboardCopyFavorite, !isBulk {
            Button { state.copyAndFavorite(item) } label: { Label("Copy + Favorite", systemImage: "star.square.on.square") }
        }
        if !isBulk, item.type == .url, let url = URL(string: item.previewText) {
            Button { NSWorkspace.shared.open(url) } label: { Label("Open Link", systemImage: "safari") }
        }
        if ReadAloudService.shared.isSpeaking {
            Button { ReadAloudService.shared.stop() } label: { Label("Stop Reading", systemImage: "speaker.slash") }
        } else if isTextLike {
            Button {
                ReadAloudService.shared.speak(targets.filter { $0.type != .image && $0.type != .file }
                    .map(\.content).joined(separator: "\n\n"))
            } label: { Label("Read Aloud", systemImage: "speaker.wave.2") }
        }
        Divider()
        let allStarred = targets.allSatisfy(\.isPinned)
        Button { state.toggleFavorite(ids) } label: {
            Label(allStarred ? "Remove from Favorites" : "Add to Favorites", systemImage: allStarred ? "star.slash" : "star")
        }
        Menu {
            ForEach(state.pinboards) { board in
                Button { state.assign(ids, to: board.name) } label: {
                    if targets.allSatisfy({ $0.board == board.name }) {
                        Label(board.name, systemImage: "checkmark")
                    } else {
                        Text(board.name)
                    }
                }
            }
        } label: { Label("Pin", systemImage: "pin") }
        if targets.contains(where: { $0.board != nil }) {
            Button { state.assign(ids, to: nil) } label: { Label("Remove from Pinboard", systemImage: "pin.slash") }
        }
        if state.clipboardTagsEnabled {
            Menu {
                ForEach(state.clipboardTags) { tag in
                    Button { state.toggleClipTag(tag.name, on: ids) } label: {
                        if targets.allSatisfy({ $0.tags.contains(tag.name) }) {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
                if !state.clipboardTags.isEmpty { Divider() }
                Button("New Tag…") { state.promptNewClipTag(for: ids) }
            } label: { Label("Tag", systemImage: "tag") }
        }
        if !isBulk {
            Button { ClipPreview.show(targets) } label: { Label("Preview", systemImage: "eye") }
            if let onRename {
                Button { onRename() } label: { Label("Rename…", systemImage: "pencil") }
            }
            if item.type == .image, let text = item.ocrText {
                Button { write(text) } label: { Label("Copy Text", systemImage: "text.viewfinder") }
            }
            if item.type == .file {
                Button { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) } label: { Label("Show in Finder", systemImage: "folder") }
            }
            if item.type != .image && item.type != .file {
                Menu {
                    Button("UPPERCASE") { write(item.uppercaseContent) }
                    Button("lowercase") { write(item.lowercaseContent) }
                    Button("Trimmed") { write(item.trimmedContent) }
                    if let rgb = item.rgbFormatted { Button(rgb) { write(rgb) } }
                    if let swiftUI = item.swiftUIColorFormatted { Button("SwiftUI Color") { write(swiftUI) } }
                    if let nsColor = item.nsColorFormatted { Button("NSColor") { write(nsColor) } }
                } label: {
                    Label("Copy As", systemImage: "wand.and.stars")
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
                state.deleteClipboardItems(ids: ids)
            }
        } label: { Label(isBulk ? "Delete \(targets.count) Items" : "Delete", systemImage: "trash") }
    }

    private func write(_ text: String) {
        ClipboardService.shared.copyToPasteboard(text: text)
        DroppyAudio.playCopySuccess()
    }
}

// MARK: - Preview

/// "Preview": the clip in Quick Look. Text clips are written to a temporary
/// file first (RTF when they have formatting), so every kind previews alike.
@MainActor
enum ClipPreview {
    static func show(_ items: [ClipboardItem]) {
        let urls = items.flatMap(urls(for:))
        guard !urls.isEmpty else { return NSSound.beep() }
        QuickLookService.shared.preview(urls)
    }

    private static func urls(for item: ClipboardItem) -> [URL] {
        switch item.type {
        case .image:
            return [ClipboardImageStore.url(for: item.content)]
        case .file:
            return item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        default:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TamaClipPreview", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = (item.customTitle ?? item.displayTitle).replacingOccurrences(of: "/", with: "-")
            if let rtf = item.rtfData, !item.isSensitive {
                let url = dir.appendingPathComponent("\(name).rtf")
                return (try? rtf.write(to: url)) != nil ? [url] : []
            }
            let url = dir.appendingPathComponent("\(name).txt")
            return (try? item.content.write(to: url, atomically: true, encoding: .utf8)) != nil ? [url] : []
        }
    }
}

// MARK: - Source app look

/// A clip's source app: its colour (the card header's tint) and a short
/// relative time, shared by both layouts.
@MainActor
enum ClipSource {
    private static var tints: [String: Color?] = [:]

    /// The app icon's most colourful hue, deepened so white text reads on it.
    static func tint(for bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        if let known = tints[bundleID] { return known }
        let color = AppIcon.image(bundleID: bundleID).flatMap(dominantColor)
        tints[bundleID] = color
        return color
    }

    private static func dominantColor(_ image: NSImage) -> Color? {
        let side = 16
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = context.data else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var buckets = [(r: Double, g: Double, b: Double, n: Double, score: Double)](repeating: (0, 0, 0, 0, 0), count: 12)
        for i in 0..<(side * side) where pixels[i * 4 + 3] > 200 {
            let r = Double(pixels[i * 4]) / 255, g = Double(pixels[i * 4 + 1]) / 255, b = Double(pixels[i * 4 + 2]) / 255
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            guard s > 0.25, v > 0.2 else { continue }
            let index = min(Int(h * 12), 11)
            buckets[index].r += r; buckets[index].g += g; buckets[index].b += b
            buckets[index].n += 1; buckets[index].score += Double(s * v)
        }
        guard let best = buckets.max(by: { $0.score < $1.score }), best.n >= 3 else { return nil }
        let color = NSColor(srgbRed: best.r / best.n, green: best.g / best.n, blue: best.b / best.n, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: min(max(s, 0.45), 0.8), brightness: 0.55, alpha: 1))
    }

    static func appName(_ bundleID: String?) -> String? {
        guard let bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return nil }
        return ClipboardPrivacy.appName(for: bundleID)
    }

    /// "now", "2 min ago", "3 hr ago", then a date.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hr ago" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400)) d ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Small coloured chips for a clip's tags.
struct ClipTagChips: View {
    let tags: [String]
    var compact = false
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { name in
                let color = state.clipboardTags.first { $0.name == name }?.color ?? .gray
                if compact {
                    Circle().fill(color).frame(width: 7, height: 7).help(name)
                } else {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(color.opacity(0.55), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.isEmpty ? "" : "Tags: \(tags.joined(separator: ", "))")
    }
}
