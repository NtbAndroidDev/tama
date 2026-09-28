import SwiftUI
import Combine

// MARK: - Settings stores
// User preferences live in one store per area (`PomodoroSettings`,
// `ClipboardSettings`, `HUDSettings`…), each a set of @AppStorage properties.
// A view observes only the stores it reads, so changing a Pomodoro length no
// longer redraws the clipboard, and a new feature brings its own store instead
// of adding properties to AppState.
//
// Adding a setting: put the @AppStorage property in its area's store, add its
// key to that store's `keys`, and to `AppState.settingsKeys` so Reset, Export
// and Import cover it (SettingsStoreTests checks the last part).

/// Base class of the settings stores.
///
/// @AppStorage on an ObservableObject doesn't publish objectWillChange, so a
/// store is told when one of its own keys changes in UserDefaults — whoever
/// wrote it: the store, a view's own @AppStorage, Reset or Import.
@MainActor
public class SettingsStore: ObservableObject {
    init(keys: [String]) {
        SettingsChangeCenter.shared.register(self, keys: keys)
    }
}

/// One UserDefaults observer for every store, so a write anywhere costs a
/// single notification hop rather than one per store.
@MainActor
final class SettingsChangeCenter {
    static let shared = SettingsChangeCenter()

    private struct Entry {
        weak var store: SettingsStore?
        let keys: [String]
        var snapshot: NSDictionary
    }

    private var entries: [Entry] = []
    private var watch: AnyCancellable?

    private init() {}

    func register(_ store: SettingsStore, keys: [String]) {
        entries.append(Entry(store: store, keys: keys, snapshot: Self.snapshot(keys)))
        guard watch == nil else { return }
        watch = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.defaultsChanged() }
    }

    private func defaultsChanged() {
        for index in entries.indices {
            let now = Self.snapshot(entries[index].keys)
            guard now != entries[index].snapshot else { continue }
            entries[index].snapshot = now
            entries[index].store?.objectWillChange.send()
        }
    }

    private static func snapshot(_ keys: [String]) -> NSDictionary {
        UserDefaults.standard.dictionaryWithValues(forKeys: keys) as NSDictionary
    }
}
