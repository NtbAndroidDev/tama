import SwiftUI

// MARK: - Model

/// One block of an article. Everything the guide can draw is here, so an
/// article stays a plain description of itself and `GuideArticleView` is the
/// only place that knows what a step or a key row looks like.
enum GuideBlock: Identifiable {
    /// A paragraph.
    case text(String)
    /// A bulleted list.
    case bullets([String])
    /// A numbered walkthrough.
    case steps([String])
    /// A card of fixed keys: the thing on the left, the keys on the right.
    case keyTable([GuideKey])
    /// A card of recordable shortcuts, drawn with whatever they are set to now.
    case shortcutTable([ShortcutAction])
    /// A card of links that open Settings on the row they name.
    case settings([GuideSettingLink])
    /// A highlighted aside.
    case tip(String)
    /// An aside for what can go wrong.
    case caution(String)

    var id: String { plainText }

    /// Everything a reader could search for in this block.
    var plainText: String {
        switch self {
        case .text(let s), .tip(let s), .caution(let s): s
        case .bullets(let items), .steps(let items): items.joined(separator: " ")
        case .keyTable(let keys): keys.map { "\($0.title) \($0.keys)" }.joined(separator: " ")
        case .shortcutTable(let actions): actions.map(\.title).joined(separator: " ")
        case .settings(let links): links.map(\.title).joined(separator: " ")
        }
    }
}

struct GuideKey: Hashable {
    let title: String
    let keys: String
    init(_ title: String, _ keys: String) {
        self.title = title
        self.keys = keys
    }
}

/// A jump into Settings. `anchor` is a `SettingsSearchIndex` anchor, so the
/// row is scrolled to and highlighted exactly as a search hit is.
struct GuideSettingLink: Hashable {
    let title: String
    let anchor: String
    init(_ title: String, _ anchor: String) {
        self.title = title
        self.anchor = anchor
    }
}

struct GuideSection: Identifiable {
    let title: String
    let blocks: [GuideBlock]
    var id: String { title }

    init(_ title: String, _ blocks: [GuideBlock]) {
        self.title = title
        self.blocks = blocks
    }
}

enum GuideCategory: String, CaseIterable, Identifiable {
    case start = "Start here"
    case surface = "The notch"
    case files = "Files"
    case clipboard = "Clipboard"
    case media = "Media"
    case productivity = "Productivity"
    case tools = "Tools"
    case reference = "Reference"

    var id: Self { self }
}

struct GuideArticle: Identifiable, Equatable {
    let id: String
    let category: GuideCategory
    let icon: String
    let title: String
    /// One line under the title, and the subtitle in the sidebar.
    let summary: String
    let sections: [GuideSection]

    static func == (a: GuideArticle, b: GuideArticle) -> Bool { a.id == b.id }

    /// Title, summary and every block, for the sidebar's search field.
    var searchText: String {
        ([title, summary, category.rawValue]
            + sections.flatMap { [$0.title] + $0.blocks.map(\.plainText) })
            .joined(separator: " ")
            .lowercased()
    }

    func matches(_ query: String) -> Bool {
        let haystack = searchText
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains($0) }
    }
}

// MARK: - The guide

enum DroppyGuide {
    /// Every article, in the order the sidebar lists them.
    static let articles: [GuideArticle] = [
        basics, permissions, surface, huds, tray, basket, sharing, clipboard,
        player, calendar, focus, capture, droplets, shortcuts, troubleshooting,
    ]

    static func article(_ id: String) -> GuideArticle? { articles.first { $0.id == id } }

    static func articles(in category: GuideCategory) -> [GuideArticle] {
        articles.filter { $0.category == category }
    }

    // MARK: Start here

