import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

// Thunderstorm's floating launcher: a Spotlight-style black glass bar
// ("Search your Mac") summoned by a shortcut, separate from the widget
// console. Results come in sections — apps, Tama commands and settings,
// droplets, System Settings panes, system commands, weather, files and web
// searches — with a blue selected row and a ↵ hint.

// MARK: - Items

struct LauncherItem: Identifiable {
    enum Icon {
        case file(URL)
        case symbol(String, Color)
        case droplet(DropletModel)
    }

    enum Accessory {
        case hint(String)
        case droplet(isEnabled: Bool)
        case none
    }

    /// What a finished action leaves on screen.
    enum Outcome {
        case close
        case stay(String?)
    }

    let id: String
    let title: String
    var subtitle: String = ""
    let icon: Icon
    var accessory: Accessory = .hint("↩")
    /// Shown instead of the subtitle after the first Return; the second one runs it.
    var confirmation: String?
    /// Files and apps: reveal, Quick Look, Tray, copy path and Move to Trash work on it.
    var url: URL?
    var isApp = false
    let action: @MainActor () async -> Outcome
}

struct LauncherSection: Identifiable {
    let title: String
    let items: [LauncherItem]
    var id: String { title }
}

// MARK: - Model

@MainActor
final class ThunderstormLauncherModel: ObservableObject {
    enum Mode { case search, droplets }

    enum Answer: Equatable {
        case none
        case loading(String)
        case found(InstantAnswer)
        case empty(String)
    }

    @Published var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    @Published private(set) var mode: Mode = .search
    @Published private(set) var sections: [LauncherSection] = []
    @Published var selectedID: String?
    /// The item waiting for a second Return, and whether that Return moves it to the Trash.
    @Published private(set) var pendingID: String?
    @Published private(set) var pendingIsTrash = false
    @Published private(set) var status: String?
    @Published private(set) var answer: Answer = .none
    /// Arrow keys moved the selection, so the list should scroll to it.
    @Published var isNavigating = false
    /// Bumped each time the launcher opens, so the field takes focus again.
    @Published private(set) var focusToken = 0

    let files = SpotlightSearchService()
    private var cancellables = Set<AnyCancellable>()
    private var answerTask: Task<Void, Never>?
    private var statusWork: DispatchWorkItem?
    private var watchesWeather = false

    var items: [LauncherItem] { sections.flatMap(\.items) }
    var selected: LauncherItem? { items.first { $0.id == selectedID } ?? items.first }
    var isSearchingFiles: Bool { files.isSearching }

    init() {
        // After the publish, so `files.sections` holds the new results.
        files.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        WeatherService.shared.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in if self?.watchesWeather == true { self?.rebuild() } }
            .store(in: &cancellables)
        AppState.shared.$droplets
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    func opened() {
        focusToken &+= 1
        if !query.isEmpty { files.search(query) }
    }

    func closed() {
        files.stop()
        answerTask?.cancel()
        stopWeather()
        pendingID = nil
    }

    func reset() {
        mode = .search
        query = ""
        status = nil
        answer = .none
        sections = []
    }

    func showDroplets() {
        mode = .droplets
        query = ""
        rebuild()
    }

    func back() {
        mode = .search
        query = ""
        rebuild()
    }

    private func queryChanged() {
        pendingID = nil
        isNavigating = false
        if mode == .search { files.search(query) }
        scheduleAnswer()
        rebuild()
    }

    // MARK: Sections

