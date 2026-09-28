import SwiftUI

// Settings › Shelf behaviour that isn't geometry: rearranging widgets,
// swiping between pages, favorites.

extension AppState {
    // MARK: Widget order

    /// Opens the Widgets page with every widget in a grid to drag around.
    public func beginRearrangingWidgets() {
        guard ShelfSettings.shared.isEnabled else { return }
        cancelHomeCustomization()
        open(.widgets)
        withAnimation(DS.Motion.fluid) {
            activeDropletID = nil
            isRearrangingWidgets = true
        }
        NotchWindowController.shared.focusPanel()
        DroppyAudio.playTick()
    }

    public func endRearrangingWidgets() {
        guard isRearrangingWidgets else { return }
        withAnimation(DS.Motion.fluid) { isRearrangingWidgets = false }
        DroppyAudio.playTick()
    }

    /// Puts the enabled widgets in `enabledOrder`. Switched-off widgets keep
    /// their places in between, so turning one back on returns it to its spot.
    public func reorderWidgets(_ enabledOrder: [String]) {
        var queue = enabledOrder.filter { id in droplets.contains { $0.id == id && $0.isEnabled } }
        let missing = droplets.filter { $0.isEnabled && !queue.contains($0.id) }.map(\.id)
        queue += missing
        var result: [DropletModel] = []
        for droplet in droplets {
            if droplet.isEnabled, !queue.isEmpty {
                let id = queue.removeFirst()
                if let next = droplets.first(where: { $0.id == id }) { result.append(next) }
            } else if !droplet.isEnabled {
                result.append(droplet)
            }
        }
        guard result.map(\.id) != droplets.map(\.id), result.count == droplets.count else { return }
        droplets = result
    }

    /// Applies the saved order (`dropletOrder`) to the built-in list; widgets
    /// the save doesn't know yet keep their default place at the end.
    func applyStoredDropletOrder(_ order: [String]) {
        guard !order.isEmpty else { return }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let indexed = droplets.enumerated().map { ($0, $1) }
        droplets = indexed.sorted { a, b in
            (rank[a.1.id] ?? order.count + a.0, a.0) < (rank[b.1.id] ?? order.count + b.0, b.0)
        }.map(\.1)
    }

    // MARK: Gestures

    /// The pages a sideways swipe walks through, in bar order.
    static let swipePages: [ShelfPage] = [.home, .tray, .widgets, .calendar]

    /// A two-finger swipe moved to the next (+1) or previous (−1) page.
    public func selectAdjacentPage(_ step: Int) {
        guard let index = Self.swipePages.firstIndex(of: shelfPage) else { return }
        let target = index + step
        guard Self.swipePages.indices.contains(target) else { return }
        select(Self.swipePages[target])
    }

    // MARK: Favorites

    public func setFavorite(_ favorite: ShelfFavorite?, at index: Int) {
        var list = shelfFavorites
        if let favorite {
            list.removeAll { $0 == favorite }
            if index < list.count { list[index] = favorite } else { list.append(favorite) }
        } else if list.indices.contains(index) {
            list.remove(at: index)
        }
        shelfFavorites = Array(list.prefix(ShelfFavorite.limit))
        DroppyAudio.playTick()
    }
}