    private static let basics = GuideArticle(
        id: "basics", category: .start, icon: "hand.wave.fill",
        title: "Tama in a minute",
        summary: "What the notch does, and how to open it",
        sections: [
            GuideSection("The resting notch", [
                .text("Tama lives at the top of the screen. At rest it hugs the hardware notch — or draws a small floating pill on a Mac without one — and only grows two wings when it has something to say: album art and a music wave while something plays, the number of files you are holding, a running timer, a charger going in."),
                .text("Clicking the wave plays or pauses. Double-clicking the notch does the same. A two-finger scroll on it changes the volume, and ⌥-scroll changes the brightness."),
            ]),
            GuideSection("Opening the shelf", [
                .text("Click the notch and it unfolds into the shelf: one page at a time, with a small capsule underneath to switch pages."),
                .keyTable([
                    GuideKey("Open or close the shelf", "Click the notch"),
                    GuideKey("Close it", "Esc"),
                    GuideKey("Switch page (shelf focused)", "⌘1 ⌘2 ⌘3 ⌘4"),
                    GuideKey("The menu", "Right-click the notch"),
                ]),
                .shortcutTable([.toggleIsland]),
                .tip("Hover-to-open is off to begin with, so the shelf only opens when you ask. Turn it on in Settings › Shelf if you would rather it opened by itself."),
                .settings([
                    GuideSettingLink("How the shelf opens and closes", "shelf.behavior"),
                    GuideSettingLink("Which page it opens on", "shelf.pages"),
                ]),
            ]),
            GuideSection("The four pages", [
                .bullets([
                    "**Player** — what is playing, with artwork, a scrubber, lyrics and the output picker.",
                    "**Tray** — the files you have dropped on the notch.",
                    "**Widgets** — your Droplets: timers, capture, notes, terminal, weather and the rest.",
                    "**Calendar** — today's events and reminders, and a field to add one.",
                ]),
                .text("The capsule under the shelf switches between them. Which pages appear, and which one opens first, are in Settings › Shelf."),
            ]),
            GuideSection("Where everything lives", [
                .bullets([
                    "The **menu bar icon** opens the same pages, the clipboard and Settings.",
                    "**Right-clicking the notch** does too, without leaving what you are doing.",
                    "The **clipboard** slides up from the bottom of the screen, not out of the notch.",
                    "A **Basket** floats over every Space, for carrying files between windows.",
                ]),
                .settings([GuideSettingLink("Menu bar and Dock icons", "general.startup")]),
            ]),
        ])

    private static let permissions = GuideArticle(
        id: "permissions", category: .start, icon: "lock.shield.fill",
        title: "Permissions",
        summary: "What macOS asks for, and why",
        sections: [
            GuideSection("Grant them as you need them", [
                .text("Tama asks for nothing at launch. Each permission is asked for by the first feature that needs it, and Settings › General shows every one of them live, with Allow, Open Settings and a Reset for a grant macOS has gone stale on."),
                .settings([GuideSettingLink("Permissions overview", "general.permissions")]),
            ]),
            GuideSection("What each one is for", [
                .bullets([
                    "**Accessibility** — pasting a clip with ⌘V, Window Snap, the media keys for browser playback, and hiding the macOS volume and brightness HUDs. On macOS 27 this list is called *Device Control and Data Access*.",
                    "**Automation** — reading and controlling Music, Spotify and browser tabs. Each app is asked for separately.",
                    "**Screen Recording** — snips, screenshots and the capture editor.",
                    "**Calendars & Reminders** — the Calendar page and the next-meeting countdown.",
                    "**Notifications** — Pomodoro, timers and due reminders.",
                    "**Microphone & Speech Recognition** — Voice Transcribe and the meeting mic level.",
                    "**Input Monitoring** — Mechey's keyboard sounds, and nothing else. Keystrokes are never stored.",
                    "**Full Disk Access** — reading the notification store for the Notification HUD.",
                    "**Camera** — Notchface.",
                ]),
            ]),
            GuideSection("If a permission stops working", [
                .text("macOS ties a grant to the exact signature of the app. A rebuilt Tama that is only ad-hoc signed looks like a different app, so Accessibility, Automation and Screen Recording are dropped."),
                .text("Use Reset on the row in Settings › General, then allow it again. Reset also explains the extra step Automation needs, since macOS has no way for an app to re-ask."),
            ]),
        ])

    // MARK: The notch

