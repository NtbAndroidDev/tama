## Coverage safety-net: misc.txt (367 lines) and noise.txt (370 lines)

I read every line of both files. Each row below is a feature the strings reveal. Many are cross-cutting or look like they have no owner among the six area auditors; I flagged those rows with **(orphan)**. I checked each against `Sources/` with grep only and did not change any files.

### 1. Features revealed

| Feature revealed (evidence) | Likely area | Ours | | What to change |
|---|---|---|---|---|
| **Menu Bar Manager (orphan)** that hides menu-bar icons: "Clean up your menu bar", "Show or hide the hidden section", "Clock is managed by macOS and can't be hidden.", "Rehide after a delay / when switching apps", "Hide application menus", "Override the auto-hide delay for selected apps." | shell/tools (maybe "Thaw") | none. `AppDelegate.swift:87` only has our own status item | ❌ | Build a hidden-section manager: a separator status item, show/hide toggle, rehide timer, per-app delay rules, and hiding app menus. Needs Accessibility. |
| **Launcher system commands**: "Shut down your Mac", "Restart your Mac", "Log out of your macOS account", "Eject every disk and network drive", "Quit every running application"-style, "Open the Clock app", "Press Return to eject" | tools/launcher (Thunderstorm) | `ThunderstormConsoleView.swift:173` only has open/reveal/quickLook/tray/copyPath | ❌ | Add a "Commands" result group that runs these through AppleScript/System Events and `NSWorkspace.unmountAndEjectDevice`. |
| **System Settings pane search**: "Printers & Scanners", "Wallet & Apple Pay", "Touch ID & Password", "Internet Accounts", "Language & Region", "Game Controllers", "Wireless network connection, known networks, and hotspots.", "App limits, downtime, and communication limits." | launcher | none. Only 2 hard-coded `x-apple.systempreferences` links (`CalendarPage.swift:195`) | ❌ | Add a static table of panes (name, keywords, description, URL) to the launcher search. |
| **Launcher web answers**: "Google Answer", "Web Result", "⇧⌘Space" | launcher | none | ❌ | Add a web-search fallback row. Check the default ⇧⌘Space hotkey. |
| **LocalSend-compatible nearby transfer (orphan)**: "Droppy LocalSend TLS", "Announcing this Mac on the local network.", "Scanning network", "Nearby", "Receive from anyone", "Incoming requests", "Encrypted (HTTPS)", "Same network, no internet"; device icons "MacBook Pro/iMac/Mac mini/iPhone" | files/share | 🟡 `LANShareService.swift:5` is an HTTP link/QR share only. AirDrop at `DroppyCloudShareView.swift:100` | 🟡 | Add the LocalSend protocol: multicast announce/discovery, HTTPS with a self-signed cert, a peer list with device icons, and a receive mode ("anyone" / accept prompt). |
| **Droppy Cloud upload (hosted)**: "Droppy Cloud returned an invalid upload manifest.", "Delete from server", "Server not configured" | share | 🟡 The `DroppyCloudShareView` name exists, but it is LAN-only | 🟡 | Out of scope without a backend. Label it honestly. |
| **Licensing/activation**: "Deactivate this Mac", "One-time purchase. Multiple Macs.", "Incorrect code.", "Too many attempts, try again in a minute", "verified license lease" | shell | none | ❌ (intentional) | Skip for a clone. |
| **Keep-awake watchdog with timed presets**: "Running indefinitely", "Timed modes (15m, 1h, etc)", "1/2/5/12/24 hours", "Blocked by another session", watchdog helper strings | productivity/high alert | `SleepBlockerService.swift:16,24` and `HighAlertConsoleView.swift:70` | ✅ | Check that the presets include 5h, 12h and 24h. Optionally show "Blocked by another session" when another assertion exists. |
| **AI background removal with styling**: "AI Removal", "Removing Background…", "Background Padding", "Background Radius", "Enable styled background", "Shadow Strength" | files/convert | `AICutoutConsoleView.swift:335` | 🟡 | Add padding, radius and shadow options for the styled backdrop on the cutout. |
| **On-device ASR engines**: "Parakeet Core ML models", "Nemotron", "Parakeet handles multilingual detection automatically", "Parakeet models require Apple Silicon", CTC ja/zh-CN, "Auto (best available)", "Balanced speed & accuracy", "Downloading live model", "All model caches cleared", "Verifying model integrity" | tools/voice transcribe | `VoiceTranscribeService.swift:57` uses `SFSpeechRecognizer` only | 🟡 | Keep Apple's recognizer. Add an engine picker UI (Auto/Fast/Balanced/Best), plus model management (download, clear cache) only if you adopt a CoreML engine. |
| **Speaker diarization** in transcripts: "Sortformer", "LS-EEND", "VBx speaker count", "Speaker Clustering" | meetings/transcribe | none | ❌ | Low priority. There is no native API for this. |
| **Text-to-speech / voice cloning (orphan)**: "Kokoro", "PocketTTS", "Downloading Mimi encoder for voice cloning..." | tools/AI | none | ❌ | Could add read-aloud with `AVSpeechSynthesizer`. Voice cloning is out of scope. |
| **macOS notification mirroring**: "…/NotificationCenter/db/db", "group.com.apple.usernoted/db", "Biome Notification.Delivery" | productivity/notification HUD | none (no DB reader) | ❌ | Needs Full Disk Access plus a SQLite read of the usernoted DB. Confirm with the productivity auditor. |
| **iMessage reply / chat in notch (orphan)**: "FROM message m … ORDER BY m.date DESC", "Type a message, then press Return to send", "Typing Indicator", "Message from another session" | productivity | none | ❌ | Read `chat.db` (needs Full Disk Access) and send through Messages AppleScript. |
| **Browser extension bridge**: NativeMessagingHosts paths for Chrome, Arc, Brave, Edge, Vivaldi, Opera, Zen and Firefox; "Unexpected extension id '" | media (tab control) / clipboard | none | ❌ | Probably feeds browser media or tab info. Our AppleScript path covers part of it. |
| **Recent Cursor/VS Code projects**: "Cursor/User/globalStorage/state.vscdb", "Visual Studio Code", "Warp" | AI agents/terminal | none | ❌ | Confirm with the productivity (AI agents) auditor. |
| **BetterDisplay integration**: "Checks whether BetterDisplay's local HTTP API is reachable." | HUD/brightness | none (`BrightnessService` only) | ❌ | Optionally route brightness to the BetterDisplay HTTP API for external displays. |
| **Audio/Bluetooth device battery**: "Show connected audio device battery percentage.", "Audio device battery", "Accessory Category", "Headphone controls and supported audio device preferences." | media/HUD | `HeadphoneBatteryService`, `HomePage.swift:871`, lock screen | 🟡 | Add a battery badge to the device-connect live activity and the volume HUD, plus a settings toggle. |
| **Audio quality badge / gradient visuals**: "Audio quality badge", "Use gradient-based audio visuals." | media/player | none | ❌ | Add a Lossless/Hi-Res badge in the player and a gradient visualizer toggle. |
| **Multiple live activities at once**: "Multi Live Activities", "Show in resting state", "Left side of shelf / Right side of shelf", "Primary/Secondary Widget", "Widget 1/2" | shell/island | 🟡 `IslandCompactView.swift:23` shows one `top(.ambient)` | 🟡 | Allow two concurrent wing activities (left and right) and a setting to choose them. |
| **Rearrange widgets/edit mode (onboarding)**: "Opens the Widgets page and enters rearrange mode", "Rearrange quickly", "Open widget grid", "Opens the real shelf and enters edit mode" | shell/widgets | 🟡 `ShelfView.swift:245` `beginCustomizingHome` for Home. No reorder on WidgetsPage | 🟡 | Add drag-reorder for droplets. |
| **Quick Action tiles (configurable)**: "Add quick action", "Quick action title/description", "Two-column tile layout", "Take this tile off the row" | files/shelf | `ShelfView.swift:252` has 4 fixed tiles | 🟡 | Make the tiles user-configurable (add/remove, 2-column layout). |
| **Second bucket in the Basket**: "Add a second bucket for rarely used items" | basket | none | ❌ | Add a secondary basket section. |
| **Starred items**: "Mark items with a star to keep them handy." | clipboard/tray | 🟡 clipboard favourites at `ClipboardShelfView.swift:42` | 🟡 | Check that Tray and Basket items can also be starred. |
| **Clipboard "Reject duplicates"** | clipboard | none | ❌ | Add a dedupe toggle to the capture rules. |
| **Accent presets + custom colour**: "Cyan, Ember, Graphite, Midnight, Mint, Ocean, Twilight", "Edit custom color", "Widget Color" | settings | 🟡 `Constants.swift:10` has 6 other presets and no custom colour | 🟡 | Match the preset names and add a custom `ColorPicker`, plus a per-widget tint. |
| **Liquid vs regular style**: "Liquid Mode", "Regular or liquid", "Carved black silhouette", "Compact circular layout", "Vertical or rounded layout" | shell/HUD | 🟡 `SettingsView.swift:519` has a Liquid Glass section | 🟡 | Expose a single "Regular / Liquid" style switch and a HUD layout variant (circular/vertical). |
| **HUD placement and auto-dismiss**: "Under Pointer", "Closest Corner", "Vertical position / Fine-tune the vertical position.", "Auto-dismiss delay", "Auto-hide preview" | HUD/capture | none | ❌ | Add HUD position (notch/under pointer/closest corner), a vertical offset slider and a dismiss delay. |
| **Pointer-first mode / navigation style**: "Pointer-first Mode", "Navigation style", "Pointer controls", "External Mouse" | liquidmouse/shell | none | ❌ | Clarify with the tools auditor. It looks like a mouse-first navigation option. |
| **Diagnostic logging**: "Write detailed logs for troubleshooting", "Menu bar & diagnostics" | settings | none | ❌ | Add an `os.Logger` verbose toggle and an "Export logs" button. |
| **Haptics** ("Enable subtle tactile feedback.") | settings | `SettingsView.swift:286` | ✅ | none |
| **Show tooltips toggle** | settings | 🟡 `.help` is used everywhere with no toggle | 🟡 | Add the toggle. |
| **What's New / support**: "New Features", "Bug Fixes", "More polish", "Direct feature talks", "Indie sustainability", "Setup Guide", "Recommended setup", "Quick one-time setup" | onboarding/shell | none (no onboarding) | ❌ | Add a What's New sheet and a setup checklist. |
| **Call controls in notch**: "Hang up", "Mute audio/Unmute audio" | meetings | 🟡 `MeetingControlService` has mute/camera/share | 🟡 | Add Hang up. |
| **Offline/connectivity states**: "No Internet Connection", "Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue." | shell | none (no `NWPathMonitor`) | ❌ | Show an offline state in weather, lyrics and share. |
| **Low Power Mode live activity** ("Low Power Mode enabled") | HUD | `BatteryService.swift:24` | ✅ | none |
| **Lyrics lookup by artist/title**: "Found by artist", "Found by title" | media | `LyricsService` (LRCLIB) | ✅ | Optionally show which match was used. |
| **Calendar sync state**: "Waiting for first sync", "Tap to sync now.", "Refresh Upcoming", "No upcoming" | calendar | none | 🟡 | Add a manual refresh and an empty state. |
| **Animated companion / "Clicky"**: "Animated companion", `…/Droppy/Clicky` | tools (likely key-sound pack or mascot) | none | ❌ | Unclear. Check with the tools auditor. |
| **Background Noise** (ambient sound?) | media/pomodoro | none | ❌ | Probably pomodoro focus noise. Confirm with the productivity auditor. |
| **AI agent with tools/API key**: "You have access to the following tools", "API Key", "Empty prompt" | AI agents | none | ❌ | Covered by the productivity auditor. |
| **Stopwatch** ("Stopwatch Paused") | timer | `TimerConsoleView.swift:3` | ✅ | none |
| **Shelf on/off**: "Enable The Shelf", "Turn the shelf UI on or off." | shell | none | ❌ | Add a master toggle that turns the expanded shelf off, leaving only live activities. |

