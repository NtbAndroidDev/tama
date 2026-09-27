import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Spotlight in the notch: type, arrow to a result, then open, reveal, Quick
/// Look, copy its path or send it to the Tray without leaving the keyboard.
public struct ThunderstormConsoleView: View {
    @ObservedObject private var search = SpotlightSearchService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var keys = ThunderstormKeyMonitor()
    @State private var text = ""
    @State private var selectedID: String?
    @State private var status: String?
    @FocusState private var isFieldFocused: Bool

    public init() {}

    private var selected: SearchResult? {
        search.results.first { $0.id == selectedID } ?? search.results.first
    }

    public var body: some View {
        VStack(spacing: DS.Space.sm) {
            field
            resultsList
            footer
        }
        .onAppear {
            // The notch panel doesn't take key focus by itself; the field needs it to type.
            NotchWindowController.shared.focusPanel()
            DispatchQueue.main.async { isFieldFocused = true }
            keys.start(handler: handleKey)
            if !text.isEmpty { search.search(text) }
        }
        .onDisappear {
            keys.stop()
            search.stop()
            AppState.shared.clearEditing(withPrefix: "droplet.thunderstorm")
        }
        // A half-typed query holds the shelf open.
        .onChange(of: isFieldFocused) { _, focused in
            AppState.shared.setEditing(focused, owner: "droplet.thunderstorm.field")
        }
        .onChange(of: text) { _, newValue in
            keys.isNavigating = false
            search.search(newValue)
        }
        .onChange(of: search.results.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchPalette.secondary)
                .accessibilityHidden(true)
            TextField("Search your Mac — try kind:pdf or ext:swift", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .focused($isFieldFocused)
                .accessibilityLabel("Search your Mac")
                .onSubmit { perform(.open) }
            if search.isSearching {
                ProgressView().controlSize(.mini).accessibilityLabel("Searching")
            }
            if !text.isEmpty {
                DroppyIconButton("xmark.circle.fill", size: 20, help: "Clear search") { text = "" }
            }
            DroppyChip(search.searchesWholeMac ? "Mac" : "Home",
                       systemName: search.searchesWholeMac ? "desktopcomputer" : "house",
                       isSelected: search.searchesWholeMac,
                       help: search.searchesWholeMac ? "Searching the whole Mac" : "Searching your home folder and Applications") {
                search.searchesWholeMac.toggle()
                DroppyAudio.playTick()
            }
            .accessibilityLabel(search.searchesWholeMac ? "Search scope: whole Mac" : "Search scope: home folder")
            DroppyIconButton("macwindow.on.rectangle", size: 22, tone: .tonal,
                             help: "Open the floating launcher\(GlobalShortcutService.shared.display(for: .thunderstorm).map { " (\($0))" } ?? "")") {
                ThunderstormLauncherController.shared.show()
            }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(NotchPalette.control))
    }

    // MARK: Results

    @ViewBuilder
    private var resultsList: some View {
        if search.sections.isEmpty {
            Group {
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    DroppyEmptyState(systemName: "bolt.fill", title: "Search files, folders and apps",
                                     subtitle: "kind:pdf · kind:image · kind:app · ext:swift")
                } else if search.isSearching || search.lastQuery != text {
                    DroppyEmptyState(systemName: "ellipsis", title: "Searching…", compact: true)
                } else {
                    DroppyEmptyState(systemName: "questionmark.folder", title: "No matches",
                                     subtitle: search.searchesWholeMac ? nil : "Try searching the whole Mac")
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(search.sections, id: \.group) { section in
                            Text(section.group.title.uppercased())
                                .font(DS.Typo.micro)
                                .foregroundStyle(NotchPalette.tertiary)
                                .padding(.leading, DS.Space.sm)
                                .padding(.top, DS.Space.sm)
                                .padding(.bottom, DS.Space.xxs)
                                .accessibilityLabel(section.group.title)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.items) { result in
                                ThunderstormRow(
                                    result: result,
                                    isSelected: result.id == selected?.id,
                                    onSelect: { selectedID = result.id },
                                    onAction: { perform($0, on: result) }
                                )
                                .id(result.id)
                            }
                        }
                    }
                }
                .onChange(of: selectedID) { _, id in
                    guard let id, keys.isNavigating else { return }
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { proxy.scrollTo(id) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if let status {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.success)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            } else {
                hint("↩", "Open")
                hint("⌘↩", "Reveal")
                hint("␣ ⌘Y", "Look")
                hint("⌘T", "Tray")
                hint("⌘C", "Copy path")
            }
            Spacer(minLength: 0)
            if !search.results.isEmpty {
                Text("\(search.results.count)")
                    .font(DS.Typo.numericSmall.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityLabel("\(search.results.count) results")
            }
        }
        .font(DS.Typo.caption)
        .frame(height: 14)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: status)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(key).foregroundStyle(DS.Palette.textPrimary.opacity(0.8))
            Text(label).foregroundStyle(DS.Palette.textSecondary)
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    enum Action { case open, reveal, quickLook, tray, copyPath }

