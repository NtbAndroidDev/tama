import SwiftUI

// MARK: - Window content

/// Settings, laid out like the reference: a glass window with a sidebar
/// (search, then General and Droplets, Workspace, System and About) beside a
/// lighter rounded content panel. Every page is built from the blocks in
/// SettingsPrimitives.swift, and search jumps to any row by its anchor
/// (SettingsSearch.swift).
public struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state = AppState.shared
    @ObservedObject private var navigator = SettingsNavigator.shared
    @State private var query = ""

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(query: $query)
                .frame(width: 208)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding([.top, .bottom, .trailing], 10)
        }
        .background(windowBackground.ignoresSafeArea())
        .tint(state.accentColor.color)
        .frame(minWidth: 700, idealWidth: 780, minHeight: 520, idealHeight: 660)
        // Every fill here (cards, tiles, hairlines, the solid background) is
        // white-on-dark, so the window is dark whatever the system appearance.
        // SettingsWindowController already sets darkAqua on the window; this
        // keeps the view honest wherever it is hosted.
        .preferredColorScheme(.dark)
    }

    /// Dark glass, washed with Theming › Window tint — or one opaque colour
    /// when Theming › Settings window › Solid background is on.
    private var windowBackground: some View {
        ZStack {
            if state.solidSettingsBackground {
                Color(red: 0.11, green: 0.11, blue: 0.12)
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.18)
            }
            if let tint = state.windowTintColor { tint.opacity(0.12) }
        }
    }

    @ViewBuilder private var content: some View {
        if navigator.page == .droplets {
            DropletsStoreTab(openDropletID: $navigator.openDropletID)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    page
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 24)
                }
                .id(navigator.page)
                .onAppear { scroll(proxy) }
                .onChange(of: navigator.scrollTarget) { _, _ in scroll(proxy) }
            }
        }
    }

    /// Search set a row to show: wait a beat for a page switch to lay out.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = navigator.scrollTarget else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { proxy.scrollTo(target, anchor: .center) }
            navigator.scrollTarget = nil
        }
    }

    @ViewBuilder private var page: some View {
        switch navigator.page {
        case .general: GeneralSettingsPage()
        case .droplets: EmptyView()
        case .shortcuts: KeyboardShortcutsSettingsPage()
        case .shelf: ShelfSettingsPage()
        case .basket: BasketSettingsPage()
        case .clipboard: ClipboardSettingsPage()
        case .lockScreen: LockScreenSettingsPage()
        case .huds: HUDsSettingsPage()
        case .theming: ThemingSettingsPage()
        case .accessibility: AccessibilitySettingsPage()
        case .about: AboutSettingsPage()
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var query: String
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var navigator = SettingsNavigator.shared
    /// The result ↑ and ↓ have moved to; Return opens it.
    @State private var selection = 0

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var results: [SettingsSearchEntry] { SettingsSearchIndex.search(query) }

    /// While searching, the guide articles that answer the same question.
    /// Settings search is where people look for "how do I…" as well as for a
    /// switch, and an option alone often isn't the answer.
    private var matchingArticles: [GuideArticle] {
        guard trimmedQuery.count > 1 else { return [] }
        return Array(DroppyGuide.articles.filter { $0.matches(trimmedQuery) }.prefix(5))
    }

    /// While searching, droplets whose name or tag match too.
    private var matchingDroplets: [DropletModel] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return state.droplets.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.tag.localizedCaseInsensitiveContains(q)
        }
    }

    /// Every result in the order it's listed, for keyboard selection.
    private enum Hit {
        case entry(SettingsSearchEntry)
        case droplet(DropletModel)
        case article(GuideArticle)
    }

    private var hits: [Hit] {
        results.map(Hit.entry) + matchingDroplets.map(Hit.droplet) + matchingArticles.map(Hit.article)
    }

    private func open(_ hit: Hit) {
        switch hit {
        case .entry(let entry): go(entry)
        case .droplet(let droplet): openDroplet(droplet)
        case .article(let article): openArticle(article)
        }
    }

    /// Moves the keyboard selection, wrapping at either end.
    private func moveSelection(by step: Int) -> KeyPress.Result {
        let count = hits.count
        guard count > 0 else { return .ignored }
        selection = ((selection + step) % count + count) % count
        return .handled
    }

    private func highlighted(_ text: String) -> AttributedString {
        SettingsSearchIndex.highlighted(text, query: trimmedQuery, color: state.accentColor.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
                .padding(.top, 38) // clear of the traffic lights
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if query.isEmpty {
                            navigation
                        } else {
                            searchResults
                        }
                    }
                }
                .onChange(of: selection) { _, index in
                    guard !query.isEmpty else { return }
                    proxy.scrollTo("search-hit-\(index)")
                }
            }
            Spacer(minLength: 0)
            Button { state.open(.home) } label: {
                Label("Open the shelf", systemImage: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .accessibilityLabel("Search settings")
                .onExitCommand { query = "" }
                .onSubmit {
                    let list = hits
                    if list.indices.contains(selection) { open(list[selection]) } else if let first = list.first { open(first) }
                }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .onChange(of: query) { _, _ in selection = 0 }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    @ViewBuilder private var navigation: some View {
        ForEach(SettingsPage.Group.allCases, id: \.self) { group in
            if !group.rawValue.isEmpty {
                Text(group.rawValue)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10).padding(.top, 14).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(SettingsPage.allCases.filter { $0.group == group }) { page in
                Button { navigator.open(page) } label: {
                    HStack(spacing: 10) {
                        SidebarGlyph(symbol: page.icon)
                        Text(page.title)
                        Spacer(minLength: 0)
                        if page == .droplets {
                            Text("\(state.droplets.filter(\.isEnabled).count)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                    .modifier(SidebarRowStyle(isSelected: navigator.page == page && navigator.openDropletID == nil))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(navigator.page == page ? .isSelected : [])
            }
        }
        // Ours: switched-on droplets listed like apps under System Settings.
        let hidden = Set(state.sidebarHiddenDroplets.split(separator: ",").map(String.init))
        let enabled = state.droplets.filter { $0.isEnabled && !hidden.contains($0.id) }
        if !enabled.isEmpty {
            Text("Enabled Droplets")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10).padding(.top, 14).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(enabled) { droplet in dropletRow(droplet) }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let entries = results
        let droplets = matchingDroplets
        let articles = matchingArticles
        if entries.isEmpty && droplets.isEmpty && articles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No results for \u{201C}\(trimmedQuery)\u{201D}")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Try a feature, an option, or a synonym.").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Search the guide instead") { UserGuideWindowController.shared.search(query) }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.accentColor.color)
            }
            .font(.system(size: 11))
            .padding(.leading, 10).padding(.top, 6)
        }
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            Button { go(entry) } label: {
                HStack(spacing: 10) {
                    SidebarGlyph(symbol: entry.page.icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(highlighted(entry.title)).lineLimit(1)
                        Text(entry.page.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .modifier(SidebarRowStyle(isSelected: selection == index))
            }
            .buttonStyle(.plain)
            .help(entry.title)
            .accessibilityLabel("\(entry.title), \(entry.page.title)")
            .accessibilityAddTraits(selection == index ? .isSelected : [])
            .id("search-hit-\(index)")
        }
        if !droplets.isEmpty {
            resultsHeader("Droplets")
            ForEach(Array(droplets.enumerated()), id: \.element.id) { offset, droplet in
                let index = entries.count + offset
                dropletRow(droplet, highlightsQuery: true, isKeyboardSelected: selection == index)
                    .id("search-hit-\(index)")
            }
        }
        if !articles.isEmpty {
            resultsHeader("From the guide")
            ForEach(Array(articles.enumerated()), id: \.element.id) { offset, article in
                let index = entries.count + droplets.count + offset
                Button { openArticle(article) } label: {
                    HStack(spacing: 10) {
                        SidebarGlyph(symbol: article.icon)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(highlighted(article.title)).lineLimit(1)
                            Text(article.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .modifier(SidebarRowStyle(isSelected: selection == index))
                }
                .buttonStyle(.plain)
                .help("Open this in the Tama Guide")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
                .id("search-hit-\(index)")
            }
        }
    }

    private func resultsHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.leading, 10).padding(.top, 12).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func openArticle(_ article: GuideArticle) {
        UserGuideWindowController.shared.show(topic: article.id, query: query)
        DroppyAudio.playTick()
    }

    private func openDroplet(_ droplet: DropletModel) {
        navigator.page = .droplets
        navigator.openDropletID = droplet.id
    }

    private func dropletRow(_ droplet: DropletModel, highlightsQuery: Bool = false,
                            isKeyboardSelected: Bool = false) -> some View {
        Button {
            openDroplet(droplet)
        } label: {
            HStack(spacing: 10) {
                DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 22)
                Text(highlightsQuery ? highlighted(droplet.name) : AttributedString(droplet.name)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .modifier(SidebarRowStyle(isSelected: isKeyboardSelected || navigator.openDropletID == droplet.id))
        }
        .buttonStyle(.plain)
        .help(droplet.tag)
        .accessibilityAddTraits(navigator.openDropletID == droplet.id ? .isSelected : [])
    }

    private func go(_ entry: SettingsSearchEntry) {
        navigator.reveal(entry)
        DroppyAudio.playTick()
    }
}

/// The small monochrome glyph tile in front of each sidebar row.
private struct SidebarGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A sidebar row: a lighter rounded fill when selected, a faint one on hover.
private struct SidebarRowStyle: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(.primary)
            .background(isSelected ? Color.white.opacity(0.12) : (isHovered ? Color.white.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

/// Keys shown in a grey pill, for shortcuts that can't be changed.
struct KeyPill: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

// MARK: - General

struct GeneralSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var login = LaunchAtLoginService.shared
    @ObservedObject private var permissions = PermissionService.shared
    @State private var isConfirmingHideMenuBar = false

    private var grantedCount: Int {
        PermissionService.Kind.allCases.filter { permissions.status($0) == .granted }.count
    }

    /// Hiding the icon asks first, and says where Settings lives then.
    private var menuBarIcon: Binding<Bool> {
        Binding(get: { state.showInMenuBar }, set: { on in
            if on { state.showInMenuBar = true } else { isConfirmingHideMenuBar = true }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Startup") {
                SettingsGroup {
                    SettingsRow("Startup & visibility",
                                help: "Where Tama shows up: its drop in the menu bar, an icon in the Dock and Command-Tab, and whether it opens when you log in.",
                                anchor: "general.startup")
                    ToggleTiles([
                        ToggleTile("Menu bar icon", icon: "menubar.rectangle", isOn: menuBarIcon),
                        ToggleTile("Dock icon", icon: "dock.rectangle", isOn: $state.showInDock),
                        ToggleTile("Launch at login", icon: "power",
                                   isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) })),
                    ])
                    if login.needsApproval {
                        SettingsDivider()
                        SettingsRow("Allow Tama in Login Items to finish turning this on.") {
                            Button("Open Login Items") { login.openLoginItemsSettings() }
                        }
                    }
                    if let error = login.lastError {
                        SettingsNote(error, icon: "exclamationmark.triangle.fill", tint: DS.Palette.danger)
                            .padding(.top, 10)
                    }
                    if !state.showInMenuBar && !state.showInDock {
                        SettingsNote("Right-click the Notch or Island to access Settings anytime.", icon: "cursorarrow.click.2")
                            .padding(.top, 10)
                    }
                }
            }

            SettingsSection("Permissions") {
                SettingsGroup {
                    SummaryDisclosureRow("Permissions overview", subtitle: "Review and grant everything Tama can use.",
                                         done: grantedCount, total: PermissionService.Kind.allCases.count,
                                         unit: "granted", anchor: "general.permissions") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(PermissionService.Kind.allCases) { kind in
                                PermissionRow(kind: kind, status: permissions.status(kind),
                                              needsRelaunch: kind == .screenRecording && permissions.screenRecordingNeedsRelaunch)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                SettingsDivider()
                            }
                            SettingsNote("Rebuilt or updated Tama and a switch in System Settings is on but doesn't work? Use Reset, then grant it again. Resetting Music or Spotify clears Tama's Automation access for every app.")
                                .padding(.top, 10)
                        }
                    }
                }
            }

            SettingsSection("File handling") {
                SettingsGroup {
                    SettingsRow("File actions",
                                help: "Auto-remove takes a file off the Tray once it's been dragged into another app. Protect originals makes every drag out of the Tray and Basket a copy, so Finder can never move your original out of its folder.",
                                anchor: "general.fileActions")
                    ToggleTiles([
                        ToggleTile("Auto-remove", icon: "trash", isOn: $state.removeOnDragOut),
                        ToggleTile("Protect originals", icon: "lock.shield", isOn: $state.protectOriginals),
                    ])
                }
            }

            QuickActionsSettingsSection()

            AutomationSettingsSection()

            ConversionSettingsSection()

            BackgroundRemovalSettingsSection()

            HelperToolsSettingsSection()

            IntegrationsSettingsSection()

            SettingsSection("Keyboard shortcuts",
                            subtitle: "The Basket and Clipboard shortcuts are on their own pages.",
                            anchor: "general.shortcuts") {
                SettingsGroup {
                    ShortcutRecorderRow(.toggleIsland)
                    SettingsDivider()
                    ShortcutRecorderRow(.openPlayer)
                    SettingsDivider()
                    ShortcutRecorderRow(.snipToTray)
                    SettingsDivider()
                    ShortcutRecorderRow(.toggleLiveActivity)
                    if state.droplets.contains(where: { $0.id == "ring" && $0.isEnabled }) {
                        SettingsDivider()
                        ShortcutRecorderRow(.ring, title: "Ring at the pointer",
                                            help: "Hold the shortcut, point at an action and release.")
                    }
                    SettingsDivider()
                    SettingsRow("Switch shelf page (shelf focused)") { KeyPill("⌘1 – ⌘4") }
                    SettingsDivider()
                    SettingsRow("Collapse the island") { KeyPill("Esc") }
                    SettingsDivider()
                    SettingsRow("Every shortcut, including per-widget ones") {
                        Button("Show All") { SettingsNavigator.shared.open(.shortcuts) }
                            .help("Open Settings › Keyboard Shortcuts")
                    }
                }
            }

            SettingsSection("Gestures", anchor: "general.gestures") {
                SettingsGroup {
                    SettingsRow("Expand the island") { KeyPill("Click the notch") }
                    SettingsDivider()
                    SettingsRow("Play / pause") { KeyPill("Double-click the notch") }
                    SettingsDivider()
                    SettingsRow("Volume", subtitle: "Or open the shelf instead: Shelf › Behavior › Scroll on the notch.") {
                        KeyPill("Two-finger scroll on the notch")
                    }
                    SettingsDivider()
                    SettingsRow("Switch shelf pages", subtitle: "Shelf › Behavior › Gestures.") { KeyPill("Two-finger swipe sideways") }
                    SettingsDivider()
                    SettingsRow("Select all files in the Tray") { KeyPill("⌘A") }
                }
            }
        }
        .onAppear {
            login.refresh()
            permissions.refresh()
        }
        .confirmationDialog("Hide menu bar icon?", isPresented: $isConfirmingHideMenuBar) {
            Button("Hide Icon") { state.showInMenuBar = false }
        } message: {
            Text("Right-click the Notch or Island to access Settings anytime.")
        }
    }
}

// MARK: - Shelf
// ShelfSettingsPage lives in ShelfSettingsPage.swift.

// MARK: - Basket

// BasketSettingsPage lives in FilesSettingsSections.swift.

// MARK: - Clipboard
// The Clipboard page is in ClipboardSettingsPage.swift.

// MARK: - Lock screen
// The Lock screen page is in LockScreenSettingsPage.swift.


// MARK: - HUDs
// The HUDs page is in HUDsSettingsPage.swift.

/// Notch vs Island on the desktop wallpaper.
struct DisplayStyleThumbnail: View {
    let style: IslandStyle

    var body: some View {
        VStack(spacing: 0) {
            if style == .notchAttached {
                NotchWithEarsShape(cornerRadius: 8, earRadius: 5)
                    .fill(Color.black)
                    .frame(width: 110, height: 20)
                    .overlay(miniContent.padding(.horizontal, 14))
            } else {
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .frame(width: 104, height: 22)
                    .overlay(miniContent.padding(.horizontal, 10))
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var miniContent: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.5)).frame(width: 9, height: 9)
            Spacer(minLength: 0)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 2, height: CGFloat(4 + i * 2))
            }
        }
    }
}

