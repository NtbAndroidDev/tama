import SwiftUI

/// Settings › Keyboard Shortcuts: every recordable shortcut in one list,
/// grouped by area, plus an optional shortcut per widget that opens its
/// console, a filter and Reset all shortcuts.
struct KeyboardShortcutsSettingsPage: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var shortcuts = GlobalShortcutService.shared
    @State private var filter = ""
    @State private var isConfirmingReset = false

    private func matches(_ title: String, _ extra: String = "") -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        _ = shortcuts.revision
        return "\(title) \(extra)".lowercased().contains(q)
    }

    private func actions(in group: ShortcutGroup) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { action in
            action.group == group && matches(action.title, shortcuts.display(for: action) ?? "")
        }
    }

    private var widgetSlots: [DropletModel] {
        state.droplets.filter { $0.isEnabled && matches("Open \($0.name)", shortcuts.combo(for: .droplet($0.id))?.display ?? "") }
    }

    private var isEmpty: Bool {
        ShortcutGroup.allCases.filter { $0 != .widgets }.allSatisfy { actions(in: $0).isEmpty } && widgetSlots.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Keyboard Shortcuts",
                            subtitle: "Record a shortcut, press ⌫ while recording to clear it, or ↺ to go back to its default.",
                            anchor: "shortcuts.all") {
                SettingsGroup {
                    SettingsRow("Filter", icon: "magnifyingglass") {
                        TextField("Search shortcuts", text: $filter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .accessibilityLabel("Filter shortcuts")
                            .onExitCommand { filter = "" }
                    }
                    SettingsDivider()
                    SettingsRow("Reset all shortcuts", subtitle: "Every shortcut goes back to its default; widget shortcuts are cleared.",
                                anchor: "shortcuts.resetAll") {
                        Button("Reset All…") { isConfirmingReset = true }
                    }
                }
            }

            if isEmpty {
                SettingsGroup {
                    SettingsNote("No shortcuts match \u{201C}\(filter.trimmingCharacters(in: .whitespaces))\u{201D}.", icon: "magnifyingglass")
                        .padding(.top, 10)
                }
            }

            ForEach(ShortcutGroup.allCases.filter { $0 != .widgets }, id: \.self) { group in
                let list = actions(in: group)
                if !list.isEmpty {
                    SettingsSection(group.rawValue) {
                        SettingsGroup {
                            ForEach(Array(list.enumerated()), id: \.element) { index, action in
                                if index > 0 { SettingsDivider() }
                                ShortcutRecorderRow(action, help: note(for: action))
                            }
                        }
                    }
                }
            }

            // While filtering, an empty widget list would only repeat the
            // "No shortcuts found" note above.
            if filter.isEmpty || !widgetSlots.isEmpty {
                SettingsSection("Widget shortcuts",
                                subtitle: "An optional shortcut per widget that opens its console in the shelf; press it again to close.",
                                anchor: "shortcuts.widgets") {
                    SettingsGroup {
                        let widgets = widgetSlots
                        if widgets.isEmpty {
                            SettingsNote(filter.isEmpty ? "Install and enable widgets to record per-widget shortcuts here."
                                                        : "No widget shortcuts found.",
                                         icon: "puzzlepiece.extension")
                                .padding(.top, 10)
                        } else {
                            ForEach(Array(widgets.enumerated()), id: \.element.id) { index, droplet in
                                if index > 0 { SettingsDivider() }
                                ShortcutRecorderRow(slot: .droplet(droplet.id))
                            }
                        }
                    }
                }
            }

            if filter.isEmpty {
                SettingsSection("Built-in") {
                    SettingsGroup {
                        SettingsRow("Switch shelf page (shelf focused)") { KeyPill("⌘1 – ⌘4") }
                        SettingsDivider()
                        SettingsRow("Collapse the island") { KeyPill("Esc") }
                        SettingsDivider()
                        SettingsRow("Thunderstorm: reveal, Quick Look, Tray, copy path, Move to Trash") {
                            KeyPill("⌘↩ ⌘Y ⌘T ⌘C ⌘⌫")
                        }
                    }
                }
            }
        }
        .confirmationDialog("Reset all shortcuts?", isPresented: $isConfirmingReset) {
            Button("Reset All Shortcuts", role: .destructive) {
                shortcuts.resetAll()
                DroppyAudio.playTick()
            }
        } message: {
            Text("Every shortcut goes back to its default, and widget shortcuts are cleared.")
        }
    }

    /// Why a shortcut might not fire: its droplet is off.
    private func note(for action: ShortcutAction) -> String? {
        guard let id = action.dropletID, let droplet = state.droplets.first(where: { $0.id == id }),
              !droplet.isEnabled else { return nil }
        return "Works while the \(droplet.name) droplet is on."
    }
}
