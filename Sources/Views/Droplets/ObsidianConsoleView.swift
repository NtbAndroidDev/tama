import SwiftUI
import AppKit

// Obsidian — the vault live on the shelf: a list of its notes (newest first)
// that open and edit inline, plus quick capture into the daily note or an inbox.

struct ObsidianConsoleView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var obsidian = ObsidianService.shared
    @State private var draft = ""
    @State private var asTask = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .notes
    @State private var editing: VaultNote?
    @State private var editorText = ""
    @State private var saveWork: DispatchWorkItem?
    @FocusState private var editorFocused: Bool

    enum Mode { case notes, capture }

    private let tint = Color(red: 0.49, green: 0.33, blue: 0.87)

    var body: some View {
        VStack(spacing: DS.Space.md) {
            if let editing {
                noteEditor(editing)
            } else {
                header
                if obsidian.isVaultUnavailable {
                    vaultUnavailable
                } else if obsidian.vaultURL == nil {
                    noVault
                } else if mode == .notes {
                    // Creating a note from the header can fail; say so here too,
                    // not only in the capture view.
                    if let errorMessage {
                        Text(errorMessage)
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.danger)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    noteList
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: DS.Space.md) {
                            if showSettings { settings }
                            composer
                            quickActions
                            recent
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { obsidian.refreshNotes() }
        .onChange(of: obsidian.vaultPath) { _, _ in obsidian.refreshNotes() }
        .onDisappear {
            if let editing { saveNow(editing) }
            // A focused TextEditor going away doesn't report losing focus, so
            // the "someone is typing" flag stayed true and auto-collapse was
            // off for the rest of the session.
            state.clearEditing(withPrefix: "droplet.obsidian")
        }
        .shelfAccessories("obsidian", [
            ShelfAccessory(id: "obsidian.close", icon: "xmark", help: "Close", page: .widgets, dropletID: "obsidian") {
                DroppyAudio.playTick()
                AppState.shared.activeDropletID = nil
            },
        ])
    }

    // MARK: Notes

    private var noteList: some View {
        Group {
            if obsidian.vaultNotes.isEmpty {
                Group {
                    if obsidian.isRefreshingNotes {
                        VStack(spacing: DS.Space.sm) {
                            ProgressView().controlSize(.small).accessibilityHidden(true)
                            Text("Refreshing vault notes…").font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        DroppyEmptyState(systemName: "doc.text", title: "No notes in this vault yet",
                                         subtitle: "Use the pencil to write one, or capture into your daily note.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.sm) {
                        ForEach(obsidian.vaultNotes) { note in
                            VaultNoteRow(note: note) { openNote(note) }
                        }
                    }
                    .padding(.bottom, DS.Space.sm)
                }
            }
        }
    }

    private func noteEditor(_ note: VaultNote) -> some View {
        VStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                NotchCircleButton("chevron.left", size: 28, iconSize: 11, help: "All notes") { closeNote() }
                Text(note.title)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(note.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NotchCircleButton("arrow.up.forward.app", size: 28, iconSize: 11, help: "Open in Obsidian") {
                    saveNow(note)
                    obsidian.open(note)
                }
                NotchCircleButton("doc.on.doc", size: 28, iconSize: 11, help: "Copy note") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editorText, forType: .string)
                    DroppyAudio.playCopySuccess()
                }
            }
            TextEditor(text: $editorText)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .accessibilityLabel("Note text")
                .padding(DS.Space.sm)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface1))
                .onChange(of: editorText) { _, _ in scheduleSave(note) }
                .onChange(of: editorFocused) { _, focused in
                    state.setEditing(focused, owner: "droplet.obsidian.editor")
                }
            if let errorMessage {
                Text(errorMessage).font(DS.Typo.caption).foregroundStyle(DS.Palette.danger).lineLimit(1)
                    .help(errorMessage)
            }
        }
    }

    private func openNote(_ note: VaultNote) {
        DroppyAudio.playTick()
        editorText = obsidian.readNote(note)
        errorMessage = nil
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { editing = note }
        NotchWindowController.shared.focusPanel()
        DispatchQueue.main.async { editorFocused = true }
    }

    private func closeNote() {
        DroppyAudio.playTick()
        if let editing { saveNow(editing) }
        state.setEditing(false, owner: "droplet.obsidian.editor")
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { editing = nil }
        obsidian.refreshNotes()
    }

    private func scheduleSave(_ note: VaultNote) {
        saveWork?.cancel()
        let work = DispatchWorkItem { saveNow(note) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func saveNow(_ note: VaultNote) {
        saveWork?.cancel()
        saveWork = nil
        do {
            try obsidian.saveNote(note, text: editorText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var vaultUnavailable: some View {
        VStack(spacing: DS.Space.sm) {
            DroppyEmptyState(systemName: "externaldrive.badge.exclamationmark", title: "Vault unavailable",
                             subtitle: "\(obsidian.vaultPath ?? "The vault") can't be read. It may have moved, or its drive isn't connected.")
            DroppyPillButton("Choose the vault again…", systemName: "folder", tone: .accent,
                             help: "Pick the vault's folder") {
                obsidian.pickVault()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "diamond.fill").foregroundColor(tint).accessibilityHidden(true)
            Text("Obsidian").font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if obsidian.isRefreshingNotes, mode == .notes, !obsidian.vaultNotes.isEmpty {
                ProgressView().controlSize(.mini)
                    .help("Refreshing vault notes…")
                    .accessibilityLabel("Refreshing vault notes")
            }
            Spacer()
            vaultMenu
            if obsidian.vaultURL != nil {
                if mode == .capture {
                    DroppyIconButton("gearshape", size: 26, isActive: showSettings, help: "Note settings") {
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.disclose)) { showSettings.toggle() }
                    }
                }
                DroppyIconButton(mode == .notes ? "tray.and.arrow.down" : "list.bullet", size: 26, tone: .tonal,
                                 help: mode == .notes ? "Quick capture into the daily note or inbox" : "Vault notes") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { mode = mode == .notes ? .capture : .notes }
                    DroppyAudio.playTick()
                }
                NotchCircleButton("square.and.pencil", size: 28, iconSize: 12, help: "New note") {
                    do {
                        openNote(try obsidian.createNote())
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private var vaultMenu: some View {
        Menu {
            let detected = ObsidianService.detectedVaults()
            if !detected.isEmpty {
                Section("Detected vaults") {
                    ForEach(detected, id: \.self) { url in
                        Button(url.lastPathComponent) { obsidian.vaultPath = url.path }
                    }
                }
            }
            Button("Choose Folder…") { obsidian.pickVault() }
            if obsidian.vaultURL != nil {
                Divider()
                Button("Open this vault in Obsidian") { obsidian.openVault() }
                Button("Refresh notes") { obsidian.refreshNotes() }
            }
        } label: {
            Label(obsidian.vaultName ?? "Choose vault", systemImage: "folder")
                .font(DS.Typo.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(obsidian.vaultPath ?? "Choose an Obsidian vault")
    }

    private var noVault: some View {
        VStack(spacing: DS.Space.sm) {
            DroppyEmptyState(systemName: "diamond", title: "No vault selected",
                             subtitle: "Pick the folder of an Obsidian vault to start capturing.")
            DroppyPillButton("Choose vault…", systemName: "folder", tone: .accent,
                             help: "Pick the folder of an Obsidian vault") {
                obsidian.pickVault()
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            settingField("Daily folder", text: $obsidian.dailyFolderOverride,
                         placeholder: obsidian.dailyFolder.isEmpty ? "Vault root" : obsidian.dailyFolder)
            settingField("Date format", text: $obsidian.dailyFormatOverride, placeholder: obsidian.dailyFormat)
            settingField("Inbox note", text: $obsidian.inboxPath, placeholder: "Inbox.md")
        }
        .padding(DS.Space.md)
        .dsSurface(1, radius: DS.Radius.sm)
    }

    private func settingField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(label)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 76, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.Typo.mono)
                .padding(.horizontal, DS.Space.sm)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: DS.Radius.xs).fill(DS.Palette.surfaceSunken))
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xs) {
                ForEach(ObsidianService.Target.allCases, id: \.self) { target in
                    DroppyChip(target.rawValue, systemName: target == .daily ? "calendar" : "tray",
                               isSelected: obsidian.target == target) {
                        obsidian.target = target
                        DroppyAudio.playTick()
                    }
                }
                Spacer()
                Text(obsidian.notePath(for: obsidian.target))
                    .font(DS.Typo.mono)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            HStack(spacing: DS.Space.sm) {
                Button {
                    asTask.toggle()
                    DroppyAudio.playTick()
                } label: {
                    Image(systemName: asTask ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(asTask ? tint : DS.Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DroppyPressStyle())
                .help(asTask ? "Append as a task" : "Append as a timestamped bullet")
                .accessibilityLabel("Append as a task")
                .accessibilityValue(asTask ? "On" : "Off")

                TextField(asTask ? "New task…" : "Quick note…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(DS.Typo.body)
                    .accessibilityLabel(asTask ? "New task" : "Quick note")
                    .onSubmit(appendDraft)

                DroppyPillButton("Append", systemName: "arrow.turn.down.left", tone: .accent,
                                 help: "Append to \(obsidian.notePath(for: obsidian.target)) (Return)") {
                    appendDraft()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: 34)
            .dsSurface(1, radius: DS.Radius.sm)

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .lineLimit(2)
                    .help(errorMessage)
            }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: DS.Space.sm) {
            DroppyPillButton("Clipboard", systemName: "doc.on.clipboard",
                             help: "Append the current clipboard (text, image or files)") {
                perform { "\(try obsidian.appendClipboard(asTask: asTask)) added" }
            }

            DroppyPillButton("Latest note", systemName: "note.text",
                             help: "Append the note you edited last in Notes") {
                perform {
                    try obsidian.append(NotesStore.shared.latest?.text ?? "", asTask: asTask)
                    return "Note added"
                }
            }
            .disabled(NotesStore.shared.latest?.isEmpty ?? true)

            Menu {
                if state.shelfItems.isEmpty {
                    Text("The Tray is empty")
                } else {
                    ForEach(state.shelfItems) { item in
                        Button(item.name) {
                            perform {
                                try obsidian.attach(item.url)
                                return "\(item.name) attached"
                            }
                        }
                    }
                }
            } label: {
                Label("Tray file", systemImage: "paperclip").font(DS.Typo.caption).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Copy a Tray file into the vault and embed it")

            Spacer()

            DroppyPillButton("Open", systemName: "arrow.up.forward.app", help: "Open the note in Obsidian") {
                obsidian.openNote()
            }
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recent: some View {
        if !obsidian.recentEntries.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("RECENT")
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityLabel("Recent")
                    .accessibilityAddTraits(.isHeader)
                ForEach(obsidian.recentEntries) { entry in
                    HStack(spacing: DS.Space.sm) {
                        Text(entry.date, style: .time)
                            .font(DS.Typo.mono.monospacedDigit())
                            .foregroundStyle(DS.Palette.textSecondary)
                        Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.sm)
                        Text((entry.note as NSString).lastPathComponent)
                            .font(DS.Typo.micro)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func appendDraft() {
        perform {
            try obsidian.append(draft, asTask: asTask)
            draft = ""
            return asTask ? "Task added" : "Note added"
        }
    }

    private func perform(_ action: () throws -> String) {
        do {
            let message = try action()
            errorMessage = nil
            DroppyAudio.playDropSuccess()
            state.showNotification(appName: "Obsidian", title: message,
                                   message: obsidian.notePath(for: obsidian.target),
                                   actionTitle: "Open", action: { ObsidianService.shared.openNote() })
        } catch {
            errorMessage = error.localizedDescription
            DroppyAudio.playTick()
        }
    }
}

/// A vault note: title, modified time and first line.
private struct VaultNoteRow: View {
    let note: VaultNote
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(note.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: DS.Space.xs) {
                    Text(Calendar.current.isDateInToday(note.modified)
                         ? note.modified.formatted(date: .omitted, time: .shortened)
                         : note.modified.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NotchPalette.secondary)
                    Text(note.preview)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NotchPalette.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isHovered ? DS.Palette.surface3 : DS.Palette.surface2))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .help(note.path)
        .contextMenu {
            Button("Open in Obsidian") { ObsidianService.shared.open(note) }
            Button("Reveal in Finder") {
                if let url = ObsidianService.shared.url(for: note) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}
