# Reference Settings window (from the user's screenshots, 2026-09-22)

Screenshots: `/private/tmp/claude-501/-Users-Shared-Data-source-macos-droppy/a9707a50-3595-43fc-a8ec-8b834cfe4ff3/images/2.png` … `26.png`. Treat them as the visual target for Settings.

## Window chrome
- Translucent dark glass window with rounded corners. The sidebar sits on the glass, and the content area is a slightly lighter rounded panel inset from it.
- Sidebar: a Search field at the top, then these groups (no header on the first group):
  - (no header): **General**, **Droplets**
  - **Workspace**: **Shelf**, **Basket**, **Clipboard**, **Lock screen**
  - **System**: **HUDs**, **Theming**, **Accessibility**
  - **About**: **License** (skip), **About**
- Each row has a small monochrome glyph tile. The selected row is a lighter rounded fill.
- Content is made of section titles (grey, semibold) followed by rounded group cards. Rows inside a card are separated by hairlines, and each row can carry an ⓘ help icon.

### Recurring controls
- **Toggle tiles**: a full-width segmented row where each segment is an independent on/off toggle with an icon and a label. A segment that is on is filled lighter. Examples: Menu bar icon | Dock icon | Launch at login.
- **Choice tiles**: the same look, but only one segment can be selected (Regular | Enlarged, Show | Hide media | Hide all).
- **Preview cards**: dark "maze" wallpaper thumbnails that show a miniature of the option. The selected card gets a white 2pt border, with the title and subtitle underneath (Notch / "Carved black silhouette").
- **Sliders**: a dotted track with a value pill on the right ("Standard", "0.10s", "Balanced", "+0 pt"), plus a reset ↺ where it applies.
- **Shortcut rows**: a label, a pill showing the current keys (or "None"), a blue "Record shortcut" button and a reset ↺.
- **Summary rows**: "Permissions overview — 4 of 10 granted ⌄" and "Widget settings — 3 of 13 widgets active ⌄" show a progress ring and expand in place.

## Pages

### General
- **Startup**
  - Startup & visibility toggle tiles: Menu bar icon, Dock icon, Launch at login.
- **Permissions**
  - Permissions overview: a progress ring, "N of 10 granted", expandable.
- **File handling**
  - File actions tiles: Auto-remove, Protect originals.
- **Quick Actions**
  - Quick Actions master toggle.
  - Quick Action tiles editor: a capsule of round tiles (Drop, AirDrop, Convert, dashed +). "Tap a tile to swap or remove it, or tap + to add. These tiles appear when you drag files onto the Shelf, Basket, or island."
  - Quick Action mail app: Default | Mail | Outlook.
- **Automation**
  - Auto-copy OCR text, Smart Export, Tracked folders (toggles).

### Droplets
- Filter chips: Installed, AI, Productivity, Media.
- "Explore" large title.
- Hero carousel: a large card with an image, title and tagline, ‹ › arrows and page dots.
- Two-column list. Each row has a 56pt app-style icon, a category caption (AI / Productivity / Media / Community Droplet), a bold title, a two-line subtitle and a chevron. The hovered row is filled lighter.
- Detail page:
  - ‹ back button and a large title.
  - Top-right actions: red "Set Up" pill, "⏻ Turn On" pill.
  - Big icon, tagline, a category chip and a status chip ("Needs Setup", orange).
  - Screenshot, description paragraph, then the droplet's own settings rows (for example "Audio quality badge", "Media widget › Left button").

### Shelf
- **The Shelf**
  - Master toggle with Regular | Enlarged.
- **Navigation style**
  - Preview cards: "Regular buttons" (tabs inside the notch wings) and "Floating bar" (glass capsule under the shelf, the default).
- **Multi Live Activities**
  - Preview cards On (call pill plus a second circular pill with artwork) and Off.
