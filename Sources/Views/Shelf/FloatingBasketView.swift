import SwiftUI
import UniformTypeIdentifiers

/// A floating Basket: its own files, gathered from anywhere, in a grid or a
/// list. The header says how many files and how big; "To Shelf" moves them
/// onto the Shelf. While a file drag hovers it, it turns into the Quick
/// Action tiles. It collapses to a pill that still accepts drops. Several can
/// be out at once in Multi-Basket mode, each in its own colour.
public struct FloatingBasketView: View {
    let basketID: UUID
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var basketSettings = BasketSettings.shared
    @ObservedObject private var traySettings = TraySettings.shared
    @State private var isDropTargeted = false
    @State private var isMinimized = false
    @State private var isHovered = false
    @State private var previewItem: ShelfItem?
    @State private var browsingFolder: ShelfItem?
    @State private var selection = Set<UUID>()
    /// Last plainly clicked file: shift-click selects the run from here, and
    /// the arrow keys move from here.
    @State private var selectionAnchor: UUID?
    /// Second bucket: 0 is the main bucket, 1 the one for rarely used files.
    @State private var bucket = 0
    /// Tile under a file drag over the open Basket.
    @State private var hoveredAction: QuickAction?
    /// The files a drag picked up; ones added mid-drag stay.
    @State private var draggedIDs = Set<UUID>()
    /// List row under the pointer, for hover feedback.
    @State private var hoveredRowID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `.key` while this Basket's panel holds the keyboard.
    @Environment(\.controlActiveState) private var activeState

    /// Shown while the keys would reach this Basket, so it's clear where an
    /// arrow or a ⌫ is about to land — and that the app underneath isn't
    /// getting them.
    private var hasKeyboard: Bool { activeState == .key }

    public init(basketID: UUID) {
        self.basketID = basketID
    }

    private var basket: Basket? { state.basket(basketID) }
    private var tint: Color { basket?.color ?? DS.accent }
    private var allItems: [ShelfItem] { basket?.items ?? [] }

    /// The files in the bucket on show.
    private var items: [ShelfItem] {
        guard basketSettings.secondBucket else { return allItems }
        return allItems.filter { $0.stack == bucket }
    }

    private var targets: [ShelfItem] {
        let picked = items.filter { selection.contains($0.id) }
        return picked.isEmpty ? items : picked
    }

