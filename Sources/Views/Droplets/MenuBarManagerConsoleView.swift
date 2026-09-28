import SwiftUI

/// Menu Bar Manager in the shelf: show or hide the hidden icons, the
/// always-hidden ones too, reset the layout, and how to arrange them.
public struct MenuBarManagerConsoleView: View {
    @ObservedObject private var manager = MenuBarManagerService.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var menuBarSettings = MenuBarSettings.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: manager.isRevealed ? "menubar.arrow.down.rectangle" : "menubar.rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.Palette.surface2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(manager.isRevealed ? "Hidden icons are showing" : "Hidden icons are tucked away")
                        .font(DS.Typo.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Space.sm) {
                DroppyPillButton(manager.isRevealed ? "Hide" : "Show", systemName: manager.isRevealed ? "eye.slash" : "eye",
                                 tone: .accent,
                                 help: manager.isRevealed ? "Hide the icons left of the divider" : "Show the hidden icons") { manager.toggle() }
                if menuBarSettings.alwaysHidden {
                    DroppyPillButton("Show all", systemName: "eye.circle", tone: .tonal,
                                     help: "Include the always-hidden section") { manager.reveal(all: true) }
                }
                Spacer(minLength: 0)
                DroppyPillButton("Reset layout", systemName: "arrow.counterclockwise", tone: .tonal,
                                 help: "Put Tama's toggle and dividers back in their starting places") { manager.resetLayout() }
            }
            .disabled(!manager.isRunning)
            if manager.isMisordered {
                Label("A divider is right of the toggle, so nothing is hidden. ⌘-drag it back left, or reset the layout.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Hold ⌘ and drag icons to the left of the | divider to hide them. Click the toggle to show them, Option-click to include the always-hidden ones.")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Space.xs)
    }

    private var detail: String {
        guard menuBarSettings.autoRehide else { return "They stay until you click the toggle again." }
        return "They fold away again after \(Int(menuBarSettings.rehideDelay)) s."
    }
}
