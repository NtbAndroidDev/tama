import AppKit

/// Settings › Basket › Basket Switcher: its shortcut lists every Basket at
/// the pointer, with its colour and file count, to bring one over, make a
/// new one, or put them all away.
@MainActor
enum BasketSwitcher {
    static func show() {
        let state = AppState.shared
        let menu = NSMenu(title: "Baskets")
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Baskets", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let baskets = state.basketMode == .single ? Array(state.baskets.prefix(1)) : state.baskets
        for (index, basket) in baskets.enumerated() {
            let size = ByteCountFormatter.string(fromByteCount: basket.totalSize, countStyle: .file)
            let title = "\(basket.colorName) Basket — \(basket.items.count) file\(basket.items.count == 1 ? "" : "s")"
                + (basket.items.isEmpty ? "" : ", \(size)")
            let item = menu.add(title, image: HeldItemsMenu.tagDot(basket.color)) { state.focusBasket(basket.id) }
            item.state = state.isBasketVisible && (basket.isOpen || state.basketMode == .single) ? .on : .off
            if index < 9 { item.keyEquivalent = "\(index + 1)" }
            item.keyEquivalentModifierMask = []
        }
        if baskets.isEmpty {
            menu.add("Show Basket", symbol: "basket") { state.showBasket(nearPointer: true) }
        }
        menu.addItem(.separator())
        if state.basketMode == .multi {
            menu.add("New Basket", symbol: "plus") { state.spawnBasket() }
        }
        if state.isBasketVisible {
            menu.add("Hide Baskets", symbol: "eye.slash") { state.isBasketVisible = false }
        }
        menu.popUpAtPointer()
    }
}