    func rebuild() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var result: [LauncherSection] = []
        if mode == .droplets {
            result = [LauncherSection(title: "Droplets", items: dropletItems(trimmed, all: true))]
        } else if !trimmed.isEmpty {
            if let math = mathItem(trimmed) { result.append(LauncherSection(title: "Calculator", items: [math])) }
            if let answer = answerItem(trimmed) { result.append(LauncherSection(title: "Web Result", items: [answer])) }
            let fileResults = files.results
            let apps = fileResults.filter { $0.group == .applications }.prefix(5).map(fileItem)
            if !apps.isEmpty { result.append(LauncherSection(title: "Applications", items: Array(apps))) }
            let droppy = commandItems(trimmed) + dropletItems(trimmed, all: false) + settingsItems(trimmed)
            if !droppy.isEmpty { result.append(LauncherSection(title: "Tama", items: Array(droppy.prefix(8)))) }
            let panes = paneItems(trimmed)
            if !panes.isEmpty { result.append(LauncherSection(title: "System Settings", items: panes)) }
            if ThunderstormSettings.shared.systemCommands {
                let commands = systemCommandItems(trimmed)
                if !commands.isEmpty { result.append(LauncherSection(title: "Commands", items: commands)) }
            }
            if let weather = weatherItem(trimmed) { result.append(LauncherSection(title: "Weather", items: [weather])) }
            let others = fileResults.filter { $0.group != .applications }.prefix(24).map(fileItem)
            if !others.isEmpty { result.append(LauncherSection(title: "Files", items: Array(others))) }
            if ThunderstormSettings.shared.webSearch {
                result.append(LauncherSection(title: "Search the Web", items: webItems(trimmed)))
            }
        }
        sections = result
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
    }

    private func fileItem(_ hit: SearchResult) -> LauncherItem {
        let isApp = hit.group == .applications
        return LauncherItem(
            id: "file:" + hit.url.path,
            title: isApp ? (hit.name as NSString).deletingPathExtension : hit.name,
            subtitle: hit.parentPath,
            icon: .file(hit.url),
            url: hit.url,
            isApp: isApp
        ) {
            NSWorkspace.shared.open(hit.url)
            return .close
        }
    }

    private func mathItem(_ text: String) -> LauncherItem? {
        // Only something that looks like arithmetic: a digit and an operator.
        guard text.rangeOfCharacter(from: .decimalDigits) != nil,
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷()")) != nil,
              let value = MathEvaluator.evaluate(text) else { return nil }
        let formatted = MathEvaluator.format(value)
        return LauncherItem(id: "math", title: "= \(formatted)", subtitle: "Press Return to copy",
                            icon: .symbol("function", .green)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formatted, forType: .string)
            DroppyAudio.playCopySuccess()
            return .stay("Copied \(formatted)")
        }
    }

    private func answerItem(_ text: String) -> LauncherItem? {
        switch answer {
        case .loading(let q) where q == text:
            return LauncherItem(id: "answer", title: "Looking up an inline answer…", subtitle: "DuckDuckGo",
                                icon: .symbol("sparkle.magnifyingglass", .orange), accessory: .none) { .stay(nil) }
        case .found(let found):
            return LauncherItem(id: "answer", title: found.heading.isEmpty ? found.text : found.heading,
                                subtitle: found.heading.isEmpty ? found.source : "\(found.text) · \(found.source)",
                                icon: .symbol("text.magnifyingglass", .orange)) {
                if let url = found.url {
                    NSWorkspace.shared.open(url)
                    return .close
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(found.text, forType: .string)
                return .stay("Copied the answer")
            }
        case .empty(let q) where q == text:
            return LauncherItem(id: "answer", title: "No inline answer for \u{201C}\(q)\u{201D}", subtitle: "Try a web search below",
                                icon: .symbol("questionmark.circle", .gray), accessory: .none) { .stay(nil) }
        default:
            return nil
        }
    }

    private func commandItems(_ text: String) -> [LauncherItem] {
        let shortcuts = GlobalShortcutService.shared
        func sub(_ base: String, _ action: ShortcutAction?) -> String {
            guard let action, let keys = shortcuts.display(for: action) else { return base }
            return "\(base) · \(keys)"
        }
        let isOn = { (id: String) in AppState.shared.droplets.contains { $0.id == id && $0.isEnabled } }
        var candidates: [(LauncherItem, [String])] = []
        if isOn("voiceTranscribe") {
            candidates.append((LauncherItem(id: "cmd.quickRecord", title: "Quick Record",
                                            subtitle: sub("Voice Transcribe", .quickRecord),
                                            icon: .symbol("waveform.badge.mic", .red)) {
                VoiceTranscribeService.shared.quickRecord()
                return .close
            }, ["record", "voice", "transcribe", "dictate", "memo", "microphone"]))
        }
        candidates.append((LauncherItem(id: "cmd.clipboard", title: "Open Clipboard",
                                        subtitle: sub("Clipboard history", .toggleClipboard),
                                        icon: .symbol("doc.on.clipboard", .blue)) {
            AppState.shared.showClipboard()
            return .close
        }, ["clipboard", "history", "paste", "copied"]))
        candidates.append((LauncherItem(id: "cmd.shelf", title: "Open the Shelf",
                                        subtitle: sub("The notch", .toggleIsland),
                                        icon: .symbol("rectangle.topthird.inset.filled", .blue)) {
            AppState.shared.toggleIsland()
            return .close
        }, ["notch", "island", "shelf", "tray"]))
        candidates.append((LauncherItem(id: "cmd.basket", title: "Toggle Floating Basket",
                                        subtitle: sub("Basket", .toggleBasket),
                                        icon: .symbol("basket", .orange)) {
            AppState.shared.isBasketVisible.toggle()
            return .close
        }, ["basket", "files", "gather"]))
        if isOn("snipper") {
            for mode in CaptureMode.allCases {
                candidates.append((LauncherItem(id: "cmd.capture.\(mode.rawValue)", title: mode.shortcutAction.title,
                                                subtitle: sub("Element Capture", mode.shortcutAction),
                                                icon: .symbol("camera.viewfinder", .pink)) {
                    // Wait for the launcher to leave the screen first.
                    try? await Task.sleep(for: .milliseconds(250))
                    ScreenCaptureService.shared.capture(mode)
                    return .close
                }, ["screenshot", "capture", "snip", "screen"]))
            }
        }
        if isOn("menuBar") {
            candidates.append((LauncherItem(id: "cmd.menuBar", title: "Show or Hide Menu Bar Items",
                                            subtitle: sub("Menu Bar Manager", .menuBarToggle),
                                            icon: .symbol("menubar.rectangle", .gray)) {
                MenuBarManagerService.shared.toggle()
                return .close
            }, ["menu bar", "hidden", "icons", "reveal", "thaw"]))
        }
        candidates.append((LauncherItem(id: "cmd.settings", title: "Tama Settings", subtitle: "Open Settings",
                                        icon: .symbol("gearshape", .gray)) {
            SettingsWindowController.shared.showWindow()
            return .close
        }, ["preferences", "settings", "tama", "options"]))
        candidates.append((LauncherItem(id: "cmd.shortcuts", title: "Keyboard Shortcuts", subtitle: "Tama Settings",
                                        icon: .symbol("command", .gray)) {
            SettingsWindowController.shared.showWindow(page: .shortcuts)
            return .close
        }, ["hotkeys", "shortcuts", "keys", "bindings"]))
        candidates.append((LauncherItem(id: "cmd.allDroplets", title: "See Every Droplet", subtitle: "Turn widgets on or off",
                                        icon: .symbol("puzzlepiece.extension", .purple), accessory: .hint("→")) { [weak self] in
            self?.showDroplets()
            return .stay(nil)
        }, ["droplets", "widgets", "extensions", "install", "uninstall", "enable"]))
        return candidates
            .compactMap { item, keywords in LauncherMatch.score(text, title: item.title, keywords: keywords).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func dropletItems(_ text: String, all: Bool) -> [LauncherItem] {
        let state = AppState.shared
        let matches = state.droplets.compactMap { droplet -> (DropletModel, Int)? in
            if all && text.isEmpty { return (droplet, 0) }
            return LauncherMatch.score(text, title: droplet.name, keywords: [droplet.tag]).map { (droplet, $0) }
        }
        let sorted = all ? matches.sorted { $0.0.name < $1.0.name } : matches.sorted { $0.1 > $1.1 }
        return sorted.prefix(all ? 100 : 3).map { droplet, _ in
            LauncherItem(id: "droplet:" + droplet.id, title: droplet.name, subtitle: droplet.tag,
                         icon: .droplet(droplet), accessory: .droplet(isEnabled: droplet.isEnabled)) {
                guard droplet.isEnabled else {
                    ThunderstormLauncherModel.setDroplet(droplet.id, enabled: true)
                    return .stay("\(droplet.name) is on")
                }
                GlobalShortcutService.openDroplet(droplet.id)
                return .close
            }
        }
    }

    static func setDroplet(_ id: String, enabled: Bool) {
        let state = AppState.shared
        guard let index = state.droplets.firstIndex(where: { $0.id == id }) else { return }
        state.droplets[index].isEnabled = enabled
        DroppyAudio.playTick()
    }

    private func settingsItems(_ text: String) -> [LauncherItem] {
        SettingsSearchIndex.search(text).prefix(4).map { entry in
            LauncherItem(id: "setting:" + entry.anchor, title: entry.title, subtitle: "Tama Settings › \(entry.page.title)",
                         icon: .symbol("gearshape.fill", .gray)) {
                SettingsNavigator.shared.reveal(entry)
                SettingsWindowController.shared.showWindow()
                return .close
            }
        }
    }

    private func paneItems(_ text: String) -> [LauncherItem] {
        SystemSettingsPane.all
            .compactMap { pane in LauncherMatch.score(text, title: pane.name, keywords: pane.keywords).map { (pane, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { pane, _ in
                LauncherItem(id: "pane:" + pane.id, title: pane.name, subtitle: pane.detail,
                             icon: .symbol(pane.symbol, .gray)) {
                    if let url = pane.url { NSWorkspace.shared.open(url) }
                    return .close
                }
            }
    }

    private func systemCommandItems(_ text: String) -> [LauncherItem] {
        SystemCommand.allCases
            .compactMap { command in LauncherMatch.score(text, title: command.title, keywords: command.keywords).map { (command, $0) } }
            .sorted { $0.1 > $1.1 }
            .map { command, _ in
                LauncherItem(id: "system:" + command.rawValue, title: command.title, subtitle: command.detail,
                             icon: .symbol(command.symbol, .gray), confirmation: command.confirmation) {
                    // Off the screen before the Mac locks, sleeps or restarts.
                    ThunderstormLauncherController.shared.hide()
                    if let line = await command.perform() {
                        AppState.shared.showNotification(appName: "Thunderstorm", title: command.title, message: line,
                                                         icon: command.symbol)
                    }
                    return .close
                }
            }
    }

    private static let weatherWords = ["weather", "temperature", "forecast", "rain", "sunny", "wetter", "temp"]

    private func weatherItem(_ text: String) -> LauncherItem? {
        let lower = text.lowercased()
        guard Self.weatherWords.contains(where: { $0.hasPrefix(lower) || lower.hasPrefix($0) }), lower.count >= 3 else {
            stopWeather()
            return nil
        }
        if !watchesWeather {
            watchesWeather = true
            WeatherService.shared.start(for: "thunderstorm")
        }
        let weather = WeatherService.shared
        let title: String
        let subtitle: String
        if let snapshot = weather.snapshot {
            title = "\(snapshot.temperatureText) · \(snapshot.summary)"
            subtitle = [weather.placeTitle, snapshot.rangeText].compactMap { $0 }.joined(separator: " · ")
        } else {
            title = weather.lastError ?? "Loading weather…"
            subtitle = weather.placeTitle
        }
        return LauncherItem(id: "weather", title: title, subtitle: subtitle + " · Return opens Weather",
                            icon: .symbol(weather.snapshot?.symbol ?? "cloud.sun.fill", .cyan)) {
            GlobalShortcutService.openDroplet("weather")
            return .close
        }
    }

    private func stopWeather() {
        guard watchesWeather else { return }
        watchesWeather = false
        WeatherService.shared.stop(for: "thunderstorm")
    }

    private func webItems(_ text: String) -> [LauncherItem] {
        var items = WebSearchEngine.allCases.map { engine in
            LauncherItem(id: "web:" + engine.rawValue, title: engine.title,
                         subtitle: "Search for \u{201C}\(text)\u{201D}", icon: .symbol(engine.symbol, .blue)) {
                if let url = engine.url(for: text) { NSWorkspace.shared.open(url) }
                return .close
            }
        }
        if !ThunderstormSettings.shared.inlineAnswers, answer == .none {
            items.append(LauncherItem(id: "web:answer", title: "Look Up an Inline Answer",
                                      subtitle: "Ask DuckDuckGo for \u{201C}\(text)\u{201D}",
                                      icon: .symbol("sparkle.magnifyingglass", .orange)) { [weak self] in
                self?.lookUp(text)
                return .stay(nil)
            })
        }
        return items
    }

    // MARK: Instant answers

    /// With Settings › Inline web answers on, asks DuckDuckGo shortly after
    /// typing stops. Off, only the "Look Up" row asks.
    private func scheduleAnswer() {
        answerTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        answer = .none
        guard mode == .search, ThunderstormSettings.shared.inlineAnswers, text.count >= 3 else { return }
        answerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self?.lookUp(text)
        }
    }

    private func lookUp(_ text: String) {
        answerTask?.cancel()
        answer = .loading(text)
        rebuild()
        answerTask = Task { [weak self] in
            let found = try? await InstantAnswerService.lookUp(text)
            guard !Task.isCancelled, let self, self.query.trimmingCharacters(in: .whitespaces) == text else { return }
            self.answer = found.map(Answer.found) ?? .empty(text)
            self.rebuild()
            if found != nil { self.selectedID = "answer" }
        }
    }

    // MARK: Actions

    func move(_ delta: Int) {
        let all = items
        guard !all.isEmpty else { return }
        isNavigating = true
        pendingID = nil
        let current = all.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = all[min(max(current + delta, 0), all.count - 1)].id
    }

    func activate(_ item: LauncherItem? = nil) {
        guard let item = item ?? selected else { return }
        selectedID = item.id
        if pendingID == item.id, pendingIsTrash { return moveToTrash(item) }
        if let confirmation = item.confirmation, pendingID != item.id {
            pendingID = item.id
            pendingIsTrash = false
            flash(confirmation)
            return
        }
        pendingID = nil
        status = nil
        Task {
            switch await item.action() {
            case .close:
                ThunderstormLauncherController.shared.hide()
            case .stay(let line):
                if let line { flash(line) }
            }
        }
    }

    func reveal() {
        guard let url = selected?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        ThunderstormLauncherController.shared.hide()
    }

    func quickLook() {
        guard let url = selected?.url else { return }
        QuickLookService.shared.preview([url])
    }

    func addToTray() {
        guard let item = selected, let url = item.url else { return }
        AppState.shared.addShelfItems([ShelfItem(url: url)])
        DroppyAudio.playDropSuccess()
        flash("Added \(item.title) to the Tray")
    }

    func copyPath() -> Bool {
        guard let url = selected?.url else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        DroppyAudio.playCopySuccess()
        flash("Copied path")
        return true
    }

    /// ⌘⌫: first press asks, Return (or ⌘⌫ again) moves it.
    func requestTrash() {
        guard let item = selected, item.url != nil else { return }
        if pendingID == item.id, pendingIsTrash { return moveToTrash(item) }
        pendingID = item.id
        pendingIsTrash = true
        flash(item.isApp ? "Press Return to move \(item.title) to the Trash" : "Press Return to move to Trash")
    }

    private func moveToTrash(_ item: LauncherItem) {
        pendingID = nil
        pendingIsTrash = false
        guard let url = item.url else { return }
        if item.isApp, NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == url }) {
            flash("Quit \(item.title) first")
            return
        }
        NSWorkspace.shared.recycle([url]) { _, error in
            Task { @MainActor in
                let model = ThunderstormLauncherController.shared.model
                if error != nil {
                    AppState.shared.showNotification(appName: "Thunderstorm", title: "Couldn't move to Trash",
                                                     message: "\(item.title) couldn't be moved to the Trash.", icon: "trash.slash")
                } else {
                    DroppyAudio.playTick()
                    model.flash("Moved \(item.title) to the Trash")
                    model.files.search(model.query)
                }
            }
        }
    }

    func cancelPending() -> Bool {
        guard pendingID != nil else { return false }
        pendingID = nil
        pendingIsTrash = false
        status = nil
        return true
    }

    func flash(_ line: String) {
        status = line
        statusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                if self?.status == line, self?.pendingID == nil { self?.status = nil }
            }
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    /// Returns true when the key was used, so it doesn't reach the text field.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_DownArrow: move(1)
        case kVK_UpArrow: move(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            command ? reveal() : activate()
        case kVK_Escape:
            if cancelPending() { return true }
            if mode == .droplets { back() } else if !query.isEmpty { query = "" } else {
                ThunderstormLauncherController.shared.hide()
            }
        case kVK_Delete where command:
            requestTrash()
        case kVK_ANSI_Y where command:
            quickLook()
        case kVK_ANSI_T where command:
            addToTray()
        // Tama has no Edit menu, so the field editor never gets these by itself.
        case kVK_ANSI_V where command:
            guard let editor = event.window?.firstResponder as? NSTextView else { return false }
            editor.paste(nil)
        case kVK_ANSI_A where command:
            guard let editor = event.window?.firstResponder as? NSTextView else { return false }
            editor.selectAll(nil)
        case kVK_ANSI_X where command:
            guard let editor = event.window?.firstResponder as? NSTextView else { return false }
            editor.cut(nil)
        case kVK_ANSI_Z where command:
            guard let editor = event.window?.firstResponder as? NSTextView else { return false }
            flags.contains(.shift) ? editor.undoManager?.redo() : editor.undoManager?.undo()
        case kVK_ANSI_C where command:
            if let editor = event.window?.firstResponder as? NSTextView,
               editor.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
                editor.copy(nil)
            } else if !copyPath() {
                return false
            }
        default:
            return false
        }
        return true
    }
}

