import SwiftUI
import AppKit

/// Notes (the Scratchpad droplet): a list of notes with title, time and
/// preview, and a rich-text editor with a floating format bar. Syncs with a
/// "Tama" folder in Apple Notes when that's on.
struct ScratchpadConsoleView: View {
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var notesSettings = NotesSettings.shared
    @State private var openID: UUID?
    @StateObject private var controller = RichTextController()
    @State private var editorHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let openID, let note = store.note(openID) {
                editor(note)
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .trailing))))
            } else {
                list
                    .transition(DS.Motion.transition(reduceMotion, .opacity))
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: openID)
        .onAppear {
            store.pullFromAppleNotes()
            if let requested = store.requestedNoteID {
                open(requested)
                store.requestedNoteID = nil
            }
        }
        .onChange(of: store.requestedNoteID) { _, requested in
            guard let requested else { return }
            open(requested)
            store.requestedNoteID = nil
        }
        .onDisappear {
            if let openID { store.discardIfEmpty(openID) }
            state.dropletConsoleHeight = nil
            // The editor clears this as it is dismantled, but the order of the
            // two isn't guaranteed and a flag left set turns auto-collapse off.
            state.clearEditing(withPrefix: "droplet.scratchpad")
        }
        .shelfAccessories("notes", [
            ShelfAccessory(id: "notes.close", icon: "xmark", help: "Close", page: .widgets, dropletID: "scratchpad") {
                DroppyAudio.playTick()
                AppState.shared.activeDropletID = nil
            },
        ])
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Text("Notes")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                syncBadge
                Spacer()
                NotchCircleButton("square.and.pencil", size: 28, iconSize: 12, help: "New note") {
                    DroppyAudio.playTick()
                    open(store.create())
                }
            }
            syncError
            if store.notes.isEmpty {
                DroppyEmptyState(systemName: "note.text", title: "No notes yet",
                                 subtitle: "Quick notes that live in your notch. Click the pencil to start one.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.sm) {
                        ForEach(store.ordered) { note in
                            NoteRow(note: note) { open(note.id) }
                        }
                    }
                    .padding(.bottom, DS.Space.sm)
                }
            }
        }
    }

    @ViewBuilder
    private var syncBadge: some View {
        if notesSettings.appleSync {
            switch store.syncStatus {
            case .syncing:
                ProgressView().controlSize(.mini).tint(DS.Palette.textPrimary)
                    .help("Syncing with Apple Notes…")
                    .accessibilityLabel("Syncing with Apple Notes")
            case .idle:
                Image(systemName: "checkmark.icloud")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .help("Syncing with Apple Notes (folder \u{201C}Tama\u{201D}).")
                    .accessibilityLabel("Synced with Apple Notes")
            case .unreachable, .scriptFailed:
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.warning)
                    .help("Apple Notes sync isn't working")
                    .accessibilityLabel("Apple Notes sync isn't working")
            }
        }
    }

    @ViewBuilder
    private var syncError: some View {
        if notesSettings.appleSync {
            switch store.syncStatus {
            case let .unreachable(detail):
                errorLine("Couldn't reach Apple Notes. Allow Tama to control Notes in System Settings › Privacy & Security › Automation.",
                          detail: detail, showsSettings: true)
            case let .scriptFailed(detail):
                errorLine("Notes script failed.", detail: detail, showsSettings: false)
            default:
                EmptyView()
            }
        }
    }

    private func errorLine(_ text: String, detail: String, showsSettings: Bool) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(text)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.warning)
                .lineLimit(2)
                .help(detail)
            Spacer(minLength: DS.Space.xs)
            if showsSettings {
                DroppyPillButton("Settings", help: "Open Automation in System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            DroppyPillButton("Retry", help: "Sync with Apple Notes again") { store.pullFromAppleNotes() }
        }
    }

    // MARK: Editor

    private func editor(_ note: DroppyNote) -> some View {
        VStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                NotchCircleButton("chevron.left", size: 28, iconSize: 11, help: "All notes") { close() }
                Spacer()
                Text("Edited \(note.modified.formatted(date: Calendar.current.isDateInToday(note.modified) ? .omitted : .abbreviated, time: .shortened))")
                    .font(DS.Typo.headline.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                NotchCircleButton("tray.and.arrow.down", size: 28, iconSize: 11, help: "Add to Tray as a text file") {
                    addToTray(note)
                }
                .disabled(note.isEmpty)
                NotchCircleButton("doc.on.doc", size: 28, iconSize: 11, help: "Copy note") {
                    store.copy(note.id)
                }
                .disabled(note.isEmpty)
                NotchCircleButton("trash", size: 28, iconSize: 11, help: "Delete note") {
                    let id = note.id
                    close(discarding: false)
                    store.delete(id)
                }
                .contextMenu {
                    Button("Clear Note") { store.clear(note.id) }.disabled(note.isEmpty)
                }
            }
            RichTextEditor(noteID: note.id, rtf: note.rtf, controller: controller,
                           onChange: { store.update(note.id, with: $0) },
                           onHeight: { grow(to: $0) })
                .id(note.id)
                .padding(.bottom, notesSettings.showToolbar ? 30 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if notesSettings.showToolbar {
                        NoteFormatBar(controller: controller)
                    }
                }
        }
        .onAppear { NotchWindowController.shared.focusPanel() }
    }

    /// Grow canvas: the console gets taller with the note, up to a limit.
    private func grow(to contentHeight: CGFloat) {
        editorHeight = contentHeight
        guard notesSettings.growCanvas else {
            if state.dropletConsoleHeight != nil { state.dropletConsoleHeight = nil }
            return
        }
        let chrome: CGFloat = 34 + 6 + (notesSettings.showToolbar ? 30 : 0) + 20
        let wanted = min(max(contentHeight + chrome, DroppyShelfMetrics.widgetsConsoleHeight), DroppyShelfMetrics.notesMaxConsoleHeight)
        let rounded = (wanted / 10).rounded(.up) * 10
        let height: CGFloat? = rounded == DroppyShelfMetrics.widgetsConsoleHeight ? nil : rounded
        if state.dropletConsoleHeight != height { state.dropletConsoleHeight = height }
    }

    private func open(_ id: UUID) {
        if let openID, openID != id { store.discardIfEmpty(openID) }
        openID = id
    }

    private func close(discarding: Bool = true) {
        DroppyAudio.playTick()
        if discarding, let openID { store.discardIfEmpty(openID) }
        openID = nil
        state.dropletConsoleHeight = nil
        AppState.shared.clearEditing(withPrefix: "droplet.scratchpad")
    }

    /// Ours: the note as a .txt in the Tray, ready to drag anywhere.
    private func addToTray(_ note: DroppyNote) {
        let base = note.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
        let name = String((base.isEmpty ? "Note" : base).prefix(60)) + ".txt"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TamaNotes-\(UUID().uuidString.prefix(8))")
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try note.text.write(to: url, atomically: true, encoding: .utf8)
            state.addShelfItems([ShelfItem(url: url)])
            state.showNotification(appName: "Notes", title: "Note saved to Tray", message: "\(name) is ready to drag out")
            DroppyAudio.playDropSuccess()
        } catch {
            state.showNotification(appName: "Notes", title: "Couldn't save note", message: error.localizedDescription)
        }
    }
}

