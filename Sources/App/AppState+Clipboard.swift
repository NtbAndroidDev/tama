import SwiftUI
import AppKit
import Combine

// Clipboard history and pinboards.

extension AppState {
    // MARK: - Clipboard Management
    func setupClipboardMonitoring() {
        ClipboardService.shared.onNewItem = { [weak self] item in
            guard let self = self else { return }
            // A repeat of an older clip moves that clip to the front rather
            // than stacking a second copy of it.
            guard let updated = ClipboardHistory.inserting(item, into: self.clipboardItems,
                                                           rejectDuplicates: ClipboardSettings.shared.rejectDuplicates) else { return }
            // Trimmed before it's published: every write to the list redraws the tree.
            self.clipboardItems = ClipboardHistory.trimmed(updated, limit: ClipboardSettings.shared.historyLimit)
            if item.type == .image, !updated.contains(where: { $0.id == item.id }) {
                // Its PNG was already written; the kept clip has its own.
                let url = ClipboardImageStore.url(for: item.content)
                Task.detached(priority: .background) { try? FileManager.default.removeItem(at: url) }
            }
            // A burst of screenshots mustn't sit over the image cap until the hourly pass.
            if item.type == .image { self.applyClipboardRetention() }
        }
        ClipboardService.shared.latestImageHash = { [weak self] in self?.clipboardItems.first?.imageHash }
        ClipboardService.shared.onRecognizedText = { [weak self] id, text, changeCount in
            guard let self, let index = self.clipboardItems.firstIndex(where: { $0.id == id }) else { return }
            self.clipboardItems[index].ocrText = text
            self.autoCopyClipText(text, copiedAt: changeCount)
        }
        // Image files are removed lazily so "Clear History" can still be undone.
        ClipboardService.shared.removeUnusedImages(referencedBy: clipboardItems)
        if ClipboardSettings.shared.isEnabled { ClipboardService.shared.startMonitoring() }
        ClipboardPrivacy.shared.startRetention(for: self)
    }

    /// Settings › Clipboard › Clipboard manager: start or stop recording, and
    /// put the clipboard away when it's switched off.
    func applyClipboardEnabled() {
        if ClipboardSettings.shared.isEnabled {
            if !ClipboardService.shared.isMonitoring { ClipboardService.shared.startMonitoring() }
        } else {
            ClipboardService.shared.stopMonitoring()
            isClipboardVisible = false
        }
    }

    /// The shortcut, menus and Ring go through here: with the manager off
    /// they point at Settings instead.
    func clipboardIsAvailable() -> Bool {
        guard ClipboardSettings.shared.isEnabled else {
            showNotification(
                appName: "Clipboard",
                title: "Clipboard is off",
                message: "Enable Clipboard in Settings",
                icon: "doc.on.clipboard",
                actionTitle: "Settings",
                action: {
                    SettingsNavigator.shared.open(.clipboard)
                    SettingsWindowController.shared.showWindow()
                }
            )
            return false
        }
        return true
    }

