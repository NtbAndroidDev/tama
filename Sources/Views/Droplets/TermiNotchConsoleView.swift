import SwiftUI
import AppKit

// TermiNotch — a real shell on a pty in the notch. Expanded mode fills the
// shelf with the terminal (no chrome, the prompt at the top); the quick bar
// is a one-line command field over the last lines of output.

struct TermiNotchConsoleView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var sessions = TermiNotchSessions.shared
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let session = sessions.active {
                if state.termiNotchQuickBar {
                    TermiNotchQuickBar(session: session)
                } else {
                    expanded(session)
                }
            } else {
                // The first shell starts when the droplet opens.
                VStack(spacing: DS.Space.sm) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text("Starting the shell…")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { TermiNotchSessions.shared.ensureSession() }
            }
        }
        // ↗ and ↻ beside the navigation bar, like the reference's TermiNotch.
        .shelfAccessories("termiNotch", [
            ShelfAccessory(id: "termiNotch.open", icon: "arrow.up.forward",
                           help: "Open in \(state.termiNotchTerminalApp.title)",
                           page: .widgets, dropletID: "termiNotch") { TermiNotchSessions.shared.openInTerminalApp() },
            ShelfAccessory(id: "termiNotch.restart", icon: "arrow.clockwise", help: "Restart session",
                           page: .widgets, dropletID: "termiNotch") { TermiNotchSessions.shared.active?.restart() },
            ShelfAccessory(id: "termiNotch.close", icon: "xmark", help: "Back to widgets",
                           page: .widgets, dropletID: "termiNotch") {
                DroppyAudio.playTick()
                AppState.shared.activeDropletID = nil
            },
        ])
        .onAppear { applyHeight() }
        .onChange(of: state.termiNotchQuickBar) { _, _ in applyHeight() }
        .onDisappear { state.clearEditing(withPrefix: "droplet.terminotch") }
    }

    private func applyHeight() {
        state.dropletConsoleHeight = state.termiNotchQuickBar
            ? DroppyShelfMetrics.termiNotchBarHeight : DroppyShelfMetrics.termiNotchExpandedHeight
    }

    private func expanded(_ session: TerminalSession) -> some View {
        VStack(spacing: DS.Space.xs) {
            if sessions.sessions.count > 1 { tabStrip }
            TerminalCanvas(session: session, fontSize: CGFloat(state.termiNotchFontSize),
                           editingOwner: "droplet.terminotch.terminal")
                .id(session.id)
                .accessibilityLabel("Terminal, \(session.title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering { hoverTools(session) }
        }
        .onHover { hovering in
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { isHovering = hovering }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(sessions.sessions) { tab in
                    TermiNotchTab(session: tab, isActive: tab.id == sessions.active?.id)
                }
            }
        }
        .frame(height: 20)
    }

    private func hoverTools(_ session: TerminalSession) -> some View {
        HStack(spacing: DS.Space.xs) {
            DroppyIconButton("plus", size: 22, help: "New tab (⌘T)") { TermiNotchSessions.shared.newTab() }
            DroppyIconButton("clear", size: 22, help: "Clear terminal output (⌘K)") { session.clear() }
            DroppyIconButton("rectangle.compress.vertical", size: 22, help: "Quick command bar") {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.termiNotchQuickBar = true }
            }
        }
        .padding(DS.Space.xs)
        .background(.black.opacity(0.55), in: Capsule())
        .transition(.opacity)
    }
}

private struct TermiNotchTab: View {
    @ObservedObject var session: TerminalSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text(session.title)
                .font(DS.Typo.mono.weight(isActive ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            Button {
                TermiNotchSessions.shared.close(session)
            } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    // The glyph is 7 pt; give the click a target it can hit.
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DroppyPressStyle(scale: 0.85))
            .foregroundStyle(DS.Palette.textSecondary)
            .accessibilityLabel("Close \(session.title)")
            .help("Close tab (⌘W)")
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: 18)
        .background(Capsule().fill(isActive ? DS.Palette.surface3 : DS.Palette.surface1))
        .contentShape(Capsule())
        .onTapGesture { TermiNotchSessions.shared.select(session) }
        .help(session.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { TermiNotchSessions.shared.select(session) }
    }
}

/// "Quick command bar": the last few lines of output and a one-line field
/// that types into the same shell. Ctrl-C stops what's running.
private struct TermiNotchQuickBar: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject private var state = AppState.shared
    @State private var command = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            let lines = session.screen.lastLines(4)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(TerminalPalette.attributed(line, size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
                // Redraw on output.
                Color.clear.frame(height: 0).id(session.revision)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            HStack(spacing: DS.Space.sm) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: TerminalPalette.color(.ansi(2))))
                    .accessibilityHidden(true)
                TextField("Run a command…", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .onSubmit(run)
                    .accessibilityLabel("Command")
                    .onKeyPress(keys: ["c"], phases: .down) { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        session.interrupt()
                        return .handled
                    }
                if session.isBusy {
                    DroppyIconButton("stop.fill", size: 22, help: "Send Ctrl-C") { session.interrupt() }
                }
                DroppyIconButton("rectangle.expand.vertical", size: 22, help: "Expanded terminal") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.termiNotchQuickBar = false }
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 5)
            .background(DS.Palette.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .onAppear { focused = true }
        // A half-typed command holds the shelf open; collapsing would reset the
        // page and take the line with it.
        .onChange(of: focused) { _, isFocused in
            state.setEditing(isFocused, owner: "droplet.terminotch.quickBar")
        }
        .onDisappear { state.setEditing(false, owner: "droplet.terminotch.quickBar") }
    }

    private func run() {
        let text = command
        command = ""
        session.send(text + "\r")
        focused = true
    }
}