    private static let surface = GuideArticle(
        id: "surface", category: .surface, icon: "macbook",
        title: "Shape, style and displays",
        summary: "Notch or island, surfaces, and which screens Tama uses",
        sections: [
            GuideSection("Notch or Island", [
                .text("**Notch** carves Tama out of the black around the hardware notch. **Island** floats a rounded pill just below the top edge. A display that has a notch always uses the notch; for displays that don't — an external monitor, or a Mac without one — you choose which of the two they get."),
                .text("The surface itself is set separately for the two kinds of display: solid black, black fading into Liquid Glass, or tinted glass."),
                .settings([
                    GuideSettingLink("Style for displays without a notch", "huds.displayStyle"),
                    GuideSettingLink("Surface on a notched display", "theming.notched"),
                    GuideSettingLink("Surface on a display without a notch", "theming.notchless"),
                    GuideSettingLink("Hide the physical notch", "huds.hideNotch"),
                ]),
            ]),
            GuideSection("Surface and motion", [
                .text("A subtle outline keeps a black surface visible against a dark wallpaper, and can stay on while the notch is resting."),
                .text("Motion has a style — Dynamic Island, Snappy, Gentle, Minimal — and a separate speed, so you can keep the feel and just make it quicker. Under Reduce Motion everything becomes instant."),
                .settings([
                    GuideSettingLink("Subtle outline", "theming.outline"),
                    GuideSettingLink("Animation style", "shelf.motion"),
                    GuideSettingLink("Animation speed", "shelf.speed"),
                    GuideSettingLink("Shelf size", "shelf.size"),
                ]),
            ]),
            GuideSection("More than one screen", [
                .text("Tama can follow the screen your pointer is on, stay on the built-in display, mirror onto every screen, or appear only on the ones you tick. Each external display can be told to keep its surface visible when nothing is playing, or to stay out of the way."),
                .settings([
                    GuideSettingLink("Which displays show Tama", "huds.targetDisplay"),
                    GuideSettingLink("Per-display visibility", "huds.perDisplay"),
                    GuideSettingLink("Keep external surfaces visible", "huds.showWhenIdle"),
                ]),
            ]),
            GuideSection("Getting it out of the way", [
                .bullets([
                    "**In fullscreen** — show everything, hide just the media surface, or hide all of it.",
                    "**In Mission Control** — hide while Mission Control or App Exposé is open.",
                    "**Hide from screenshots** — leave the notch out of screenshots and screen shares.",
                    "**Hold to reveal** — keep it hidden until you hold a modifier.",
                    "**Hide Notch** in the right-click menu, and right-click the empty silhouette to bring it back.",
                ]),
                .settings([
                    GuideSettingLink("In fullscreen", "huds.fullscreen"),
                    GuideSettingLink("Hide in Mission Control", "huds.missionControl"),
                    GuideSettingLink("Hide from screenshots", "a11y.screenshots"),
                ]),
            ]),
        ])

    private static let huds = GuideArticle(
        id: "huds", category: .surface, icon: "speaker.wave.2.fill",
        title: "HUDs and Live Activities",
        summary: "Volume, brightness, battery and what's happening now",
        sections: [
            GuideSection("Volume and brightness", [
                .text("The volume and brightness keys spread their level into the notch wings. Each has its own duration, meter style — white, your accent, or *Decibel*, which runs green to red — percentage, label and animation speed."),
                .text("Turn on **Hide the macOS HUD** and Tama handles those keys itself: the same 1/16 steps, ⌥⇧ for finer ones, the same feedback sound, but only the notch shows it. Outputs with a fixed volume, and displays macOS will not let Tama dim, keep the system HUD."),
                .settings([
                    GuideSettingLink("Volume HUD", "huds.volume"),
                    GuideSettingLink("Brightness HUD", "huds.brightness"),
                    GuideSettingLink("Scroll on the notch", "shelf.scrollAction"),
                ]),
            ]),
            GuideSection("Live Activities", [
                .text("The resting wings also carry what is happening now: the countdown to your next meeting with a **Join** button, a charger going in, a low or full battery, AirPods connecting, a running timer or Pomodoro, a download in progress, a VPN session, an agent still working."),
                .text("Urgent ones take over from music for a moment and then hand it back. Each kind can be switched off on its own."),
                .settings([
                    GuideSettingLink("Live Activities", "huds.liveActivities"),
                    GuideSettingLink("Several at once", "shelf.multiLive"),
                ]),
                .shortcutTable([.toggleLiveActivity]),
            ]),
            GuideSection("The lock screen", [
                .text("Tama can draw its own lock screen over the macOS one: the player, the weather, your next event, battery and headphones, with volume and brightness sliders. It is off until you turn it on."),
                .settings([GuideSettingLink("Lock screen", "lock.enable")]),
            ]),
        ])

    // MARK: Files