/// A note in the list: title, time and preview; pin, copy and delete on hover
/// and in the context menu.
struct NoteRow: View {
    let note: DroppyNote
    var compact = false
    let open: () -> Void
    @ObservedObject private var store = NotesStore.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.Space.sm) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        Text(note.title)
                            .font(.system(size: compact ? 13 : 14, weight: .bold))
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)
                    }
                    HStack(spacing: DS.Space.xs) {
                        Text(timeLabel)
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(NotchPalette.secondary)
                        Text(note.preview)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(NotchPalette.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.xs)
                if isHovered && !compact {
                    HStack(spacing: DS.Space.xs) {
                        NotchCircleButton(note.isPinned ? "pin.slash" : "pin", size: 24, iconSize: 10,
                                          help: note.isPinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
                        NotchCircleButton("doc.on.doc", size: 24, iconSize: 10, help: "Copy note") { store.copy(note.id) }
                        NotchCircleButton("trash", size: 24, iconSize: 10, help: "Delete note") { store.delete(note.id) }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, compact ? DS.Space.sm : DS.Space.md)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isHovered ? DS.Palette.surface3 : DS.Palette.surface2))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
            Button("Copy Note") { store.copy(note.id) }
            Divider()
            Button("Delete Note", role: .destructive) { store.delete(note.id) }
        }
        .accessibilityLabel(note.isPinned ? "Pinned, \(note.title), \(timeLabel)" : "\(note.title), \(timeLabel)")
    }

    private var timeLabel: String {
        Calendar.current.isDateInToday(note.modified)
            ? note.modified.formatted(date: .omitted, time: .shortened)
            : note.modified.formatted(.dateTime.day().month(.abbreviated))
    }
}
