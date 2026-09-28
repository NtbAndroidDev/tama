import SwiftUI
import AppKit

/// The User Guide window: a searchable sidebar of articles on the left, the
/// article on the right. It reads the same shortcut service and Settings
/// index the rest of the app does, so what it shows is what is set now and
/// "Open in Settings" lands on the exact row.
struct UserGuideView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @ObservedObject var model: UserGuideModel
    @FocusState private var searchFocused: Bool

    private var results: [GuideArticle] {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return DroppyGuide.articles }
        return DroppyGuide.articles.filter { $0.matches(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(SettingsStyle.hairline)
            detail
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.18)
            }
            .ignoresSafeArea()
        )
        .tint(themeSettings.accentColor.color)
        .onAppear { searchFocused = true }
        // ⌘F puts the caret back in the search field from anywhere in the window.
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Esc clears a search first, then closes the window like every other
        // Tama panel. A key equivalent, so it reaches past the search field.
        .background {
            Button("") {
                if model.query.isEmpty {
                    NSApp.keyWindow?.performClose(nil)
                } else {
                    model.query = ""
                    searchFocused = true
                }
            }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search the guide", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { model.select(first) } }
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear the search")
                    .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SettingsStyle.cardFill, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.top, 34)
            .padding(.bottom, 10)

            ScrollView {
                // Not pinned: a floating header over a translucent sidebar
                // sits on top of the row it passes, and the list is short
                // enough that a header never leaves the screen for long.
                VStack(alignment: .leading, spacing: 2) {
                    let found = results
                    if found.isEmpty {
                        SettingsNote("Nothing in the guide matches that.", icon: "magnifyingglass")
                            .padding(.top, 14)
                            .padding(.horizontal, 10)
                    }
                    ForEach(GuideCategory.allCases) { category in
                        let articles = found.filter { $0.category == category }
                        if !articles.isEmpty {
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(articles) { article in
                                GuideSidebarRow(article: article, isSelected: article.id == model.selection) {
                                    model.select(article)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 236)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let article = DroppyGuide.article(model.selection) {
            ScrollViewReader { proxy in
                ScrollView {
                    GuideArticleView(article: article, highlight: model.query)
                        .padding(.horizontal, 34)
                        .padding(.top, 36)
                        .padding(.bottom, 40)
                        .id("top")
                }
                .onChange(of: model.selection) { _, _ in
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            DroppyEmptyState(systemName: "book", title: "Pick a topic")
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Sidebar row

private struct GuideSidebarRow: View {
    let article: GuideArticle
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: article.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? themeSettings.accentColor.color : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(article.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(article.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // The one-line summary truncates in the narrow sidebar.
        .help(article.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return SettingsStyle.tileOn }
        return isHovered ? SettingsStyle.tileHover : .clear
    }
}

// MARK: - Article

private struct GuideArticleView: View {
    let article: GuideArticle
    /// The search query, so the matching words can be picked out in the body.
    let highlight: String
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: article.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(themeSettings.accentColor.color.gradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title).font(.system(size: 22, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(article.summary).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }

            ForEach(article.sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeSettings.accentColor.color)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.blocks) { block in
                        GuideBlockView(block: block, highlight: highlight)
                    }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct GuideBlockView: View {
    let block: GuideBlock
    let highlight: String

    var body: some View {
        switch block {
        case .text(let string):
            GuideText(string, highlight: highlight)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tertiary).accessibilityHidden(true)
                        GuideText(item, highlight: highlight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .steps(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                        GuideText(item, highlight: highlight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .keyTable(let keys):
            GuideCard {
                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                    if index > 0 { SettingsDivider() }
                    GuideRow(title: key.title) { KeyPill(key.keys) }
                }
            }
        case .shortcutTable(let actions):
            GuideShortcutTable(actions: actions)
        case .settings(let links):
            GuideCard {
                ForEach(Array(links.enumerated()), id: \.element) { index, link in
                    if index > 0 { SettingsDivider() }
                    GuideSettingRow(link: link)
                }
            }
        case .tip(let string):
            GuideAside(icon: "lightbulb.fill", label: "Tip", tint: .yellow, text: string, highlight: highlight)
        case .caution(let string):
            GuideAside(icon: "exclamationmark.triangle.fill", label: "Caution", tint: .orange, text: string, highlight: highlight)
        }
    }
}

/// Body copy. `**bold**` and `` `code` `` are rendered, and the words being
/// searched for are picked out so a hit is findable on a long page.
private struct GuideText: View {
    let string: String
    let highlight: String

    init(_ string: String, highlight: String) {
        self.string = string
        self.highlight = highlight
    }

    var body: some View {
        Text(attributed)
            .font(.system(size: 12.5))
            .foregroundStyle(.primary.opacity(0.88))
            .lineSpacing(3)
    }

    private var attributed: AttributedString {
        var text = (try? AttributedString(markdown: string)) ?? AttributedString(string)
        let terms = highlight.lowercased().split(separator: " ").map(String.init).filter { $0.count > 1 }
        for term in terms {
            var search = text.startIndex..<text.endIndex
            while let found = text[search].range(of: term, options: .caseInsensitive) {
                text[found].backgroundColor = .systemYellow.withAlphaComponent(0.28)
                guard found.upperBound < text.endIndex else { break }
                search = found.upperBound..<text.endIndex
            }
        }
        return text
    }
}

private struct GuideCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SettingsStyle.hairline))
    }
}

private struct GuideRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text((try? AttributedString(markdown: title)) ?? AttributedString(title))
                .font(.system(size: 12))
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Recordable shortcuts, drawn from whatever is set right now. An unset one
/// says so and offers to take you to the recorder rather than showing nothing.
private struct GuideShortcutTable: View {
    let actions: [ShortcutAction]
    @ObservedObject private var shortcuts = GlobalShortcutService.shared

    var body: some View {
        GuideCard {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                if index > 0 { SettingsDivider() }
                GuideRow(title: action.title) {
                    if let keys = shortcuts.display(for: action) {
                        KeyPill(keys)
                    } else {
                        // Drawn like the Settings rows' links, so it reads as one.
                        Button { GuideNavigation.openSetting("shortcuts.all") } label: {
                            HStack(spacing: 4) {
                                Text("Not set")
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 9, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help("Record one in Settings › Keyboard Shortcuts")
                            .accessibilityLabel("Not set")
                            .accessibilityHint("Opens Settings › Keyboard Shortcuts to record one")
                    }
                }
            }
        }
        // The service bumps `revision` when a shortcut changes, so the table
        // redraws while Settings is open beside the guide.
        .id(shortcuts.revision)
    }
}

private struct GuideSettingRow: View {
    let link: GuideSettingLink
    @State private var isHovered = false

    var body: some View {
        Button { GuideNavigation.openSetting(link.anchor) } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(link.title).font(.system(size: 12))
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? SettingsStyle.tileHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open this in Settings")
        .accessibilityHint("Opens this in Settings")
    }
}

private struct GuideAside: View {
    let icon: String
    /// What VoiceOver reads for the icon: the aside's kind.
    let label: String
    let tint: Color
    let text: String
    let highlight: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityLabel(label)
            GuideText(text, highlight: highlight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }
}

// MARK: - Jumping into Settings

enum GuideNavigation {
    /// Opens Settings on the row an anchor names, highlighting it the way a
    /// search hit is. An anchor with no entry still opens its page.
    @MainActor static func openSetting(_ anchor: String) {
        if let entry = SettingsSearchIndex.entries.first(where: { $0.anchor == anchor }) {
            SettingsNavigator.shared.reveal(entry)
        }
        SettingsWindowController.shared.showWindow()
    }
}