    private static let tray = GuideArticle(
        id: "tray", category: .files, icon: "tray.full.fill",
        title: "The Tray",
        summary: "Dropping files on the notch, and what you can do with them",
        sections: [
            GuideSection("Dropping something", [
                .steps([
                    "Start dragging a file anywhere — Finder, a browser, Mail.",
                    "Move the pointer onto the notch. It unfolds into four tiles.",
                    "Release on the tile you want: **Keep** holds it in the Tray, **Share Link**, **AirDrop** and **Convert** act on it straight away.",
                ]),
                .text("Which tiles appear, and in what order, is up to you — iCloud Drive, Mail, Messages, ZIP Hover and QuickShare can take a slot."),
                .settings([
                    GuideSettingLink("Quick Action tiles", "general.quickActionTiles"),
                    GuideSettingLink("Open the Tray after a drop", "shelf.openTrayAfterDrop"),
                ]),
            ]),
            GuideSection("Working with held files", [
                .text("The Tray page is a rail of tiles with names underneath. Click to select, double-click to open, drag out into any app. The round buttons in the corner share, convert, zip and clear."),
                .text("Right-click a file for everything else: Quick Look, reveal in Finder, copy the path, rename, tag, move, extract text with OCR, edit a screenshot, convert to another format, compress to a target size."),
                .keyTable([
                    GuideKey("Move through the files", "← → ↑ ↓"),
                    GuideKey("Extend the selection", "⇧ + arrows"),
                    GuideKey("Select all", "⌘A"),
                    GuideKey("Quick Look", "Space"),
                    GuideKey("Open", "Return"),
                    GuideKey("Copy", "⌘C"),
                    GuideKey("Remove (undoable)", "⌫"),
                    GuideKey("Undo the removal", "⌘Z"),
                    GuideKey("Move somewhere", "⇧⌘M"),
                ]),
                .tip("Removing a file from the Tray never deletes it. Snips, conversions and archives Tama made are kept in its own folder so they survive a restart."),
            ]),
            GuideSection("Converting and compressing", [
                .text("Right-click a file › Convert. What is offered depends on the file: images to PNG, JPEG, HEIC, GIF, TIFF or PDF; PDFs to images per page or to text; video to MP4, MOV, GIF or M4A; documents to PDF, TXT, RTF, HTML or DOCX."),
                .text("A few formats need a helper: WebP needs `cwebp`, video needs `ffmpeg`, heavy PDF compression needs Ghostscript, Office files need LibreOffice. Settings › General › Helper tools installs them with Homebrew and shows what is already there."),
                .caution("Conversions keep running when the shelf closes. A progress ring in the notch follows them, and cancelling removes the partial file."),
                .settings([
                    GuideSettingLink("Helper tools", "general.helperTools"),
                    GuideSettingLink("Where converted files go", "general.convertDestination"),
                    GuideSettingLink("Smart Export", "general.smartExport"),
                ]),
            ]),
            GuideSection("Files that arrive by themselves", [
                .text("**Tracked folders** watch a folder and act on anything new: add it to the Tray, add it to a Basket, or add and compress it. **Finder Services** put *Add to Tama Tray* and *Extract Text with Tama* in the right-click menu of any file, and *Send to Tama Scratchpad* under selected text."),
                .settings([
                    GuideSettingLink("Tracked folders", "general.trackedFolders"),
                    GuideSettingLink("Finder Services", "general.finderServices"),
                ]),
                .shortcutTable([.snipToTray]),
            ]),
        ])

    private static let basket = GuideArticle(
        id: "basket", category: .files, icon: "basket.fill",
        title: "The floating Basket",
        summary: "A tray that follows you across Spaces",
        sections: [
            GuideSection("Summoning one", [
                .bullets([
                    "**Shake a drag.** Start dragging a file, shake it, and a Basket flies in to catch it.",
                    "**Ask for one.** The shortcut below, the menu bar, or the notch's right-click menu.",
                    "**Send from the Tray.** Right-click held files › Move to Basket.",
                ]),
                .shortcutTable([.toggleBasket, .basketSwitcher]),
                .settings([
                    GuideSettingLink("Shake to open", "basket.shake"),
                    GuideSettingLink("How hard to shake", "basket.sensitivity"),
                    GuideSettingLink("Basket mode", "basket.mode"),
                ]),
            ]),
            GuideSection("Using it", [
                .text("A Basket floats over every window and every Space. Drag files in, drag them out one at a time, or use **Drag all** to carry the lot. Minimised, it becomes a small pill that still takes drops."),
                .text("It takes the keyboard when you click it — its outline brightens to say so — and hands it straight back when you click another app."),
                .keyTable([
                    GuideKey("Move, extend, select all", "arrows · ⇧ + arrows · ⌘A"),
                    GuideKey("Quick Look · Open · Copy", "Space · Return · ⌘C"),
                    GuideKey("Remove (undoable)", "⌫"),
                    GuideKey("Move the files somewhere", "⇧⌘M"),
                    GuideKey("Send the selection to the Shelf", "⌘↑"),
                    GuideKey("Minimise to the pill", "⌘M"),
                    GuideKey("Put the Basket away", "⌘W"),
                ]),
                .tip("A Basket can hide itself after a while of being ignored, and come back the moment you drag something. Both are in Settings › Basket."),
            ]),
        ])

