import SwiftUI
import AppKit

// Window Snapper Console — interactive console for this Droplet, presented inside the Droplets lane.

struct WindowSnapperConsoleView: View {
    static let tint = Color(red: 70/255, green: 200/255, blue: 250/255)

    @ObservedObject var state = AppState.shared
    @State private var activeSnapTitle: String? = nil
    @State private var isTrusted = AXIsProcessTrusted()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Granting happens in System Settings, so re-check while it's missing.
    private let trustPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: DS.Space.md) {
            // Header
            HStack {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "rectangle.split.2x1")
                        .foregroundColor(Self.tint)
                        .accessibilityHidden(true)
                    Text("Snap & layouts")
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                if !isTrusted {
                    Text("Needs \(PermissionService.accessibilityName)")
                        .font(DS.Typo.caption)
                        .foregroundColor(DS.Palette.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // Requesting also adds Tama to the list, so there's a switch to turn on.
                    DroppyPillButton("Grant", systemName: "lock.open", tone: .accent,
                                     help: "Allow Tama to move other apps' windows") {
                        PermissionService.shared.request(.accessibility)
                    }
                }
            }
            
            Text(isTrusted
                 ? "Snaps the focused window of the app you were last using."
                 : "Allow \(PermissionService.accessibilityName) access so Tama can move other apps' windows.")
                .font(DS.Typo.label)
                .foregroundColor(DS.Palette.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Every layout; the display moves and Bring to Front last.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.sm), count: 6), spacing: DS.Space.sm) {
                    ForEach(SnapLayout.allCases) { layout in
                        SnapPresetButton(layout: layout, isSelected: activeSnapTitle == layout.title) {
                            performSnap(layout)
                        }
                    }
                }
            }
            // Every snap fails without access, so the grid reads as unavailable until then.
            .disabled(!isTrusted)
            
            Spacer()
        }
        .onAppear { isTrusted = AXIsProcessTrusted() }
        .onReceive(trustPoll) { _ in
            if !isTrusted { isTrusted = AXIsProcessTrusted() }
        }
    }
    
    private func performSnap(_ layout: SnapLayout) {
        withAnimation(DS.Motion.respecting(reduceMotion, .easeInOut(duration: 0.15))) {
            activeSnapTitle = layout.title
        }
        DroppyAudio.playTick()
        WindowSnapService.shared.perform(layout, fromShortcut: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if self.activeSnapTitle == layout.title {
                withAnimation(DS.Motion.respecting(self.reduceMotion, .default)) {
                    self.activeSnapTitle = nil
                }
            }
        }
    }
}

struct SnapPresetButton: View {
    let layout: SnapLayout
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    private var tint: Color { WindowSnapperConsoleView.tint }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xxs) {
                Image(systemName: layout.icon)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                    .foregroundColor(isSelected ? .white : (isHovered ? tint : DS.Palette.textPrimary))
                
                Text(layout.detail)
                    .font(DS.Typo.micro)
                    .foregroundColor(isSelected ? .white : DS.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(isSelected ? tint : isHovered ? DS.Palette.surface2 : DS.Palette.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : (isHovered ? tint.opacity(0.5) : DS.Palette.hairline), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(DroppyPressStyle(scale: 0.97))
        .help(shortcutHelp)
        .accessibilityLabel(layout.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = isEnabled && $0 }
        .animation(DS.Motion.hover, value: isHovered)
    }

    private var shortcutHelp: String {
        GlobalShortcutService.shared.display(for: layout.shortcutAction).map { "\(layout.title) (\($0))" } ?? layout.title
    }
}