### 2. Discarded as internal
- About 250 ML/ASR/TTS/diarization engine logs and errors, such as the Kokoro, PocketTTS, Sortformer and VBx messages.
- About 25 audio-pipeline and device-listener logs.
- About 20 license, manifest, runtime and watchdog plumbing strings.
- About 15 HTTP and TLS errors ("Too Many Requests", "Invalid token").
- About 25 file paths. I used them only as evidence.
- About 30 dev fixtures and sample data ("Droppy Quarterly Plan", "Fix login bug", "Safari • 10:42", "DEV Teams Meeting", "Seed demo library", "Inject test files", "Developer tools unlocked").
- About 60 generic words, colours, key names, font names and a Supabase anon JWT.
- About 5 SQL fragments.

The two highest-value gaps nobody owns are the Menu Bar Manager and LocalSend-style nearby transfer. After those come the launcher system commands and System Settings pane search.
## Done in phase 1
- ✅ **Accent presets + custom colour**: added Cyan, Ember, Graphite, Midnight, Mint, Ocean and Twilight, plus a custom hex. These are picked on the Theming › Highlight color tape.
  - Skipped: the per-widget tint, which belongs to the Droplets phase.
- ✅ **Haptics**: moved to Settings › Accessibility.
- 🟡 **What's New / setup**: the first-run tour includes a permissions quick-grant step, and About opens the bundled changelog.
  - Skipped: a separate What's New sheet.
