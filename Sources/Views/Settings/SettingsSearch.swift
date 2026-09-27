import SwiftUI

// MARK: - Pages

/// The Settings sidebar, grouped like the reference: General and Droplets,
/// then Workspace, System and About.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, droplets, shortcuts
    case shelf, basket, clipboard, lockScreen
    case huds, theming, accessibility
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .droplets: "Droplets"
        case .shortcuts: "Keyboard Shortcuts"
        case .shelf: "Shelf"
        case .basket: "Basket"
        case .clipboard: "Clipboard"
        case .lockScreen: "Lock screen"
        case .huds: "HUDs"
        case .theming: "Theming"
        case .accessibility: "Accessibility"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .droplets: "puzzlepiece.extension.fill"
        case .shortcuts: "command"
        case .shelf: "tray.fill"
        case .basket: "basket.fill"
        case .clipboard: "clipboard.fill"
        case .lockScreen: "lock.fill"
        case .huds: "sun.max.fill"
        case .theming: "paintpalette.fill"
        case .accessibility: "accessibility"
        case .about: "info.circle.fill"
        }
    }

    enum Group: String, CaseIterable {
        case main = "", workspace = "Workspace", system = "System", about = "About"
    }

    var group: Group {
        switch self {
        case .general, .droplets, .shortcuts: .main
        case .shelf, .basket, .clipboard, .lockScreen: .workspace
        case .huds, .theming, .accessibility: .system
        case .about: .about
        }
    }
}

// MARK: - Index

/// One searchable option: what it's called, the words people might type
/// instead, and where it lives (page + the row's anchor).
struct SettingsSearchEntry: Identifiable, Hashable {
    let anchor: String
    let title: String
    let page: SettingsPage
    let keywords: [String]
    var id: String { anchor }

    init(_ anchor: String, _ title: String, _ page: SettingsPage, _ keywords: [String] = []) {
        self.anchor = anchor
        self.title = title
        self.page = page
        self.keywords = keywords
    }

    /// Every word of the query must appear in the title, the page or a
    /// keyword, so "external monitor" and "hide icon" both find their rows.
    func matches(_ query: String) -> Bool {
        let haystack = ([title, page.title] + keywords).joined(separator: " ").lowercased()
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains($0) }
    }

    /// Title hits rank above keyword hits.
    func score(_ query: String) -> Int {
        let q = query.lowercased()
        if title.lowercased().hasPrefix(q) { return 0 }
        if title.lowercased().contains(q) { return 1 }
        return 2
    }
}

enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = [
        // General
        .init("general.startup", "Startup & visibility", .general,
              ["menu bar icon", "dock icon", "launch at login", "start at login", "open at login", "hide icon", "command-tab", "status bar"]),
        .init("general.permissions", "Permissions overview", .general,
              ["permission", "privacy", "grant", "allow", "accessibility", "screen recording", "calendar", "reminders",
               "automation", "microphone", "notifications", "input monitoring", "tcc"]),
        .init("general.fileActions", "File actions", .general,
              ["auto-remove", "remove after drag", "drag out", "protect originals", "copy", "move", "originals", "tray files"]),
        .init("general.autoCopyOCR", "Auto-copy OCR text", .general,
              ["ocr", "text recognition", "extract text", "copy text", "clipboard", "scan"]),
        .init("general.quickActions", "Quick Actions", .general,
              ["drop tiles", "drag tiles", "quick action", "keep", "airdrop", "convert", "share"]),
        .init("general.quickActionTiles", "Quick Action tiles", .general,
              ["tiles", "add quick action", "quickshare", "icloud drive", "mail", "messages", "share link", "swap tile"]),
        .init("general.mailApp", "Quick Action mail app", .general, ["mail", "outlook", "email", "compose", "default mail"]),
        .init("general.quickshareConfirm", "Require upload confirmation", .general,
              ["quickshare", "0x0", "upload", "ask before uploading", "confirm"]),
        .init("general.uploads", "Recent uploads", .general,
              ["quickshare", "upload manager", "manage uploads", "links", "shared files", "delete upload"]),
        .init("general.smartExport", "Smart Export", .general,
              ["auto-save", "export", "compressed", "converted", "processed files", "folders", "auto route"]),
        .init("general.trackedFolders", "Tracked folders", .general,
              ["watch folder", "watched folder", "auto-add", "auto-process", "monitor folder", "hot folder",
               "watch and process files from selected folders"]),
        .init("general.trackedFoldersLevel", "Tracked folders compression level", .general,
              ["watch folder", "add and compress", "compression level", "unattended"]),
        .init("general.convertDestination", "Converted file save location", .general,
              ["destination folder", "converted files", "downloads", "save location", "conversion"]),
        .init("general.afterConvert", "After converting", .general,
              ["show in finder", "open folder", "add to shelf", "conversion complete"]),
        .init("general.cutoutStyle", "Background removal", .general,
              ["remove background", "cutout", "padding", "corner radius", "shadow", "transparent", "backdrop"]),
        .init("general.helperTools", "Helper tools", .general,
              ["homebrew", "brew", "ffmpeg", "ghostscript", "webp", "cwebp", "libreoffice", "install"]),
        .init("general.finderServices", "Finder Services", .general,
              ["services", "right-click", "add to tama shelf", "add to tama basket", "finder", "setup guide"]),
        .init("general.alfred", "Alfred", .general, ["alfred", "workflow", "launcher", "file action"]),
        .init("general.urlScheme", "URL scheme", .general, ["tama://", "url", "scheme", "automation", "shortcuts", "script"]),
        .init("general.shortcuts", "Keyboard shortcuts", .general,
              ["shortcut", "hotkey", "hot key", "keybinding", "record shortcut", "toggle island", "snip", "player", "ring", "live activity"]),
        .init("general.gestures", "Gestures", .general,
              ["click", "double-click", "play pause", "scroll", "select all"]),
        // Droplets
        .init("droplets.store", "Droplets", .droplets,
              ["widgets", "extensions", "plugins", "store", "install", "enable droplet", "explore", "featured",
               "uninstall", "community droplet", "installed", "droplet store"]),
        .init("droplet.appleMusic.quality", "Audio quality badge", .droplets, ["lossless", "hi-res", "apple music", "quality"]),
        .init("droplet.appleMusic.buttons", "Media widget buttons", .droplets,
              ["left button", "right button", "apple music", "shuffle", "repeat"]),
        .init("droplet.weather.style", "Weather style", .droplets, ["weather", "colorful", "dark", "liquid glass", "card"]),
        .init("droplet.weather.location", "Weather location", .droplets, ["city", "location", "automatic", "place", "search"]),
        .init("droplet.weather.refresh", "Weather refresh interval", .droplets, ["weather", "refresh", "update", "interval"]),
        .init("droplet.weather.aqi", "Air quality", .droplets, ["aqi", "air quality", "weather", "pollution"]),
        .init("droplet.weather.sun", "Sunrise & sunset", .droplets, ["sunrise", "sunset", "weather", "sun"]),
        .init("droplet.termiNotch.app", "Open in Terminal app", .droplets, ["terminotch", "terminal", "iterm", "ghostty", "warp", "open in terminal"]),
        .init("droplet.termiNotch.bar", "Show TermiNotch bar", .droplets, ["terminotch", "quick command bar", "expanded", "terminal"]),
        .init("droplet.termiNotch.prompt", "TermiNotch prompt", .droplets, ["terminotch", "zsh", "prompt", "user@host"]),
        .init("droplet.termiNotch.fontSize", "TermiNotch text size", .droplets, ["terminotch", "font", "text size", "terminal"]),
        .init("droplet.termiNotch.floating", "Show TermiNotch as a floating button", .droplets, ["terminotch", "floating button", "favorite"]),
        .init("droplet.meetings.callHUD", "Show active call HUD", .droplets, ["meetings", "call", "timer", "phone", "hud", "zoom", "teams", "facetime", "whatsapp"]),
        .init("droplet.meetings.micLevel", "Live mic level", .droplets, ["meetings", "microphone", "level", "waveform", "bars"]),
        .init("droplet.meetings.pause", "Pause media during meetings", .droplets, ["meetings", "pause music", "media paused for meeting"]),
        .init("droplet.meetings.pauseTrigger", "Pause media when mic is unmuted", .droplets, ["meetings", "unmuted", "mic", "pause"]),
        .init("droplet.meetings.resume", "Resume media after meeting", .droplets, ["meetings", "resume", "music", "play again"]),
        .init("droplet.notifications.access", "Notification HUD Full Disk Access", .droplets, ["notifications", "full disk access", "usernoted", "permission"]),
        .init("droplet.notifications.duration", "Notification duration", .droplets, ["notifications", "how long", "auto-dismiss", "visible"]),
        .init("droplet.notifications.preview", "App icon and notification preview", .droplets, ["notifications", "preview", "body", "icon"]),
        .init("droplet.notifications.burst", "Burst notifications", .droplets, ["notifications", "burst", "queue", "summary"]),
        .init("droplet.notifications.filters", "Show notification filter choices", .droplets, ["notifications", "filter", "chips"]),
        .init("droplet.notifications.floating", "Show Notifications as a floating button", .droplets, ["notifications", "floating button"]),
        .init("droplet.notifications.reply", "Quick reply", .droplets, ["notifications", "reply", "imessage", "messages", "whatsapp", "telegram"]),
        .init("droplet.notifications.hideAfterReply", "Auto-hide after replying", .droplets, ["notifications", "reply", "hide"]),
        .init("droplet.notifications.apps", "Per-app notification filtering", .droplets, ["notifications", "don't show", "block", "apps", "filter"]),
        .init("droplet.notifications.native", "Hide native banners", .droplets, ["notifications", "system banners", "replace system notifications"]),
        .init("droplet.agents.claude", "Claude Code agent", .droplets, ["agents", "claude", "claude code", "ai coding"]),
        .init("droplet.agents.hooks", "Claude Code hooks", .droplets, ["agents", "claude", "hooks", "settings.json", "install"]),
        .init("droplet.agents.codex", "Codex agent", .droplets, ["agents", "codex", "openai", "sessions"]),
        .init("droplet.agents.cursor", "Cursor agent", .droplets, ["agents", "cursor", "composer"]),
        .init("droplet.agents.notch", "Show agents in the notch", .droplets, ["agents", "spinner", "notch", "live activity"]),
        .init("droplet.agents.done", "Agent finished banner", .droplets, ["agents", "background task completed", "done", "notify"]),
        .init("droplet.notchface.camera", "Notchface camera", .droplets, ["notchface", "camera", "webcam", "continuity"]),
        .init("droplet.notchface.mirror", "Mirror the preview", .droplets, ["notchface", "mirror", "flip"]),
        .init("droplet.notchface.access", "Camera access", .droplets, ["notchface", "camera permission", "privacy"]),
        .init("droplet.notchface.floating", "Show Notchface as a floating button", .droplets, ["notchface", "floating button"]),
        .init("droplet.snipper.shortcuts", "Capture keyboard shortcuts", .droplets,
              ["element capture", "screenshot", "shortcut", "hotkey", "area", "window", "full screen", "element", "ocr"]),
        .init("droplet.snipper.destinations", "Capture destinations", .droplets,
              ["screenshot", "clipboard", "tray", "folder", "editor", "where captures go"]),
        .init("droplet.snipper.folder", "Screenshot destination folder", .droplets, ["screenshot", "save", "folder", "desktop", "location"]),
        .init("droplet.snipper.editor", "Open editor instantly", .droplets, ["screenshot", "edit after capture", "annotate", "editor"]),
        .init("droplet.snipper.preview", "Screenshot preview", .droplets, ["quick actions", "pin", "copied", "thumbnail", "corner"]),
        .init("droplet.snipper.compress", "Auto-compress screenshots", .droplets, ["screenshot", "compress", "smaller", "file size"]),
        .init("droplet.snipper.exclude", "Leave Tama out of captures", .droplets, ["screenshot", "exclude", "hide notch", "own windows"]),
        .init("droplet.snipper.zoom", "Default zoom level", .droplets, ["screenshot editor", "zoom", "native", "fit"]),
        .init("droplet.snipper.color", "Default annotation color", .droplets, ["screenshot editor", "color", "colour", "highlight color", "red"]),
        .init("droplet.snipper.font", "Annotation text font", .droplets, ["screenshot editor", "font", "text", "typeface"]),
        .init("droplet.snipper.radius", "Screenshot Radius", .droplets, ["screenshot", "corner radius", "rounded", "beautify", "backdrop"]),
        .init("droplet.snipper.editorShortcuts", "Editor shortcuts", .droplets, ["screenshot editor", "keyboard", "cheat sheet", "keys"]),
        .init("droplet.ocr.autoCopy", "OCR Auto-Copy", .droplets, ["ocr", "text recognition", "auto-copy", "clipboard"]),
        .init("droplet.windowSnapper.preview", "Show snap preview", .droplets, ["window snap", "preview", "zone", "overlay"]),
        .init("droplet.windowSnapper.shortcuts", "Snap with shortcuts", .droplets,
              ["window snap", "shortcut", "halves", "thirds", "two thirds", "quarters", "center", "maximize",
               "next display", "previous display", "bring window to front", "tile"]),
        .init("droplet.liquidMouse.status", "External mouse status", .droplets, ["liquidmouse", "mouse", "connected", "detect"]),
        .init("droplet.liquidMouse.smooth", "Smooth Scrolling", .droplets, ["liquidmouse", "smooth", "scroll", "wheel"]),
        .init("droplet.liquidMouse.liquid", "Liquid Mode", .droplets, ["liquidmouse", "momentum", "inertia", "trackpad-like"]),
        .init("droplet.liquidMouse.axis", "Scroll axis", .droplets, ["liquidmouse", "vertical", "horizontal", "direction"]),
        .init("droplet.liquidMouse.reverse", "Reverse Scroll Direction", .droplets, ["liquidmouse", "invert", "natural", "reverse"]),
        .init("droplet.liquidMouse.speed", "Scroll speed", .droplets, ["liquidmouse", "speed", "faster", "slower"]),
        .init("droplet.liquidMouse.curve", "Scroll curve", .droplets,
              ["liquidmouse", "curve", "linear", "balanced", "ease in", "ease out", "cubic", "quartic", "soft start", "stable", "fluid"]),
        .init("droplet.liquidMouse.restore", "Restore balanced preset", .droplets, ["liquidmouse", "reset", "balanced", "default"]),
        .init("droplet.voiceTranscribe.quickRecord", "Quick Record", .droplets,
              ["voice transcribe", "record", "shortcut", "hotkey", "dictate", "microphone", "visible window"]),
        .init("droplet.voiceTranscribe.floating", "External Recorder", .droplets,
              ["voice transcribe", "floating panel", "recorder window", "inline expansion"]),
        .init("droplet.voiceTranscribe.menuBar", "Show recording icon in menu bar", .droplets,
              ["voice transcribe", "menu bar", "recording indicator", "status item", "red mic"]),
        .init("droplet.voiceTranscribe.engine", "Transcription engine", .droplets,
              ["voice transcribe", "on-device", "server", "speech", "whisper", "parakeet", "model", "auto"]),
        .init("droplet.voiceTranscribe.live", "Live transcription", .droplets, ["voice transcribe", "live", "streaming", "words"]),
        .init("droplet.voiceTranscribe.skipResult", "Skip result window and copy transcription instantly", .droplets,
              ["voice transcribe", "copy", "clipboard", "result", "instantly"]),
        .init("droplet.voiceTranscribe.retention", "Recording retention", .droplets,
              ["voice transcribe", "keep", "delete audio", "storage", "recordings", "after transcription"]),
        .init("droplet.thunderstorm.shortcut", "Open Thunderstorm", .droplets,
              ["thunderstorm", "launcher", "spotlight", "search your mac", "shortcut", "hotkey"]),
        .init("droplet.thunderstorm.commands", "Thunderstorm system commands", .droplets,
              ["thunderstorm", "lock screen", "sleep", "restart", "shut down", "log out", "eject", "quit all"]),
        .init("droplet.thunderstorm.web", "Thunderstorm web search", .droplets,
              ["thunderstorm", "google", "duckduckgo", "wikipedia", "web"]),
        .init("droplet.thunderstorm.answers", "Inline web answers", .droplets,
              ["thunderstorm", "instant answer", "duckduckgo", "web result", "answer"]),
        .init("droplet.menuBar.toggle", "Menu Bar Manager", .droplets,
              ["menu bar", "hide icons", "hidden section", "clean up", "thaw", "bartender", "status items"]),
        .init("droplet.menuBar.shortcut", "Show or hide the hidden section", .droplets, ["menu bar", "shortcut", "hotkey", "reveal"]),
        .init("droplet.menuBar.alwaysHidden", "Always-hidden section", .droplets, ["menu bar", "always hidden", "option-click"]),
        .init("droplet.menuBar.rehide", "Rehide automatically", .droplets, ["menu bar", "rehide", "delay", "timer"]),
        .init("droplet.menuBar.appSwitch", "Rehide when switching apps", .droplets, ["menu bar", "rehide", "app switch"]),
        .init("droplet.menuBar.icon", "Menu bar toggle icon", .droplets, ["menu bar", "chevron", "dot", "icon"]),
        .init("droplet.menuBar.template", "Render icon as a template", .droplets, ["menu bar", "template", "monochrome", "color"]),
        .init("droplet.menuBar.reset", "Reset menu bar layout", .droplets, ["menu bar", "reset", "layout", "order"]),
        // Keyboard Shortcuts
        .init("shortcuts.all", "All keyboard shortcuts", .shortcuts,
              ["shortcut", "hotkey", "hot key", "keybinding", "change shortcut", "record shortcut", "all shortcuts"]),
        .init("shortcuts.resetAll", "Reset all shortcuts", .shortcuts, ["reset", "shortcuts", "defaults", "hotkeys"]),
        .init("shortcuts.widgets", "Widget shortcuts", .shortcuts,
              ["per-widget", "widget", "droplet", "open console", "shortcut to open"]),
        // Shelf
        .init("shelf.enable", "The Shelf", .shelf,
              ["enable shelf", "turn off shelf", "disable shelf", "notch shelf", "shelf on off"]),
        .init("shelf.size", "Shelf size", .shelf, ["regular", "enlarged", "bigger", "larger", "scale", "size"]),
        .init("shelf.navStyle", "Navigation style", .shelf,
              ["floating bar", "regular buttons", "tabs", "wing tabs", "capsule", "navigation", "lane pill", "nav bar"]),
        .init("shelf.calendarButton", "Calendar button", .shelf, ["calendar", "floating button", "tasks"]),
        .init("shelf.multiLive", "Multi Live Activities", .shelf,
              ["live activity", "second activity", "two activities", "concurrent", "split island", "circle pill"]),
        .init("shelf.customShelf", "Custom Shelf", .shelf,
              ["customize home", "home widgets", "edit shelf", "weather", "player", "preview", "layout"]),
        .init("shelf.widgetIcons", "Widget icons", .shelf,
              ["rearrange", "reorder", "widget order", "drag", "icons", "sort widgets"]),
        .init("shelf.widgetSettings", "Widget settings", .shelf,
              ["widgets active", "enable widget", "disable widget", "droplets", "turn on"]),
        .init("shelf.floatingSize", "Floating button size", .shelf,
              ["floating buttons", "round buttons", "size", "favorites", "lane pill"]),
        .init("shelf.floatingStyle", "Floating button style", .shelf,
              ["floating button style", "colored", "glass", "monochrome", "widget tint", "accent"]),
        .init("shelf.floatingIconColor", "Icon color", .shelf,
              ["icon color", "text color", "colored floating buttons", "light", "dark"]),
        .init("shelf.favorites", "Favorites", .shelf,
              ["favorite", "pin app", "shortcut", "shortcuts app", "quick launch", "floating buttons"]),
        .init("shelf.behavior", "Auto-collapse & auto-expand", .shelf,
              ["hover", "open on hover", "auto expand", "auto collapse", "stay open", "keep open", "close automatically"]),
        .init("shelf.collapseDelay", "Collapse delay", .shelf, ["auto collapse", "close after leaving", "hide delay"]),
        .init("shelf.expandDelay", "Auto-expand delay", .shelf, ["hover delay", "dwell", "open delay"]),
        .init("shelf.speed", "Animation speed", .shelf,
              ["turtle", "human", "cheetah", "falcon", "faster", "slower", "speed", "tempo"]),
        .init("shelf.motion", "Animation style", .shelf, ["motion", "spring", "bounce", "animation", "morph", "snappy", "gentle"]),
        .init("shelf.gestures", "Gestures", .shelf,
              ["swipe", "trackpad", "two finger", "swipe down", "swipe pages", "gesture"]),
        .init("shelf.swipeDirection", "Swipe direction", .shelf,
              ["reverse swipe direction", "reversed", "flip swipe", "pages", "tray stacks", "swipe between stacks"]),
        .init("shelf.scrollAction", "Scroll on the notch", .shelf, ["scroll volume", "swipe to open", "scroll", "volume"]),
        .init("shelf.openTrayAfterDrop", "Open tray after drop", .shelf, ["drop", "tray", "reveal", "after drop", "files"]),
        .init("shelf.pages", "Pages & default page", .shelf,
              ["open shelf on", "default page", "now playing", "tray page", "calendar page", "command 1"]),
        .init("shelf.player", "Lyrics online", .shelf, ["lyrics", "lrclib", "up next", "queue", "player"]),
        .init("shelf.autoExpandLyrics", "Auto-expand lyrics", .shelf, ["lyrics", "auto", "open lyrics", "synced"]),
        .init("shelf.tray", "Tray capacity", .shelf, ["tray", "files", "limit", "capacity"]),
        .init("shelf.autoCleanup", "Auto-cleanup", .shelf,
              ["expire", "expiry", "auto-remove", "hours", "clean up", "expires soon", "pin"]),
        .init("shelf.twoStacks", "Two Stacks", .shelf, ["stack", "stack 1", "stack 2", "one stack", "second stack"]),
        .init("shelf.capturePlacement", "Preview placement", .shelf,
              ["closest corner", "hud placement", "under pointer", "bottom right", "screenshot preview"]),
        .init("shelf.screenshots", "Snip preview", .shelf, ["screenshot", "capture", "preview", "snip", "thumbnail"]),
        .init("shelf.pomodoro", "Pomodoro durations", .shelf, ["pomodoro", "focus", "break", "timer", "slider"]),
        .init("shelf.pomodoro.ambient", "Enable ambient sound", .shelf,
              ["pomodoro", "ambient", "noise", "background noise", "white noise", "brown noise", "rain", "focus sound"]),
        .init("shelf.pomodoro.ambientSound", "Ambient sound", .shelf, ["pomodoro", "rain", "waves", "pink noise", "brown noise"]),
        .init("shelf.pomodoro.volume", "Ambient sound volume", .shelf, ["pomodoro", "ambient", "volume", "loudness"]),
        .init("shelf.pomodoro.focus", "Turn on Focus during sessions", .shelf,
              ["focus mode", "do not disturb", "dnd", "shortcuts", "tama focus on", "tama focus off", "pomodoro"]),
        .init("shelf.pomodoro.visible", "Keep timer visible in notch", .shelf,
              ["timer visibility", "pomodoro", "compact hud", "countdown", "priority", "wings"]),
        .init("shelf.pomodoro.momentum", "Momentum", .shelf,
              ["pomodoro", "streak", "sessions today", "focus streak", "momentum"]),
        .init("shelf.pomodoro.hover", "Open Pomodoro on hover", .shelf, ["hover", "timer", "pomodoro", "open shelf"]),
        .init("shelf.highAlert.mode", "High Alert mode", .shelf,
              ["high alert", "keep awake", "caffeine", "screen awake", "system awake", "lid closed", "clamshell", "sleep"]),
        .init("shelf.highAlert.sleep", "System sleep & Sleep Now", .shelf,
              ["high alert", "sleep now", "system sleep", "put your mac to sleep", "pmset", "disablesleep"]),
        .init("shelf.tasks.show", "Show reminders & events", .shelf,
              ["tasks", "calendar", "reminders", "events", "show tasks", "hide tasks", "tasks & calendar"]),
        .init("shelf.tasks.hideUndated", "Hide undated tasks", .shelf, ["tasks", "reminders", "no due date", "undated"]),
        .init("shelf.tasks.weekNumbers", "Week numbers", .shelf, ["week #", "wk", "calendar", "week of year"]),
        .init("shelf.tasks.cleanup", "Remove completed tasks after", .shelf,
              ["completed", "done", "clean up", "struck through", "tasks", "reminders"]),
        .init("shelf.tasks.defaultList", "Default list for new tasks", .shelf, ["reminders list", "tasks", "default list", "new task"]),
        .init("shelf.tasks.defaultCalendar", "Default calendar", .shelf, ["calendar", "new event", "meeting reminders", "default"]),
        .init("shelf.tasks.calendars", "Calendars shown", .shelf, ["calendars", "choose calendars", "filter", "hide calendar"]),
        .init("shelf.tasks.lists", "Reminder lists shown", .shelf, ["reminder lists", "lists", "filter", "tasks"]),
        .init("shelf.tasks.dueAlerts", "Due alerts", .shelf,
              ["due soon", "notifications", "task due", "reminder alert", "tasks", "alerts"]),
        .init("shelf.tasks.headsUp", "Heads-up before due", .shelf, ["heads-up", "lead time", "before due", "early warning"]),
        .init("shelf.tasks.chime", "Due alert chime", .shelf, ["chime", "sound", "due", "alert sound"]),
        .init("shelf.tasks.eventRing", "Event progress ring", .shelf, ["event", "progress", "ring", "live activity", "meeting"]),
        .init("shelf.tasks.nextEvent", "Next event in the notch", .shelf, ["next event", "upcoming", "next task", "wing"]),
        .init("shelf.tasks.popout", "Keep calendar window on top", .shelf,
              ["pop out calendar", "floating calendar", "window", "always on top", "tasks & calendar"]),
        .init("shelf.notes.sync", "Sync with Apple Notes", .shelf, ["notes", "apple notes", "sync", "icloud", "scratchpad"]),
        .init("shelf.notes.toolbar", "Show formatting toolbar", .shelf,
              ["notes", "bold", "italic", "underline", "headings", "lists", "formatting", "rich text"]),
        .init("shelf.notes.grow", "Grow canvas with longer notes", .shelf, ["notes", "grow", "height", "canvas", "taller"]),
        // Basket
        .init("basket.show", "Floating Basket", .basket, ["basket", "float", "window", "gather files", "enable"]),
        .init("basket.instant", "Instant appear & Auto-hide", .basket,
              ["instant basket", "no shake", "delay", "auto-hide", "hide when idle", "latency"]),
        .init("basket.shake", "Shake to summon", .basket, ["jiggle", "shake", "drag", "summon"]),
        .init("basket.sensitivity", "Shake sensitivity", .basket, ["jiggle sensitivity", "shake", "movement", "balanced"]),
        .init("basket.dragShortcut", "Drag shortcut", .basket, ["modifier", "option", "hold while dragging", "reveal"]),
        .init("basket.shortcut", "Summon Basket", .basket, ["shortcut", "hotkey", "basket", "toggle"]),
        .init("basket.mode", "Basket mode", .basket,
              ["single basket", "multi-basket", "multiple baskets", "new basket", "workspace", "slots", "colors"]),
        .init("basket.switcher", "Basket Switcher", .basket, ["switch baskets", "all baskets", "shortcut"]),
        .init("basket.secondBucket", "Second bucket", .basket, ["bucket", "rarely used", "second"]),
        // Clipboard
        .init("clipboard.recording", "Pause clipboard", .clipboard, ["pause", "record", "stop saving"]),
        .init("clipboard.pasteShortcut", "Paste shortcut", .clipboard,
              ["separate paste shortcut", "paste hotkey", "paste from clipboard", "open paste"]),
        .init("clipboard.shortcut", "Clipboard shortcut", .clipboard, ["shortcut", "hotkey", "open clipboard"]),
        .init("clipboard.history", "History limit", .clipboard, ["history", "limit", "keep history", "retention", "images", "storage"]),
        .init("clipboard.privacy", "Skip passwords", .clipboard,
              ["password", "sensitive", "credit card", "token", "privacy", "skip sensitive content"]),
        .init("clipboard.enable", "Clipboard manager", .clipboard, ["enable clipboard", "keep clipboard history", "turn off", "master"]),
        .init("clipboard.locations", "Clipboard locations", .clipboard, ["menu bar", "right-click menu", "open clipboard", "shelf menu"]),
        .init("clipboard.layout", "Clipboard layout", .clipboard, ["alpha", "legacy", "list", "window", "cards", "compact", "appearance"]),
        .init("clipboard.favoritesBar", "Favorites bar", .clipboard,
              ["favourites bar", "starred clips", "pinned clips", "quick clips", "star"]),
        .init("clipboard.typeFilters", "Type filters", .clipboard, ["filter rail", "images", "links", "colors", "files"]),
        .init("clipboard.retention", "Keep history for", .clipboard, ["retention", "days", "expire", "image storage"]),
        .init("clipboard.blur", "Blur sensitive content", .clipboard, ["blur", "hide", "password", "reveal"]),
        .init("clipboard.clearOnQuit", "Clear history on quit", .clipboard, ["quit", "clear", "erase", "privacy"]),
        .init("clipboard.duplicates", "Reject duplicates", .clipboard, ["duplicate", "dedupe", "repeat", "same"]),
        .init("clipboard.pasteIntoApp", "Paste into the previous app", .clipboard, ["paste", "auto paste", "copy only", "plain text"]),
        .init("clipboard.accessibility", "Accessibility Paste Support", .clipboard, ["accessibility", "permission", "paste"]),
        .init("clipboard.actions", "Clipboard actions", .clipboard, ["tags", "copy + favorite", "auto-focus", "search focus"]),
        .init("clipboard.tags", "Clipboard tags", .clipboard, ["tag", "label", "new tag", "collect"]),
        .init("clipboard.clear", "Clear clipboard history", .clipboard, ["clear history", "purge", "delete all"]),
        .init("clipboard.excluded", "Excluded apps", .clipboard, ["exclude", "ignore app", "password manager", "filtering", "add excluded app"]),
        // Lock screen
        .init("lock.enable", "Lock screen", .lockScreen, ["lock screen", "locked", "login window"]),
        .init("lock.status", "Status widgets row", .lockScreen, ["battery", "headphones", "next event", "weather", "air quality", "widgets"]),
        .init("lock.player", "Lock screen media HUD", .lockScreen, ["now playing", "media", "music", "player"]),
        .init("lock.animation", "Lock/unlock animation", .lockScreen, ["animation", "fade", "lock sound", "unlock sound"]),
        .init("lock.sound", "Lock & unlock sound", .lockScreen, ["sound", "lock sound", "unlock sound", "chime"]),
        .init("lock.mediaMaterial", "Lock screen media HUD material", .lockScreen, ["material", "blur", "liquid", "glass"]),
        .init("lock.volume", "Lock screen volume slider", .lockScreen, ["volume", "slider", "sound"]),
        .init("lock.brightness", "Lock screen brightness slider", .lockScreen, ["brightness", "slider", "display"]),
        .init("lock.screensaver", "Keep visible during screensaver", .lockScreen, ["screensaver", "screen saver"]),
        .init("lock.keepAwake", "Keep awake while locked", .lockScreen, ["keep awake", "sleep", "display sleep", "caffeine"]),
        .init("lock.widgetStyle", "Lock screen widget style", .lockScreen, ["vertical", "rounded", "inline", "layout"]),
        .init("lock.widgetLook", "Lock screen widget look", .lockScreen, ["light", "dark", "appearance"]),
        .init("lock.widgetMaterial", "Lock screen widget material", .lockScreen, ["regular", "liquid", "glass", "material"]),
        // HUDs
        .init("huds.hideExternal", "Hide on external displays", .huds,
              ["external monitor", "external display", "disable", "connected monitors", "hide island"]),
        .init("huds.displayStyle", "External displays style", .huds,
              ["notch", "island", "dynamic island", "floating pill", "carved black", "placement", "style"]),
        .init("huds.showWhenIdle", "Show when idle", .huds, ["idle", "nothing playing", "keep visible", "external", "fade"]),
        .init("huds.perDisplay", "Per-display visibility", .huds,
              ["which displays", "monitor", "screen", "checkbox", "external display rules"]),
        .init("huds.hideNotch", "Hide physical notch", .huds, ["notch", "black bar", "menu bar", "camera housing", "hide notch"]),
        .init("huds.targetDisplay", "Show Tama on", .huds,
              ["target display", "external monitor", "display", "screen", "multi monitor", "all displays", "follow mouse"]),
        .init("huds.islandHeight", "Island height", .huds, ["size", "pill", "taller", "height", "standard"]),
        .init("huds.islandWidth", "Island width", .huds, ["size", "pill", "wider", "width", "standard"]),
        .init("huds.islandPosition", "Island position", .huds, ["vertical offset", "move down", "position", "gap"]),
        .init("huds.notchHeight", "Notch height", .huds, ["size", "hud", "notch", "height", "taller"]),
        .init("huds.notchWidth", "Notch width", .huds, ["size", "hud", "notch", "width", "wings", "wider"]),
        .init("huds.scope", "Collapsed HUD scope", .huds, ["under pointer", "all displays", "every screen", "mirror"]),
        .init("huds.fullscreen", "In fullscreen", .huds,
              ["fullscreen", "full screen", "hide media", "hide all", "games", "video"]),
        .init("huds.missionControl", "Hide in Mission Control", .huds, ["mission control", "app expose", "exposé", "spaces"]),
        .init("huds.priority", "Compact HUD priority", .huds, ["priority", "music first", "live activities first", "wings"]),
        .init("huds.linger", "Finished HUD linger", .huds, ["linger", "how long", "duration", "stay", "dismiss delay"]),
        .init("huds.keepHovered", "Keep HUD visible while hovered", .huds, ["hover", "keep visible", "stay", "hud"]),
        .init("huds.volumeCard", "Volume HUD", .huds, ["volume", "sound", "osd", "replace system osd"]),
        .init("huds.brightnessCard", "Brightness HUD", .huds, ["brightness", "display", "osd"]),
        .init("huds.keyboardHUD", "Keyboard brightness HUD", .huds, ["keyboard", "backlight", "illumination", "osd"]),
        .init("huds.batteryHUD", "Battery status", .huds, ["battery", "charging", "low battery", "power"]),
        .init("huds.fileTrayHUD", "File tray HUD", .huds, ["tray", "drop", "files", "after drop"]),
        .init("huds.capsLock", "Caps Lock", .huds, ["caps lock", "capslock", "uppercase", "indicator"]),
        .init("huds.recording", "Recording status", .huds,
              ["microphone", "mic", "screen recording", "camera", "privacy indicator", "in use"]),
        .init("huds.airpods", "AirPods & headphones", .huds,
              ["airpods", "headphones", "bluetooth", "beats", "earbuds", "battery", "connected"]),
        .init("huds.focus", "Focus mode", .huds, ["focus", "do not disturb", "dnd", "sleep", "work"]),
        .init("huds.offline", "No internet", .huds, ["offline", "internet", "wifi", "network", "connection"]),
        .init("huds.vpn", "VPN connected", .huds, ["vpn", "tunnel", "wireguard", "timer"]),
        .init("huds.nowPlaying", "Now Playing", .huds, ["media", "music", "now playing", "media hud", "hide media", "wings"]),
        .init("huds.autoHide", "Auto-hide preview", .huds, ["fade", "mini player", "paused", "hide after", "media"]),
        .init("huds.nowPlayingDisplay", "Now Playing display", .huds, ["under pointer", "macbook", "which display", "media"]),
        .init("huds.nowPlayingSize", "Now Playing size", .huds,
              ["regular", "smaller", "compact player", "media hud layout", "player size"]),
        .init("huds.trackTitle", "Notch track title", .huds, ["song title", "artist", "wings", "media player text"]),
        .init("huds.visualizer", "Visualizer", .huds, ["bars", "spectrum", "mono", "gradient", "equalizer", "wave"]),
        .init("huds.liveVisualizer", "Live audio visualizer", .huds, ["audio", "real levels", "bounce", "spectrum", "output"]),
        .init("huds.liveArtwork", "Live album artwork", .huds, ["artwork", "cover", "fullscreen", "expanded", "album art"]),
        .init("huds.artworkTint", "Artwork tint", .huds, ["gradient", "background", "colour", "color", "album art", "tint"]),
        .init("huds.defaultMusicApp", "Default music app", .huds, ["apple music", "spotify", "open music", "launch", "play"]),
        .init("huds.trackSwipe", "Track swipe", .huds, ["swipe", "skip", "next track", "gesture", "two finger"]),
        .init("huds.trackSwipeDirection", "Track swipe direction", .huds, ["reverse", "reversed", "standard", "swipe"]),
        .init("huds.notchClick", "On notch click", .huds, ["click", "media widget", "open media", "player"]),
        .init("huds.playbackButtons", "Playback buttons", .huds,
              ["shuffle", "repeat", "left button", "right button", "favorite", "heart", "media widget"]),
        .init("huds.filterSources", "Filter media sources", .huds, ["sources", "apps", "browser", "ignore", "allow"]),
        .init("huds.builtInSpeakers", "Always use built-in speakers", .huds,
              ["audio output", "speakers", "headphones", "airpods", "default output", "keep sound"]),
        .init("huds.hideIncognito", "Hide Incognito media", .huds, ["incognito", "private", "private browsing", "chrome"]),
        .init("huds.playbackKeys", "Playback keys", .huds,
              ["media keys", "play pause", "next", "previous", "f8", "keyboard", "default app"]),
        .init("huds.droplets", "Droplet HUDs", .huds,
              ["meetings", "pomodoro", "calendar", "notifications", "high alert", "terminotch", "agents", "set up"]),
        .init("huds.keySound", "Key sound", .huds, ["feedback", "pop", "volume sound", "beep", "click"]),
        .init("huds.desktopVolume", "Desktop volume slider", .huds, ["desktop", "slider", "volume", "widget"]),
        .init("huds.desktopBrightness", "Desktop brightness slider", .huds, ["desktop", "slider", "brightness", "widget"]),
        .init("huds.keyTarget", "Media key target", .huds,
              ["brightness keys", "which display", "under pointer", "main macbook", "external brightness"]),
        .init("huds.betterDisplay", "BetterDisplay integration", .huds, ["betterdisplay", "ddc", "external brightness", "monitor"]),
        .init("huds.autoBrightness", "Automatic brightness HUD", .huds, ["ambient", "auto brightness", "true tone", "brightness"]),
        .init("huds.keyboardKeys", "Keyboard brightness keys", .huds, ["keyboard", "backlight", "illumination", "keys"]),
        .init("huds.backlightShortcuts", "Keyboard backlight shortcuts", .huds,
              ["brighten", "dim", "keyboard", "backlight", "shortcut", "hotkey"]),
        .init("huds.liveActivities", "Live Activities", .huds, ["meeting", "countdown", "downloads"]),
        .init("huds.volume", "Volume HUD style", .huds, ["volume", "sound", "osd", "hud", "media keys", "scroll volume", "meter"]),
        .init("huds.brightness", "Brightness HUD style", .huds, ["brightness", "display", "osd", "hud", "dim", "meter"]),
        // Theming
        .init("theming.notched", "Notched display surface", .theming,
              ["surface", "dynamic glass", "black", "notch", "transparency", "glass"]),
        .init("theming.notchless", "Notchless display surface", .theming,
              ["surface", "dynamic glass", "black", "liquid glass", "external", "transparency", "tinted"]),
        .init("theming.outline", "Subtle outline", .theming, ["outline", "border", "hairline", "stroke", "resting state"]),
        .init("theming.solidSettings", "Solid background", .theming,
              ["solid settings background", "opaque", "no transparency", "settings window", "glass off"]),
        .init("theming.glow", "Border glow", .theming, ["glow", "sheen", "halo", "hover"]),
        .init("theming.fillet", "Notch corner fillet", .theming, ["corner", "fillet", "radius", "ears"]),
        .init("theming.mediaHUD", "Media HUD position", .theming,
              ["vertical position", "offset", "floating pill", "media hud", "move down"]),
        .init("theming.highlight", "Highlight color", .theming,
              ["accent", "highlight", "color", "colour", "custom color", "hex", "tint"]),
        .init("theming.windowTint", "Window tint", .theming, ["tint", "window", "glass", "background color"]),
        .init("theming.volumeColor", "Volume slider color", .theming, ["volume", "meter", "slider", "color", "decibel"]),
        .init("theming.brightnessColor", "Brightness slider color", .theming, ["brightness", "meter", "slider", "color"]),
        // Accessibility
        .init("a11y.rightClickHide", "Right-click to hide", .accessibility, ["hide notch", "hide island", "context menu", "hide"]),
        .init("a11y.rightClickReveal", "Right-click to reveal", .accessibility, ["show notch", "reveal", "unhide"]),
        .init("a11y.holdReveal", "Hold to reveal", .accessibility, ["modifier", "hold", "hidden", "reveal", "peek"]),
        .init("a11y.haptics", "Haptic feedback", .accessibility, ["haptic", "vibration", "tactile", "force touch", "trackpad"]),
        .init("a11y.sounds", "Sound effects", .accessibility, ["sound", "tick", "audio feedback", "clicks"]),
        .init("a11y.tooltips", "Show tooltips", .accessibility, ["tooltip", "hover help", "help tags", "hints", "popups"]),
        .init("a11y.screenshots", "Hide from screenshots", .accessibility,
              ["screenshot", "screen sharing", "screen recording", "capture", "privacy", "zoom"]),
        // About
        .init("about.version", "Version", .about, ["version", "build", "update"]),
        .init("about.changelog", "Changelog", .about, ["changelog", "history", "what's new", "release notes"]),
        .init("about.intro", "Introduction", .about, ["onboarding", "welcome tour", "tutorial", "replay"]),
        .init("about.privacy", "Privacy", .about, ["tracking", "analytics", "on-device", "online features", "data"]),
        .init("about.hardReset", "Hard reset", .about, ["reset", "reset everything", "factory reset", "defaults", "restore"]),
        .init("about.transfer", "Transfer settings", .about, ["export", "import", "backup", "settings file", "new mac", "json"]),
        .init("about.whatsNew", "What's New", .about, ["new features", "bug fixes", "release notes", "update", "changes"]),
        .init("about.userGuide", "Tama Guide", .about,
              ["user guide", "guide", "help", "manual", "how to", "documentation", "handbook", "instructions", "tutorial", "learn"]),
        .init("about.setupGuide", "Setup Guide", .about, ["recommended setup", "checklist", "one-time setup", "getting started", "onboarding"]),
        .init("about.crashReport", "Tell me after a crash", .about,
              ["crash", "crashed", "crash report", "diagnostic report", "ips", "bug report", "report a bug"]),
        .init("about.lastCrash", "Last crash report", .about,
              ["crash", "crash report", "copy crash report", "diagnosticreports", "quit unexpectedly"]),
        .init("about.logging", "Diagnostic logging", .about,
              ["logs", "debug", "verbose", "troubleshooting", "write detailed logs", "diagnostics", "bug report"]),
        .init("about.exportLogs", "Export logs", .about, ["logs", "report", "support", "diagnostics", "send logs", "crash"]),
        // LocalSend droplet
        .init("droplet.localSend.name", "LocalSend device name", .droplets,
              ["localsend", "device name", "alias", "reset to this mac's name", "computer name"]),
        .init("droplet.localSend.visible", "Visible to other devices", .droplets,
              ["localsend", "discoverable", "announce", "nearby", "multicast", "hidden"]),
        .init("droplet.localSend.receive", "Receive from", .droplets,
              ["localsend", "receive from anyone", "favorites", "incoming", "accept", "receive files"]),
        .init("droplet.localSend.quickSave", "Quick Save for favorites", .droplets, ["localsend", "auto accept", "favorites", "no prompt"]),
        .init("droplet.localSend.pin", "LocalSend PIN", .droplets, ["localsend", "pin", "password", "code", "security"]),
        .init("droplet.localSend.folder", "Save received files to", .droplets,
              ["localsend", "save location", "download folder", "received files", "destination"]),
        .init("droplet.localSend.shelf", "Add received files to the shelf", .droplets, ["localsend", "tray", "shelf", "received"]),
        .init("droplet.localSend.encrypted", "Encrypted (HTTPS)", .droplets,
              ["localsend", "https", "tls", "certificate", "fingerprint", "encryption", "http", "transfer security"]),
        .init("droplet.localSend.favorites", "LocalSend favorites", .droplets,
              ["localsend", "forget this device", "favorite devices", "known devices", "trusted"]),
        .init("droplet.localSend.browser", "Share in a browser", .droplets,
              ["localsend", "browser", "web", "download", "web page", "share link", "no app", "phone", "v1", "older devices"]),
    ] + AppState.defaultDroplets.map { droplet in
        // Each droplet page's "Shortcut to open".
        .init("droplet.\(droplet.id).openShortcut", "Shortcut to open \(droplet.name)", .droplets,
              ["widget shortcut", "hotkey", "open", droplet.name.lowercased()])
    } + AppState.defaultDroplets.map { droplet in
        .init("droplet.\(droplet.id).sidebar", "Show \(droplet.name) in Settings sidebar", .droplets,
              ["sidebar", "settings sidebar", "enabled droplets", droplet.name.lowercased()])
    }

    static func search(_ query: String) -> [SettingsSearchEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return entries.filter { $0.matches(q) }.sorted { $0.score(q) < $1.score(q) }
    }

    /// `text` with every occurrence of each query word drawn in `color`
    /// and bold, so a result shows why it matched.
    static func highlighted(_ text: String, query: String, color: Color) -> AttributedString {
        var result = AttributedString(text)
        for word in query.split(whereSeparator: \.isWhitespace) {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<text.endIndex) {
                if let range = Range(found, in: result) {
                    result[range].foregroundColor = color
                    result[range].inlinePresentationIntent = .stronglyEmphasized
                }
                searchStart = found.upperBound
            }
        }
        return result
    }
}

