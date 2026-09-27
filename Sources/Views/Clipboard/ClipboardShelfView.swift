import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Alpha clipboard: a black shelf docked to the bottom of the screen with
/// a row of clip cards, a Clipboard tab, your pinboards and your tags.
public struct ClipboardShelfView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var privacy = ClipboardPrivacy.shared
    @ObservedObject private var browser = ClipboardBrowser.shared
    @State private var renamingID: UUID?
    /// False for the first pass after the controller mounts this view, so it
    /// starts below the panel and `isShown` changes — slide-in and focus run.
    @State private var hasAppeared = false
    @State private var isAddingBoard = false
    @State private var newBoardName = ""
    /// The typed pinboard name is already taken; the field stays open, ringed.
    @State private var boardNameTaken = false
    /// The tab a card is being dragged over.
    @State private var targetedTab: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var keyboardFocused: Bool
    @FocusState private var boardFieldFocused: Bool
    @Namespace private var tabIndicator

    public init() {}

    private var clips: [ClipboardItem] { browser.clips(from: state.clipboardItems) }

    public var body: some View {
        // Filtered once per pass: the search runs over every clip's content
        // and OCR text, and the header, cards and onChange all need the list.
        let list = clips
        return VStack(spacing: 11) {
            header(list)
            favoritesBar
            cards(list)
        }
        .padding(.top, 11)
        .padding(.horizontal, 12 + 21)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ClipboardDockShape(topRadius: 26, earRadius: 21)
                .fill(Color.black)
                .overlay(
                    ClipboardDockShape(topRadius: 26, earRadius: 21)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .offset(y: isShown ? 0 : ClipboardWindowController.height + 20)
        // ClipboardWindowController.slideOutDelay waits for this slide.
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: isShown)
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onKeyPress(action: handleKey)
        // A new search (or clips arriving) can filter the selection away;
        // keep one selected so Return still pastes.
        .onChange(of: browser.query) { _, _ in browser.select(clips.first?.id) }
        .onChange(of: list.map(\.id)) { _, ids in
            browser.reconcile(with: list)
            // The clip being renamed can leave the list without the field ever
            // closing — pruned by retention, deleted elsewhere, or simply
            // filtered out by a board, tag or type. Its id then stayed set and
            // `handleKey` refused every key, so the keyboard went dead until
            // the clipboard was closed and opened again.
            if let renamingID, !ids.contains(renamingID) { self.renamingID = nil }
        }
        .onAppear { DispatchQueue.main.async { hasAppeared = true } }
        .onChange(of: isShown) { _, visible in
            if visible {
                browser.select(clips.first?.id)
                // Settings › Clipboard › Auto-focus: straight into search.
                if state.clipboardAutoFocusSearch {
                    browser.isSearching = true
                    searchFocused = true
                } else {
                    keyboardFocused = true
                }
            } else {
                browser.reset()
                renamingID = nil
                isAddingBoard = false
                newBoardName = ""
                boardNameTaken = false
            }
        }
    }

    /// Only the Alpha layout slides this shelf in.
    private var isShown: Bool { hasAppeared && state.isClipboardVisible && state.clipboardLayout == .alpha }

    // MARK: Favorites bar

    /// Settings › Clipboard › Favorites bar: the starred clips as a strip of
    /// chips above the cards, so they stay one click away whatever the search
    /// or the pinboard tab is showing.
    private var favorites: [ClipboardItem] { state.clipboardItems.filter(\.isPinned) }

    @ViewBuilder
    private var favoritesBar: some View {
        if state.clipboardFavoritesBar, !favorites.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(favorites) { item in
                        favoriteChip(item)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 26)
            .transition(DS.Motion.transition(reduceMotion, .opacity))
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: favorites.map(\.id))
            .accessibilityLabel("Favorites")
        }
    }

    private func favoriteChip(_ item: ClipboardItem) -> some View {
        Button {
            ClipboardWindowController.shared.paste([item])
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityHidden(true)
                Text(item.displayTitle)
                    .font(DS.Typo.label)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .frame(maxWidth: 150)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help("Paste \u{201C}\(item.displayTitle)\u{201D}")
        .accessibilityLabel("Favorite: \(item.displayTitle)")
        .contextMenu {
            Button { ClipboardWindowController.shared.paste([item]) } label: {
                Label("Paste", systemImage: "arrow.down.doc")
            }
            Button {
                if state.copyClipboardItems([item]) { DroppyAudio.playCopySuccess() }
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            Divider()
            Button { state.togglePin(item) } label: {
                Label("Take this favorite off the bar", systemImage: "star.slash")
            }
        }
    }

    // MARK: Header

    private func header(_ list: [ClipboardItem]) -> some View {
        ZStack {
            if browser.isMultiSelecting {
                bulkBar(list).transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96))))
            } else if browser.isSearching {
                searchField.transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.96))))
            } else {
                tabs.transition(.opacity)
            }
            if !browser.isMultiSelecting {
                HStack(spacing: 8) {
                    Spacer()
                    if privacy.isPaused {
                        pausedPill.transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.9))))
                    }
                    moreMenu
                }
            }
        }
        .frame(height: 29)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: browser.isSearching)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: browser.isMultiSelecting)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: privacy.isPaused)
    }

    private var tabs: some View {
        // Scrolls once there are more pinboards than fit; the trailing inset
        // keeps the last tab from sliding under the ⋯ menu.
        ScrollView(.horizontal, showsIndicators: false) {
            tabRow
        }
        .horizontalEdgeFade(12)
        .padding(.trailing, 29 + 8 + (privacy.isPaused ? pausedPillWidth + 8 : 0))
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            circleButton("magnifyingglass", help: "Search") {
                browser.isSearching = true
                searchFocused = true
            }
            if state.clipboardTypeFilters {
                filterRow
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 3)
            tab(title: "Clipboard", board: nil, color: nil)
            ForEach(state.pinboards) { pinboard in
                tab(title: pinboard.name, board: pinboard.name, color: pinboard.color)
                    .contextMenu {
                        // Undo from the toast puts the board and its clips back.
                        Button(role: .destructive) {
                            if browser.board == pinboard.name { browser.showBoard(nil) }
                            state.removePinboard(pinboard)
                        } label: { Label("Delete Pinboard", systemImage: "trash") }
                    }
            }
            if isAddingBoard {
                TextField("Name", text: $newBoardName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 90)
                    .padding(.horizontal, 12)
                    .frame(height: 29)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(DS.Palette.danger, lineWidth: 1.5).opacity(boardNameTaken ? 1 : 0))
                    .help(boardNameTaken ? "There's already a pinboard with this name" : "Name the new pinboard, then press Return")
                    .focused($boardFieldFocused)
                    .onAppear { boardFieldFocused = true }
                    .onChange(of: newBoardName) { _, _ in boardNameTaken = false }
                    .onSubmit(submitBoardName)
                    // Clicking away drops the half-made tab, without pulling
                    // focus back from wherever the click went.
                    .onChange(of: boardFieldFocused) { _, focused in
                        guard !focused, isAddingBoard else { return }
                        newBoardName = ""
                        boardNameTaken = false
                        isAddingBoard = false
                    }
                    .onExitCommand(perform: endAddingBoard)
                    .accessibilityLabel(boardNameTaken ? "New pinboard name, already in use" : "New pinboard name")
            } else {
                circleButton("plus", help: "Create pinboard") { isAddingBoard = true }
            }
            if state.clipboardTagsEnabled, !state.clipboardTags.isEmpty {
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 3)
                ForEach(state.clipboardTags) { tag in
                    tagTab(tag)
                }
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: browser.board)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: browser.tag)
    }

    /// Show only one kind of clip: favourites, text, images, links, colours or files.
    private var filterRow: some View {
        HStack(spacing: 1) {
            ForEach(ClipFilter.allCases) { filter in
                let isActive = browser.kind == filter
                Button {
                    browser.kind = filter
                    browser.select(clips.first?.id)
                    DroppyAudio.playTick()
                } label: {
                    Image(systemName: filter.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(isActive ? 1 : 0.6))
                        .frame(width: 27, height: 27)
                        .background(Circle().fill(Color.white.opacity(isActive ? 0.14 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help(filter.title)
                .accessibilityLabel(filter.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: browser.kind)
    }

    private func tab(title: String, board target: String?, color: Color?) -> some View {
        let isActive = browser.board == target && browser.tag == nil
        // Pinboard names are never empty, so "" stands for the Clipboard tab.
        let key = target ?? ""
        let isTargeted = targetedTab == key && ClipDrag.current != nil
        return Button {
            browser.showBoard(target)
            browser.select(clips.first?.id)
            DroppyAudio.playTick()
        } label: {
            HStack(spacing: 7) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.88))
            }
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .matchedGeometryEffect(id: "tab", in: tabIndicator)
                }
            }
            .overlay(Capsule().strokeBorder(DS.accent, lineWidth: 1.5).opacity(isTargeted ? 1 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isTargeted)
        .accessibilityLabel(target == nil ? title : "Pinboard \(title)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // Drag a card onto a tab to file it there. Image and file cards carry
        // their real image or files, so the card is found by the drag itself.
        .onDrop(of: [.plainText, .fileURL, .image], isTargeted: Binding(
            get: { targetedTab == key },
            set: { targeted in
                if targeted { targetedTab = key } else if targetedTab == key { targetedTab = nil }
            }
        )) { _ in
            guard let id = ClipDrag.current,
                  let item = state.clipboardItems.first(where: { $0.id == id }) else { return false }
            ClipDrag.current = nil
            state.assign(item, to: target)
            return true
        }
    }

    /// A tag's tab: its clips, whatever pinboard they're on. Dropping a card
    /// on it adds the tag.
    private func tagTab(_ tag: ClipTag) -> some View {
        let isActive = browser.tag == tag.name
        let key = "#" + tag.name
        let isTargeted = targetedTab == key && ClipDrag.current != nil
        return Button {
            browser.showTag(tag.name)
            browser.select(clips.first?.id)
            DroppyAudio.playTick()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(tag.color)
                Text(tag.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.88))
            }
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .matchedGeometryEffect(id: "tab", in: tabIndicator)
                }
            }
            .overlay(Capsule().strokeBorder(DS.accent, lineWidth: 1.5).opacity(isTargeted ? 1 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .contextMenu {
            Button(role: .destructive) {
                if browser.tag == tag.name { browser.showBoard(nil) }
                state.removeClipTag(tag)
            } label: { Label("Delete Tag", systemImage: "trash") }
        }
        .onDrop(of: [.plainText, .fileURL, .image], isTargeted: Binding(
            get: { targetedTab == key },
            set: { targeted in
                if targeted { targetedTab = key } else if targetedTab == key { targetedTab = nil }
            }
        )) { _ in
            guard let id = ClipDrag.current,
                  let item = state.clipboardItems.first(where: { $0.id == id }) else { return false }
            ClipDrag.current = nil
            if !item.tags.contains(tag.name) { state.toggleClipTag(tag.name, on: [id]) }
            return true
        }
        .accessibilityLabel("Tag \(tag.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func circleButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 29, height: 29)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            TextField("Search clipboard", text: $browser.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .focused($searchFocused)
                // Return pastes the highlighted match; ↑ ↓ step through them
                // without leaving the field.
                .onSubmit {
                    if clips.contains(where: { $0.id == browser.selectedID }) {
                        paste(plainText: NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.shift))
                    } else {
                        keyboardFocused = true
                    }
                }
                .onKeyPress(.upArrow) { browser.move(by: -1, in: clips); return .handled }
                .onKeyPress(.downArrow) { browser.move(by: 1, in: clips); return .handled }
                // First Esc leaves search and hands keys back to the cards;
                // the next one reaches handleKey and closes the shelf.
                .onExitCommand(perform: endSearch)
            Button(action: endSearch) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("Close search")
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 12)
        .frame(width: 320, height: 29)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    /// Several cards picked: act on all of them at once.
    private func bulkBar(_ clips: [ClipboardItem]) -> some View {
        let targets = browser.targets(in: clips)
        let ids = Set(targets.map(\.id))
        return HStack(spacing: 6) {
            Text("\(targets.count) selected")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 29)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            circleButton("arrow.down.doc", help: "Paste all selected items") { paste() }
            circleButton("doc.on.doc", help: "Copy \(targets.count) items") {
                if state.copyClipboardItems(targets) { DroppyAudio.playCopySuccess() }
            }
            circleButton(targets.allSatisfy(\.isPinned) ? "star.slash" : "star",
                         help: targets.allSatisfy(\.isPinned) ? "Remove from favorites" : "Add to favorites") {
                state.toggleFavorite(ids)
            }
            Menu {
                ForEach(state.pinboards) { board in
                    Button(board.name) { state.assign(ids, to: board.name) }
                }
                Divider()
                Button("Remove from Pinboard") { state.assign(ids, to: nil) }
            } label: { menuGlyph("pin") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Pin to a pinboard")
                .accessibilityLabel("Pin to a pinboard")
            if state.clipboardTagsEnabled {
                Menu {
                    ForEach(state.clipboardTags) { tag in
                        Button(tag.name) { state.toggleClipTag(tag.name, on: ids) }
                    }
                    if !state.clipboardTags.isEmpty { Divider() }
                    Button("New Tag…") { state.promptNewClipTag(for: ids) }
                } label: { menuGlyph("tag") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Tag selected items")
                    .accessibilityLabel("Tag selected items")
            }
            circleButton("trash", help: "Delete \(targets.count) items") {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.deleteClipboardItems(ids: ids) }
                browser.select(clips.first?.id)
            }
            Spacer()
            circleButton("xmark", help: "Clear selection") {
                browser.select(browser.selectedID)
                keyboardFocused = true
            }
        }
    }

    private func menuGlyph(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 29, height: 29)
            .background(Circle().fill(Color.white.opacity(0.07)))
    }

    /// Hands the keys back to the cards, or ← → and Return would stay dead.
    private func endAddingBoard() {
        newBoardName = ""
        boardNameTaken = false
        isAddingBoard = false
        keyboardFocused = true
    }

    /// A blank name just closes the field; a taken one keeps it open so it
    /// can be changed.
    private func submitBoardName() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return endAddingBoard() }
        guard state.addPinboard(named: name) else {
            boardNameTaken = true
            boardFieldFocused = true
            NSSound.beep()
            return
        }
        endAddingBoard()
    }

    private func endSearch() {
        browser.query = ""
        browser.isSearching = false
        searchFocused = false
        keyboardFocused = true
    }

    private let pausedPillWidth: CGFloat = 150

    /// Recording is off: says so in the header, and one click turns it back on.
    private var pausedPill: some View {
        Button {
            privacy.resume()
            DroppyAudio.playTick()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(DS.Palette.warning)
                Text("Paused")
                    .foregroundStyle(.white.opacity(0.9))
                Text("· Resume")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(width: pausedPillWidth, height: 29)
            .background(Capsule().fill(DS.Palette.warning.opacity(0.16)))
            .overlay(Capsule().strokeBorder(DS.Palette.warning.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .help("\(privacy.pauseDescription). Click to resume.")
        .accessibilityLabel("Clipboard paused. Resume")
    }

    private var moreMenu: some View {
        Menu {
            if privacy.isPaused {
                Button { privacy.resume() } label: { Label("Resume Clipboard", systemImage: "play.circle") }
            } else {
                Menu {
                    ForEach(ClipboardPauseDuration.allCases) { duration in
                        Button(duration.title) { privacy.pause(duration) }
                    }
                } label: { Label("Pause Clipboard", systemImage: "pause.circle") }
            }
            Button { withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.clearClipboardWithUndo() } } label: { Label("Clear History", systemImage: "trash") }
            Divider()
            Button { QuickshareService.shared.uploadFromClipboard() } label: {
                Label("Upload from Clipboard", systemImage: "link.icloud")
            }
            Divider()
            Button {
                SettingsNavigator.shared.open(.clipboard)
                SettingsWindowController.shared.showWindow()
            } label: { Label("Settings…", systemImage: "gearshape") }
            Button { state.isClipboardVisible = false } label: { Label("Close", systemImage: "xmark") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 29, height: 29)
                .background(Circle().fill(Color(white: 0.086)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More clipboard options")
    }

    // MARK: Cards

    @ViewBuilder
    private func cards(_ list: [ClipboardItem]) -> some View {
        if list.isEmpty {
            let empty = ClipboardEmptyState.content(browser: browser, isPaused: privacy.isPaused,
                                                    pauseDescription: privacy.pauseDescription)
            DroppyEmptyState(systemName: empty.icon, title: empty.title, subtitle: empty.subtitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(list) { item in
                            ClipCard(
                                item: item,
                                isSelected: browser.selectedID == item.id || browser.selection.contains(item.id),
                                isRenaming: renamingID == item.id,
                                menuTargets: browser.menuTargets(for: item, in: list),
                                onSelect: { modifiers in
                                    browser.click(item, in: list, modifiers: modifiers)
                                    // Clicking a card leaves search or a rename, so keys reach the cards.
                                    if renamingID != item.id { renamingID = nil }
                                    keyboardFocused = true
                                },
                                onPaste: {
                                    browser.select(item.id)
                                    paste()
                                },
                                onRename: { renamingID = item.id },
                                onRenameDone: { title in
                                    state.renameClip(item, to: title)
                                    renamingID = nil
                                    keyboardFocused = true
                                },
                                boardTint: item.board.flatMap { board in state.pinboards.first(where: { $0.name == board })?.color },
                                showsTags: state.clipboardTagsEnabled
                            )
                            .id(item.id)
                            .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onChange(of: browser.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(height: ClipCard.height)
        }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard renamingID == nil, !searchFocused else { return .ignored }
        let list = clips
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .escape:
            if browser.isMultiSelecting {
                browser.select(browser.selectedID)
            } else {
                state.isClipboardVisible = false
            }
            return .handled
        case .leftArrow:
            browser.move(by: -1, in: list, extend: extend)
            return .handled
        case .rightArrow:
            browser.move(by: 1, in: list, extend: extend)
            return .handled
        case .return:
            // ⌥⏎ / ⇧⏎: Paste as Plain Text.
            paste(plainText: press.modifiers.contains(.option) || press.modifiers.contains(.shift))
            return .handled
        case .space:
            ClipPreview.show(browser.targets(in: list))
            return .handled
        case .delete, .deleteForward:
            let targets = browser.targets(in: list)
            guard let last = targets.last, let index = list.firstIndex(where: { $0.id == last.id }) else { return .handled }
            let ids = Set(targets.map(\.id))
            let next = list[(index + 1)...].first { !ids.contains($0.id) }?.id
                ?? list[..<index].last { !ids.contains($0.id) }?.id
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.deleteClipboardItems(ids: ids) }
            browser.select(next)
            return .handled
        default:
            if press.modifiers.contains(.command) {
                switch press.characters {
                case "c":
                    if state.copyClipboardItems(browser.targets(in: list)) { DroppyAudio.playCopySuccess() }
                    return .handled
                case "a":
                    browser.selection = Set(list.map(\.id))
                    return .handled
                case "z":
                    // ⌘Z takes back the last delete or clear while its toast is up.
                    return state.performActiveUndo() ? .handled : .ignored
                case "f":
                    browser.isSearching = true
                    searchFocused = true
                    return .handled
                default:
                    return .ignored
                }
            }
            // Start typing to filter: the first letter opens search with it.
            guard !press.modifiers.contains(.control), ClipboardTyping.isPrintable(press.characters) else { return .ignored }
            browser.query += press.characters
            browser.isSearching = true
            searchFocused = true
            ClipboardTyping.moveCursorToEnd()
            return .handled
        }
    }

    private func paste(plainText: Bool = false) {
        browser.paste(clips, plainText: plainText)
    }
}

/// "Start typing immediately to filter clipboard history".
@MainActor
enum ClipboardTyping {
    static func isPrintable(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
    }

    /// A text field that just took focus selects all it holds, so the next
    /// key would replace the letter that opened search; put the caret after it.
    static func moveCursorToEnd() {
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }
}

// MARK: - Card

/// One clip, like the reference's Alpha cards: a header strip tinted by the
/// source app's colour with the title, how long ago and the app icon on the
/// corner; the clip itself; a footer chip ("66 characters ≡ 2", "1728 × 1117")
/// and a ★ when it's a favourite.
struct ClipCard: View {
    static let width: CGFloat = 164
    static let height: CGFloat = 132

    let item: ClipboardItem
    let isSelected: Bool
    let isRenaming: Bool
    let menuTargets: [ClipboardItem]
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onPaste: () -> Void
    let onRename: () -> Void
    let onRenameDone: (String) -> Void
    /// The clip's pinboard colour and the tags setting, handed in so a card
    /// doesn't observe AppState and redraw on every change to it.
    let boardTint: Color?
    let showsTags: Bool

    /// Actions only; not observed (see `boardTint`).
    private var state: AppState { AppState.shared }
    @State private var isHovered = false
    @State private var draft = ""
    @FocusState private var titleFocused: Bool
    @State private var renameFinished = false
    /// Pixel size of an image clip, for the footer; read from the file's header.
    @State private var imageSize: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var headerTint: Color? {
        ClipSource.tint(for: item.sourceBundleID) ?? boardTint
    }

    /// Blur sensitive content: veiled until the pointer is on it.
    private var isVeiled: Bool { item.isSensitive && !isHovered }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .blur(radius: isVeiled ? 7 : 0)
                .overlay {
                    if isVeiled {
                        Label("Sensitive", systemImage: "eye.slash.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .clipped()
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(white: 0.11))
        .overlay(alignment: .bottom) { footer }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered && !isRenaming {
                // -2 keeps the circles 4pt apart once each has a 25pt hit frame.
                HStack(spacing: -2) {
                    cornerButton(item.isPinned ? "star.fill" : "star", help: item.isPinned ? "Remove from favorites" : "Add to favorites") {
                        state.togglePin(item)
                    }
                    cornerButton("trash", help: "Delete from clipboard history") {
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.deleteClipboardItem(id: item.id) }
                    }
                }
                .padding(3)
                .transition(.opacity)
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isSelected)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        // One gesture reading the click count: a separate double-tap gesture
        // would hold every single click back until the double-click time ran out.
        .onTapGesture {
            let event = NSApp.currentEvent
            if event?.clickCount == 2 { onPaste() } else { onSelect(event?.modifierFlags ?? []) }
        }
        .task(id: item.content) {
            guard item.type == .image else { return }
            imageSize = await ClipThumbnail.pixelSize(for: item.content)
        }
        .onDrag {
            ClipDrag.begin(item.id)
            return dragProvider
        } preview: { dragPreview }
        .contextMenu { ClipMenu(item: item, targets: menuTargets, onRename: onRename) }
        .help(item.isSensitive ? item.displayTitle : helpText.prefix(300) + "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type.label): \(item.displayTitle), \(item.isSensitive ? "sensitive" : (item.type == .image ? (item.ocrText ?? "image") : String(helpText.prefix(120))))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect([]) }
        .accessibilityAction(named: "Paste") { onPaste() }
        .accessibilityAction(named: "Copy") { state.copyClipboardItem(item) }
        .accessibilityAction(named: item.isPinned ? "Remove from favorites" : "Add to favorites") { state.togglePin(item) }
        .accessibilityAction(named: "Delete") { state.deleteClipboardItem(id: item.id) }
    }

    /// What leaves the card: the real image or file for those clips, so a drop
    /// into Finder or Slack gets the thing itself rather than its filename.
    private var dragProvider: NSItemProvider {
        switch item.type {
        case .image:
            if let provider = NSItemProvider(contentsOf: ClipboardImageStore.url(for: item.content)) { return provider }
        case .file:
            if let url = item.fileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return NSItemProvider(object: url as NSURL)
            }
        default:
            break
        }
        return NSItemProvider(object: item.content as NSString)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if let color = item.parsedColor {
            // An inset swatch with the code in its corner, like a paint chip.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .overlay(alignment: .bottomLeading) {
                    Text(item.previewText.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLight ? Color.black.opacity(0.75) : .white.opacity(0.95))
                        .padding(8)
                }
                .padding(8)
        } else if item.type == .image {
            ClipThumbnail(filename: item.content)
        } else if item.type == .file {
            // The file itself, centred: its Finder icon over its name.
            VStack(spacing: 6) {
                Image(nsImage: ClipThumbnail.fileIcon(for: item.fileURLs.first?.path ?? ""))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .bottomTrailing) {
                        if item.fileURLs.count > 1 {
                            Text("\(item.fileURLs.count)")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(.white))
                                .offset(x: 4, y: 2)
                        }
                    }
                Text(item.fileURLs.count > 1
                     ? "\(item.fileURLs[0].lastPathComponent) and \(item.fileURLs.count - 1) more"
                     : (item.fileURLs.first?.deletingPathExtension().lastPathComponent ?? item.displayTitle))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(item.displayPreview)
                .font(item.type == .code
                      ? .system(size: 10, weight: .medium, design: .monospaced)
                      : .system(size: 11.5, weight: .medium))
                .foregroundStyle(item.type == .url ? DS.Palette.info : .white.opacity(0.94))
                .lineSpacing(2)
                .padding(EdgeInsets(top: 9, leading: 11, bottom: 24, trailing: 11))
        }
    }

    private var helpText: String {
        switch item.type {
        case .image: return item.ocrText ?? item.displayTitle
        case .file: return item.fileURLs.map(\.path).joined(separator: "\n")
        default: return item.displayPreview
        }
    }

    private var isLight: Bool {
        guard let (r, g, b) = item.parsedColorComponents else { return false }
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.62
    }

    // MARK: Header & footer

    /// Title (or the name given to it), how long ago, tag dots, and the app it
    /// came from on the corner. Double-click the title to rename the card.
    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if isRenaming {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .onSubmit { finishRename(draft) }
                            .onExitCommand { finishRename(item.customTitle ?? "") }
                            .onAppear {
                                draft = item.displayTitle
                                renameFinished = false
                                titleFocused = true
                            }
                            // Clicking elsewhere keeps what was typed and ends the rename.
                            .onChange(of: titleFocused) { _, focused in
                                if !focused { finishRename(draft) }
                            }
                            .accessibilityLabel("Clip name")
                    } else {
                        Text(item.displayTitle)
                            .lineLimit(1)
                            .help(item.displayTitle)
                            .onTapGesture {
                                let event = NSApp.currentEvent
                                if event?.clickCount == 2 { onRename() } else { onSelect(event?.modifierFlags ?? []) }
                            }
                    }
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Text(ClipSource.ago(item.copiedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(headerTint == nil ? 0.5 : 0.78))
                        .lineLimit(1)
                    if showsTags, !item.tags.isEmpty {
                        ClipTagChips(tags: item.tags, compact: true)
                    }
                }
            }
            Spacer(minLength: 2)
            // Room for the source icon, which bleeds off the card's corner.
            Color.clear.frame(width: 22)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if let headerTint {
                LinearGradient(colors: [headerTint, headerTint.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
            } else {
                Color.white.opacity(0.08)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let icon = AppIcon.image(bundleID: item.sourceBundleID) {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: 7, y: -1)
                    .opacity(isHovered && !isRenaming ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// ★ on the left for a favourite, and the size chip.
    private var footer: some View {
        HStack(spacing: 4) {
            if item.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.3))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .accessibilityLabel("Favorite")
            }
            Spacer(minLength: 4)
            if let chip = footerChip {
                HStack(spacing: 4) {
                    Text(chip.left)
                    if let right = chip.right {
                        Image(systemName: "line.3.horizontal").font(.system(size: 8, weight: .bold))
                            .accessibilityHidden(true)
                        Text(right)
                    }
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(Color.black.opacity(0.62)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            if !item.isPinned { Spacer(minLength: 4) }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    /// "66 characters ≡ 2" for text; the size of what else it holds.
    private var footerChip: (left: String, right: String?)? {
        switch item.type {
        case .text, .code, .url:
            let text = item.content
            // Counted in place: `split` built an array of every line per render.
            let lines = text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
            return ("\(text.count) character\(text.count == 1 ? "" : "s")", "\(lines)")
        case .file:
            let urls = item.fileURLs
            guard urls.count == 1, let url = urls.first else { return ("\(urls.count) files", nil) }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return ("Folder", nil)
            }
            return (url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased(), nil)
        case .image:
            if let imageSize { return ("\(Int(imageSize.width)) × \(Int(imageSize.height))", nil) }
            return item.ocrText.map { ("\($0.count) characters", nil) }
        case .color:
            return nil
        }
    }

    private func cornerButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color(white: 0.14))
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.white.opacity(0.88)))
                // Looks 19pt, clicks like 25pt.
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var dragPreview: some View {
        Text((item.type == .image || item.type == .file || item.isSensitive ? item.displayTitle : item.displayPreview).prefix(60) + "")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: 180)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)))
    }

    private func finishRename(_ title: String) {
        guard !renameFinished else { return }
        renameFinished = true
        onRenameDone(title)
    }
}