- **Widgets**
  - Custom Shelf: a live, editable preview of the shelf. The hand icon enters edit mode.
  - Widget icons: a grid of app-style widget icons (Weather, Media HUD, Clipboard).
  - Widget settings: "3 of 13 widgets active ⌄".
  - Favorites: nav capsule plus a dashed + slot. "Tap a slot to pick a widget, app, or shortcut — or remove it. Favorites sit beside the floating navigation bar under your shelf."
- **Behavior**
  - Shelf behavior toggle tiles: Auto-collapse, Auto-expand.
  - Collapse delay slider (0.10s).
  - Animation speed: Turtle | Human | Cheetah | Falcon.
  - Gestures On | Off.
  - Open tray after drop.

### Basket
- **Floating Basket**
  - Master toggle with toggle tiles Instant appear, Auto-hide.
  - Shake sensitivity slider (Balanced).
  - Drag shortcut: None / Record shortcut.
- **Multi-Basket**
  - Basket mode: Single Basket | Multi-Basket.
  - Basket Switcher: shortcut.

### Clipboard
- **Clipboard**
  - Clipboard manager master toggle, with location tiles Menu bar and Shelf right-click menu.
- **Clipboard appearance**
  - Clipboard layout: Alpha clipboard (card strip, like ours) | Legacy clipboard (list window).
  - Type filters toggle.
  - Alpha preview: cards whose header strip is tinted by the source app (Screenshot=brown, Work=blue). Each header has the title, a relative time and the app icon at the corner. The footer has a chip like "66 characters ≡ 2" or "1728 × 1117", and a ★.
- **Shortcuts**
  - Shortcut ⇧⌘Space with Record and reset.
  - History limit slider ("13 of 50 items saved").
  - Toggles: Skip passwords, Clear history on quit, Reject duplicates.
  - Clipboard actions toggle tiles: Tags, Copy + favorite, Auto-focus.
- **Filtering**
  - Excluded apps: chips or "No apps added", plus "Add app…".

### Lock screen
- Master toggle with toggle tiles: Lock/unlock animation, Lock & unlock sound.
- Lock sound and Unlock sound pickers (None / Default / …) with a ▶ preview.
- **Features**: Lock screen media HUD, Volume slider, Brightness slider, Keep visible during screensaver, Keep awake slider (Off…).
- **Widgets**: Status widgets row.

### HUDs
- **Display style**
  - Hide on external displays.
  - External displays preview cards: Notch "Carved black silhouette" | Dynamic Island "Floating pill surface".
  - Toggles: Show when idle, Per-display visibility, Hide physical notch.
- **Size**
  - Sliders with a "Standard" pill: Island height, Island width, Island position, Notch height (and Notch width).
- **Behavior**
  - Collapsed HUD scope: Under pointer | All displays.
  - In fullscreen: Show | Hide media | Hide all.
- **Media**
  - Now Playing and Auto-hide preview toggles.
  - Now Playing display: Under pointer | MacBook.
  - Notch track title toggle.
  - Visualizer preview cards: mono bars | gradient bars.
  - Live audio visualizer and Live album artwork toggles.
- **Media Controls**
  - Default music app: Apple Music | Spotify.
  - Track swipe On | Off; Track swipe direction Standard | Reversed.
  - On notch click: Media widget | Default.
  - Filter media sources and Hide Incognito media toggles.
- **System**: a 3-column grid of HUD preview cards. Each card toggles its HUD and shows a subtitle:
  - Volume "Replace system OSD", Brightness "Replace brightness OSD", Keyboard brightness "Replace backlight OSD"
  - Battery status "Charge + low battery", File tray "After drop sessions", Caps Lock "On / Off indicator"
  - Recording status "Mic + screen indicator", Droppy updates (skip), AirPods & headphones "Show when connected"
  - Focus mode "Show when toggled", No internet "Pop up when offline", VPN connected "Tunnel name + timer"
- **Droplets**: a grid of droplet HUD cards with a "Set up" badge:
  - Meetings "Call timer + live audio", Pomodoro, Calendar "Event progress ring"
  - Notifications "Live notification HUD", High Alert "Stay-awake status", TermiNotch
  - Agents "Claude, Codex & Cursor status"