    /// Settings › General › Auto-copy OCR text, for image clips: once Vision
    /// has read a copied image its text replaces it on the pasteboard, unless
    /// something else was copied in the meantime. Written as our own copy, so
    /// it isn't recorded as a second clip.
    private func autoCopyClipText(_ text: String, copiedAt changeCount: Int) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TraySettings.shared.autoCopyOCRText, !clean.isEmpty, ClipboardService.shared.changeCount == changeCount else { return }
        ClipboardService.shared.copyToPasteboard(text: clean)
        DroppyAudio.playCopySuccess()
        showNotification(appName: "Clipboard", title: "Auto-copy result",
                         message: "Extracted text copied to clipboard", icon: "text.viewfinder")
    }

    /// Settings › Clipboard › Clear history on quit. Starred and pinboard
    /// clips are kept, as with Clear History.
    func clearClipboardOnQuitIfNeeded() {
        guard ClipboardSettings.shared.clearOnQuit else { return }
        clearClipboard()
    }

    /// History clips (not starred, not on a pinboard), for "N of M items saved".
    public var clipboardHistoryCount: Int {
        clipboardItems.filter { !$0.isPinned && $0.board == nil }.count
    }
    
    /// Drops the oldest history clips past the limit. Starred clips and clips
    /// filed on a pinboard don't count and are never removed.
    func trimClipboardHistory(undoLimit: Int? = nil) {
        let snapshot = clipboardItems
        let kept = ClipboardHistory.trimmed(clipboardItems, limit: ClipboardSettings.shared.historyLimit)
        guard kept.count != clipboardItems.count else { return }
        clipboardItems = kept
        // Lowering the limit in Settings drops clips in one go; Undo puts
        // back both the limit and the clips.
        if let undoLimit, undoLimit > ClipboardSettings.shared.historyLimit {
            let keptIDs = Set(kept.map(\.id))
            let removed = Set(snapshot.map(\.id)).subtracting(keptIDs)
            showNotification(
                appName: "Clipboard",
                title: "History limit lowered",
                message: "Removed the oldest \(removed.count) clip\(removed.count == 1 ? "" : "s")",
                actionTitle: "Undo",
                action: {
                    let state = AppState.shared
                    ClipboardSettings.shared.historyLimit = undoLimit
                    state.restoreClipboardItems(snapshot, removed: removed)
                }
            )
        }
        // Trimmed images are left for the launch-time sweep: a pending
        // "Clear History" undo may still need them.
    }

    /// False, with a banner, when the clip's image or files are gone.
    @discardableResult
    public func copyClipboardItem(_ item: ClipboardItem) -> Bool {
        guard ClipboardService.shared.copyToPasteboard(item: item) else {
            showNotification(
                appName: "Clipboard",
                title: "Can't copy this clip",
                message: item.type == .image ? "Its image is no longer stored." : "Its files were moved or deleted."
            )
            return false
        }
        defer { if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        } }
        return true
    }
    
    public func clearClipboard() {
        clipboardItems.removeAll(where: { !$0.isPinned && $0.board == nil })
    }

    /// Copy + Favorite: copies the clip and stars it.
    public func copyAndFavorite(_ item: ClipboardItem) {
        guard copyClipboardItem(item) else { return }
        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) { clipboardItems[index].isPinned = true }
        DroppyAudio.playCopySuccess()
    }

    // MARK: - Several clips at once

    /// Stars every clip, or un-stars them all when every one already is.
    public func toggleFavorite(_ ids: Set<UUID>) {
        let targets = clipboardItems.indices.filter { ids.contains(clipboardItems[$0].id) }
        let star = !targets.allSatisfy { clipboardItems[$0].isPinned }
        for index in targets { clipboardItems[index].isPinned = star }
        DroppyAudio.playTick()
    }

    public func assign(_ ids: Set<UUID>, to board: String?) {
        for index in clipboardItems.indices where ids.contains(clipboardItems[index].id) {
            clipboardItems[index].board = board
        }
        DroppyAudio.playTick()
    }

    /// False, with a banner, when none of the clips could be put on the pasteboard.
    @discardableResult
    public func copyClipboardItems(_ items: [ClipboardItem], plainText: Bool = false) -> Bool {
        guard ClipboardService.shared.copyToPasteboard(items: items, plainText: plainText) else {
            showNotification(appName: "Clipboard", title: "Can't copy these clips",
                             message: "Their images or files are no longer on this Mac.")
            return false
        }
        return true
    }

    public func togglePin(_ item: ClipboardItem) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[index].isPinned.toggle()
        DroppyAudio.playTick()
    }

    public func assign(_ item: ClipboardItem, to board: String?) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[index].board = board
        DroppyAudio.playTick()
    }

    public func renameClip(_ item: ClipboardItem, to title: String) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        clipboardItems[index].customTitle = clean.isEmpty ? nil : clean
    }

    // MARK: - Tags

    /// False when the name is blank or already a tag.
    @discardableResult
    public func addClipTag(named name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clipboardTags.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return false }
        clipboardTags.append(ClipTag(name: clean, tint: (clipboardTags.count + 2) % Pinboard.tints.count))
        return true
    }

    /// Deletes a tag and takes it off every clip.
    /// Deletes the tag and strips it from every clip, with an Undo toast that
    /// puts the tag back in its place and back on the clips that had it.
    public func removeClipTag(_ tag: ClipTag) {
        let position = clipboardTags.firstIndex { $0.name == tag.name }
        let tagged = Set(clipboardItems.filter { $0.tags.contains(tag.name) }.map(\.id))
        clipboardTags.removeAll { $0.name == tag.name }
        for index in clipboardItems.indices where clipboardItems[index].tags.contains(tag.name) {
            clipboardItems[index].tags.removeAll { $0 == tag.name }
        }
        showNotification(
            appName: "Clipboard",
            title: "Tag deleted",
            message: tagged.isEmpty ? tag.name : "\(tag.name) · \(tagged.count) clip\(tagged.count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: {
                let state = AppState.shared
                if !state.clipboardTags.contains(where: { $0.name == tag.name }) {
                    state.clipboardTags.insert(tag, at: min(position ?? state.clipboardTags.count, state.clipboardTags.count))
                }
                for index in state.clipboardItems.indices
                where tagged.contains(state.clipboardItems[index].id) && !state.clipboardItems[index].tags.contains(tag.name) {
                    state.clipboardItems[index].tags.append(tag.name)
                }
            }
        )
    }

    /// Adds the tag to every clip, or removes it when every one already has it.
    public func toggleClipTag(_ tag: String, on ids: Set<UUID>) {
        let targets = clipboardItems.indices.filter { ids.contains(clipboardItems[$0].id) }
        let add = !targets.allSatisfy { clipboardItems[$0].tags.contains(tag) }
        for index in targets {
            clipboardItems[index].tags.removeAll { $0 == tag }
            if add { clipboardItems[index].tags.append(tag) }
        }
        DroppyAudio.playTick()
    }

    /// Asks for a name, makes the tag and puts it on the clips.
    public func promptNewClipTag(for ids: Set<UUID>) {
        let alert = NSAlert()
        alert.messageText = "New Tag"
        alert.informativeText = "Assign this tag to items to collect them here."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Tag name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Tag")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        addClipTag(named: name)
        // An existing name (any case) is reused rather than duplicated.
        let tag = clipboardTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name ?? name
        if !ids.isEmpty { toggleClipTag(tag, on: ids) }
    }

    func persistClipboardTags() {
        if let data = try? JSONEncoder().encode(clipboardTags) {
            UserDefaults.standard.set(data, forKey: "clipboardTags")
        }
    }

    static func loadClipboardTags() -> [ClipTag] {
        guard let data = UserDefaults.standard.data(forKey: "clipboardTags"),
              let tags = try? JSONDecoder().decode([ClipTag].self, from: data) else { return [] }
        return tags
    }

    // MARK: - Pinboards

    /// False when the name is blank or already a pinboard.
    @discardableResult
    public func addPinboard(named name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !pinboards.contains(where: { $0.name == clean }) else { return false }
        pinboards.append(Pinboard(name: clean, tint: pinboards.count % Pinboard.tints.count))
        return true
    }

    /// Deletes a pinboard; its clips go back to plain history. The toast's
    /// Undo puts the board back where it was and refiles those clips.
    public func removePinboard(_ board: Pinboard) {
        guard let position = pinboards.firstIndex(where: { $0.id == board.id }) else { return }
        pinboards.remove(at: position)
        var filed = Set<UUID>()
        for index in clipboardItems.indices where clipboardItems[index].board == board.name {
            clipboardItems[index].board = nil
            filed.insert(clipboardItems[index].id)
        }
        showNotification(
            appName: "Clipboard",
            title: "Pinboard deleted",
            message: filed.isEmpty ? board.name : "\(board.name) · \(filed.count) clip\(filed.count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: { AppState.shared.restorePinboard(board, at: position, clips: filed) }
        )
    }

    /// Clips filed elsewhere since the delete stay where they were moved.
    func restorePinboard(_ board: Pinboard, at position: Int, clips: Set<UUID>) {
        if !pinboards.contains(where: { $0.name == board.name }) {
            pinboards.insert(board, at: min(position, pinboards.count))
        }
        for index in clipboardItems.indices
        where clips.contains(clipboardItems[index].id) && clipboardItems[index].board == nil {
            clipboardItems[index].board = board.name
        }
        DroppyAudio.playTick()
    }

    func persistPinboards() {
        if let data = try? JSONEncoder().encode(pinboards) {
            UserDefaults.standard.set(data, forKey: "pinboards")
        }
    }

    static func loadPinboards() -> [Pinboard] {
        if let data = UserDefaults.standard.data(forKey: "pinboards"),
           let boards = try? JSONDecoder().decode([Pinboard].self, from: data) {
            return boards
        }
        return [Pinboard(name: "Work", tint: 0), Pinboard(name: "Prompts", tint: 1)]
    }
}

// MARK: - Auto-copy OCR text

extension AppState {
    /// Settings › General › Auto-copy OCR text: text read from a file or a
    /// capture goes straight to the clipboard (and its history), as if copied.
    public func autoCopyRecognizedText(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TraySettings.shared.autoCopyOCRText, !clean.isEmpty else { return }
        ClipboardService.shared.copyToPasteboard(text: clean)
        // Through the monitor's path so dedupe and the history limit apply.
        ClipboardService.shared.onNewItem?(ClipboardItem(content: clean, type: .text))
        DroppyAudio.playCopySuccess()
        showNotification(appName: "OCR", title: "Text copied", message: "\(clean.count) characters")
    }
}
