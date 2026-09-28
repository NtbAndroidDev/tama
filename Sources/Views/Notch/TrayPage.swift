import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The file tray: a dashed drop zone while empty, then a rail of held files
/// with a few round actions in the corner. With Two Stacks on, a pill in the
/// other corner switches stacks; tags in use can filter the rail.
public struct TrayPage: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var traySettings = TraySettings.shared
    @State private var selection = Set<UUID>()
    /// Last plainly clicked tile: shift-click selects the run from here, and
    /// the arrow keys move from here.
    @State private var selectionAnchor: UUID?
    @State private var isDropTargeted = false
    @State private var previewItem: ShelfItem?
    @State private var shareItems: [ShelfItem]?
    @State private var browsingFolder: ShelfItem?
    /// What the "N selected" chip picked up when its drag began; files
    /// selected or added mid-drag stay.
    @State private var draggedIDs = Set<UUID>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    /// The files on show: the current stack, narrowed by the tag filter.
    private var visibleItems: [ShelfItem] {
        state.shelfItems.filter { item in
            (!traySettings.twoStacks || item.stack == state.activeTrayStack)
                && (state.trayTagFilter.map { item.tags.contains($0) } ?? true)
        }
    }

    /// What the corner actions apply to: the selection, or everything shown.
    private var targets: [ShelfItem] {
        let picked = visibleItems.filter { selection.contains($0.id) }
        return picked.isEmpty ? visibleItems : picked
    }

    /// A right-click acts on the selection when the file is part of it.
    private func menuTargets(for item: ShelfItem) -> [ShelfItem] {
        selection.contains(item.id) ? visibleItems.filter { selection.contains($0.id) } : [item]
    }

    public var body: some View {
        // Filtered once per pass; the closures below filter again when they fire.
        let visible = visibleItems
        return ZStack {
            if visible.isEmpty {
                dropZone
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96))))
            } else {
                rail(visible)
                    .transition(.opacity)
                actions
            }
            if showsFilters {
                filters
            }
            if let converting = state.pendingConvert {
                ConvertBar(items: converting)
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .bottom))))
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: visible.isEmpty)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: state.pendingConvert != nil)
        .background { keyboardShortcuts }
        // Same types as the island, so a screenshot thumbnail, a text snippet or
        // a Mail / Photos promise lands here too; DragDropService turns them
        // into files. A tile dragged out of the Tray itself is ignored.
        .onDrop(of: DragDropService.acceptedTypes, delegate: ShelfDropDelegate(surface: .tray, isTargeted: $isDropTargeted) { providers in
            DragDropService.shared.handleDrop(providers: providers) { items in
                guard !items.isEmpty else { return state.notifyNothingAdded() }
                state.addShelfItems(items)
                DroppyAudio.playDropSuccess()
            }
        })
        .sheet(item: $previewItem) { item in
            ShelfItemPreviewModal(item: item) { previewItem = nil }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            DroppyCloudShareView(items: shareItems ?? []) { shareItems = nil }
        }
        .sheet(item: $browsingFolder) { folder in
            FolderBrowserSheet(root: folder.url) { browsingFolder = nil }
        }
        .onChange(of: previewItem?.id) { _, _ in syncModal() }
        .onChange(of: shareItems == nil) { _, _ in syncModal() }
        .onChange(of: browsingFolder?.id) { _, _ in syncModal() }
        .onAppear(perform: consumePendingShare)
        .onChange(of: state.pendingShare) { _, _ in consumePendingShare() }
        .onChange(of: state.shelfItems) { old, items in
            let ids = Set(items.map(\.id))
            selection.formIntersection(ids)
            // Files expire and are pruned when they vanish from Finder, so the
            // keyboard's row can go without anyone pressing a key. Step to the
            // neighbour instead of leaving a dead anchor, which sent the next
            // arrow key to the first or last file in the Tray.
            if let anchor = selectionAnchor, !ids.contains(anchor) {
                selectionAnchor = FocusAfterRemoval.next(after: anchor, in: old.map(\.id), surviving: ids)
            }
            prunePendingConvert()
            // A tag nobody carries any more stops filtering.
            if let tag = state.trayTagFilter, !items.contains(where: { $0.tags.contains(tag) }) {
                state.trayTagFilter = nil
            }
        }
        .onChange(of: state.activeTrayStack) { _, _ in
            selection.removeAll()
            selectionAnchor = nil
        }
        // Files trashed or moved in Finder leave the Tray instead of lingering.
        .onAppear {
            state.pruneMissingShelfItems()
            prunePendingConvert()
        }
    }

    // MARK: Keyboard

    @ViewBuilder
    private var keyboardShortcuts: some View {
        // Invisible, but still answer while the Tray is on screen.
        Group {
            Button("Select All", action: selectAll)
                .keyboardShortcut("a", modifiers: .command)
            // ⌫ removes the selected files (with an Undo toast).
            Button("Remove Selected", action: removeSelection)
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection.isEmpty)
            // Space and Return do what they do in Finder. (Esc is taken by
            // GlobalShortcutService, which collapses the shelf.)
            Button("Quick Look Selected") {
                QuickLookService.shared.preview(visibleItems.filter { selection.contains($0.id) }.map(\.url))
            }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(selection.isEmpty)
            Button("Open Selected") {
                visibleItems.filter { selection.contains($0.id) }.forEach { $0.openFile() }
            }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selection.isEmpty)
            // Keyboard-first: arrows move the focus, ⇧ extends the selection.
            Button("Next File") { moveFocus(by: 1, extend: false) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Previous File") { moveFocus(by: -1, extend: false) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Extend Selection Right") { moveFocus(by: 1, extend: true) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Extend Selection Left") { moveFocus(by: -1, extend: true) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            // ⇧⌘M: Move to… for the selection.
            Button("Move Selected To…") { FileOperations.moveWithPicker(targets) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(selection.isEmpty)
            // ⌘C puts the selected files on the pasteboard, as Finder does
            // and as the clipboard shelf already did.
            Button("Copy Selected") {
                FileOperations.copyToPasteboard(visibleItems.filter { selection.contains($0.id) })
                DroppyAudio.playCopySuccess()
            }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selection.isEmpty)
            // ⌘Z takes back a removal while its toast is still up.
            Button("Undo") { state.performActiveUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(state.activeNotification?.actionTitle != "Undo")
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moveFocus(by step: Int, extend: Bool) {
        let ids = visibleItems.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectionAnchor.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        if extend {
            selection.insert(ids[next])
        } else {
            selection = [ids[next]]
        }
        selectionAnchor = ids[next]
        DroppyAudio.playTick()
    }

    // MARK: Empty

    /// Never flips under Reduce Motion, so the icon doesn't bounce.
    private var bounceTrigger: Bool { !reduceMotion && isDropTargeted }

    private var emptyTitle: String {
        if let tag = state.trayTagFilter, !state.shelfItems.isEmpty { return "No items with the \(tag) tag." }
        if traySettings.twoStacks { return "Stack \(state.activeTrayStack + 1)" }
        return "Tray"
    }

    /// One line saying what to do with an empty Tray. A tag filter already
    /// explains itself, so it stays quiet there.
    private var emptyHint: String? {
        guard state.trayTagFilter == nil else { return nil }
        return isDropTargeted ? "Release to keep them here" : "Drop files here, or onto the notch"
    }

    private var dropZone: some View {
        dropZoneOutline
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(emptyTitle) is empty")
            .accessibilityHint("Choose files to add to the Tray")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { chooseFiles() }
            .overlay(alignment: .bottomTrailing) {
                Button(action: snipToTray) {
                    Label("Snip", systemImage: "camera.viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(NotchPalette.control))
                }
                .buttonStyle(PressableStyle())
                .help("Snip part of the screen into the Tray")
                .padding(.bottom, 18)
                .padding(.trailing, 10)
            }
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isDropTargeted)
    }

    private var dropZoneOutline: some View {
        VStack(spacing: 9) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 24, weight: .regular))
                .symbolEffect(.bounce, value: bounceTrigger)
            Text(emptyTitle)
                .font(.system(size: 15, weight: .semibold))
            if let emptyHint {
                Text(emptyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Color.white.opacity(isDropTargeted ? 0.85 : 0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isDropTargeted ? Color.white.opacity(0.06) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isDropTargeted ? 0.5 : 0.26),
                    style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])
                )
        )
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: chooseFiles)
        .help("Drop files here — or click to choose files")
    }

    // MARK: Rail

    private func rail(_ visibleItems: [ShelfItem]) -> some View {
        // Ticks every 30 s so "Expires soon" badges appear on time.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // Lazy, like the clipboard rail: a Tray holding dozens of
                    // files only builds the tiles on screen, so their
                    // thumbnails are decoded as they're scrolled to rather
                    // than all at once when the shelf opens.
                    LazyHStack(alignment: .top, spacing: 24) {
                        ForEach(visibleItems) { item in
                            TrayFileTile(
                                item: item,
                                isSelected: selection.contains(item.id),
                                now: context.date,
                                onSelect: { toggleSelection(item) },
                                onOpen: { open(item) },
                                onDelete: {
                                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeShelfItemsWithUndo(ids: [item.id]) }
                                },
                                onPreview: { previewItem = item },
                                dragURLs: { dragURLs(for: item) },
                                menu: { menu(for: item) },
                                // Handed in so a tile needn't observe AppState itself.
                                expiryInterval: traySettings.expiry.interval,
                                tagColors: tagColors(for: item)
                            )
                            .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.8).combined(with: .opacity)))
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                // The rail scrolls, so the arrow keys could walk the focus off
                // the end of what's on screen: bring the tile they land on
                // into view.
                .onChange(of: selectionAnchor) { _, id in scroll(proxy, to: id) }
                // New files go in at the front, which a rail scrolled deep into
                // the list isn't showing. Only while the keyboard isn't
                // somewhere else: a file expiring must not drag the rail back.
                .onChange(of: visibleItems.first?.id) { _, id in
                    guard selectionAnchor == nil else { return }
                    scroll(proxy, to: id)
                }
            }
        }
        .horizontalEdgeFade(18)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .allowsHitTesting(false)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: UUID?) {
        guard let id, visibleItems.contains(where: { $0.id == id }) else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func tagColors(for item: ShelfItem) -> [Color] {
        item.tags.compactMap { tag in state.pinboards.first { $0.name == tag }?.color }
    }

    /// Dragging a selected tile takes the whole selection, like Finder.
    private func dragURLs(for item: ShelfItem) -> [URL] {
        let picked = menuTargets(for: item)
        draggedIDs = Set(picked.map(\.id))
        return picked.map(\.url)
    }

    private func menu(for item: ShelfItem) -> NSMenu {
        HeldItemsMenu.build(.init(
            items: menuTargets(for: item),
            surface: .shelf,
            onPreview: { previewItem = $0 },
            onBrowseFolder: { browsingFolder = $0 },
            clearSelection: { selection.removeAll() }
        ))
    }

    /// Double-click: a pinned folder opens in Tama's browser, anything else
    /// in its app.
    private func open(_ item: ShelfItem) {
        if item.isPinned, item.isDirectory {
            browsingFolder = item
        } else {
            item.openFile()
        }
    }

    // MARK: Stacks and tags

    private var showsFilters: Bool {
        traySettings.twoStacks || !state.shelfTagsInUse.isEmpty
    }

    private var filters: some View {
        HStack(spacing: 6) {
            if traySettings.twoStacks {
                // Both stacks counted in one pass over the Tray.
                let secondCount = state.shelfItems.reduce(0) { $1.stack == 1 ? $0 + 1 : $0 }
                let counts = [state.shelfItems.count - secondCount, secondCount]
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { stack in
                        let count = counts[stack]
                        Button {
                            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.activeTrayStack = stack }
                            DroppyAudio.playTick()
                        } label: {
                            Text(count > 0 ? "\(stack + 1) · \(count)" : "\(stack + 1)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(state.activeTrayStack == stack ? .black : .white)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Capsule().fill(state.activeTrayStack == stack ? Color.white : Color.clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                        .help("Stack \(stack + 1)")
                        .accessibilityLabel("Stack \(stack + 1), \(count == 1 ? "1 file" : "\(count) files")")
                        .accessibilityAddTraits(state.activeTrayStack == stack ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(Capsule().fill(NotchPalette.control))
            }
            let tags = state.shelfTagsInUse
            if !tags.isEmpty {
                Menu {
                    Button("All files") { state.trayTagFilter = nil }
                    Divider()
                    ForEach(tags) { tag in
                        Button {
                            state.trayTagFilter = state.trayTagFilter == tag.name ? nil : tag.name
                        } label: {
                            if state.trayTagFilter == tag.name {
                                Label(tag.name, systemImage: "checkmark")
                            } else {
                                Text(tag.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill").font(.system(size: 9, weight: .semibold))
                        // A long tag name mustn't push the pill across the rail.
                        Text(state.trayTagFilter ?? "Tags").font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 120)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Capsule().fill(NotchPalette.control))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show only files with a tag")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, -2)
    }

    // MARK: Corner actions

    private var actions: some View {
        HStack(spacing: 8) {
            if !selection.isEmpty {
                // A tile drags itself (or the selection it's part of); this
                // drags the whole selection from anywhere.
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(selection.count) selected")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(NotchPalette.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(NotchPalette.control))
                .overlay {
                    MultiFileDragSource(urls: {
                        let picked = targets
                        draggedIDs = Set(picked.map(\.id))
                        return picked.map(\.url)
                    }) { accepted in
                        guard accepted, traySettings.removeOnDragOut else { return }
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeShelfItemsWithUndo(ids: draggedIDs) }
                    }
                }
                .help("Drag the selected files out together")
                .padding(.trailing, 2)
            }
            NotchCircleButton("square.and.arrow.up", size: 30, iconSize: 12.5,
                              help: selection.isEmpty ? "Actions for every file" : "Actions for the selection") {
                let menu = HeldItemsMenu.build(.init(
                    items: targets, surface: .shelf,
                    onPreview: { previewItem = $0 },
                    onBrowseFolder: { browsingFolder = $0 },
                    clearSelection: { selection.removeAll() }
                ))
                menu.addItem(.separator())
                menu.add("Snip screen to Tray", symbol: "camera.viewfinder") { snipToTray() }
                menu.add("Show Floating Basket", symbol: "basket") { state.showBasket(nearPointer: false) }
                menu.popUpAtPointer()
            }
            .accessibilityLabel("Share, convert or compress")

            NotchCircleButton("trash", size: 30, iconSize: 12.5, help: selection.isEmpty ? "Clear the Tray" : "Remove selected") {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                    if selection.isEmpty {
                        state.clearTrayWithUndo()
                    } else {
                        state.removeShelfItemsWithUndo(ids: selection)
                        selection.removeAll()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.bottom, -4)
    }

    // MARK: Helpers

    private func toggleSelection(_ item: ShelfItem) {
        let ids = visibleItems.map(\.id)
        if NSEvent.modifierFlags.contains(.shift),
           let anchor = selectionAnchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: item.id) {
            // Shift-click: everything between the last click and this one.
            selection.formUnion(ids[min(from, to)...max(from, to)])
        } else {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            selectionAnchor = item.id
        }
        DroppyAudio.playTick()
    }

    private func removeSelection() {
        guard !selection.isEmpty else { return }
        // Step to the nearest file that survives, and select it: pressing ⌫
        // again then carries on down the rail instead of doing nothing, which
        // is what the clipboard already does.
        let order = visibleItems.map(\.id)
        let surviving = Set(order).subtracting(selection)
        // Measure from the file the keyboard was on, or from the first one
        // going if the anchor is stale. An anchor that isn't going stays put.
        let from = selectionAnchor.flatMap { order.contains($0) ? $0 : nil }
            ?? order.first { selection.contains($0) }
        let next: UUID?
        if let from, surviving.contains(from) {
            next = from
        } else if let from {
            next = FocusAfterRemoval.next(after: from, in: order, surviving: surviving)
        } else {
            next = nil
        }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeShelfItemsWithUndo(ids: selection) }
        selection = next.map { [$0] } ?? []
        selectionAnchor = next
    }

    /// The Convert bar only offers files still in the Tray, and goes when
    /// none are left.
    private func prunePendingConvert() {
        guard let pending = state.pendingConvert else { return }
        let held = Set(state.shelfItems.map(\.id))
        let live = pending.filter { held.contains($0.id) }
        guard live.count != pending.count else { return }
        state.pendingConvert = live.isEmpty ? nil : live
    }

    private func selectAll() {
        guard !visibleItems.isEmpty else { return }
        selection = Set(visibleItems.map(\.id))
        DroppyAudio.playTick()
    }

    /// Clicking the empty zone is the keyboard-free way in: a plain file picker.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add to Tray"
        // Keep the shelf open behind the picker, and bring it forward from an
        // accessory app that isn't active.
        state.setModal(true, owner: "tray.page")
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        syncModal()
        guard response == .OK, !panel.urls.isEmpty else { return }
        state.addShelfItems(panel.urls.map { ShelfItem(url: $0) })
        DroppyAudio.playDropSuccess()
    }

    private func syncModal() {
        state.setModal(previewItem != nil || shareItems != nil || browsingFolder != nil,
                       owner: "tray.page")
    }

    private func consumePendingShare() {
        guard let pending = state.pendingShare else { return }
        state.pendingShare = nil
        shareItems = pending
    }

    private func snipToTray() {
        TrayActions.snipToTray()
    }
}

// MARK: - Tile

/// A held file: a 56pt rounded thumbnail with its name underneath. Hover shows
/// a delete badge; a click selects; a double click opens; drag it anywhere;
/// right-click for everything else. Badges: pinned, expiring soon, tags.
public struct TrayFileTile: View {
    public let item: ShelfItem
    public var isSelected: Bool
    /// The Basket shows empty selection circles on hover, like its reference.
    public var showsSelectionCircle: Bool
    public var now: Date
    public var surface: TrayActions.DragSurface
    public var onSelect: () -> Void
    public var onOpen: (() -> Void)?
    public var onDelete: () -> Void
    public var onPreview: () -> Void
    public var dragURLs: (() -> [URL])?
    public var menu: (() -> NSMenu?)?
    /// The Tray's expiry and the tags' pinboard colours. Callers hand them in
    /// so the tile doesn't observe AppState; nil reads AppState unobserved,
    /// which the Basket (itself observing AppState) relies on.
    public var expiryInterval: TimeInterval?
    public var tagColorsOverride: [Color]?

    /// Actions and fallbacks only; not observed (see `expiryInterval`).
    private var state: AppState { AppState.shared }
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let side = DroppyShelfMetrics.fileTile
    private static let width: CGFloat = 70
    /// The thumbnail's left edge inside the tile.
    private static let inset = (width - side) / 2

    public init(
        item: ShelfItem,
        isSelected: Bool = false,
        showsSelectionCircle: Bool = false,
        now: Date = Date(),
        onSelect: @escaping () -> Void = {},
        onOpen: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        onPreview: @escaping () -> Void,
        surface: TrayActions.DragSurface = .tray,
        dragURLs: (() -> [URL])? = nil,
        menu: (() -> NSMenu?)? = nil,
        expiryInterval: TimeInterval? = nil,
        tagColors: [Color]? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.showsSelectionCircle = showsSelectionCircle
        self.now = now
        self.onSelect = onSelect
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.onPreview = onPreview
        self.surface = surface
        self.dragURLs = dragURLs
        self.menu = menu
        self.expiryInterval = expiryInterval
        self.tagColorsOverride = tagColors
    }

    private var expiresSoon: Bool {
        surface == .tray && item.expiresSoon(after: expiryInterval ?? TraySettings.shared.expiry.interval, now: now)
    }

    private var tagColors: [Color] {
        tagColorsOverride ?? item.tags.compactMap { tag in state.pinboards.first { $0.name == tag }?.color }
    }

    public var body: some View {
        VStack(spacing: 7) {
            thumbnail
                .frame(width: Self.side, height: Self.side)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.11 : 0), lineWidth: 5)
                        .padding(-5)
                )
            HStack(spacing: 3) {
                ForEach(Array(tagColors.prefix(3).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
                Text(item.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: Self.width)
        }
        .frame(width: Self.width)
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isSelected)
        // Clicks, drags out, the context menu and hover, in AppKit.
        .overlay {
            TileInteraction(
                urls: { dragURLs?() ?? [item.url] },
                surface: surface,
                onClick: { count in
                    if count == 2 {
                        // The first click of the pair already toggled selection;
                        // undo that so opening leaves the selection as it was.
                        onSelect()
                        if let onOpen { onOpen() } else { item.openFile() }
                    } else {
                        onSelect()
                    }
                },
                onHover: { isHovered = $0 },
                menu: { menu?() ?? HeldItemsMenu.build(.init(items: [item], surface: .shelf, onPreview: { _ in onPreview() })) },
                onDragEnded: { accepted in
                    guard accepted, TraySettings.shared.removeOnDragOut else { return }
                    // Everything the drag carried (the selection it was part of).
                    let urls = Set((dragURLs?() ?? [item.url]).map(\.standardizedFileURL))
                    let held = state.shelfItems + state.baskets.flatMap(\.items)
                    let ids = Set(held.filter { urls.contains($0.url.standardizedFileURL) }.map(\.id))
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                        state.removeHeldItemsWithUndo(ids: ids)
                    }
                },
                help: helpText
            )
        }
        .overlay(alignment: .topLeading) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color.white))
                        // 17pt badge, 26pt hit target.
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Remove from \(surface == .tray ? "Tray" : "Basket")")
                .accessibilityLabel("Remove \(item.name)")
                .offset(x: Self.inset - 13 + 2.5, y: -13 + 2.5)
                .transition(DS.Motion.transition(reduceMotion, .scale.combined(with: .opacity)))
            }
        }
        .overlay(alignment: .top) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white))
                    .offset(y: -9)
                    .allowsHitTesting(false)
                    .transition(DS.Motion.transition(reduceMotion, .scale.combined(with: .opacity)))
            } else if showsSelectionCircle, isHovered {
                Circle()
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 17, height: 17)
                    .offset(y: -9)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            badges
                .frame(width: Self.side, height: Self.side, alignment: .bottomTrailing)
                .offset(x: Self.inset + 5, y: 5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if expiresSoon {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(DS.Palette.warning))
                    .offset(x: -Self.inset + 6, y: -6)
                    .help("Expires soon")
                    .allowsHitTesting(false)
            }
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Open") { if let onOpen { onOpen() } else { item.openFile() } }
        .accessibilityAction(named: "Quick Look") { onPreview() }
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { state.togglePin([item.id]) }
        .accessibilityAction(named: "Remove") { onDelete() }
    }

    @ViewBuilder
    private var badges: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(35))
                .frame(width: 16, height: 16)
                .background(Circle().fill(DS.accent))
        }
    }

    private var helpText: String {
        var text = "\(item.name) · \(item.formattedSize)"
        if item.isPinned { text += " · Pinned" }
        if expiresSoon { text += " · Expires soon" }
        if !item.tags.isEmpty { text += " · " + item.tags.joined(separator: ", ") }
        return text
    }

    private var accessibilityText: String {
        var text = "\(item.name), \(item.formattedSize)"
        if item.isPinned { text += ", pinned" }
        if expiresSoon { text += ", expires soon" }
        if !item.tags.isEmpty { text += ", tagged " + item.tags.joined(separator: ", ") }
        return text
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.isImage {
            // Decoded small and off the main thread: a 100 MP photo must not
            // be loaded whole just to fill a 56 pt tile.
            ShelfThumbnail(url: item.url, maxPixelSize: 112, contentMode: .fill) {
                Image(systemName: item.systemIconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(item.badgeColor)
            }
            .frame(width: Self.side, height: Self.side)
            .background(Color(white: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            Image(nsImage: FileIcon.image(for: item.url))
                .resizable()
                .scaledToFit()
                .frame(width: Self.side - 4, height: Self.side - 4)
                .frame(width: Self.side, height: Self.side)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(white: 0.07)))
        }
    }
}