- **Media keys**
  - Key sound Off | On.
  - Desktop volume slider and Desktop brightness slider toggles.
  - Media key target: Under pointer | Main MacBook.
  - BetterDisplay integration ("Get app").
  - Automatic brightness HUD and Keyboard brightness keys toggles.
- **Keyboard backlight**
  - Brighten shortcut and Dim shortcut.

### Theming
- **Notched display** preview cards: Dynamic Glass "Black fading into Liquid Glass" (default) | Black "Matches the physical notch".
- **Notchless display**: Dynamic Glass | Black "Classic solid black" | Liquid Glass "Tinted Liquid Glass".
- **Outline**
  - Subtle outline toggle.
  - Show in resting state (disabled unless the outline is on).
- **Settings window**: options (not captured).
- **Media HUD position**: a preview with a mini floating media HUD, plus a Vertical position slider "+0 pt" with reset.
- **Branding**: App icon picker (skip; these are the reference's own assets).
- **General**: "Scrub each tape to pick a color. Default keeps Droppy's automatic color; the last swatch is a custom hex."
  - Tape pickers (dot plus tick-tape scrubber with a "Default" label) for Highlight color, Window tint, Volume slider color and Brightness slider color.

### Accessibility
- **Interaction**: Right-click to hide, Right-click to reveal (on), Hold to reveal, Haptic feedback (on).
- **Screen capture**: Hide from screenshots.

### About
- **Software update**: glowing round icon, "Droppy 14.2.0", "You're up to date", Beta updates. Skip the updater and show the version only.
- **About**: cards Changelog "Read the full history", Developer, Introduction "Replay the welcome tour".
- **Privacy**: cards with ⓘ: Tracking "Off", On-device data "Stays on your Mac", Online features "Opt-in".
- **Troubleshooting**: cards Hard reset "Reset all settings to defaults", Transfer settings "Export or import your settings".

## Shelf (live)
- The Home page shows the player on the left and a **grey liquid-glass weather card** (~210×150 pt) on the right: "Local ➤", a thin 60pt temperature, a condition icon, "Cloudy", "H:19° L:13°" and a 4-column hourly row.
- The player's transport has an AirPods/output glyph on the right.
- The shelf fades from black to glass along its bottom edge.
- Below it sits a single glass capsule with house / tray / grid icons; the selected icon has a lighter disc.

## Done in phase 1
- ✅ **Window chrome**: the window is translucent dark glass with a lighter inset content panel. The sidebar has a Search field and the groups General/Droplets, Workspace, System and About, with monochrome glyph tiles and a lighter selected fill. The License row is skipped (out of scope). Enabled droplets are still listed under the groups (ours only).
- ✅ **Recurring controls**: `Views/Settings/SettingsPrimitives.swift` provides section titles, group cards with hairlines and ⓘ popovers, ToggleTiles, ChoiceTiles, PreviewCardPicker on a drawn maze wallpaper, SettingsSlider (value pill and ↺), ShortcutRecorderRow, SummaryDisclosureRow with a ring, SettingsCardButton and TapeColorPicker.
- ✅ **Search**: `SettingsSearch.swift` indexes about 55 options with synonyms. Picking a result opens the page, scrolls to the row and flashes it.
- ✅ **General**: Startup & visibility tiles, with a confirm when hiding the menu bar icon. Permissions overview ("N of 10 granted", expands to the full permission rows). File actions: Auto-remove and Protect originals. Automation: Auto-copy OCR text. Every global shortcut is recordable.
  - Skipped: the Quick Actions master toggle, tile editor and mail app, and the Smart Export and Tracked folders toggles. These belong to Phase 5.
- ✅ **Theming**:
  - Notched display: Dynamic Glass | Black.
  - Notchless display: Dynamic Glass | Black | Liquid Glass.
  - The island and shelf render the chosen surface.
  - Subtle outline, plus Show in resting state.
  - Media HUD position: a preview and a Vertical position slider that offsets the floating island pill.
  - Tapes: Highlight color (the reference preset names plus a custom hex), Window tint (Settings and glass surfaces), and Volume and Brightness slider colors. The slider-color tapes map onto the meter styles Accent, White, Decibel and Custom.
  - Skipped: the App icon picker (out of scope) and the "Settings window" options (not captured).
- ✅ **Accessibility**: Right-click to hide, Right-click to reveal, Hold to reveal (choice of modifier combo), Haptic feedback, Sound effects, and Hide from screenshots.
- ✅ **About**: version from the bundle, Changelog (a bundled `CHANGELOG.md` shown in a sheet), Developer, Introduction (replays onboarding), Privacy cards with ⓘ, Hard reset (settings only, or everything with an optional "keep clipboard history" and a relaunch), and Transfer settings (export and import).
  - Skipped: the updater and Beta updates (out of scope).
- 🟡 **Other pages**: Shelf, Basket, Clipboard, Lock screen and HUDs now use the new blocks and hold all the existing settings. Sound and Display became the HUDs page's Volume and Brightness sections. Their reference-only rows (floating nav, multi-basket, HUD cards grid and so on) are left to later phases.

## Done in phase 2
- ✅ **Shelf › The Shelf**: master toggle (`shelfEnabled`; off = the notch never opens into the shelf or drop tiles, HUDs/banners/live activities still show) and Regular | Enlarged (`shelfSize`, the whole open shelf scaled ×1.12 below the notch).
- ✅ **Navigation style**: preview cards Regular buttons (tabs in the notch wings; a tab row without a notch) | Floating bar (default; one grey-glass capsule 95×30 pt, house/tray/grid, lighter disc on the selected page, 12 pt under the shelf). Calendar left the capsule: a round glass Calendar button (toggle) or the right wing, plus ⌘4. Customize left it too: Custom Shelf's hand, clicking Home again, or the context menu.
- ✅ **Multi Live Activities** On | Off preview cards (`multiLiveActivities`, on).
- ✅ **Widgets**: Custom Shelf (the live Home page scaled on the maze, chips to pick up to two widgets in place, hand opens the real shelf in edit mode); Widget icons (enabled widgets in their order, drag to reorder, hand opens rearrange mode on the shelf); Widget settings "N of M widgets active ⌄" with a switch per widget; Favorites editor (nav capsule + slots + dashed +; a popover picks a widget, an app or a Shortcut, or removes it).
- ✅ **Behavior**: Auto-collapse | Auto-expand tiles, Collapse delay, Auto-expand delay, Animation speed Turtle | Human | Cheetah | Falcon (a tempo multiplier over our kept motion styles), Gestures On | Off plus "Scroll on the notch: Volume | Open shelf" so swipe-to-open and scroll-volume never conflict, Open tray after drop.
- ✅ **Search**: every new row is indexed (18 Shelf entries).
- 🟡 **Shelf (live)**: width/corner/capsule match §5 of 1-shell-settings.md; the weather card and player output button belong to the player phase.

## Done in phase 3
- ✅ **HUDs page** (`Views/Settings/HUDsSettingsPage.swift`) in reference order: Display style, Size, Behavior, System grid, Droplets grid, Media keys, Keyboard backlight. Droppy's own Target display, Live Activities (meetings, downloads) and the detailed Volume/Brightness sections follow them. 44 HUD search entries.
- ✅ **Display style**: Hide on external displays; External displays Notch | Dynamic Island cards (`islandStyle`, applied to every notchless screen); Show when idle (off: an external island fades out while nothing is live, and comes back on hover or a file drag); Per-display visibility with a checkbox per external display (stable vendor-model-serial key); Hide physical notch (`NotchCoverController`, a black strip as tall as the menu bar on notched displays, placed under the menu bar).
- ✅ **Size**: Island height/width/position and Notch height/width sliders, each with a "Standard" pill and a reset. They feed `AppState+Geometry`, so the panel and hit-testing stay in sync.
- ✅ **Behavior**: Collapsed HUD scope; In fullscreen Show | Hide media | Hide all (`ScreenStateService`: AXFullScreen, or a window covering the whole screen); Hide in Mission Control (the Dock's AXExpose notifications, with a failsafe); Compact HUD priority; Finished HUD linger; Keep HUD visible while hovered.
- ✅ **System grid**: 11 toggle cards. The new HUDs are Keyboard brightness, File tray, Caps Lock, Recording, Focus and No internet.
- ✅ **Droplets grid**: "Set up" cards that open the droplet's detail page. Calendar, Notifications and Agents aren't droplets yet, so they open the store.
- ✅ **Media keys**: Key sound, Desktop volume/brightness sliders, Media key target, BetterDisplay integration, Automatic brightness HUD, Keyboard brightness keys. **Keyboard backlight**: Brighten/Dim shortcuts; hold to repeat.
- ⏭ Skipped: Droppy updates card (updater out of scope). Media and Media Controls belong to Phase 4.

## Done in phase 4
- ✅ **HUDs › Media**: Now Playing, Auto-hide preview (plus a delay), Now Playing display, Notch track title, Visualizer preview cards (Mono bars / Gradient bars), Live audio visualizer, Live album artwork, and Artwork tint.
- ✅ **HUDs › Media Controls**: Default music app, Track swipe, Track swipe direction, On notch click, Playback buttons (per source), Filter media sources (checklist), Hide Incognito media.
- ✅ **HUDs › Media keys**: a Playback keys row ("Choose what Droppy handles for media keys").
- ✅ **Droplet detail**: Apple Music (Audio quality badge, Media widget › Left/Right button) and Weather (style, location, city search, refresh interval, AQI, sunrise and sunset) droplets, in a new **Media** category.
- ✅ **Search**: 23 new entries. `droplet.*` anchors open the droplet's page.
- ✅ **Shelf (live)**: grey liquid-glass weather card beside the player, and the output glyph in the transport row.

## Done in phase 5
- ✅ **General**: Quick Actions master toggle, the tile editor (a capsule on the maze with Drop, the chosen tiles and a dashed +; tap a tile to swap or remove it) and the Mail app choice (Default | Mail | Outlook); Require upload confirmation and Recent Uploads; Automation with Auto-copy OCR text, Smart Export (folder plus Compressed / Converted / Background removed tiles) and Tracked folders (folder list); Conversion (destination, After converting); Background removal; Helper tools (Homebrew); Integrations (Finder Services guide, Alfred, URL scheme).
- ✅ **Basket**: Floating Basket toggle with the Instant appear | Auto-hide tiles and their delays, Shake sensitivity slider ("Balanced"), Drag shortcut (a modifier recorder), Summon Basket shortcut; Multi-Basket: Basket mode Single Basket | Multi-Basket, the Basket Switcher shortcut, Second bucket.
- ✅ **Shelf › Tray**: Auto-cleanup and Two Stacks.
- ✅ **Search**: 25 new entries.

## Done in phase 6
- ✅ **Clipboard** page (`Views/Settings/ClipboardSettingsPage.swift`): Clipboard manager + location tiles; Clipboard appearance (layout tiles, Type filters, live Alpha/Legacy preview on the maze); Shortcuts (⇧⌘Space recorder, history slider, retention, image cap, Skip passwords, Blur sensitive, Clear on quit, Reject duplicates, Paste into previous app, Accessibility, Clipboard actions tiles, tags, Clear History); Filtering (excluded-app chips, Add app…). 15 new search entries.

## Done in phase 7
- ✅ **Lock screen** page (`Views/Settings/LockScreenSettingsPage.swift`): master toggle with Lock/unlock animation | Lock & unlock sound tiles; Lock/Unlock sound pickers (None / Default / system sounds) with ▶; Features: media HUD (+ material Dark | Regular | Liquid), Volume slider, Brightness slider, Keep visible during screensaver, Keep awake slider (Off…1 hr, Always); Widgets: Status widgets row, style Inline | Vertical | Rounded, look Light | Dark, material, per-widget toggles. 12 new search entries.

## Done in phase 10
- ✅ **Droplets** (`Views/Settings/DropletStore.swift`):
  - Filter chips All | Installed (with a count) | AI | Productivity | Media, each a large glass capsule. Tapping the selected chip again returns to All.
  - "Explore" large title.
  - Hero carousel of 10 featured droplets (filtered by the chip). Each card has art we draw ourselves: a tinted gradient, light streaks, and a motif such as a launcher bar, LocalSend rings, an agent terminal or a large symbol. It shows the title, our own tagline and an "Installed" badge. It has ‹ › arrows and page dots that grow on the current page, and auto-advances every 6 s, pausing on hover. Reduce Motion cross-fades instead of sliding.
  - Two-column list: 56 pt icon, category caption ("Community Droplet" for High Alert, Meetings, Timer and Mechey), bold title with an Installed or Needs Setup mark, two-line subtitle and a chevron. Rows fill lighter on hover and are separated by hairlines.
- ✅ **Detail page**:
  - A round ‹ back button (Esc) and a 28 pt title.
  - Top-right actions: a red "Set Up" pill when setup is missing, and a "⏻ Turn On" / "Turn Off" pill.
  - An 88 pt icon with the tagline, a category chip tinted by the droplet, a status chip (Needs Setup in orange, Installed, Not Installed) and New.
  - An illustration: the droplet's art behind a miniature shelf with the nav capsule.
  - The description, plus the reason for any setup, and the Use rows: Home page, Open, Shortcut, and the new Show in Settings sidebar.
  - Then all of the droplet's existing settings (`DropletSettingsSections`), unchanged.
  - Search jumps scroll to the row.
  - "Needs Setup" is worked out live:
    - Apple Music: Automation.
    - Window Snap, LiquidMouse and Meetings: Accessibility.
    - Element Capture: Screen Recording.
    - Voice Transcribe: Microphone and Speech.
    - Mechey: Input Monitoring.
    - Notification HUD: Full Disk Access.
    - Obsidian: a vault.
- ✅ **LocalSend droplet page**: device name ("Reset to this Mac's name"), Visible to other devices, Receive from Off | Favorites | Anyone, Quick Save for favorites, PIN, Save received files to, Add received files to the shelf, Encrypted (HTTPS), Fingerprint, receiver status, and Favorites with "Forget this device".
- ✅ **About**:
  - What's New and Setup Guide cards.
  - Troubleshooting has Diagnostic logging ("Write detailed logs for troubleshooting"), plus Logs: Show in Finder, Clear and Export Logs….
- ✅ **Accessibility**: Show tooltips.
- ✅ **Search**: 17 new entries: the LocalSend options, tooltips, logging, export logs, What's New, Setup Guide, and a sidebar entry per droplet. The existing "droplets.store" entry gained the store's synonyms.
- ⏭ The reference's Install / Uninstall progress model was not adopted. Built-in droplets have nothing to download, so Turn On / Turn Off is the honest equivalent. Screenshots are replaced by drawn illustrations, because rule 5 forbids copying the reference's assets and we have no real screenshots to bundle.

## Done in phase 11
- ✅ **Theming › Settings window**: the one option we could infer, "Solid background", is built. It paints the window in one opaque colour instead of the glass, which keeps the cards readable over a bright desktop.
- ✅ **Shelf › Widgets › Widget icons** (bug): the card's height was worked out from a guessed 520 pt width, so in a wide window the icons needed fewer rows than the frame reserved and the card ended in a band of dead black. It now measures its own width and sizes itself to the rows it really draws.
- ✅ **Lock screen › Widgets** (bug): the status-row preview claimed 1100 pt, pushing the whole card past the right edge of the page — the Widget style, look and material tiles and every per-widget switch were clipped. Fixed; see 2-media-hud-lockscreen › Done in phase 11.
- ✅ **New rows indexed in search**: Solid background, Swipe direction, Preview placement, Floating button size / style / Icon color, Now Playing Size, Always use built-in speakers, Paste shortcut, Favorites bar and Momentum.
- ✅ **Copy**: "Homebrew Detected." → "Homebrew detected." in `General › Helper tools` and in the Homebrew install prompt.