    private static let sharing = GuideArticle(
        id: "sharing", category: .files, icon: "paperplane.fill",
        title: "Sharing files",
        summary: "AirDrop, a link on your Wi-Fi, and LocalSend",
        sections: [
            GuideSection("Share Link", [
                .text("Tama serves the files you picked from a small web server on your Mac, behind a random-token link and a QR code. A phone on the same Wi-Fi can scan it and download them. Nothing is uploaded anywhere."),
                .text("The link stops after 15 minutes, after an hour, or when Tama quits — whichever you chose when you made it."),
            ]),
            GuideSection("AirDrop and the rest", [
                .text("**AirDrop** hands the files to the system sheet. **iCloud Drive** copies them there and reveals the copy. **Mail** and **Messages** open a new message with them attached. **QuickShare** uploads to 0x0.st and copies the link back, and asks first unless you tell it not to."),
                .settings([
                    GuideSettingLink("Ask before uploading", "general.quickshareConfirm"),
                    GuideSettingLink("Recent uploads", "general.uploads"),
                    GuideSettingLink("Mail app", "general.mailApp"),
                ]),
            ]),
            GuideSection("LocalSend", [
                .text("The LocalSend droplet talks to the LocalSend app on phones and other computers on the same network. It can receive automatically, ask each time, or ask only for devices you have not saved; a PIN and encryption are optional, and **Share in a browser** hands a plain download page to a device with no app installed."),
                .settings([
                    GuideSettingLink("Device name", "droplet.localSend.name"),
                    GuideSettingLink("How incoming files are handled", "droplet.localSend.receive"),
                    GuideSettingLink("Where they are saved", "droplet.localSend.folder"),
                ]),
            ]),
        ])

    // MARK: Clipboard

    private static let clipboard = GuideArticle(
        id: "clipboard", category: .clipboard, icon: "doc.on.clipboard.fill",
        title: "The clipboard",
        summary: "History, pinboards, search and privacy",
        sections: [
            GuideSection("Opening it", [
                .text("The clipboard is its own shelf, docked to the bottom of the screen: a row of cards for text, links, code, colors, images and files copied in Finder, each with a chip naming the app it came from."),
                .shortcutTable([.toggleClipboard, .pasteFromClipboard]),
                .keyTable([
                    GuideKey("Move between clips", "← →"),
                    GuideKey("Paste into the app underneath", "Return"),
                    GuideKey("Copy", "⌘C"),
                    GuideKey("Remove", "⌫"),
                    GuideKey("Search", "⌘F"),
                    GuideKey("Close", "Esc"),
                ]),
                .caution("Return-to-paste presses ⌘V for you, which needs Accessibility. Without it the clip is copied and Tama tells you to paste yourself."),
            ]),
            GuideSection("Finding things again", [
                .text("⌘F searches the text of every clip — and the words *inside* images, because each image clip is read with on-device text recognition when it arrives. A screenshot of an error message is findable by the error."),
                .text("**Pinboards** are tabs of your own: add one with **+**, then drag a card onto a tab to file it. Pinboard clips survive Clear History. Starring a card keeps it at the front, and double-clicking its chip renames it."),
                .settings([
                    GuideSettingLink("Layout", "clipboard.layout"),
                    GuideSettingLink("Favourites bar", "clipboard.favoritesBar"),
                    GuideSettingLink("Tags", "clipboard.tags"),
                ]),
            ]),
            GuideSection("Privacy", [
                .bullets([
                    "Anything a password manager marks concealed is never recorded, and password managers are excluded by default.",
                    "**Pause** recording for five minutes, an hour, or until you start it again.",
                    "**Skip sensitive** leaves out anything shaped like a card number, a private key, an AWS key or a token.",
                    "**Blur sensitive** keeps the clip but hides it until you ask to see it.",
                    "History can be kept forever or for 1, 7 or 30 days, and cleared on quit.",
                ]),
                .text("Everything stays on your Mac. Clearing history can be undone from the banner, so the images behind cleared clips are tidied up later rather than straight away."),
                .settings([
                    GuideSettingLink("Recording and pause", "clipboard.recording"),
                    GuideSettingLink("Privacy filters", "clipboard.privacy"),
                    GuideSettingLink("Excluded apps", "clipboard.excluded"),
                    GuideSettingLink("How long history is kept", "clipboard.retention"),
                ]),
            ]),
        ])

    // MARK: Media