// MARK: - Thumbnail

/// An image file drawn from a downsampled copy, decoded off the main thread
/// and kept in a small shared cache; `placeholder` shows until it's ready or
/// when the file can't be read (moved, deleted, not really an image).
struct ShelfThumbnail<Placeholder: View>: View {
    let url: URL
    let maxPixelSize: Int
    var contentMode: ContentMode = .fit
    @ViewBuilder let placeholder: () -> Placeholder

    @MainActor private static var cache: NSCache<NSString, NSImage> {
        ShelfThumbnailCache.shared
    }

    @State private var image: NSImage?
    /// The file couldn't be decoded: a fixed icon instead of the placeholder,
    /// which may be a spinner.
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: maxPixelSize > 200 ? 28 : 16, weight: .regular))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .help("This image can't be previewed")
                    .accessibilityLabel("Preview unavailable")
            } else {
                placeholder()
            }
        }
        .task(id: "\(url.path)#\(maxPixelSize)") {
            failed = false
            let key = "\(url.path)#\(maxPixelSize)" as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            let url = url, size = maxPixelSize
            let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            guard let cgImage else {
                image = nil
                failed = true
                return
            }
            let loaded = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            Self.cache.setObject(loaded, forKey: key)
            image = loaded
        }
    }
}

@MainActor
enum ShelfThumbnailCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 150
        return cache
    }()
}

