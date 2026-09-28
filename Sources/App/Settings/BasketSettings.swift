import SwiftUI

/// Settings › Basket: how the floating Basket appears, hides and lays out.
@MainActor
public final class BasketSettings: SettingsStore {
    public static let shared = BasketSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "jiggleToOpenBasket", "basketInstantAppear", "basketInstantDelay", "basketAutoHide",
        "basketAutoHideDelay", "basketShakeSensitivity", "basketDragModifiers", "basketMode",
        "basketSecondBucket", "basketLayout"
    ]

    /// Shake a file drag to summon the Basket.
    @AppStorage("jiggleToOpenBasket") public var jiggleToOpenBasket: Bool = true
    /// Instant appear: any file drag shows the Basket after a short delay, no shake needed.
    @AppStorage("basketInstantAppear") public var instantAppear: Bool = false
    @AppStorage("basketInstantDelay") public var instantDelay: Double = 0.35
    /// Auto-hide: the Basket goes once it's been idle (no drag, pointer away) this long.
    @AppStorage("basketAutoHide") public var autoHide: Bool = false
    @AppStorage("basketAutoHideDelay") public var autoHideDelay: Double = 3
    /// 0 (a big, deliberate shake) … 1 (a flick is enough).
    @AppStorage("basketShakeSensitivity") public var shakeSensitivity: Double = 0.5
    /// Drag shortcut: modifiers (NSEvent.ModifierFlags raw value) that, held
    /// while dragging files, bring the Basket. 0 = none.
    @AppStorage("basketDragModifiers") public var dragModifiers: Int = 0
    @AppStorage("basketMode") public var mode: BasketMode = .single {
        didSet { if mode == .single { AppState.shared.mergeBasketsIntoFirst() } }
    }
    /// A second bucket in each Basket for rarely used items.
    @AppStorage("basketSecondBucket") public var secondBucket: Bool = false
    @AppStorage("basketLayout") public var layout: BasketLayout = .grid

    private init() { super.init(keys: Self.keys) }
}