// MARK: - Theming

struct ThemingSettingsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state = AppState.shared
    @AppStorage(DroppyAccentColor.customHexKey) private var accentHex = ""
    @State private var isPreviewHovered = false
    /// Light the preview's glow while the slider is dragged, so the change is visible.
    @State private var isAdjustingGlow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Notched display",
                            help: "How the notch and the shelf are painted on a Mac with a notch. Dynamic Glass keeps the part under the notch black and turns glassy towards the bottom edge.",
                            anchor: "theming.notched") {
                SettingsGroup {
                    PreviewCardPicker(IslandSurfaceStyle.notchedChoices.map {
                        PreviewCardOption($0, $0.title, subtitle: $0.subtitle(notched: true))
                    }, selection: $state.notchedSurfaceStyle) { style in
                        SurfaceThumbnail(surface: style, notched: true)
                    }
                }
            }

            SettingsSection("Notchless display",
                            help: "How the floating island and its shelf are painted on displays without a notch.",
                            anchor: "theming.notchless") {
                SettingsGroup {
                    PreviewCardPicker(IslandSurfaceStyle.notchlessChoices.map {
                        PreviewCardOption($0, $0.title, subtitle: $0.subtitle(notched: false))
                    }, selection: $state.notchlessSurfaceStyle) { style in
                        SurfaceThumbnail(surface: style, notched: false)
                    }
                }
            }

            SettingsSection("Outline") {
                SettingsGroup {
                    SettingsToggleRow("Subtle outline",
                                      help: "A hairline around the open island and shelf, so a black surface stays visible against dark wallpapers.",
                                      anchor: "theming.outline", isOn: $state.subtleOutline)
                    SettingsDivider()
                    SettingsToggleRow("Show in resting state",
                                      subtitle: state.subtleOutline ? nil : "Needs Subtle outline.",
                                      help: "Draw the outline around the resting notch or island too.",
                                      isOn: $state.outlineInRestingState)
                        .settingsDisabled(!state.subtleOutline)
                }
            }

            SettingsSection("Glow & corners") {
                SettingsGroup {
                    SettingsSlider("Border glow", value: $state.borderGlowIntensity, in: 0...1.5, step: 0.05,
                                   defaultValue: 0.8,
                                   help: "While the pointer is on the island: the floating pill gets a highlight-colored border and glow; on a notch, the open shelf casts a halo. 0 % turns it off.",
                                   anchor: "theming.glow") { "\(Int($0 * 100))%" }
                        .onHover { isAdjustingGlow = $0 }
                    SettingsDivider()
                    SettingsSlider("Notch corner fillet", value: $state.notchEarFilletRadius, in: 0...24, step: 1,
                                   defaultValue: 12,
                                   help: "Rounds the corners where the open shelf meets the top of the screen. The resting notch keeps the hardware's own curve.",
                                   anchor: "theming.fillet") { "\(Int($0)) pt" }
                    SettingsDivider()
                    AppearancePreview(isGlowing: isPreviewHovered || isAdjustingGlow)
                        .onHover { isPreviewHovered = $0 }
                        .accessibilityHidden(true)
                        .padding(12)
                }
            }

            SettingsSection("Settings window") {
                SettingsGroup {
                    SettingsToggleRow("Solid background",
                                      help: "Paint this window in one opaque color instead of translucent glass, so a bright desktop behind it doesn't wash the text out.",
                                      anchor: "theming.solidSettings", isOn: $state.solidSettingsBackground)
                }
            }

            SettingsSection("Media HUD position", subtitle: "Fine-tune the vertical position.") {
                SettingsGroup {
                    ZStack(alignment: .top) {
                        PreviewWallpaper()
                        IslandSurfaceFill(surface: state.notchlessSurfaceStyle, tint: state.windowTintColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            .overlay(
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3).fill(state.accentColor.color).frame(width: 14, height: 14)
                                    Capsule().fill(Color.white.opacity(0.7)).frame(width: 50, height: 4)
                                    Spacer(minLength: 0)
                                    Image(systemName: "waveform").font(.system(size: 9)).foregroundStyle(.white)
                                }
                                .padding(.horizontal, 8)
                            )
                            .frame(width: 130, height: 26)
                            .offset(y: 6 + max(-6, state.mediaHUDVerticalOffset) * 0.6)
                    }
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(12)
                    .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: state.mediaHUDVerticalOffset)
                    .accessibilityHidden(true)
                    SettingsDivider()
                    SettingsSlider("Vertical position", value: $state.mediaHUDVerticalOffset, in: -8...40, step: 1,
                                   defaultValue: 0,
                                   help: "Moves the floating island (with its media HUD) down from the top of a display without a notch.",
                                   anchor: "theming.mediaHUD") { String(format: "%+.0f pt", $0) }
                }
            }

            SettingsSection("General",
                            subtitle: "Scrub each tape to pick a color. Default keeps Tama's automatic color; the last swatch is a custom hex.") {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        TapeColorPicker("Highlight color",
                                        help: "Tints controls, highlights and icons in the shelf, the basket and Settings.",
                                        anchor: "theming.highlight", swatches: accentSwatches,
                                        selection: accentSelection, customHex: $accentHex)
                        TapeColorPicker("Window tint",
                                        help: "A subtle wash over Settings and the glass surfaces of the island.",
                                        anchor: "theming.windowTint", swatches: Self.paletteSwatches,
                                        selection: tapeSelection($state.windowTint),
                                        customHex: customHex($state.windowTint))
                    }
                    GridRow {
                        TapeColorPicker("Volume slider color",
                                        help: "The volume HUD's meter. Default follows the highlight color; White and Decibel are the HUD's own styles.",
                                        anchor: "theming.volumeColor", swatches: Self.meterSwatches,
                                        selection: meterSelection($state.hudMeterStyle, $state.hudMeterCustomColor),
                                        customHex: customHex($state.hudMeterCustomColor))
                        TapeColorPicker("Brightness slider color",
                                        help: "The brightness HUD's meter. Default follows the highlight color; White and Decibel are the HUD's own styles.",
                                        anchor: "theming.brightnessColor", swatches: Self.meterSwatches,
                                        selection: meterSelection($state.brightnessHUDMeterStyle, $state.brightnessHUDMeterCustomColor),
                                        customHex: customHex($state.brightnessHUDMeterCustomColor))
                    }
                }
            }
        }
    }

    // MARK: Tapes

    private var accentSwatches: [TapeSwatch] {
        [TapeSwatch(id: "default", name: "Default", color: DroppyAccentColor.electricBlue.color)]
            + DroppyAccentColor.allCases.filter { $0 != .electricBlue && $0 != .custom }
                .map { TapeSwatch(id: $0.rawValue, name: $0.rawValue, color: $0.color) }
            + [TapeSwatch(id: "custom", name: "Custom", color: nil)]
    }

    private var accentSelection: Binding<String> {
        Binding(
            get: {
                switch state.accentColor {
                case .electricBlue: "default"
                case .custom: "custom"
                default: state.accentColor.rawValue
                }
            },
            set: { id in
                switch id {
                case "default": state.accentColor = .electricBlue
                case "custom":
                    if accentHex.isEmpty { accentHex = state.accentColor.color.hexString }
                    state.accentColor = .custom
                default: state.accentColor = DroppyAccentColor(rawValue: id) ?? .electricBlue
                }
            }
        )
    }

    static let paletteSwatches: [TapeSwatch] =
        [TapeSwatch(id: "default", name: "Default", color: Color(white: 0.45))]
        + TapePalette.swatches.map { TapeSwatch(id: $0.id, name: $0.name, color: Color(hex: $0.hex)) }
        + [TapeSwatch(id: "custom", name: "Custom", color: nil)]

    static let meterSwatches: [TapeSwatch] =
        [TapeSwatch(id: "default", name: "Default", color: Color(white: 0.45)),
         TapeSwatch(id: "white", name: "White", color: .white),
         TapeSwatch(id: "decibel", name: "Decibel", color: Color(hue: 0.3, saturation: 0.7, brightness: 1))]
        + TapePalette.swatches.map { TapeSwatch(id: $0.id, name: $0.name, color: Color(hex: $0.hex)) }
        + [TapeSwatch(id: "custom", name: "Custom", color: nil)]

    /// A tape stored in one string: "" (default), a palette id, or "#RRGGBB".
    private func tapeSelection(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: {
                if value.wrappedValue.isEmpty { return "default" }
                return value.wrappedValue.hasPrefix("#") ? "custom" : value.wrappedValue
            },
            set: { id in
                switch id {
                case "default": value.wrappedValue = ""
                case "custom":
                    let current = TapePalette.color(for: value.wrappedValue) ?? state.accentColor.color
                    value.wrappedValue = current.hexString
                default: value.wrappedValue = id
                }
            }
        )
    }

    /// The custom hex of a one-string tape (empty unless it holds a hex).
    private func customHex(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.hasPrefix("#") ? value.wrappedValue : "" },
            set: { value.wrappedValue = $0 }
        )
    }

    /// Meter tapes map onto the HUD's meter styles: Default is Accent,
    /// White and Decibel are themselves, and a colour is Custom + that colour.
    private func meterSelection(_ style: Binding<HUDMeterStyle>, _ color: Binding<String>) -> Binding<String> {
        Binding(
            get: {
                switch style.wrappedValue {
                case .accent: "default"
                case .white: "white"
                case .decibel: "decibel"
                case .custom: color.wrappedValue.hasPrefix("#") || color.wrappedValue.isEmpty ? "custom" : color.wrappedValue
                }
            },
            set: { id in
                switch id {
                case "default": style.wrappedValue = .accent
                case "white": style.wrappedValue = .white
                case "decibel": style.wrappedValue = .decibel
                case "custom":
                    let current = TapePalette.color(for: color.wrappedValue) ?? state.accentColor.color
                    color.wrappedValue = current.hexString
                    style.wrappedValue = .custom
                default:
                    color.wrappedValue = id
                    style.wrappedValue = .custom
                }
            }
        )
    }
}

