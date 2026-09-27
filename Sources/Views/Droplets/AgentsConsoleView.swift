import SwiftUI

// Agents — what Claude Code, Codex and Cursor are doing: the glyph and name,
// the task line, "▶ Running …", and the latest reply on a card.

struct AgentsConsoleView: View {
    @ObservedObject private var agents = AgentActivityService.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if agents.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.md) {
                        ForEach(agents.sessions) { AgentCard(session: $0) }
                    }
                }
            }
        }
        .onAppear { agents.sync() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "sparkles").foregroundStyle(AgentKind.claude.tint).accessibilityHidden(true)
                Text("No coding agent is working right now")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            sourceRow(.claude, detail: agents.claudeHooksInstalled
                      ? "Hooks installed — new Claude Code sessions show up here."
                      : "Needs Tama's hooks in ~/.claude/settings.json.",
                      ready: agents.claudeHooksInstalled) {
                if !agents.claudeHooksInstalled {
                    DroppyPillButton("Set up…", systemName: "wrench.and.screwdriver", tone: .accent,
                                     help: "Add Tama's hooks to ~/.claude/settings.json") {
                        agents.installClaudeHooks()
                    }
                }
            }
            sourceRow(.codex, detail: agents.codexAvailable ? "Reading Codex's session logs." : "Codex not found (~/.codex/sessions).",
                      ready: agents.codexAvailable) { EmptyView() }
            sourceRow(.cursor, detail: agents.cursorAvailable ? "Reading Cursor's recent chat status (best effort)." : "Cursor not found.",
                      ready: agents.cursorAvailable) { EmptyView() }
            if let error = agents.lastError {
                Text(error).font(DS.Typo.caption).foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sourceRow<Trailing: View>(_ kind: AgentKind, detail: String, ready: Bool,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(kind.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                Text(detail).font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
                    .help(detail)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            trailing()
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? DS.Palette.success : DS.Palette.textSecondary)
                .accessibilityLabel(ready ? "Ready" : "Not set up")
        }
    }
}

/// One agent session, laid out like the reference's expanded widget.
struct AgentCard: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    ZStack {
                        if session.activity.isWorking {
                            ActivitySpinner(tint: session.kind.tint, size: 26)
                        }
                        Image(systemName: session.kind.symbol)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(session.kind.tint)
                    }
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                    Text(session.kind.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    if !session.task.isEmpty {
                        Circle().fill(session.kind.tint).frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text(session.task)
                            .font(DS.Typo.headline)
                            .foregroundStyle(session.kind.tint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(session.task)
                    }
                }
                HStack(spacing: DS.Space.sm) {
                    // The line says what the agent is doing; the glyph only echoes it.
                    Image(systemName: statusSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(session.kind.tint)
                        .accessibilityHidden(true)
                    Text(session.activity.line)
                        .font(DS.Typo.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(session.activity.line)
                }
                if !session.project.isEmpty {
                    Text(session.project).font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !session.assistantText.isEmpty {
                Text(session.assistantText)
                    .font(DS.Typo.label)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .truncationMode(.tail)
                    .padding(DS.Space.md)
                    .frame(width: 210)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface2))
                    .help(session.assistantText)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch session.activity {
        case .tool, .thinking: "play.fill"
        case .waiting: "exclamationmark.circle.fill"
        case .finished: "checkmark"
        case .failed: "xmark"
        case .idle: "pause.fill"
        }
    }
}
