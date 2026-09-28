import SwiftUI
import AppKit

// The floating Baskets and what Shelf and Baskets share: each Basket keeps
// its own files (moved to and from the Shelf), and "held items" are looked
// up across both by id, so one context menu works on either.

/// Where held files live.
public enum HeldSurface: Hashable, Sendable {
    case shelf
    case basket(UUID)

    public var name: String {
        switch self {
        case .shelf: "Shelf"
        case .basket: "Basket"
        }
    }
}

extension AppState {
    // MARK: - Held items (Shelf + Baskets)

    public func surface(of id: UUID) -> HeldSurface? {
        if shelfItems.contains(where: { $0.id == id }) { return .shelf }
        if let basket = baskets.first(where: { $0.items.contains { $0.id == id } }) { return .basket(basket.id) }
        return nil
    }

    public func items(on surface: HeldSurface) -> [ShelfItem] {
        switch surface {
        case .shelf: shelfItems
        case .basket(let id): baskets.first { $0.id == id }?.items ?? []
        }
    }

    /// The items with these ids, wherever they are, Shelf first.
    public func heldItems(_ ids: Set<UUID>) -> [ShelfItem] {
        (shelfItems + baskets.flatMap(\.items)).filter { ids.contains($0.id) }
    }

    public func updateHeldItems(ids: Set<UUID>, _ transform: (inout ShelfItem) -> Void) {
        for index in shelfItems.indices where ids.contains(shelfItems[index].id) {
            transform(&shelfItems[index])
        }
        for b in baskets.indices {
            for index in baskets[b].items.indices where ids.contains(baskets[b].items[index].id) {
                transform(&baskets[b].items[index])
            }
        }
    }