// MARK: - Thumbnails

/// Image clips are full-size PNGs on disk; cards show a small decoded copy,
/// loaded once off the main thread and kept in a shared cache.
struct ClipThumbnail: View {
    let filename: String

    @MainActor private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 132, height: 132)
                    .clipped()
            } else {
                Image(systemName: ClipboardType.image.iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(width: 132, height: 132)
            }
        }
        .task(id: filename) {
            if let cached = Self.cache.object(forKey: filename as NSString) {
                image = cached
                return
            }
            let url = ClipboardImageStore.url(for: filename)
            let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 264,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard let cgImage else { return }
            let loaded = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            Self.cache.setObject(loaded, forKey: filename as NSString)
            image = loaded
        }
    }

    @MainActor private static var pixelSizes: [String: CGSize] = [:]

    /// An image clip's pixel size, read from the file's header (no decode).
    @MainActor static func pixelSize(for filename: String) async -> CGSize? {
        if let known = pixelSizes[filename] { return known }
        let url = ClipboardImageStore.url(for: filename)
        let size = await Task.detached(priority: .utility) { () -> CGSize? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return CGSize(width: width, height: height)
        }.value
        if let size { pixelSizes[filename] = size }
        return size
    }

    /// Shares the app-wide icon cache, so the clipboard and the Tray don't
    /// each hold their own copy of the same Finder icon.
    @MainActor static func fileIcon(for path: String) -> NSImage {
        FileIcon.image(for: path)
    }
}

// MARK: - Dock shape

/// Rounded on top, flaring out into the screen edge at the bottom — the same
/// inverted fillet the notch uses, turned upside down.
struct ClipboardDockShape: Shape {
    var topRadius: CGFloat
    var earRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let ear = earRadius
        let r = topRadius
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addQuadCurve(to: CGPoint(x: ear, y: h - ear), control: CGPoint(x: ear, y: h))
        path.addLine(to: CGPoint(x: ear, y: r))
        path.addQuadCurve(to: CGPoint(x: ear + r, y: 0), control: CGPoint(x: ear, y: 0))
        path.addLine(to: CGPoint(x: w - ear - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w - ear, y: r), control: CGPoint(x: w - ear, y: 0))
        path.addLine(to: CGPoint(x: w - ear, y: h - ear))
        path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - ear, y: h))
        path.closeSubpath()
        return path
    }
}

// MARK: - Drag tracking

/// The card being dragged, so a pinboard tab knows which clip landed on it
/// even when the drag carries an image or file instead of text. Cleared a
/// moment after the button comes up, once any drop has been handled.
@MainActor
enum ClipDrag {
    static var current: UUID?

    static func begin(_ id: UUID) {
        current = id
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if current == id { current = nil }
            }
        }
    }
}
