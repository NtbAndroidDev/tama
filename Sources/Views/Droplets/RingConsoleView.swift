import SwiftUI

/// Picks and orders the Ring's actions (up to eight) and shows its shortcut.
public struct RingConsoleView: View {
    @ObservedObject private var store = RingActionStore.shared
    @ObservedObject private var shortcuts = GlobalShortcutService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var available: [RingAction] { RingAction.allCases.filter { !store.actions.contains($0) } }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Text(shortcuts.display(for: .ring) ?? "No shortcut")
                    .font(DS.Typo.numeric)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, DS.Space.sm)
                    .frame(height: 20)
                    .background(Capsule().fill(NotchPalette.control))
                    .accessibilityLabel(shortcuts.display(for: .ring).map { "Shortcut: \($0)" } ?? "No shortcut")
                Text("Hold, point, release — or tap, then click or press 1–\(store.actions.count)")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .help("Hold, point, release — or tap, then click or press 1–\(store.actions.count)")
                Spacer(minLength: 0)
                DroppyPillButton("Try it", systemName: "circle.circle", tone: .accent, help: "Open the ring now") {
                    RingWindowController.shared.show()
                }
            }
            if shortcuts.failedActions.contains(.ring) {
                HStack(spacing: DS.Space.sm) {
                    Label("Another app holds \(shortcuts.display(for: .ring) ?? "this shortcut"). Record another in Settings › General.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.warning)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    DroppyPillButton("Settings", systemName: "gear", tone: .tonal,
                                     help: "Record another shortcut in Settings › General") {
                        SettingsWindowController.shared.showWindow(page: .general)
                    }
                }
            }

            // The ring list, the catalog and Reset outgrow the fixed console
            // height, so they scroll instead of being clipped away.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    sectionLabel("In the ring · \(store.actions.count)/\(RingActionStore.maxCount)")
                    VStack(spacing: DS.Space.xxs) {
                        ForEach(Array(store.actions.enumerated()), id: \.element) { index, action in
                            HStack(spacing: DS.Space.sm) {
                                Text("\(index + 1)")
                                    .font(DS.Typo.numericSmall)
                                    .foregroundStyle(DS.Palette.textSecondary)
                                    .frame(width: 14)
                                    .accessibilityHidden(true)
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textPrimary)
                                    .frame(width: 18)
                                    .accessibilityHidden(true)
                                Text(action.title)
                                    .font(DS.Typo.label)
                                    .foregroundStyle(DS.Palette.textPrimary)
                                    .lineLimit(1)
                                    .accessibilityLabel("\(index + 1). \(action.title)")
                                Spacer(minLength: DS.Space.xs)
                                DroppyIconButton("chevron.up", size: 20, help: "Move \(action.title) earlier") { store.move(action, by: -1) }
                                    .disabled(index == 0)
                                DroppyIconButton("chevron.down", size: 20, help: "Move \(action.title) later") { store.move(action, by: 1) }
                                    .disabled(index == store.actions.count - 1)
                                DroppyIconButton("minus", size: 20, help: "Remove \(action.title) from the ring") { store.remove(action) }
                                    .disabled(store.actions.count <= RingActionStore.minCount)
                            }
                            .padding(.horizontal, DS.Space.sm)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(NotchPalette.tile))
                        }
                    }
                    .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: store.actions)

                    if !available.isEmpty {
                        sectionLabel(store.actions.count < RingActionStore.maxCount ? "Add" : "Ring is full — remove one to add")
                        FlowChips(actions: available, isEnabled: store.actions.count < RingActionStore.maxCount) { store.add($0) }
                    }
                    HStack {
                        Spacer()
                        DroppyPillButton("Reset", systemName: "arrow.counterclockwise", tone: .plain,
                                         help: "Put the ring's default actions back") { store.reset() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DS.Typo.micro)
            .foregroundStyle(DS.Palette.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Catalog chips, wrapped onto as many rows as needed.
private struct FlowChips: View {
    let actions: [RingAction]
    let isEnabled: Bool
    let onAdd: (RingAction) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: DS.Space.xs, alignment: .leading)],
                  alignment: .leading, spacing: DS.Space.xs) {
            ForEach(actions) { action in
                DroppyPillButton(action.title, systemName: action.systemImage, tone: .tonal,
                                 help: "Add \(action.title) to the ring") { onAdd(action) }
                    .disabled(!isEnabled)
            }
        }
    }
}