/// A brightness HUD drawn with one surface style, for the Theming cards.
private struct SurfaceThumbnail: View {
    let surface: IslandSurfaceStyle
    let notched: Bool
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if notched {
                    IslandSurfaceFill(surface: surface, solidTop: 14, tint: state.windowTintColor)
                        .clipShape(NotchWithEarsShape(cornerRadius: 12, earRadius: 6))
                } else {
                    IslandSurfaceFill(surface: surface, tint: state.windowTintColor)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(surface == .black ? 0.1 : 0.22), lineWidth: 1))
                }
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").font(.system(size: 11)).foregroundStyle(.white)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.yellow).frame(width: 60)
                    }
                    .frame(width: 96, height: 4)
                }
                .padding(.top, notched ? 12 : 0)
            }
            .frame(width: notched ? 170 : 160, height: notched ? 44 : 30)
            .padding(.top, notched ? 0 : 14)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Accessibility

struct AccessibilitySettingsPage: View {
    @ObservedObject var state = AppState.shared

    private var surfaceName: String {
        state.islandStyle == .notchAttached && state.notchHeight > 0 ? "Notch" : "Island"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Interaction") {
                SettingsGroup {
                    SettingsToggleRow("Right-click to hide",
                                      help: "Adds \u{201C}Hide \(surfaceName)\u{201D} to the right-click menu of the notch or island. Hidden, it stays out of sight until you bring it back; level HUDs, banners and the open shelf still show.",
                                      anchor: "a11y.rightClickHide", isOn: $state.rightClickToHide)
                    SettingsDivider()
                    SettingsToggleRow("Right-click to reveal",
                                      help: "While hidden, right-click where the notch or island sits (the top centre of the screen) to show it again.",
                                      anchor: "a11y.rightClickReveal", isOn: $state.rightClickToReveal)
                    SettingsDivider()
                    SettingsToggleRow("Hold to reveal",
                                      help: "Keep the resting notch or island hidden until you hold a modifier combo, and show it only while the keys are down.",
                                      anchor: "a11y.holdReveal", isOn: $state.holdToReveal)
                    if state.holdToReveal {
                        ChoiceTiles(ShortcutModifier.allCases.map { .init($0, $0.symbol) },
                                    selection: $state.holdToRevealModifier)
                    }
                    SettingsDivider()
                    SettingsToggleRow("Haptic feedback",
                                      help: "Subtle tactile feedback on a Force Touch trackpad when you drop files or trigger actions.",
                                      anchor: "a11y.haptics", isOn: $state.hapticFeedback)
                    SettingsDivider()
                    SettingsToggleRow("Sound effects",
                                      help: "Soft system sounds for taps, drops, copies and snips.",
                                      anchor: "a11y.sounds", isOn: $state.soundEffects)
                    SettingsDivider()
                    SettingsToggleRow("Show tooltips",
                                      help: "Hover help on Tama's buttons and settings. The ⓘ buttons still explain on click when this is off. Windows already open may keep their tooltips until Tama restarts.",
                                      anchor: "a11y.tooltips", isOn: $state.showTooltips)
                    if state.isIslandHidden {
                        SettingsDivider()
                        SettingsRow("The \(surfaceName.lowercased()) is hidden") {
                            Button("Show \(surfaceName)") { IslandVisibilityService.shared.reveal() }
                        }
                    }
                }
            }