// MARK: - Navigation

/// Which page Settings shows, and the row search wants scrolled to and
/// flashed. Shared, so anything (About, the onboarding) can open a page.
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published var page: SettingsPage = .general
    /// The droplet whose detail page the Droplets store shows, if any.
    @Published var openDropletID: String?
    /// Anchor to scroll to once the page is on screen.
    @Published var scrollTarget: String?
    /// Anchor drawn with a highlight for a moment.
    @Published private(set) var highlighted: String?
    private var clearHighlight: DispatchWorkItem?

    func open(_ page: SettingsPage) {
        self.page = page
        openDropletID = nil
    }

    func reveal(_ entry: SettingsSearchEntry) {
        open(entry.page)
        // "droplet.<id>.…": the option lives on that droplet's page.
        if entry.anchor.hasPrefix("droplet.") {
            openDropletID = entry.anchor.dropFirst("droplet.".count).split(separator: ".").first.map(String.init)
        }
        scrollTarget = entry.anchor
        highlighted = entry.anchor
        clearHighlight?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.5)) { self?.highlighted = nil }
        }
        clearHighlight = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

/// Marks a row as a search target: gives it a stable scroll id and flashes an
/// accent wash when search jumps to it.
private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var state = AppState.shared

    func body(content: Content) -> some View {
        let isLit = navigator.highlighted == anchor
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(state.accentColor.color.opacity(isLit ? 0.22 : 0))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(state.accentColor.color.opacity(isLit ? 0.7 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.25), value: isLit)
            .id(anchor)
    }
}

extension View {
    /// A search target (see `SettingsSearchIndex`); nil leaves the view alone.
    @ViewBuilder
    func settingsAnchor(_ anchor: String?) -> some View {
        if let anchor {
            modifier(SettingsAnchorModifier(anchor: anchor))
        } else {
            self
        }
    }
}
