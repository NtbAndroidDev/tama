import SwiftUI
import Combine

// MARK: - Undoable clears
// A clear wipes a whole list in one click, so each one leaves a toast that can
// put it back. Undo only restores what the clear took; anything added, edited
// or deleted since keeps its new state.
extension AppState {
    public func clearTrayWithUndo() {
        let snapshot = shelfItems
        guard !snapshot.isEmpty else { return }
        clearAllShelfItems()
        showNotification(
            appName: "Tray",
            title: "Tray cleared",
            message: "\(snapshot.count) file\(snapshot.count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: { AppState.shared.restoreShelfItems(snapshot, removed: Set(snapshot.map(\.id))) }
        )
    }

    public func removeShelfItemsWithUndo(ids: Set<UUID>) {
        var snapshot = shelfItems
        var removed = ids.intersection(snapshot.map(\.id))
        guard !removed.isEmpty else { return }
        removeShelfItems(ids: removed)
        // Removing more while the last toast is up joins it, so one Undo
        // brings back the whole run rather than only the latest file.
        if let pending = PendingUndo.tray, activeNotification?.id == pending.notification {
            snapshot = Self.merged(pending.snapshot, with: snapshot)
            removed.formUnion(pending.removed)
        }
        let (restore, removedIDs) = (snapshot, removed)
        showNotification(
            appName: "Tray",
            title: "Removed from Tray",
            message: "\(removed.count) file\(removed.count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: {
                PendingUndo.tray = nil
                AppState.shared.restoreShelfItems(restore, removed: removedIDs)
            }
        )
        PendingUndo.tray = activeNotification.map { ($0.id, snapshot, removed) }
    }

    /// Deletes one clip, joining a delete toast that's still up (see
    /// removeShelfItemsWithUndo).
    public func deleteClipboardItem(id: UUID) {
        deleteClipboardItems(ids: [id])
    }

    /// Deletes several clips (a multi-selection) under one Undo toast.
    public func deleteClipboardItems(ids: Set<UUID>) {
        var snapshot = clipboardItems
        let targets = snapshot.filter { ids.contains($0.id) }
        guard let item = targets.first else { return }
        clipboardItems.removeAll(where: { ids.contains($0.id) })
        var removed = Set(targets.map(\.id))
        if let pending = PendingUndo.clipboard, activeNotification?.id == pending.notification {
            snapshot = Self.merged(pending.snapshot, with: snapshot)
            removed.formUnion(pending.removed)
        }
        let (restore, removedIDs) = (snapshot, removed)
        // Its image stays for the launch-time sweep, so Undo can bring it back.
        showNotification(
            appName: "Clipboard",
            title: removed.count == 1 ? "Clip deleted" : "Clips deleted",
            message: removed.count == 1 ? item.displayTitle : "\(removed.count) clips",
            actionTitle: "Undo",
            action: {
                PendingUndo.clipboard = nil
                AppState.shared.restoreClipboardItems(restore, removed: removedIDs)
            }
        )
        PendingUndo.clipboard = activeNotification.map { ($0.id, snapshot, removed) }
    }

    /// The first removal's snapshot, with anything added since it was taken
    /// in front (new files and clips always arrive at the front).
    private static func merged<Item: Identifiable>(_ original: [Item], with latest: [Item]) -> [Item] where Item.ID == UUID {
        let known = Set(original.map(\.id))
        return latest.filter { !known.contains($0.id) } + original
    }

    /// ⌘Z while an Undo toast is up does what its button does.
    @discardableResult
    public func performActiveUndo() -> Bool {
        guard let notification = activeNotification, notification.actionTitle == "Undo",
              let action = notification.action else { return false }
        DroppyAudio.playTick()
        action()
        if activeNotification?.id == notification.id {
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.snap)) { activeNotification = nil }
        }
        return true
    }

    public func clearClipboardWithUndo() {
        let snapshot = clipboardItems
        // Same semantics as clearClipboard(): starred and pinboard clips stay.
        let removed = Set(snapshot.filter { !$0.isPinned && $0.board == nil }.map(\.id))
        guard !removed.isEmpty else { return }
        clearClipboard()
        showNotification(
            appName: "Clipboard",
            title: "History cleared",
            message: "\(removed.count) clip\(removed.count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: { AppState.shared.restoreClipboardItems(snapshot, removed: removed) }
        )
    }

    /// Puts removed clips back in their old places; anything copied since
    /// stays at the front.
    func restoreClipboardItems(_ snapshot: [ClipboardItem], removed: Set<UUID>) {
        let current = Dictionary(clipboardItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = Set(snapshot.map(\.id))
        let added = clipboardItems.filter { !known.contains($0.id) }
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            clipboardItems = added + snapshot.compactMap { removed.contains($0.id) ? $0 : current[$0.id] }
        }
        trimClipboardHistory()
    }

    func restoreShelfItems(_ snapshot: [ShelfItem], removed: Set<UUID>) {
        let current = Dictionary(shelfItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = Set(snapshot.map(\.id))
        let added = shelfItems.filter { !known.contains($0.id) }
        let addedURLs = Set(added.map(\.url.standardizedFileURL))
        // A file re-added since the clear already sits at the front.
        let restored = snapshot.compactMap { removed.contains($0.id) ? $0 : current[$0.id] }
            .filter { !addedURLs.contains($0.url.standardizedFileURL) }
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            shelfItems = Array((added + restored).prefix(max(TraySettings.shared.capacity, 1)))
        }
        DroppyAudio.playDropSuccess()
    }
}

/// The removal toast on screen, per list, so a following removal can join it.
@MainActor
private enum PendingUndo {
    static var tray: (notification: UUID, snapshot: [ShelfItem], removed: Set<UUID>)?
    static var clipboard: (notification: UUID, snapshot: [ClipboardItem], removed: Set<UUID>)?
}
