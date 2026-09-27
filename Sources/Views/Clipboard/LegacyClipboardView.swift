import SwiftUI
import AppKit

/// The Legacy clipboard: a dark window with "Search clipboard" on top, a
/// vertical list of clips (title, "Type · App · 1 min ago", tag chips) beside
/// a preview pane, and a bottom bar with Paste, Copy, ★ and Delete.
struct LegacyClipboardView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var privacy = ClipboardPrivacy.shared
    @ObservedObject private var browser = ClipboardBrowser.shared
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for the first pass after the controller mounts this view, so
    /// `isShown` changes and the selection and focus are set up.
    @State private var hasAppeared = false

    private var clips: [ClipboardItem] { browser.clips(from: state.clipboardItems) }
    private var isShown: Bool { hasAppeared && state.isClipboardVisible && state.clipboardLayout == .legacy }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                list.frame(width: 330)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            bottomBar
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(action: handleKey)
        .onChange(of: browser.query) { _, _ in browser.select(clips.first?.id) }
        .onChange(of: clips.map(\.id)) { _, _ in browser.reconcile(with: clips) }
        .onAppear { DispatchQueue.main.async { hasAppeared = true } }
        .onChange(of: isShown) { _, visible in
            if visible {
                browser.select(clips.first?.id)
                // The search field is always there; Auto-focus puts the caret in it.
                if state.clipboardAutoFocusSearch { searchFocused = true } else { listFocused = true }
            } else {
                browser.reset()
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.Palette.textSecondary)
                .accessibilityHidden(true)
            TextField("Search clipboard", text: $browser.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { paste(plainText: NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.shift)) }
                // Arrow keys won't navigate the list until you press Escape.
                .onExitCommand {
                    if browser.query.isEmpty { state.isClipboardVisible = false }
                    searchFocused = false
                    listFocused = true
                }
            if privacy.isPaused {
                Button { privacy.resume() } label: {
                    Label("Paused · Resume", systemImage: "pause.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.warning)
                        .lineLimit(1)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help("\(privacy.pauseDescription). Click to resume.")
                .accessibilityLabel("Clipboard paused. Resume")
            }
            if !browser.query.isEmpty {
                Button { browser.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.textSecondary)
                        .contentShape(Circle())
                }
                .buttonStyle(DroppyPressStyle())
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let items = clips
        if items.isEmpty {
            let empty = ClipboardEmptyState.content(browser: browser, isPaused: privacy.isPaused,
                                                    pauseDescription: privacy.pauseDescription)
            DroppyEmptyState(systemName: empty.icon, title: empty.title, subtitle: empty.subtitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            LegacyClipRow(item: item,
                                          isSelected: browser.selectedID == item.id || browser.selection.contains(item.id))
                                .id(item.id)
                                .onTapGesture {
                                    let event = NSApp.currentEvent
                                    if event?.clickCount == 2 {
                                        browser.select(item.id)
                                        paste()
                                    } else {
                                        browser.click(item, in: items, modifiers: event?.modifierFlags ?? [])
                                        searchFocused = false
                                        listFocused = true
                                    }
                                }
                                .contextMenu { ClipMenu(item: item, targets: browser.menuTargets(for: item, in: items)) }
                                // The tap gesture above is invisible to VoiceOver;
                                // give the row the same select / paste / delete.
                                .accessibilityAction { browser.select(item.id) }
                                .accessibilityAction(named: "Paste") {
                                    browser.select(item.id)
                                    paste()
                                }
                                .accessibilityAction(named: item.isPinned ? "Remove from favorites" : "Add to favorites") {
                                    state.togglePin(item)
                                }
                                .accessibilityAction(named: "Delete") { state.deleteClipboardItem(id: item.id) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: browser.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        let targets = browser.targets(in: clips)
        if targets.count > 1 {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 30)).foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
                Text("\(targets.count) items selected").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("Return pastes all selected items, joined.").font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if let item = targets.first {
            LegacyClipPreview(item: item)
        } else {
            DroppyEmptyState(systemName: "doc.on.clipboard", title: "Nothing selected",
                             subtitle: "Pick a clip on the left to preview it here.")
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        let targets = browser.targets(in: clips)
        let ids = Set(targets.map(\.id))
        return HStack(spacing: 6) {
            if state.clipboardTypeFilters {
                Menu {
                    ForEach(ClipFilter.allCases) { filter in
                        Button { browser.kind = filter } label: {
                            if browser.kind == filter { Label(filter.title, systemImage: "checkmark") } else { Text(filter.title) }
                        }
                    }
                } label: { chipLabel(browser.kind.title, icon: browser.kind.iconName) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Show only one kind of clip")
                    .accessibilityLabel("Show: \(browser.kind.title)")
            }
            Menu {
                Button { browser.showBoard(nil) } label: { Text("Clipboard") }
                if !state.pinboards.isEmpty { Divider() }
                ForEach(state.pinboards) { board in
                    Button { browser.showBoard(board.name) } label: { Label(board.name, systemImage: "pin") }
                }
                if state.clipboardTagsEnabled, !state.clipboardTags.isEmpty {
                    Divider()
                    ForEach(state.clipboardTags) { tag in
                        Button { browser.showTag(tag.name) } label: { Label(tag.name, systemImage: "tag") }
                    }
                }
            } label: {
                chipLabel(browser.tag ?? browser.board ?? "Clipboard", icon: browser.tag != nil ? "tag" : (browser.board != nil ? "pin" : "doc.on.clipboard"))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Pinboards and tags")
            .accessibilityLabel("Showing \(browser.tag.map { "tag \($0)" } ?? browser.board.map { "pinboard \($0)" } ?? "Clipboard")")
            Spacer()
            barButton("arrow.down.doc", help: targets.count > 1 ? "Paste all selected items" : "Paste") { paste() }
                .disabled(targets.isEmpty)
            barButton("doc.on.doc", help: "Copy") {
                if state.copyClipboardItems(targets) { DroppyAudio.playCopySuccess() }
            }
            .disabled(targets.isEmpty)
            if state.clipboardCopyFavorite, targets.count == 1, let item = targets.first {
                barButton("star.square.on.square", help: "Copy + Favorite") { state.copyAndFavorite(item) }
            }
            let allFavorite = !targets.isEmpty && targets.allSatisfy(\.isPinned)
            barButton(allFavorite ? "star.fill" : "star", help: allFavorite ? "Remove from favorites" : "Add to favorites") {
                state.toggleFavorite(ids)
            }
            .disabled(targets.isEmpty)
            barButton("eye", help: "Preview") { ClipPreview.show(targets) }
                .disabled(targets.isEmpty)
            barButton("trash", help: "Delete from clipboard history") {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.deleteClipboardItems(ids: ids) }
            }
            .disabled(targets.isEmpty)
            Menu {
                Button("Clear History…") { confirmClear() }
                Button("Settings…") {
                    SettingsNavigator.shared.open(.clipboard)
                    SettingsWindowController.shared.showWindow()
                }
            } label: { chipLabel("", icon: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More")
                .accessibilityLabel("More clipboard options")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private func chipLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !title.isEmpty { Text(title).lineLimit(1) }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 26)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    /// Starred and pinboard clips stay, and the toast can still undo it.
    private func confirmClear() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Removes every item except favorites and items on a pinboard. You can undo this from the banner right after."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.clearClipboardWithUndo()
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !searchFocused else { return .ignored }
        let items = clips
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .escape:
            state.isClipboardVisible = false
            return .handled
        case .upArrow:
            browser.move(by: -1, in: items, extend: extend)
            return .handled
        case .downArrow:
            browser.move(by: 1, in: items, extend: extend)
            return .handled
        case .return:
            paste(plainText: press.modifiers.contains(.option) || press.modifiers.contains(.shift))
            return .handled
        case .space:
            ClipPreview.show(browser.targets(in: items))
            return .handled
        case .delete, .deleteForward:
            let ids = Set(browser.targets(in: items).map(\.id))
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.deleteClipboardItems(ids: ids) }
            return .handled
        default:
            if press.modifiers.contains(.command) {
                switch press.characters {
                case "c":
                    if state.copyClipboardItems(browser.targets(in: items)) { DroppyAudio.playCopySuccess() }
                    return .handled
                case "a":
                    browser.selection = Set(items.map(\.id))
                    return .handled
                case "z":
                    return state.performActiveUndo() ? .handled : .ignored
                case "f":
                    searchFocused = true
                    return .handled
                default:
                    return .ignored
                }
            }
            guard !press.modifiers.contains(.control), ClipboardTyping.isPrintable(press.characters) else { return .ignored }
            browser.query += press.characters
            searchFocused = true
            ClipboardTyping.moveCursorToEnd()
            return .handled
        }
    }

    private func paste(plainText: Bool = false) {
        browser.paste(clips, plainText: plainText)
    }
}

/// One row: icon, title, "Type · App · 1 min ago", tag chips on the right.
private struct LegacyClipRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    @ObservedObject private var state = AppState.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = AppIcon.image(bundleID: item.sourceBundleID) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: item.type.iconName).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.isSensitive && !isHovered ? "••••••••" : title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if item.isPinned {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary.opacity(0.8) : DS.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if state.clipboardTagsEnabled {
                ClipTagChips(tags: Array(item.tags.prefix(2)))
            }
            if let board = state.pinboards.first(where: { $0.name == item.board }) {
                Text(board.name)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(board.color.opacity(0.55), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isSelected ? DS.accent.opacity(0.85) : (isHovered ? DS.Palette.surface1 : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        guard item.customTitle == nil, item.type != .image, item.type != .file else { return item.displayTitle }
        return item.previewText.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.displayTitle
    }

    private var subtitle: String {
        [item.customTitle == nil ? item.type.label : item.displayTitle,
         ClipSource.appName(item.sourceBundleID),
         ClipSource.ago(item.copiedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// The selected clip, large: text, image, colour or files, with its details.
private struct LegacyClipPreview: View {
    let item: ClipboardItem
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if item.isSensitive && !isRevealed {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill").font(.system(size: 24)).accessibilityHidden(true)
                        Text("Sensitive content").font(.system(size: 13, weight: .semibold))
                        Button("Reveal") { isRevealed = true }.controlSize(.small)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let color = item.parsedColor {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color)
                        .overlay(alignment: .bottomLeading) {
                            Text(item.previewText.uppercased())
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .padding(10)
                                .background(.black.opacity(0.35), in: Capsule())
                                .padding(10)
                        }
                } else if item.type == .image {
                    // Decoded small and off the main thread: the stored clip is
                    // a full-size PNG, and loading it whole inside `body` meant
                    // decoding a screen-sized image again on every redraw —
                    // once per keystroke in the search field.
                    ShelfThumbnail(url: ClipboardImageStore.url(for: item.content),
                                   maxPixelSize: 1200, contentMode: .fit) {
                        // A clip whose file is gone falls through to the
                        // thumbnail's own "Preview unavailable".
                        ProgressView().controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if item.type == .file {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(item.fileURLs, id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(nsImage: ClipThumbnail.fileIcon(for: url.path)).resizable().frame(width: 28, height: 28)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent).font(.system(size: 12.5, weight: .semibold))
                                            .lineLimit(1).truncationMode(.middle)
                                        Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView {
                        Text(item.content)
                            .font(item.type == .code ? .system(size: 12, design: .monospaced) : .system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(details)
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white)
        .padding(16)
        .onChange(of: item.id) { _, _ in isRevealed = false }
    }

    private var details: String {
        var parts = [item.type.label, ClipSource.ago(item.copiedAt)]
        switch item.type {
        case .text, .code, .url:
            let lines = item.content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            parts.append("\(item.content.count) characters · \(lines) line\(lines == 1 ? "" : "s")")
            if item.hasRichText { parts.append("Formatted") }
        case .image:
            if let text = item.ocrText { parts.append("Text recognized from image: \(text.count) characters") }
        default:
            break
        }
        return parts.joined(separator: " · ")
    }
}