    private func menuTargets(for item: ShelfItem) -> [ShelfItem] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }

    @ViewBuilder
    public var body: some View {
        if isMinimized {
            minimizedPill
        } else {
            fullBasket
        }
    }

    // MARK: Minimized

    private var minimizedPill: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "basket.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            if !allItems.isEmpty {
                Text("\(allItems.count)")
                    .font(DS.Typo.numeric)
                    .foregroundStyle(DS.Palette.textPrimary)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: 30)
        .background(Capsule().fill(Color.black.opacity(0.88)))
        .overlay(
            Capsule().strokeBorder(
                isDropTargeted ? tint : DS.Palette.hairlineStrong,
                lineWidth: isDropTargeted ? 1.5 : 1
            )
        )
        .dsShadow(.mid)
        .scaleEffect(reduceMotion ? 1 : (isDropTargeted ? 1.08 : (isHovered ? 1.04 : 1)))
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isDropTargeted)
        .onHover { isHovered = $0 }
        .help("Basket · \(allItems.count) item\(allItems.count == 1 ? "" : "s") — click to open, or drop files here")
        .onTapGesture { setMinimized(false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Basket, \(allItems.count) item\(allItems.count == 1 ? "" : "s")")
        .accessibilityHint("Opens the Basket")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setMinimized(false) }
        .onChange(of: isDropTargeted) { _, targeted in if targeted { DroppyAudio.playTick() } }
        .onDrop(of: DragDropService.acceptedTypes, delegate: ShelfDropDelegate(surface: .basket, isTargeted: $isDropTargeted, perform: accept))
    }

    // MARK: Expanded

    private var fullBasket: some View {
        ZStack {
            if isDropTargeted {
                actionTiles
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.97))))
            } else {
                VStack(spacing: DS.Space.sm) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 34, height: 4)
                        .accessibilityHidden(true)
                    header
                    content
                }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isDropTargeted)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.md)
        .frame(width: FloatingBasketController.fullSize.width, height: FloatingBasketController.fullSize.height)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.78)
                tint.opacity(0.10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(tint.opacity(hasKeyboard ? 0.85 : 0.35), lineWidth: hasKeyboard ? 1.5 : 1)
        )
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: hasKeyboard)
        .dsShadow(.high)
        .onDrop(of: DragDropService.acceptedTypes, delegate: BasketDropDelegate(
            actions: state.quickActions, isTargeted: $isDropTargeted, hovered: $hoveredAction, perform: perform
        ))
        .background { keyboardShortcuts }
        .sheet(item: $previewItem) { item in
            ShelfItemPreviewModal(item: item) { previewItem = nil }
        }
        .sheet(item: $browsingFolder) { folder in
            FolderBrowserSheet(root: folder.url) { browsingFolder = nil }
        }
        .onChange(of: previewItem?.id) { _, _ in syncModal() }
        .onChange(of: browsingFolder?.id) { _, _ in syncModal() }
        .onChange(of: allItems.map(\.id)) { old, ids in
            selection.formIntersection(ids)
            // A file can go without anyone pressing a key — pruned when it
            // vanishes from Finder, or moved to the Shelf from a menu. Step to
            // the neighbour rather than leave a dead anchor, which sent the
            // next arrow key back to the first file. Same as the Tray.
            if let anchor = selectionAnchor, !ids.contains(anchor) {
                selectionAnchor = FocusAfterRemoval.next(after: anchor, in: old, surviving: Set(ids))
            }
        }
        .onChange(of: bucket) { _, _ in selectionAnchor = nil }
        // Same as the Tray page: files gone from disk don't stay as dead tiles.
        .onAppear { state.pruneMissingShelfItems() }
    }

    // MARK: Keyboard

    /// The same keys the Tray answers, for the Basket. The panel takes focus
    /// when it is clicked (`BasketPanel`), so these only ever fire for the
    /// Basket somebody is actually working in.
    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Button("Select All", action: selectAll)
                .keyboardShortcut("a", modifiers: .command)
            Button("Remove Selected", action: removeSelection)
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection.isEmpty)
            Button("Quick Look Selected") {
                QuickLookService.shared.preview(selectedItems.map(\.url))
            }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(selection.isEmpty)
            Button("Open Selected") { selectedItems.forEach { open($0) } }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selection.isEmpty)
            // The grid's columns depend on the width it is given, so all four
            // arrows step through the files in order rather than pretending to
            // know where a row ends.
            Button("Next File") { moveFocus(by: 1, extend: false) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Previous File") { moveFocus(by: -1, extend: false) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next File (down)") { moveFocus(by: 1, extend: false) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Previous File (up)") { moveFocus(by: -1, extend: false) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Extend Selection Forward") { moveFocus(by: 1, extend: true) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Extend Selection Back") { moveFocus(by: -1, extend: true) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("Move Selected To…") { FileOperations.moveWithPicker(selectedItems) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(selection.isEmpty)
            Button("Copy Selected") {
                FileOperations.copyToPasteboard(selectedItems)
                DroppyAudio.playCopySuccess()
            }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selection.isEmpty)
            Button("Move Selected to Shelf") {
                state.moveToShelf(selection)
                selection.removeAll()
            }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(selection.isEmpty)
            Button("Undo") { state.performActiveUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(state.activeNotification?.actionTitle != "Undo")
            // The window keys the title bar would carry, for a panel that
            // hasn't got one.
            Button("Minimize", action: { setMinimized(true) })
                .keyboardShortcut("m", modifiers: .command)
            Button("Close Basket") {
                state.closeBasket(basketID)
                DroppyAudio.playTick()
            }
                .keyboardShortcut("w", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The files the keys act on: the selection, in the order they are drawn.
    private var selectedItems: [ShelfItem] {
        items.filter { selection.contains($0.id) }
    }

    private func selectAll() {
        guard !items.isEmpty else { return }
        selection = Set(items.map(\.id))
        DroppyAudio.playTick()
    }

    private func moveFocus(by step: Int, extend: Bool) {
        let ids = items.map(\.id)
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

    /// ⌫ keeps the keyboard on the nearest file that survives, so pressing
    /// it again carries on down the list instead of doing nothing.
    private func removeSelection() {
        guard !selection.isEmpty else { return }
        let order = items.map(\.id)
        let surviving = Set(order).subtracting(selection)
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
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
            state.removeBasketItemsWithUndo(ids: selection)
        }
        selection = next.map { [$0] } ?? []
        selectionAnchor = next
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Circle().fill(tint).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(allItems.isEmpty ? "Basket" : "\(allItems.count) file\(allItems.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(DS.Palette.textPrimary)
                if !allItems.isEmpty {
                    Text(ByteCountFormatter.string(fromByteCount: basket?.totalSize ?? 0, countStyle: .file))
                        .font(DS.Typo.caption.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            // The title is a handle: drag it to take every file (or the selection).
            .overlay {
                if !allItems.isEmpty {
                    MultiFileDragSource(urls: {
                        let picked = targets
                        draggedIDs = Set(picked.map(\.id))
                        return picked.map(\.url)
                    }, surface: .basket, onEnded: { accepted in
                        guard accepted, traySettings.removeOnDragOut else { return }
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeBasketItemsWithUndo(ids: draggedIDs) }
                    }, help: dragHelp)
                }
            }
            .help(dragHelp)

            if basketSettings.secondBucket { bucketPicker }

            Spacer(minLength: DS.Space.xs)

            if !allItems.isEmpty {
                DroppyIconButton(basketSettings.layout == .grid ? "list.bullet" : "square.grid.2x2", size: 22, tone: .tonal,
                                 help: basketSettings.layout == .grid ? "Show as list" : "Show as grid") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                        basketSettings.layout = basketSettings.layout == .grid ? .list : .grid
                    }
                    DroppyAudio.playTick()
                }
                Button {
                    state.moveToShelf(Set(targets.map(\.id)))
                    selection.removeAll()
                } label: {
                    Label("To Shelf", systemImage: "arrow.up.to.line")
                        .font(DS.Typo.labelStrong)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(DS.accent))
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help(selection.isEmpty ? "Move every file to the Shelf" : "Move the selected files to the Shelf")
                .accessibilityLabel(selection.isEmpty ? "Move every file to the Shelf" : "Move the selected files to the Shelf")
                DroppyIconButton("eraser", size: 22, tone: .tonal, help: selection.isEmpty ? "Clear Basket" : "Remove selected") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                        if selection.isEmpty {
                            state.clearBasketWithUndo(basketID)
                        } else {
                            state.removeBasketItemsWithUndo(ids: selection)
                            selection.removeAll()
                        }
                    }
                }
            }
            DroppyIconButton("minus", size: 20, help: "Minimize to a pill") { setMinimized(true) }
            DroppyIconButton("xmark", size: 20, help: allItems.isEmpty || basketSettings.mode == .single ? "Close" : "Put away (files are kept)") {
                state.closeBasket(basketID)
                DroppyAudio.playTick()
            }
        }
        .padding(.horizontal, DS.Space.lg)
    }

    private var dragHelp: String {
        allItems.isEmpty ? "Drop files here" : "Drag to take \(selection.isEmpty ? "all \(items.count) files" : "the \(selection.count) selected") out"
    }

    private var bucketPicker: some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { index in
                let count = allItems.filter { $0.stack == index }.count
                Button {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { bucket = index }
                    selection.removeAll()
                    DroppyAudio.playTick()
                } label: {
                    Text(index == 0 ? "Main\(count > 0 ? " \(count)" : "")" : "2nd\(count > 0 ? " \(count)" : "")")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(bucket == index ? .black : .white)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Capsule().fill(bucket == index ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help(index == 0 ? "Main bucket" : "Second bucket, for rarely used items")
                .accessibilityLabel("\(index == 0 ? "Main bucket" : "Second bucket"), \(count) item\(count == 1 ? "" : "s")")
                .accessibilityAddTraits(bucket == index ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(DS.Palette.surface2))
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.surfaceGhost)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
            if items.isEmpty {
                DroppyEmptyState(
                    systemName: "arrow.down.doc",
                    title: bucket == 1 ? "Second bucket is empty" : "Drop files here",
                    compact: true
                )
            } else if basketSettings.layout == .grid {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: DS.Space.md)], spacing: DS.Space.lg) {
                        ForEach(items) { item in
                            TrayFileTile(
                                item: item,
                                isSelected: selection.contains(item.id),
                                showsSelectionCircle: true,
                                onSelect: { toggle(item) },
                                onOpen: { open(item) },
                                onDelete: { withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeBasketItemsWithUndo(ids: [item.id]) } },
                                onPreview: { previewItem = item },
                                surface: .basket,
                                dragURLs: { dragURLs(for: item) },
                                menu: { menu(for: item) }
                            )
                            .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.lg)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in row(item) }
                    }
                    .padding(DS.Space.sm)
                }
            }
        }
        .padding(.horizontal, DS.Space.md)
    }

    private func row(_ item: ShelfItem) -> some View {
        let isSelected = selection.contains(item.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? tint : DS.Palette.textTertiary)
                .accessibilityHidden(true)
            Image(nsImage: FileIcon.image(for: item.url))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(item.name)
                .font(DS.Typo.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(DS.accent)
                    .accessibilityLabel("Pinned")
            }
            Spacer()
            Text(item.formattedSize)
                .font(DS.Typo.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(isSelected ? tint.opacity(0.18) : (hoveredRowID == item.id ? DS.Palette.surface1 : Color.clear))
        )
        .overlay {
            TileInteraction(
                urls: { dragURLs(for: item) },
                surface: .basket,
                onClick: { count in
                    if count == 2 { open(item) } else { toggle(item) }
                },
                onHover: { hovering in
                    if hovering { hoveredRowID = item.id } else if hoveredRowID == item.id { hoveredRowID = nil }
                },
                menu: { menu(for: item) },
                onDragEnded: { accepted in
                    guard accepted, traySettings.removeOnDragOut else { return }
                    state.removeBasketItemsWithUndo(ids: draggedIDs)
                },
                help: "\(item.name) · \(item.formattedSize)"
            )
        }
        .help("\(item.name) · \(item.formattedSize)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { toggle(item) }
        .accessibilityAction(named: "Open") { open(item) }
        .accessibilityAction(named: "Quick Look") { previewItem = item }
        .accessibilityAction(named: "Remove from Basket") {
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.removeBasketItemsWithUndo(ids: [item.id]) }
        }
    }

    // MARK: Drop tiles

    /// While a file drag hovers the open Basket it turns into the Quick
    /// Action tiles, like the notch does.
    private var actionTiles: some View {
        let actions = state.quickActions
        return VStack(spacing: BasketDropDelegate.gap) {
            ForEach(Array(BasketDropDelegate.rows(for: actions).enumerated()), id: \.offset) { _, row in
                HStack(spacing: BasketDropDelegate.gap) {
                    ForEach(row) { action in tile(action) }
                }
            }
        }
        .padding(BasketDropDelegate.inset)
    }

    private func tile(_ action: QuickAction) -> some View {
        let isHovered = hoveredAction == action
        return VStack(spacing: 7) {
            Image(systemName: action.iconName)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)
            Text(action == .keep ? "Drop" : action.title)
                .font(DS.Typo.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(isHovered ? NotchPalette.tileHover : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(isHovered ? tint.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHovered ? "active" : "idle")
    }

    private func perform(_ action: QuickAction, _ providers: [NSItemProvider]) {
        let origin = QuickActionRunner.Origin.basket(basketID, bucket: bucket)
        DragDropService.shared.handleDrop(providers: providers) { items in
            guard !items.isEmpty else { return state.notifyNothingAdded() }
            QuickActionRunner.perform(action, items: items, from: origin)
        }
    }

    // MARK: Helpers

    private func toggle(_ item: ShelfItem) {
        let ids = items.map(\.id)
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

    private func open(_ item: ShelfItem) {
        if item.isDirectory, item.isPinned { browsingFolder = item } else { item.openFile() }
    }

    private func dragURLs(for item: ShelfItem) -> [URL] {
        let picked = menuTargets(for: item)
        draggedIDs = Set(picked.map(\.id))
        return picked.map(\.url)
    }

    private func menu(for item: ShelfItem) -> NSMenu {
        HeldItemsMenu.build(.init(
            items: menuTargets(for: item),
            surface: .basket(basketID),
            onPreview: { previewItem = $0 },
            onBrowseFolder: { browsingFolder = $0 },
            clearSelection: { selection.removeAll() }
        ))
    }

    /// Each Basket owns its own slot: two Baskets can have a preview up at
    /// once, and closing one must not clear the other's.
    private var modalOwner: String { "basket.\(basketID.uuidString)" }

    private func syncModal() {
        state.setModal(previewItem != nil || browsingFolder != nil, owner: modalOwner)
    }

    private func setMinimized(_ minimized: Bool) {
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { isMinimized = minimized }
        FloatingBasketController.shared.updatePanelSize(basketID, isMinimized: minimized)
        DroppyAudio.playTick()
    }

    private func accept(_ providers: [NSItemProvider]) {
        let id = basketID, bucket = bucket
        DragDropService.shared.handleDrop(providers: providers) { items in
            guard !items.isEmpty else { return state.notifyNothingAdded() }
            state.addBasketItems(items, to: id, bucket: bucket)
            DroppyAudio.playDropSuccess()
        }
    }
}

/// Tracks which of the Basket's drop tiles is under the pointer. The tiles
/// are laid out in rows of two (a lone last tile spans the row), so the
/// pointer's position alone picks one.
private struct BasketDropDelegate: DropDelegate {
    static let inset: CGFloat = 10
    static let gap: CGFloat = 8

    let actions: [QuickAction]
    @Binding var isTargeted: Bool
    @Binding var hovered: QuickAction?
    let perform: (QuickAction, [NSItemProvider]) -> Void

    static func rows(for actions: [QuickAction]) -> [[QuickAction]] {
        stride(from: 0, to: actions.count, by: 2).map { Array(actions[$0..<min($0 + 2, actions.count)]) }
    }

    private func action(at point: CGPoint) -> QuickAction {
        let size = FloatingBasketController.fullSize
        let rows = Self.rows(for: actions)
        guard !rows.isEmpty else { return .keep }
        let rowHeight = size.height / CGFloat(rows.count)
        let row = rows[min(max(Int(point.y / rowHeight), 0), rows.count - 1)]
        if row.count == 1 { return row[0] }
        return point.x < size.width / 2 ? row[0] : row[1]
    }

    /// A tile dragged out of a Basket mustn't turn it into drop tiles.
    func validateDrop(info: DropInfo) -> Bool {
        TrayActions.internalDragSource != .basket && info.hasItemsConforming(to: DragDropService.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard TrayActions.internalDragSource != .basket else { return }
        isTargeted = true
        hovered = action(at: info.location)
        DroppyAudio.playTick()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = action(at: info.location)
        if next != hovered { hovered = next }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        hovered = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let chosen = action(at: info.location)
        isTargeted = false
        hovered = nil
        guard TrayActions.internalDragSource != .basket else { return false }
        perform(chosen, info.itemProviders(for: DragDropService.acceptedTypes))
        return true
    }
}