// MARK: - Convert bar

/// Format chips over the tray, shown after a drop on the Convert tile.
private struct ConvertBar: View {
    let items: [ShelfItem]
    /// Written to only; the Tray passes `items` in, so nothing here is observed.
    private var state: AppState { AppState.shared }
    @ObservedObject private var jobCenter = JobCenter.shared

    /// Lives in JobCenter so collapsing the shelf mid-conversion loses nothing.
    private var runningJobs: [JobCenter.Job] { jobCenter.runningJobs.filter { $0.appName == "Convert" } }
    private var isConverting: Bool { !runningJobs.isEmpty }

    private var convertible: [ShelfItem] { items.filter { !$0.convertTargets.isEmpty } }

    var body: some View {
        // Worked out once per pass: each asks FileConverter about every file.
        let convertible = convertible
        let formats = FileConverter.commonTargets(for: convertible.map(\.url))
        return VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Convert")
                        .font(.system(size: 13, weight: .bold))
                    Text(isConverting ? "Converting…" : convertible.isEmpty ? "These files can't be converted" : "\(convertible.count) file\(convertible.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchPalette.secondary)
                }
                Spacer()
                // Closing the bar leaves the job running; its progress stays in the notch.
                NotchCircleButton("xmark", size: 26, iconSize: 10, help: isConverting ? "Hide" : "Cancel") {
                    state.pendingConvert = nil
                }
            }
            ForEach(runningJobs) { job in
                JobRow(job: job) { jobCenter.cancel(job.id) }
            }
            HStack(spacing: 8) {
                ForEach(formats.prefix(Self.visibleChips), id: \.self) { format in
                    Button {
                        convert(to: format)
                    } label: {
                        chip(format)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .help("Convert to \(format)")
                    .accessibilityLabel("Convert to \(format)")
                }
                // The rest go behind a menu instead of being silently dropped.
                if formats.count > Self.visibleChips {
                    Menu {
                        ForEach(formats.dropFirst(Self.visibleChips), id: \.self) { format in
                            Button(format) { convert(to: format) }
                        }
                    } label: {
                        chip("More", systemImage: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("More formats")
                }
            }
            .disabled(isConverting)
            .opacity(isConverting ? 0.4 : 1)
        }
        .foregroundStyle(.white)
        .padding(DS.Space.lg)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.09)))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Five chips fit the shelf width; a sixth slot holds "More" when needed.
    private static let visibleChips = 5

    private func chip(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NotchPalette.control))
        .contentShape(Rectangle())
    }

    private func convert(to format: String) {
        let state = state
        ConvertActions.convert(convertible, to: format) { _ in
            state.pendingConvert = nil
        }
    }
}