    private static let player = GuideArticle(
        id: "player", category: .media, icon: "play.circle.fill",
        title: "The player",
        summary: "Music, Spotify, browser tabs, lyrics and outputs",
        sections: [
            GuideSection("What it can control", [
                .text("Apple Music and Spotify are controlled fully — play, skip, scrub, artwork, and favouriting in Music. Browser tabs that are playing audio are picked up from Safari, Chrome, Brave, Edge, Arc, Vivaldi and Opera, with titles from YouTube, YouTube Music, SoundCloud and Spotify Web."),
                .text("For a browser tab, turning on *Allow JavaScript from Apple Events* (Chromium: View › Developer; Safari: Develop) lets Tama read the real position and scrub it. Without it, Tama falls back to the media keys, which need Accessibility."),
                .shortcutTable([.openPlayer]),
                .settings([
                    GuideSettingLink("Default music app", "huds.defaultMusicApp"),
                    GuideSettingLink("Which sources to follow", "huds.filterSources"),
                ]),
            ]),
            GuideSection("Lyrics and what's next", [
                .text("Synced lyrics come from LRCLIB and follow the song; tapping a line jumps there. It is off until you turn it on, because the title and artist have to be sent to look them up."),
                .text("**Playing Next** lists the rest of the current Apple Music playlist; tapping a track plays it. Spotify and browsers do not expose a queue."),
                .settings([GuideSettingLink("Lyrics online", "shelf.player")]),
            ]),
            GuideSection("Output and volume", [
                .text("The speaker button folds out every output CoreAudio can see — built-in speakers, AirPlay, Bluetooth, displays — with the current one showing its volume as a soft fill. **Always use built-in speakers** puts sound back on the Mac when a device disconnects."),
                .settings([
                    GuideSettingLink("Now Playing size", "huds.nowPlayingSize"),
                    GuideSettingLink("Visualizer", "huds.visualizer"),
                    GuideSettingLink("Always use built-in speakers", "huds.builtInSpeakers"),
                ]),
            ]),
        ])

    // MARK: Productivity

    private static let calendar = GuideArticle(
        id: "calendar", category: .productivity, icon: "calendar",
        title: "Tasks & Calendar",
        summary: "Events, reminders and the meeting countdown",
        sections: [
            GuideSection("The page", [
                .text("A month grid with today circled, and an agenda of events and reminders from the calendars you choose. Tapping a reminder's ring completes it."),
                .text("**New Task** understands dates as you write them: \"Call Sam tomorrow at 5pm\" becomes a reminder due then."),
                .settings([
                    GuideSettingLink("What the agenda shows", "shelf.tasks.show"),
                    GuideSettingLink("Which calendars", "shelf.tasks.calendars"),
                    GuideSettingLink("Which reminder lists", "shelf.tasks.lists"),
                ]),
            ]),
            GuideSection("Meetings", [
                .text("The next event counts down in the resting notch, and when it starts a **Join** button opens the Zoom, Meet, Teams or Webex link from the invitation."),
                .text("The Meetings droplet can also pause what you are playing when a call starts — or when you unmute — and start it again afterwards, and show the call's length and your live mic level."),
                .settings([
                    GuideSettingLink("Next event in the wing", "shelf.tasks.nextEvent"),
                    GuideSettingLink("Pause media during meetings", "droplet.meetings.pause"),
                ]),
            ]),
        ])

    private static let focus = GuideArticle(
        id: "focus", category: .productivity, icon: "timer",
        title: "Focus, timers and staying awake",
        summary: "Pomodoro, Timer, High Alert",
        sections: [
            GuideSection("Pomodoro", [
                .text("Focus and break sessions — 25 and 5 minutes to start with — with a banner in the notch, a notification and a chime at each switch. An ambient sound can play while you focus, and a Shortcut can run at the start and end of each session."),
                .text("**Momentum** counts the sessions you finish each day and the days you keep it going."),
                .settings([
                    GuideSettingLink("Pomodoro", "shelf.pomodoro"),
                    GuideSettingLink("Ambient sound", "shelf.pomodoro.ambient"),
                    GuideSettingLink("Momentum", "shelf.pomodoro.momentum"),
                ]),
            ]),
            GuideSection("Timer and Stopwatch", [
                .text("A countdown with presets and ±1 minute, or a stopwatch with laps. Either one stays in the notch while it runs, so you can see it without opening anything."),
            ]),
            GuideSection("High Alert", [
                .text("Keeps the Mac and its screen awake, indefinitely or for a set time, using the system's own sleep assertions."),
                .caution("**Lid Closed** is the one mode that stops a closed MacBook sleeping at all. On battery, in a bag, that means it gets hot and flat — so Tama warns you when you start it on battery, and ends it by itself the moment the charger comes out."),
                .settings([GuideSettingLink("High Alert mode", "shelf.highAlert.mode")]),
            ]),
        ])

    // MARK: Tools