            SettingsSection("Screen capture") {
                SettingsGroup {
                    SettingsToggleRow("Hide from screenshots",
                                      help: "Leaves the notch, island, shelf, Basket, clipboard and Live Activity HUD out of screenshots and screen sharing. macOS's own screenshot tools honour this; some screen-recording apps may still capture them.",
                                      anchor: "a11y.screenshots", isOn: $state.hideFromScreenshots)
                }
            }
        }
    }
}

// MARK: - About

struct AboutSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @State private var isShowingChangelog = false
    @State private var isChoosingTransfer = false
    @State private var isConfirmingClearLogs = false
    @AppStorage(CrashReportService.promptKey) private var crashPrompt = true
    /// Looked up once, when the page appears: reading the folder on every
    /// redraw would hit the disk for a row that hardly ever changes.
    @State private var lastCrash: CrashReport?

    private var hasCrashReport: Bool { lastCrash != nil }

    private var crashSubtitle: String {
        guard let lastCrash else { return "None in the last week." }
        return "\(lastCrash.headline) · \(lastCrash.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String? {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, build != version else { return nil }
        return build
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [state.accentColor.color.opacity(0.9), state.accentColor.color.opacity(0.45)],
                                             center: .top, startRadius: 4, endRadius: 60))
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 6))
                        .frame(width: 88, height: 88)
                    Image(systemName: "drop.fill").font(.system(size: 38)).foregroundStyle(.white)
                }
                .accessibilityHidden(true)
                .shadow(color: state.accentColor.color.opacity(0.55), radius: 26)
                Text("Tama \(version)").font(.system(size: 20, weight: .bold))
                Text(build.map { "Build \($0)" } ?? "Supercharged Dynamic Island for macOS")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .settingsAnchor("about.version")

            SettingsSection("About") {
                HStack(spacing: 12) {
                    SettingsCardButton(icon: "doc.text.fill", title: "Changelog", subtitle: "Read the full history",
                                       anchor: "about.changelog") { isShowingChangelog = true }
                    SettingsCardButton(icon: "person.crop.circle.fill", title: "Developer",
                                       subtitle: "Native Swift & SwiftUI",
                                       help: "Tama for Mac is written in Swift with SwiftUI and AppKit, with no third-party code.")
                    SettingsCardButton(icon: "book.fill", title: "Introduction", subtitle: "Replay the welcome tour",
                                       anchor: "about.intro") { OnboardingWindowController.shared.show() }
                }
                HStack(spacing: 12) {
                    SettingsCardButton(icon: "sparkles", title: "What's New", subtitle: "New features, fixes and polish",
                                       anchor: "about.whatsNew") { WhatsNewController.shared.show(.whatsNew) }
                    SettingsCardButton(icon: "checklist", title: "Setup Guide", subtitle: "Recommended setup",
                                       anchor: "about.setupGuide") { WhatsNewController.shared.show(.setup) }
                    SettingsCardButton(icon: "text.book.closed.fill", title: "Tama Guide",
                                       subtitle: "How every part of Tama works",
                                       anchor: "about.userGuide") { UserGuideWindowController.shared.show() }
                }
            }

            SettingsSection("Privacy") {
                HStack(spacing: 12) {
                    SettingsCardButton(icon: "hand.raised.fill", title: "Tracking", subtitle: "Off",
                                       help: "Tama has no analytics, telemetry or crash reporting. Nothing about how you use it leaves your Mac.",
                                       anchor: "about.privacy")
                    SettingsCardButton(icon: "internaldrive.fill", title: "On-device data", subtitle: "Stays on your Mac",
                                       help: "Clipboard history, Tray files, notes and settings are stored in ~/Library/Application Support/Tama and Tama's preferences. Text recognition and transcription run on your Mac.")
                    SettingsCardButton(icon: "globe", title: "Online features", subtitle: "Opt-in",
                                       help: "Weather (Open-Meteo, with a location rounded to about a kilometre) and online lyrics (LRCLIB) only run once you turn them on. Artwork for a playing YouTube tab is loaded from YouTube. Share links stay on your local network.")
                }
            }

            SettingsSection("Troubleshooting") {
                HStack(spacing: 12) {
                    SettingsCardButton(icon: "arrow.counterclockwise", title: "Hard reset", subtitle: "Reset all settings to defaults",
                                       anchor: "about.hardReset") { HardResetFlow.run() }
                    SettingsCardButton(icon: "arrow.left.arrow.right", title: "Transfer settings",
                                       subtitle: "Export or import your settings",
                                       anchor: "about.transfer") { isChoosingTransfer = true }
                }
                SettingsGroup {
                    SettingsToggleRow("Diagnostic logging", subtitle: "Write detailed logs for troubleshooting",
                                      help: "Keeps a log of what Tama's services do in ~/Library/Logs/Tama (at most about 4 MB). Nothing is sent anywhere; Export logs saves a report you can share yourself. Clipboard contents and PINs are never logged.",
                                      anchor: "about.logging", isOn: $state.diagnosticLogging)
                    SettingsDivider()
                    SettingsToggleRow("Tell me after a crash", subtitle: "Show the report macOS wrote, to copy",
                                      help: "Tama has no crash reporting of its own and sends nothing. After a crash it reads the report macOS already wrote to ~/Library/Logs/DiagnosticReports, takes your account name, home folder and this Mac's identifiers out of it, and offers to put it on the clipboard.",
                                      anchor: "about.crashReport", isOn: $crashPrompt)
                    SettingsDivider()
                    SettingsRow("Last crash report", subtitle: crashSubtitle, anchor: "about.lastCrash") {
                        Button("Show…") { CrashReportWindowController.shared.show() }
                            .disabled(!hasCrashReport)
                    }
                    SettingsDivider()
                    SettingsRow("Logs", subtitle: "A report with version, macOS, settings and the log file.", anchor: "about.exportLogs") {
                        HStack(spacing: 8) {
                            Button("Show in Finder") {
                                try? FileManager.default.createDirectory(at: DroppyLog.folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(DroppyLog.folder)
                            }
                            Button("Clear…") { isConfirmingClearLogs = true }
                            Button("Export Logs…") { DroppyLog.export() }
                        }
                    }
                }
            }
        }
        .onAppear { lastCrash = CrashReportService.shared.latestReport() }
        .sheet(isPresented: $isShowingChangelog) { ChangelogSheet() }
        .confirmationDialog("Clear the diagnostic log?", isPresented: $isConfirmingClearLogs) {
            Button("Clear Log", role: .destructive) { DroppyLog.clear() }
        } message: {
            Text("Everything Tama has logged so far is deleted. Export the logs first if you still need them for a report.")
        }
        .confirmationDialog("Transfer settings", isPresented: $isChoosingTransfer) {
            Button("Export Settings…") { state.exportSettings() }
            Button("Import Settings…") { state.importSettings() }
        } message: {
            Text("A JSON file with every preference, including shortcuts — handy for a new Mac. Clips and files aren't included.")
        }
    }
}