- Skipped, not in this phase's scope: diagnostic logging, the Show tooltips toggle and the Enable The Shelf master toggle.

## Done in phase 2
- ✅ **Multiple live activities at once**: with Multi Live Activities on, the next concurrent activity (urgent/ambient live activity, music, Pomodoro or High Alert — never the Tray count) gets its own round pill 6 pt right of the resting island (`SecondaryActivityPill`): artwork for music, icon plus progress ring otherwise. It is status-only (clicks pass through). "Left/right side of shelf" and primary/secondary widget pickers were not added: the wings keep the existing priority order.
- ✅ **Rearrange widgets / edit mode**: the Widgets page has a rearrange mode (grid of every enabled widget, drag to reorder, Done) opened from Settings › Shelf › Widget icons' hand, the Widgets tab's context menu or the island's right-click menu. The order persists as `dropletOrder` (data key, restored in `restorePersistedState` and flushed on quit). "Opens the real shelf and enters edit mode" is Custom Shelf's hand.
- ⏭️ **Quick Action tiles (configurable)**: left to the Quick Actions phase (General › Quick Actions).

## Done in phase 3
- ✅ BetterDisplay integration: the app is detected, and its HTTP API at 127.0.0.1:55777 is pinged. When it answers, brightness keys aimed at an external display go through it; without the app, the row shows a "Get app" link.
- 🟡 Offline: `ConnectivityService` (NWPathMonitor) shows a "No Internet Connection" banner with OK and Settings after 2.5 s offline, and publishes `isOnline`. Weather, lyrics and share offline states are left to their phases.
- 🟡 HUD placement: Island position/size sliders and the linger time. No "closest corner" placement.