// MARK: - View

struct ThunderstormLauncherView: View {
    @ObservedObject var model: ThunderstormLauncherModel
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let selection = Color(red: 0.16, green: 0.40, blue: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            bar
            if !model.sections.isEmpty {
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: ToolWindowMetrics.launcherCornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.black.opacity(0.94), Color(white: 0.07).opacity(0.94)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolWindowMetrics.launcherCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: ToolWindowMetrics.launcherCornerRadius, style: .continuous))
        .onChange(of: model.focusToken) { _, _ in focusField() }
        .onAppear { focusField() }
    }

    private func focusField() {
        DispatchQueue.main.async { isFieldFocused = true }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            if model.mode == .droplets {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DroppyPressStyle())
                .foregroundStyle(Color.white.opacity(0.7))
                .help("Back to search")
                .accessibilityLabel("Back to search")
            }
            Image(systemName: model.query.isEmpty && model.mode == .search ? "cloud.bolt.rain.fill" : "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 22)
                .accessibilityHidden(true)
            TextField(model.mode == .droplets ? "Search droplets" : "Search your Mac", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .focused($isFieldFocused)
                .accessibilityLabel(model.mode == .droplets ? "Search droplets" : "Search your Mac")
            if let status = model.status {
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.pendingID != nil ? DS.Palette.warning : DS.Palette.success)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
            if model.isSearchingFiles {
                ProgressView().controlSize(.small).accessibilityLabel("Searching")
            }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DroppyPressStyle())
                .foregroundStyle(Color.white.opacity(0.5))
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: ToolWindowMetrics.launcherBarHeight)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: model.status)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.sections) { section in
                        Text(section.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .accessibilityLabel(section.title)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.leading, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(section.items) { item in
                            LauncherRow(item: item,
                                        isSelected: item.id == model.selected?.id,
                                        isPending: item.id == model.pendingID,
                                        pendingText: model.status,
                                        selection: Self.selection,
                                        model: model)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id, model.isNavigating else { return }
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { proxy.scrollTo(id) }
            }
        }
    }
}