/// CHANGELOG.md, bundled into Tama.app by build_app.sh. Headings, bullets
/// and inline Markdown are rendered; that's all the file uses.
private struct ChangelogSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var lines: [String] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return ["The changelog is bundled with Tama.app (build_app.sh copies CHANGELOG.md into it). This copy was run outside the app bundle."]
        }
        return raw.components(separatedBy: .newlines)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changelog").font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("# ") {
                            EmptyView()
                        } else if line.hasPrefix("## ") {
                            Text(inline(String(line.dropFirst(3)))).font(.system(size: 15, weight: .bold)).padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                        } else if line.hasPrefix("- ") || line.hasPrefix("  - ") {
                            let indent = line.hasPrefix("  ")
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").accessibilityHidden(true)
                                Text(inline(line.trimmingCharacters(in: .whitespaces).dropFirst(2).description))
                            }
                            .padding(.leading, indent ? 16 : 0)
                        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(inline(line))
                        }
                    }
                }
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

/// About › Hard reset: settings only, or everything (optionally keeping the
/// clipboard history) followed by a relaunch.
@MainActor
enum HardResetFlow {
    static func run() {
        let alert = NSAlert()
        alert.messageText = "Hard reset Tama?"
        alert.informativeText = "Reset Settings puts every preference back to how Tama shipped. Reset Everything also clears the Tray, notes, pinboards and Droplet switches, shows the welcome tour again and restarts Tama — keep your clipboard history or clear it too."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Everything")
        alert.addButton(withTitle: "Reset Settings")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let keep = NSButton(checkboxWithTitle: "Keep clipboard history", target: nil, action: nil)
        keep.state = .on
        alert.accessoryView = keep
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            AppState.shared.hardReset(keepClipboard: keep.state == .on)
        case .alertSecondButtonReturn:
            AppState.shared.resetSettingsToDefaults()
        default:
            break
        }
    }
}