    private static let capture = GuideArticle(
        id: "capture", category: .tools, icon: "camera.viewfinder",
        title: "Capture, the editor and OCR",
        summary: "Snips, annotation and reading text off the screen",
        sections: [
            GuideSection("Taking a capture", [
                .text("Capture an area, a window, the whole screen, a single interface element, or text straight off the screen. Each mode can have its own shortcut."),
                .shortcutTable([.snipToTray, .captureArea, .captureWindow, .captureFullscreen, .captureElement, .captureOCR]),
                .settings([
                    GuideSettingLink("Capture shortcuts", "droplet.snipper.shortcuts"),
                    GuideSettingLink("Where captures go", "droplet.snipper.destinations"),
                    GuideSettingLink("Screenshot preview", "droplet.snipper.preview"),
                ]),
            ]),
            GuideSection("The editor", [
                .text("A capture can open straight into the editor: arrow, line, rectangle, ellipse, pen, highlighter, text, numbered steps, pixelate and blur — which change the real pixels, so a blurred password is gone — and crop, with undo and redo."),
                .text("**Beautify** puts the shot on a backdrop with padding, rounded corners and a shadow, at 16:9, 4:3 or 1:1. Copy it, save it as PNG or JPEG, add it to the Tray, or drag the result out. The original is never changed."),
                .tip("Right-click any image already in the Tray › **Edit Screenshot** to open it in the same editor."),
                .settings([
                    GuideSettingLink("Open the editor after a capture", "droplet.snipper.editor"),
                    GuideSettingLink("Default annotation color", "droplet.snipper.color"),
                    GuideSettingLink("Editor shortcuts", "droplet.snipper.editorShortcuts"),
                ]),
            ]),
            GuideSection("Reading text", [
                .text("Text recognition runs on your Mac. It reads images and PDFs — using a PDF's own text layer when it has one — and also finds QR codes and barcodes. In the Tray, right-click an image › Extract Text."),
                .settings([GuideSettingLink("Copy recognised text automatically", "droplet.ocr.autoCopy")]),
            ]),
        ])

    private static let droplets = GuideArticle(
        id: "droplets", category: .tools, icon: "puzzlepiece.extension.fill",
        title: "Droplets",
        summary: "The widgets on the Widgets page, and how to arrange them",
        sections: [
            GuideSection("Turning them on", [
                .text("Droplets are Tama's widgets. Settings › Droplets lists every one with what it does; switching one on puts it on the Widgets page and, where it has options, gives it a page of its own in the sidebar."),
                .text("The Widgets page shows five at a time — scroll, swipe, drag or click the dots to move between pages. Clicking one opens its console in place."),
                .settings([
                    GuideSettingLink("Droplets", "droplets.store"),
                    GuideSettingLink("Rearrange the icons", "shelf.widgetIcons"),
                    GuideSettingLink("Per-widget shortcuts", "shortcuts.widgets"),
                ]),
            ]),
            GuideSection("What's in the box", [
                .bullets([
                    "**Element Capture**, **OCR**, **AI Cutout** — screen capture, text recognition, background removal.",
                    "**Thunderstorm** — Spotlight search from the notch, with `kind:` and `ext:` filters.",
                    "**Ring** — a radial menu of up to eight actions at the pointer.",
                    "**Window Snap** — tile the focused window into halves, thirds, quarters, centre or fullscreen.",
                    "**Timer**, **Pomodoro**, **High Alert** — time and staying awake.",
                    "**Scratchpad**, **Notes**, **Obsidian** — writing things down, and sending them to a vault.",
                    "**Quick Math**, **Color Dropper**, **System Stats**, **Weather**.",
                    "**TermiNotch** — run zsh commands in the notch.",
                    "**Voice Transcribe** — record or transcribe on-device.",
                    "**Audio Control** — per-app volume up to 150 %.",
                    "**Meetings**, **Notification HUD**, **Agents**, **Notchface**, **LocalSend**, **Menu Bar Manager**, **Mechey**, **LiquidMouse**.",
                ]),
            ]),
            GuideSection("Getting to one quickly", [
                .text("A droplet can have its own shortcut that opens its console and closes it again. Some can also sit beside the shelf as a floating button, so they are one click away without opening the Widgets page."),
                .shortcutTable([.thunderstorm, .ring, .quickRecord]),
                .settings([
                    GuideSettingLink("Floating buttons", "shelf.widgetSettings"),
                    GuideSettingLink("Favourites beside the bar", "shelf.favorites"),
                ]),
            ]),
        ])

    // MARK: Reference