## Done in phase 4
- ✅ Audio quality badge: shows Lossless or Hi-Res Lossless using Music's `kind`, bit rate and sample rate. It is hidden when Music doesn't describe the stream. The toggle is on the Apple Music droplet's page.
- ✅ Gradient visuals: gradient visualizer bars and the artwork-tinted player background.
- ✅ Lyrics "Found by artist / Found by title" is saved in the lyrics cache and shown in the lyrics card header.
- ✅ Offline: weather shows "No Internet Connection" when offline.

## Done in phase 5
- ✅ **Quick Action tiles (configurable)**: Keep plus up to three tiles, edited in Settings › General. "Add quick action" and "Take this tile off the row" are in the editor. The two-column layout is used in the Basket.
- ✅ **Second bucket in the Basket**: an optional Main | 2nd bucket per Basket.
- ✅ **Starred items**: Tray and Basket files can be pinned (the pin plays the star's role). Pinned files never expire or get trimmed.
- ⏭ LocalSend is left to Phase 10.

## Done in phase 6
- ✅ **Clipboard "Reject duplicates"**: Settings › Clipboard toggle; `ClipboardHistory.inserting(rejectDuplicates:)`.
- ✅ **Starred items**: clipboard favourites (★ on Alpha cards and Legacy rows, Copy + Favorite, bulk favourite).

## Done in phase 8b
- ✅ **macOS notification mirroring**: the usernoted store (group container `db2/db` and the older path) is read with Full Disk Access, with a guide when that access is missing. See 5-productivity › Done in phase 8b.
- ✅ **iMessage reply**: the chat is resolved from `chat.db` (`FROM message m … ORDER BY m.date DESC`) and the reply is sent through Messages AppleScript, using "Type a message, then press Return to send". WhatsApp and Telegram replies are copied and the app opens.
- 🟡 **Cursor/VS Code**: Cursor's `state.vscdb` feeds the Agents droplet's status. A "recent projects" list wasn't built, because the reference evidence ties it to agents, not a launcher.
- ✅ **Call controls in notch**: Hang up, which uses the app's shortcut or its menu item through Accessibility. Also the mute state and red "off" fills.
- ⏭ **Background Noise**: covered by phase 8a's Pomodoro ambient sound; nothing new.

## Done in phase 9b
- ✅ **Menu Bar Manager**: a new droplet, off by default, built on Droppy's own NSStatusItems (no Thaw download, no Accessibility).
  - How hiding works: a chevron toggle and a "|" divider. Icons ⌘-dragged left of the divider hide when the divider's length grows to 10,000 pt.
  - Always-hidden section: an optional second, dotted divider. Option-click reveals it.
  - Revealing: click the toggle, use a recordable shortcut, the right-click menu, or the console.
  - Rehiding: after a delay (it waits while the pointer is in the menu bar; a one-off position read, not a monitor) and/or when switching apps.
  - Appearance: toggle icon (chevron, dot, ellipsis, eye, drop), render as template or in the accent colour, and show section dividers.
  - Reset Layout forgets the saved positions.
  - A misordered divider is detected and never folds the toggle away.
  - Settings explains ⌘-dragging and that the Clock and Control Center can't be hidden.
  - ⏭ Hover, scroll and double-click reveal, per-app delay rules and "Hide application menus" (user scope: click-only, no monitoring).
- ✅ **Launcher system commands**: Shut Down, Restart, Log Out, Lock Screen, Sleep, Eject every disk and network drive ("Press Return to eject"), and Quit every running app (confirmed).
- ✅ **System Settings pane search**: a static table of 46 panes, including Printers & Scanners, Wallet & Apple Pay, Touch ID & Password, Internet Accounts, Language & Region, Game Controllers, Wi-Fi ("Wireless network connection, known networks, and hotspots.") and Screen Time ("App limits, downtime, and communication limits.").
- ✅ **Launcher web answers**: Google, DuckDuckGo and Wikipedia rows, plus a DuckDuckGo Instant Answer "Web Result" row. ⇧⌘Space stays the clipboard shortcut; Thunderstorm defaults to the shared modifier + T.

## Done in phase 10
- ✅ **LocalSend-compatible nearby transfer**: multicast announce and discovery, a subnet scan, HTTPS with a self-signed certificate, a peer list with device icons, receive modes with an accept prompt, PIN, favorites and a save location. See 3-files-basket-share › Done in phase 10.
- ✅ **Diagnostic logging**: "Write detailed logs for troubleshooting" (`diagnosticLogging`).
  - `DroppyLog` always writes to the unified log (subsystem app.getdroppy.macos). With the switch on, it also writes to `~/Library/Logs/Droppy/Droppy.log`, capped at 2 MB with one rotation.
  - Export Logs… saves a report with version, macOS, displays, droplets, permission states, settings (PIN, folders and location left out) and the logs.
  - About also has Show in Finder and Clear.
- ✅ **Show tooltips**: a switch in Accessibility. Off sets `NSInitialToolTipDelay` very long for Droppy only; on removes it. Windows that are already open may keep their tooltips until the next launch.
- ✅ **What's New and setup**:
  - What's New: a window that opens once after a version change (not on first run, which has the tour). It shows the newest CHANGELOG section grouped by its headings and has a "Show after updates" switch. It can be reopened from About.
  - Setup Guide: "Recommended setup · Quick one-time setup", a checklist with live checks for Accessibility, Open at login, Control Music, Calendar, Droplets, the Clipboard and a first drop, each with a button.
- ✅ **Offline states**: lyrics show "No Internet Connection / Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue." and retry when back online. Quickshare says the same before uploading. Weather was done in phase 4, and LocalSend's status line says "Same network, no internet".
- 🟡 **Text-to-speech**: Read Aloud (AVSpeechSynthesizer, on-device, picks a voice for the text's language) for clipboard text clips and for text, RTF or source files in the Tray and Basket menus, with a notch activity and Stop Reading. Kokoro/PocketTTS voices and voice cloning are out of scope (third-party models).
- ⏭ Still skipped:
  - Speaker diarization: no native API.
  - Browser extension bridge: needs our own browser extensions.
  - HUD "Closest Corner" placement.
  - Pointer-first mode and the "Clicky" companion: unclear, or covered by the Mechey/no-monitoring decision.
  - In-app AI agent with an API key: out of scope. The Agents droplet reads Claude, Codex and Cursor status instead.
  - Droppy Cloud: no server.

## Done in phase 11
- ✅ **HUD "Closest Corner" placement**: the screenshot preview card is the HUD the reference's placement options apply to. `Settings › Shelf › Tray & screenshots › Preview placement` offers Bottom right | Closest corner, and the corner follows the pointer so the card never lands on what was just captured. See 3-files-basket-share › Done in phase 11.
- ⏭ Still skipped, unchanged: crash report (no crash reporter), LocalSend's v1 API and web "download" mode, recent Cursor/VS Code projects in the launcher, Thunderstorm Empty Trash, and the "Settings window" options that weren't captured (the one we could confirm, a solid background, is built — see 1-shell-settings).

## Done in phase 12
- ✅ **LocalSend v1 API**: `/api/localsend/v1/` is answered beside v2, so a device still on LocalSend 1.x can send to this Mac. `LocalSendFormat.route(of:)` now reports the version as well as the route; `send-request` and `send` map onto the v2 prepare/upload handlers, v1's reply is the bare token map (no session id), `send` takes no `sessionId` because v1 has none, and a v1 sender with no fingerprint is given a stable `v1:<host>` stand-in so favorites and the device list still work.
- ✅ **LocalSend web "download" mode**: "Share in a browser". Staged files are held behind a plain page on the same port, so a device with no LocalSend — a phone, a Windows PC — can fetch them by typing this Mac's address. The page is self-contained (no scripts, no fetched assets), reads on a phone, follows the browser's light/dark setting and escapes every name. `prepare-download` and `download` serve LocalSend's own clients, the device announces `download: true` while an offer is live, and the receiving PIN guards both the page and the files. `LocalSendHTTPServer` gained a streamed file response (256 KB chunks, back-pressured on the connection) so a large video is never held in memory, plus RFC 6266 `Content-Disposition` that can't be broken out of by a hostile file name.
- ⏭ Still skipped, unchanged: crash report (no crash reporter), legacy clipboard import (undocumented store format, no sample), recent Cursor/VS Code projects in the launcher, Thunderstorm Empty Trash, and the "Settings window" options that weren't captured.