// MARK: - Permissions

struct PermissionRow: View {
    let kind: PermissionService.Kind
    let status: PermissionService.Status
    /// Screen Recording was just requested; the grant applies after a relaunch.
    var needsRelaunch = false
    @State private var isConfirmingReset = false

    /// Both automation rows share the AppleEvents TCC service, so a reset
    /// reaches every app Tama controls.
    private var resetsAllAutomation: Bool { kind.tccService == "AppleEvents" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.iconName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badge
            switch status {
            case .granted:
                if kind != .notifications {
                    resetButton(help: "Clear this grant so macOS asks again")
                }
            case .denied where needsRelaunch:
                Button("Relaunch") { PermissionService.shared.relaunch() }
                    .buttonStyle(.borderedProminent)
                Button("Open Settings") { PermissionService.shared.openSettings(kind) }
            case .denied, .notDetermined:
                Button(status == .notDetermined ? "Allow" : "Open Settings") { PermissionService.shared.request(kind) }
                    .buttonStyle(.borderedProminent)
                if kind.tccService != nil {
                    resetButton(help: "Clear a stale grant left by an older build")
                }
            case .unavailable:
                // Automation can only be asked about while the target app runs.
                if let appName = kind.automationAppName, PermissionService.shared.canLaunchAutomationTarget(kind) {
                    Button("Open \(appName)") { PermissionService.shared.launchAutomationTarget(kind) }
                        .help("Open \(appName) in the background so Tama can ask to control it")
                }
            case .checking:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog("Reset Automation access?", isPresented: $isConfirmingReset) {
            Button("Reset Automation", role: .destructive) { PermissionService.shared.reset(kind) }
        } message: {
            Text("macOS keeps one Automation permission for Tama, so this clears its access to Music, Spotify and browsers alike. Each app asks again the next time Tama controls it.")
        }
    }

    private func resetButton(help: String) -> some View {
        Button("Reset") {
            if resetsAllAutomation {
                isConfirmingReset = true
            } else {
                PermissionService.shared.reset(kind)
            }
        }
        .help(resetsAllAutomation ? "Clear Tama's Automation access for every app, so macOS asks again" : help)
    }

    private var badge: some View {
        let (text, color): (String, Color) = switch status {
        case .granted: ("Allowed", .green)
        // macOS doesn't say whether the prompt was answered Allow or Deny, so
        // the relaunch is conditional.
        case .denied where needsRelaunch: ("Relaunch after allowing", .orange)
        case .denied: ("Not allowed", .red)
        case .notDetermined: ("Not asked", .orange)
        case .unavailable: ("Open the app first", .secondary)
        case .checking: ("Checking…", .secondary)
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Appearance preview

/// A miniature desktop with the resting island on it, drawn with the same glass,
/// shape, accent and glow settings as the real one.
private struct AppearancePreview: View {
    @ObservedObject var state = AppState.shared
    var isGlowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isNotch: Bool { state.islandStyle == .notchAttached }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [state.accentColor.color.opacity(0.55), Color(white: 0.12), Color(white: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            island
                .padding(.top, isNotch ? 0 : 10)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(DS.Motion.respecting(reduceMotion, .spring(response: 0.35, dampingFraction: 0.8)), value: state.islandStyle)
        .animation(DS.Motion.respecting(reduceMotion, .easeOut(duration: 0.2)), value: isGlowing)
    }

    private var island: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(state.accentColor.color)
                .frame(width: 9, height: 9)
            Text("Tama")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Equalizer(color: state.accentColor.color)
        }
        .padding(.horizontal, isNotch ? 14 + state.notchEarFilletRadius : 16)
        .frame(width: 240 + (isNotch ? state.notchEarFilletRadius * 2 : 0), height: isNotch ? 34 : 38)
        .liquidGlass(
            cornerRadius: isNotch ? 12 : 19,
            showBorder: !isNotch,
            isHovered: isGlowing,
            isNotchAttached: isNotch,
            earRadius: isNotch ? state.notchEarFilletRadius : 0
        )
    }
}

/// Now-playing bars, animated so the preview reads as a live island.
private struct Equalizer: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: reduceMotion ? 10 : 4 + 8 * abs(sin(t * (3 + Double(i)) + Double(i))))
                }
            }
            .frame(height: 12)
        }
    }
}