    private static let shortcuts = GuideArticle(
        id: "shortcuts", category: .reference, icon: "command",
        title: "Every shortcut",
        summary: "What is set right now, and the keys that don't change",
        sections: [
            GuideSection("Global shortcuts", [
                .text("These work anywhere. They are Carbon hot keys, so they need no permission and are not passed on to the app in front. Record your own in Settings › Keyboard Shortcuts — the list below always shows what is set right now."),
                .shortcutTable(ShortcutAction.allCases.filter { $0.group == .general || $0.group == .workspace }),
                .settings([GuideSettingLink("Record a shortcut", "shortcuts.all")]),
            ]),
            GuideSection("Capture", [
                .shortcutTable(ShortcutAction.allCases.filter { $0.group == .capture }),
            ]),
            GuideSection("Window Snap", [
                .shortcutTable(ShortcutAction.allCases.filter { $0.group == .windowSnap }),
            ]),
            GuideSection("Tools and HUDs", [
                .shortcutTable(ShortcutAction.allCases.filter { $0.group == .tools || $0.group == .huds }),
            ]),
            GuideSection("Keys that don't change", [
                .keyTable([
                    GuideKey("Close the shelf", "Esc"),
                    GuideKey("Switch shelf page", "⌘1 – ⌘4"),
                    GuideKey("Tray and Basket: move, extend, select all", "arrows · ⇧ · ⌘A"),
                    GuideKey("Tray and Basket: Quick Look, open, copy", "Space · Return · ⌘C"),
                    GuideKey("Tray and Basket: remove, undo, move", "⌫ · ⌘Z · ⇧⌘M"),
                    GuideKey("Basket: to the Shelf, minimise, close", "⌘↑ · ⌘M · ⌘W"),
                    GuideKey("Clipboard: move, paste, search, close", "← → · Return · ⌘F · Esc"),
                    GuideKey("Thunderstorm: open, reveal, Quick Look", "Return · ⌘Return · ⌘Y"),
                    GuideKey("Thunderstorm: to the Tray, copy path, trash", "⌘T · ⌘C · ⌘⌫"),
                ]),
                .tip("A shortcut another app already owns is flagged in Settings › Keyboard Shortcuts. The default modifier pair is ⌃⌥, because ⌘⇧ collides with Save As and most browser shortcuts."),
            ]),
        ])

    private static let troubleshooting = GuideArticle(
        id: "troubleshooting", category: .reference, icon: "wrench.and.screwdriver.fill",
        title: "When something doesn't work",
        summary: "The usual causes, in order",
        sections: [
            GuideSection("A shortcut does nothing", [
                .bullets([
                    "Another app may own it. Settings › Keyboard Shortcuts flags a combination that is already taken.",
                    "A shortcut that belongs to a droplet only fires while that droplet is on; the row says so.",
                    "Media keys for a browser tab need Accessibility.",
                ]),
                .settings([GuideSettingLink("Keyboard Shortcuts", "shortcuts.all")]),
            ]),
            GuideSection("The player is empty", [
                .text("macOS 15.4 stopped letting ordinary apps read the system Now Playing, so Tama asks Music, Spotify and your browser directly — which needs Automation for each app. The first time, macOS asks; if you said no, the row in Settings › General resets it."),
                .text("A browser tab also needs *Allow JavaScript from Apple Events* before its position can be read."),
            ]),
            GuideSection("Pasting doesn't paste", [
                .text("Return-to-paste presses ⌘V for you, which needs Accessibility. Without it the clip is still copied — press ⌘V yourself."),
                .settings([GuideSettingLink("Accessibility for pasting", "clipboard.accessibility")]),
            ]),
            GuideSection("It worked before the update", [
                .text("macOS ties a permission to the app's signature. If Tama was rebuilt without its signing identity, macOS treats it as a new app and drops Accessibility, Automation and Screen Recording."),
                .text("Use **Reset** on the permission row, then allow it again."),
            ]),
            GuideSection("Nothing else helps", [
                .text("Turn on diagnostic logging, reproduce the problem, then export the log — it carries the version, your macOS, your settings and what the services did. Nothing is sent anywhere; the file is yours to share."),
                .text("If Tama quit by itself, macOS wrote a crash report. Tama reads the newest one, takes your account name, home folder and this Mac's identifiers out of it, and offers to put it on the clipboard. It is never sent anywhere — there is nowhere for it to go."),
                .text("**Hard reset** puts every setting back to its default, and asks whether to keep your clipboard history."),
                .settings([
                    GuideSettingLink("Diagnostic logging", "about.logging"),
                    GuideSettingLink("Export logs", "about.exportLogs"),
                    GuideSettingLink("Last crash report", "about.lastCrash"),
                    GuideSettingLink("Hard reset", "about.hardReset"),
                ]),
            ]),
        ])
}