// MARK: - Shared actions

@MainActor
public enum TrayActions {
    public static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard service.canPerform(withItems: urls) else {
            AppState.shared.showNotification(
                appName: "AirDrop",
                title: "Can't send these files",
                message: "AirDrop is off or refused the current selection."
            )
            return
        }
        DroppyAudio.playTick()
        service.perform(withItems: urls)
    }

    /// Whether a screen point is over the island or one of Tama's own windows.
    public static func isOverDroppy(_ point: NSPoint) -> Bool {
        NotchWindowController.shared.isOverIsland(point)
            || NSApp.windows.contains { $0.isVisible && $0.frame.contains(point) && !($0 is DroppyNotchPanel) }
    }

    /// Where a tile drag started. Each surface ignores drags of its own
    /// tiles, while a Tray tile can still be dropped on a Basket (and back).
    public enum DragSurface: Sendable { case tray, basket }

    /// The surface a file is currently being dragged out of, if any.
    public static var internalDragSource: DragSurface?

    /// Quick Snip to Tray: an area capture that goes only to the Tray, through
    /// the same overlay and ScreenCaptureKit path as Element Capture.
    public static func snipToTray() {
        ScreenCaptureService.shared.capture(
            .area,
            destinations: CaptureDestinations(clipboard: false, tray: true, folder: false, editor: false),
            revealTray: true
        )
    }
}

// MARK: - Drop delegate

/// A plain file drop target that ignores its own surface's tiles being
/// dragged out (see `TrayActions.internalDragSource`).
struct ShelfDropDelegate: DropDelegate {
    let surface: TrayActions.DragSurface
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !isOwnDrag && info.hasItemsConforming(to: DragDropService.acceptedTypes)
    }

    private var isOwnDrag: Bool { TrayActions.internalDragSource == surface }

    func dropEntered(info: DropInfo) {
        guard !isOwnDrag else { return }
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard !isOwnDrag else { return false }
        perform(info.itemProviders(for: DragDropService.acceptedTypes))
        return true
    }
}