private struct LauncherRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let isPending: Bool
    let pendingText: String?
    let selection: Color
    @ObservedObject var model: ThunderstormLauncherModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(isPending ? (pendingText ?? item.subtitle) : item.subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isPending ? Color.white : Color.white.opacity(isSelected ? 0.75 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 12)
        .frame(height: ToolWindowMetrics.launcherRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPending ? DS.Palette.danger.opacity(0.55)
                      : isSelected ? selection : (isHovered ? Color.white.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { model.activate(item) }
        .onTapGesture(count: 1) {
            model.isNavigating = false
            model.selectedID = item.id
        }
        .onDrag {
            guard let url = item.url else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
        .contextMenu { contextMenu }
        .help(item.url?.path ?? item.subtitle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isPending ? (pendingText ?? item.subtitle) : item.subtitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.activate(item) }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .file(let url):
            Image(nsImage: FileIcon.image(for: url))
                .resizable()
                .interpolation(.high)
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint == .gray ? Color.white.opacity(0.85) : tint)
        case .droplet(let droplet):
            DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 28)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch item.accessory {
        case .hint(let text):
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isSelected ? 0.9 : 0.35))
                .accessibilityHidden(true)
        case .droplet(let isEnabled):
            HStack(spacing: 6) {
                if isEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(DS.Typo.labelStrong)
                        .foregroundStyle(DS.Palette.success)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(DS.Palette.success.opacity(0.16)))
                }
                Button {
                    ThunderstormLauncherModel.setDroplet(dropletID, enabled: !isEnabled)
                } label: {
                    Text(isEnabled ? "Disable" : "Enable")
                        .font(DS.Typo.labelStrong)
                        .foregroundStyle(isEnabled ? DS.Palette.danger : Color.white)
                        .padding(.horizontal, DS.Space.md)
                        .frame(height: 24)
                        .background(Capsule().fill(isEnabled ? DS.Palette.danger.opacity(0.18) : Color.white.opacity(0.18)))
                        .contentShape(Capsule())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .help(isEnabled ? "Turn this Droplet off" : "Turn this Droplet on")
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isEnabled ? 0.8 : 0.3))
                    .accessibilityHidden(true)
            }
        case .none:
            EmptyView()
        }
    }

    private var dropletID: String {
        if case .droplet(let droplet) = item.icon { return droplet.id }
        return ""
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open") { model.activate(item) }
        if let url = item.url {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Quick Look") { QuickLookService.shared.preview([url]) }
            Button("Add to Tray") { AppState.shared.addShelfItems([ShelfItem(url: url)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Divider()
            Button("Move to Trash…") {
                model.selectedID = item.id
                model.requestTrash()
            }
        }
    }
}