    /// Swaps an item for others in the same place (a compressed copy, a
    /// folder made from a selection).
    public func replaceHeldItem(_ id: UUID, with replacements: [ShelfItem]) {
        let kept = keepingTemporaryFiles(replacements)
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            if let index = shelfItems.firstIndex(where: { $0.id == id }) {
                shelfItems.replaceSubrange(index...index, with: kept)
                return
            }
            for b in baskets.indices {
                if let index = baskets[b].items.firstIndex(where: { $0.id == id }) {
                    baskets[b].items.replaceSubrange(index...index, with: kept)
                    return
                }
            }
        }
        measureFolderSizes(of: kept)
    }

    /// Adds files to a surface; the Shelf path keeps its capacity and HUD.
    @discardableResult
    public func addItems(_ items: [ShelfItem], to surface: HeldSurface, bucket: Int = 0) -> [ShelfItem] {
        switch surface {
        case .shelf: return addShelfItems(items)
        case .basket(let id): return addBasketItems(items, to: id, bucket: bucket)
        }
    }

    /// Removes files from wherever they are, with an Undo toast.
    public func removeHeldItemsWithUndo(ids: Set<UUID>) {
        let onShelf = ids.intersection(shelfItems.map(\.id))
        if !onShelf.isEmpty { removeShelfItemsWithUndo(ids: onShelf) }
        let inBaskets = ids.subtracting(onShelf)
        if !inBaskets.isEmpty { removeBasketItemsWithUndo(ids: inBaskets) }
    }

    // MARK: - Baskets

    /// The Basket shown in Single Basket mode, and the first of several.
    public var primaryBasketID: UUID? { baskets.first?.id }

    public func basket(_ id: UUID) -> Basket? { baskets.first { $0.id == id } }

    /// Makes sure a Basket exists and returns it.
    @discardableResult
    func ensureBasket() -> UUID {
        if let id = baskets.first?.id { return id }
        let basket = Basket(tint: 0)
        baskets.append(basket)
        return basket.id
    }

    /// `isBasketVisible` flipped: on shows the open Baskets (or opens the
    /// first); off only hides them — their files stay.
    func basketVisibilityChanged() {
        if isBasketVisible {
            ensureBasket()
            if BasketSettings.shared.mode == .single {
                mergeBasketsIntoFirst()
                if let first = baskets.indices.first, !baskets[first].isOpen { baskets[first].isOpen = true }
            } else if !baskets.contains(where: \.isOpen), let first = baskets.indices.first {
                baskets[first].isOpen = true
            }
        }
        FloatingBasketController.shared.sync()
        // The auto-hide countdown only runs while a Basket is out.
        JiggleService.shared.syncIdleWatch()
    }

    /// Brings the Basket(s) up, beside the pointer when a drag summoned them.
    public func showBasket(nearPointer: Bool) {
        let id = ensureBasket()
        if nearPointer { FloatingBasketController.shared.moveNearPointer(id) }
        if isBasketVisible {
            if let index = baskets.firstIndex(where: { $0.id == id }), !baskets[index].isOpen {
                baskets[index].isOpen = true
            }
            FloatingBasketController.shared.sync()
        } else {
            isBasketVisible = true
        }
    }

    /// Multi-Basket: a new, empty Basket in the next colour, by the pointer.
    @discardableResult
    public func spawnBasket(nearPointer: Bool = true) -> UUID {
        let used = Set(baskets.map(\.tint))
        let tint = (0..<Basket.tints.count).first { !used.contains($0) } ?? baskets.count % Basket.tints.count
        let basket = Basket(tint: tint)
        baskets.append(basket)
        if nearPointer { FloatingBasketController.shared.moveNearPointer(basket.id, offset: CGFloat(baskets.count - 1) * 24) }
        if !isBasketVisible { isBasketVisible = true } else { FloatingBasketController.shared.sync() }
        DroppyAudio.playDropSuccess()
        return basket.id
    }

    /// Opens one Basket (from the switcher) and brings it to the pointer.
    public func focusBasket(_ id: UUID) {
        guard let index = baskets.firstIndex(where: { $0.id == id }) else { return }
        baskets[index].isOpen = true
        FloatingBasketController.shared.moveNearPointer(id)
        if !isBasketVisible { isBasketVisible = true } else { FloatingBasketController.shared.sync() }
        FloatingBasketController.shared.bringToFront(id)
    }

    /// The close button. An empty extra Basket goes away; one holding files
    /// is only put away, so its files are never lost.
    public func closeBasket(_ id: UUID) {
        guard let index = baskets.firstIndex(where: { $0.id == id }) else { return }
        // Its view is going away; it can no longer clear its own modal slot.
        clearModals(withPrefix: "basket.\(id.uuidString)")
        if BasketSettings.shared.mode == .single {
            isBasketVisible = false
            return
        }
        if baskets[index].items.isEmpty, baskets.count > 1 {
            baskets.remove(at: index)
        } else {
            baskets[index].isOpen = false
        }
        if !baskets.contains(where: \.isOpen) {
            isBasketVisible = false
        } else {
            FloatingBasketController.shared.sync()
        }
        DroppyAudio.playTick()
    }

    /// Back to Single Basket: every Basket's files move into the first.
    func mergeBasketsIntoFirst() {
        guard baskets.count > 1 else { return }
        var first = baskets[0]
        let known = Set(first.items.map(\.url.standardizedFileURL))
        first.items += baskets.dropFirst().flatMap(\.items).filter { !known.contains($0.url.standardizedFileURL) }
        first.isOpen = true
        baskets = [first]
        FloatingBasketController.shared.sync()
    }

    @discardableResult
    public func addBasketItems(_ items: [ShelfItem], to id: UUID, bucket: Int = 0) -> [ShelfItem] {
        guard let index = baskets.firstIndex(where: { $0.id == id }) else { return [] }
        var seen = Set<URL>()
        let unique = items.filter { seen.insert($0.url.standardizedFileURL).inserted }
        let kept = keepingTemporaryFiles(unique).map { item -> ShelfItem in
            var item = item
            item.stack = BasketSettings.shared.secondBucket ? bucket : 0
            return item
        }
        let incoming = Set(kept.map(\.url.standardizedFileURL))
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            baskets[index].items.removeAll { incoming.contains($0.url.standardizedFileURL) }
            baskets[index].items.insert(contentsOf: kept, at: 0)
        }
        measureFolderSizes(of: kept)
        if GeneralSettings.shared.hapticFeedback, !kept.isEmpty {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        return kept
    }

    public func removeBasketItemsWithUndo(ids: Set<UUID>) {
        let snapshot = baskets
        var count = 0
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            for index in baskets.indices {
                let before = baskets[index].items.count
                baskets[index].items.removeAll { ids.contains($0.id) }
                count += before - baskets[index].items.count
            }
        }
        guard count > 0 else { return }
        DroppyAudio.playDelete()
        showNotification(
            appName: "Basket",
            title: "Removed from Basket",
            message: "\(count) file\(count == 1 ? "" : "s")",
            actionTitle: "Undo",
            action: { AppState.shared.restoreBasketItems(from: snapshot, ids: ids) }
        )
    }

    /// Puts removed files back into their Baskets; anything added since stays.
    func restoreBasketItems(from snapshot: [Basket], ids: Set<UUID>) {
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            for old in snapshot {
                let restored = old.items.filter { ids.contains($0.id) }
                guard !restored.isEmpty else { continue }
                if let index = baskets.firstIndex(where: { $0.id == old.id }) {
                    let present = Set(baskets[index].items.map(\.id))
                    baskets[index].items += restored.filter { !present.contains($0.id) }
                } else {
                    var basket = old
                    basket.items = restored
                    baskets.append(basket)
                }
            }
        }
        DroppyAudio.playDropSuccess()
    }

    public func clearBasketWithUndo(_ id: UUID) {
        guard let basket = basket(id), !basket.items.isEmpty else { return }
        removeBasketItemsWithUndo(ids: Set(basket.items.map(\.id)))
    }

    // MARK: Moving between Shelf and Baskets

    /// Move to Shelf: the files leave the Basket for the Shelf.
    public func moveToShelf(_ ids: Set<UUID>) {
        let moving = baskets.flatMap(\.items).filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        for index in baskets.indices { baskets[index].items.removeAll { ids.contains($0.id) } }
        addShelfItems(moving.map { var item = $0; item.stack = 0; return item })
        DroppyAudio.playDropSuccess()
        showNotification(appName: "Basket", title: "Moved to Shelf",
                         message: "\(moving.count) file\(moving.count == 1 ? "" : "s")", icon: "arrow.up.to.line")
    }

    /// Move to Basket: Shelf files (or another Basket's) go into a Basket.
    public func moveToBasket(_ ids: Set<UUID>, basketID: UUID? = nil) {
        let target = basketID ?? ensureBasket()
        let moving = heldItems(ids)
        guard !moving.isEmpty else { return }
        shelfItems.removeAll { ids.contains($0.id) }
        for index in baskets.indices where baskets[index].id != target {
            baskets[index].items.removeAll { ids.contains($0.id) }
        }
        addBasketItems(moving, to: target)
        showBasket(nearPointer: false)
        DroppyAudio.playDropSuccess()
    }
}