    private func perform(_ action: Action, on result: SearchResult? = nil) {
        guard let result = result ?? selected else { return }
        selectedID = result.id
        switch action {
        case .open:
            NSWorkspace.shared.open(result.url)
            AppState.shared.setIslandExpanded(false)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([result.url])
            AppState.shared.setIslandExpanded(false)
        case .quickLook:
            QuickLookService.shared.preview([result.url])
        case .tray:
            AppState.shared.addShelfItems([ShelfItem(url: result.url)])
            DroppyAudio.playDropSuccess()
            flash("Added \(result.name) to the Tray")
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.url.path, forType: .string)
            DroppyAudio.playCopySuccess()
            flash("Copied path")
        }
    }

    private func flash(_ message: String) {
        status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if status == message { status = nil }
        }
    }

    private func move(_ delta: Int) {
        let results = search.results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = results[min(max(current + delta, 0), results.count - 1)].id
    }

    /// The focused field editor, when it has a non-empty text selection.
    private static func selectingEditor(in window: NSWindow?) -> NSTextView? {
        guard let editor = window?.firstResponder as? NSTextView,
              editor.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else { return nil }
        return editor
    }

    /// Returns true when the key was used, so it doesn't reach the text field.
    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            keys.isNavigating = true
            move(1)
        case kVK_UpArrow:
            keys.isNavigating = true
            move(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            perform(command ? .reveal : .open)
        // Space types a space until the arrows have moved into the results.
        case kVK_Space where keys.isNavigating && !command && selected != nil:
            perform(.quickLook)
        case kVK_ANSI_Y where command:
            perform(.quickLook)
        case kVK_ANSI_T where command:
            perform(.tray)
        // Selected text in the search field copies as text; otherwise ⌘C is the path.
        // Tama has no Edit menu, so the field editor never gets copy: by itself.
        case kVK_ANSI_C where command:
            if let editor = Self.selectingEditor(in: event.window) {
                editor.copy(nil)
            } else if selected != nil {
                perform(.copyPath)
            } else {
                return false
            }
        default:
            return false
        }
        return true
    }
}

// MARK: - Key monitor

/// Arrow keys, Return and ⌘-keys are taken before the text field's editor sees
/// them, but only while the notch panel is the key window.
@MainActor
final class ThunderstormKeyMonitor: ObservableObject {
    var isNavigating = false
    private var monitor: Any?

    func start(handler: @escaping @MainActor (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let panel = NotchWindowController.shared.panel, event.window === panel,
                  AppState.shared.isIslandExpanded else { return event }
            return handler(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Row

private struct ThunderstormRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    let onAction: (ThunderstormConsoleView.Action) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(nsImage: FileIcon.image(for: result.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.parentPath)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.sm)
            if isHovered {
                HStack(spacing: DS.Space.xxs) {
                    DroppyIconButton("eye", size: 22, help: "Quick Look (⌘Y)") { onAction(.quickLook) }
                    DroppyIconButton("folder", size: 22, help: "Reveal in Finder (⌘↩)") { onAction(.reveal) }
                    DroppyIconButton("tray.and.arrow.down", size: 22, help: "Add to Tray (⌘T)") { onAction(.tray) }
                    DroppyIconButton("doc.on.doc", size: 22, help: "Copy path (⌘C)") { onAction(.copyPath) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(isSelected ? NotchPalette.selection.opacity(0.55) : (isHovered ? NotchPalette.tile : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { isHovered = hovering }
        }
        .onTapGesture(count: 2) { onAction(.open) }
        .onTapGesture(count: 1, perform: onSelect)
        .onDrag {
            onSelect()
            DroppyAudio.playTick()
            return NSItemProvider(object: result.url as NSURL)
        }
        .contextMenu {
            Button("Open") { onAction(.open) }
            Button("Reveal in Finder") { onAction(.reveal) }
            Button("Quick Look") { onAction(.quickLook) }
            Divider()
            Button("Add to Tray") { onAction(.tray) }
            Button("Copy Path") { onAction(.copyPath) }
        }
        .help(result.url.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onAction(.open) }
        .accessibilityAction(named: "Reveal in Finder") { onAction(.reveal) }
        .accessibilityAction(named: "Quick Look") { onAction(.quickLook) }
        .accessibilityAction(named: "Add to Tray") { onAction(.tray) }
        .accessibilityAction(named: "Copy path") { onAction(.copyPath) }
    }
}
