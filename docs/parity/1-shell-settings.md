
# App shell parity audit: reference Droppy 14.2.0 vs our clone

I did not edit any files. Besides the bucket files, I read the reference binary's strings (`strings` dump saved as `$SP/binstr.txt`). It contains the whole Settings search index, with each setting's id, title, description, default key and enum raw values. That index settles most of the option sets below.

## 1. Feature table

Paths are relative to `/Users/Shared/Data/source/macos/droppy/Sources`. SV = `Views/Settings/SettingsView.swift`, AS = `App/AppState.swift`.

**Notch / island surface**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Notch" / "Island", "Carved black silhouette" / "Floating pill surface", "Main display style", "Dynamic Island Style" (useDynamicIslandStyle, "Force … island floats below the physical notch") | `islandStyle` AS:245; picker SV:670-681, **disabled on notched Macs** | 🟡 | Allow Island style on a notched MacBook (pill below the notch). Rename the options to "Notch" / "Island" with those two subtitles. |
| "Hide physical notch": "Draw a black bar to hide the hardware notch while using Notch style"; "Apply physical-notch hiding behavior to external screens…" | none | ❌ | Add a toggle that draws a black top bar the full width of the screen. |
| Surface style: "Classic solid black", "Black fading into Liquid Glass", "Tinted Liquid Glass", "Matches the physical notch" (raw values black/liquidGlass/dynamicGlass), set separately for "Surface style for displays with a physical notch" and "Notchless display"; "Dynamic Island Transparency", "Adjust transparent island rendering." | always black (notch) or black at 0.85 (pill), `Theme/LiquidGlassTheme.swift:241-246` | ❌ | Add a 3-way surface picker per display type. notes-screenshot-1 shows the black→glass fade. |
| "Window Tint": "Choose subtle tint color for windows and glass surfaces" | none (accent colour only) | ❌ | Add a tint wash for Settings and glass surfaces. |
| Hairline outline ("…so a black surface stays visible against dark wallpapers", "Show in resting state") | hover glow `borderGlowIntensity` AS:261, Appearance SV:519-531 | 🟡 | Add an always-on hairline option that includes the resting state. |
| "Shelf Size": "Scale the total shelf/island surface with Small, Medium, or Large presets" | fixed `App/Layout.swift` metrics | ❌ | Add S/M/L presets as a scale factor over `DroppyShelfMetrics`. |
| "Shelf Height Offset" ("Fine-tune shelf height/position."), island vertical/width offset, notch width offset | none | ❌ | Add offset sliders that feed `islandTopOffset` and widths. |
| "Animation Speed": "Retimes shelf and island open-close motion without changing the animation style" (presets snail/human/cheetah/falcon) | `IslandMotionStyle` (4 styles) SV:754-777 | 🟡 | Keep the styles and add a separate 4-step speed multiplier. |
| Notch corner fillet | SV:533-542 | ✅ ours only | |

**Shelf behaviour, hover, fullscreen**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Enable Notch Shelf" / "Enable The Shelf": "Turn the shelf UI on or off." | none | ❌ | Add a master toggle that keeps HUDs and live activities. |
| "Auto expand Shelf": "Expand shelf automatically on trigger." (**off by default**; migration `didDisableShelfAutoExpandByDefault`) | `expandOnHover` default **true** AS:246, SV:288 | 🟡 | Default to off, and move it into a Shelf "Control how the shelf expands and collapses" group. |
| "Auto collapse Shelf": "Collapse shelf after inactivity." | always collapses, `Windows/NotchWindowController.swift:650` | 🟡 | Add a toggle. |
| "Auto expand delay" / "Auto collapse delay" | `hoverOpenDelay` 0.25 s (0–1), `autoHideDelay` 0.15 s (0.1–3) SV:779-803 | ✅ (wording differs) | Rename to the reference labels. |
| "Auto-Expand Rules": "Fine-tune hover behavior for menu bar and external displays"; "Main Mac hover" / "External hover" (autoExpandOnMainMac / autoExpandOnExternalDisplays); "Connect an external display to enable External Hover." | single global toggle | ❌ | Add per-display-class hover toggles. |
| "In Fullscreen": "Choose what Droppy does while apps are fullscreen" (Show / Hide media / Hide all); "Hide on fullscreen"; "Hide media in fullscreen" | panel has `.fullScreenAuxiliary`, NotchWindowController.swift:149. Always shown. | ❌ | Detect a fullscreen space and add the 3-way option. |
| "Hide in Mission Control": "Hide notch/island while Mission Control or App Expose is open" | none | ❌ | |
| "Hide notch from screenshots": "Exclude the notch area from screenshots and screen recordings"; "Hides the notch from viewers while sharing." | none | ❌ | Set `panel.sharingType = .none` behind a toggle. |
| Hold-modifier reveal: "Keep the notch hidden until you hold a modifier combo…" | none | ❌ | |
| "Shelf Gestures": "Use a 2-finger swipe to open the shelf, switch between shelf and Now Playing…"; "Reverse swipe direction"; "Track swipe direction" | scroll = volume/brightness, `Views/Island/IslandCompactView.swift:157`; Gestures list is read-only, SV:321-326 | 🟡 | Add a swipe-to-open / swipe-between-pages toggle plus a reverse toggle. Keep scroll-volume as a choice. |
| Right-click menu: "Right-click the Notch or Island to access Settings anytime"; "Right-click hide" / "Show 'Hide Notch/Island' option in right-click menu"; "Right-click to reveal"; "Adds 'Open Clipboard' to right-click menu" | rich menu, `Views/Island/DynamicIslandView.swift:280-340` (Settings, Clipboard, pages, Quit) | 🟡 | Add a "Hide Notch/Island" item and right-click-on-silhouette to reveal, each with its own setting. |
| "Open media on notch click" | tap opens shelf, double-tap play/pause, IslandCompactView.swift:64-71 | 🟡 | Optional: add this setting. |

**Lane pill and floating buttons**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| Nav bar: "Pick where the Droppy / Tray / Widgets buttons appear when the shelf is open: wing tabs or floating capsule bar" | `LanePill` `Views/Notch/ShelfView.swift:127-250`, two capsules (home/tray/widgets + calendar/customize) | 🟡 | Screenshots show **one** capsule with 3 icons. Move calendar and customize out of it, and add the wing-tabs option. |
| "Choose which floating controls are visible under the shelf"; "Show Clipboard/Files Shelf/High Alert/Media HUD/Notchface/Pomodoro/Tasks & Calendar/TermiNotch/Weather/recent notifications as a floating button"; "Quickly enable or disable all floating buttons"; "Floating Button Size"; "Floating Button Style"; "Set icon/text color for colored floating buttons" | none | ❌ | Add round glass buttons beside the capsule, each with a toggle, plus size, style, colour and an all-off switch. |
| Favorites bar: "Pin up to four widgets, apps, or shortcuts beside the floating navigation bar" | none | ❌ | |
| Contextual circular buttons (close ✕, open-external, restart) beside the nav (pomodoro-screenshot, terminal-notch-screenshot) | none | ❌ | |

**Multi-display**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "External displays": "Pick notch or the floating island pill for connected monitors" / "External display style" | notchless screens are always pill | 🟡 | Allow Notch style on external screens. |
| "Hide on external displays"; "Per-display visibility": "Choose exactly which external displays show the top HUD surface"; "External display rules" | `displayTargetMode` (main/builtIn/external/active/all) AS:263, SV:684-752 | 🟡 | Our mode picker is coarser. Add a checkbox per detected screen; the screen list already exists. |
| "Keep the external notch or island surface visible when nothing is playing" (showIdleNotchOnExternalDisplays) | always visible | ❌ | |
| "Now Playing display": Under pointer / Main MacBook; "Collapsed HUD scope" | pointer-follow (`followPointerScreen`) | 🟡 | Expose the choice. |
| "Multi-monitor support" | mirrors, NotchWindowController.swift:361-405 | ✅ | |

**Startup and visibility, haptics**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Startup & Visibility"; "Launch at Login" / "Start at Login"; "Menu Bar Icon"; "Dock Icon" ("…Dock and Command-Tab") | SV:264-283, `Services/LaunchAtLoginService.swift`, AppDelegate.swift:68-78 | ✅ | Use the shorter labels. |
| "Hide menu bar icon?" alert: "Right-click the Notch or Island to access Settings anytime" | caption when both are off | 🟡 | Show a confirm alert when hiding the icon. |
| Haptics ("Enable subtle tactile feedback", "Get tactile feedback when dropping files or triggering actions") | `hapticFeedback` AS:247 | ✅ | Reference puts it on the Accessibility tab. |

**Settings window**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| Tabs: General, Droplets, Shelf, Basket, Clipboard, Lock screen, Droppy Cloud, HUDs, Theming, Accessibility, License, About | 12 pages, SV:3-7: General, Permissions, Appearance, Dynamic Island, Sound, Display, Shelf, Tray & Basket, Clipboard, Lock Screen, Droplets, About | 🟡 | Consider regrouping: Sound + Display → **HUDs**, Appearance → **Theming**, move Permissions and haptics into **Accessibility**, split out **Basket**. Reference tiles are glass (`SettingsSidebarGlassTile`); ours are gradient tiles. |
| Search: "Settings sidebar search prompt", "Try searching a feature, option, or synonym." (indexes every option with synonyms, e.g. "external monitor", and deep-links to it) | filters page titles, subtitles and droplets only, SV:69-85 | 🟡 | Build a per-option index with keywords and jump to the row. |
| "Solid settings background" | none | ❌ | |
| "Show in Settings sidebar" (droplets), "Droppy Cloud in sidebar" | enabled droplets always listed, SV:154-172 | 🟡 | Add a per-droplet sidebar toggle. |

**Permissions page**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Permissions overview" ("Review and grant everything Droppy can use."), "Permission prompts", "Required permissions"; kinds: Accessibility, Automation, Bluetooth, Contacts, Full Disk Access ("Needs Full Disk Access", for Focus), Calendars, Camera, Microphone, Reminders, Input Monitoring; "Open Accessibility Settings", "Permission granted." | 10 kinds with Allow / Open Settings / Reset / Relaunch, SV:363-466, `Services/PermissionService.swift:23` | 🟡 | Ours is richer (Reset, Relaunch). Add Full Disk Access, Camera, Bluetooth and Contacts only if those features exist. Add a "Required" group. |

**Onboarding**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Hey there! 👋", "Welcome to Droppy", "Choose your display style", "Drag files to your notch or island…", "Right-click the Notch or Island to access Settings anytime", "Get Started", "You're All Set!" (with a haptic finale; `hasCompletedOnboarding`), "Replay the welcome tour" | none | ❌ | Add a first-run panel of 3–4 steps, plus a replay button in About. |

**Droplet store**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Show All Droplets", "FEATURED DROPLET" hero with editorial images, "Community Droplet", categories All / Installed / Productivity / Media | list plus a segmented picker (All / AI / Productivity), SV:952-1035 | 🟡 | Add a featured hero card and the Installed and Media filters. Drop or merge AI. |
| "Install" / "Installed" / "Uninstall" / "Installing" / "Setting up droplet" / "Removing droplet"; install progress bar | on/off switch per row, SV:1039-1088 | 🟡 | thunderstorm-screenshot-3 shows a green "✓ Installed" pill, a red "Uninstall" pill and an → arrow. Consider the install model instead of a switch. |
| Detail: separate `ExtensionDetailWindow` with hero screenshots and a settings anchor | inline detail page, SV:1103-1187 | 🟡 | Add a screenshot gallery. |

**Backup, reset, about, crash report**
| Reference | Ours | Status | What to change |
|---|---|---|---|
| "Transfer settings" / "Export or import your settings… Importing restarts Droppy"; export file "Droppy Settings yyyy-MM-dd HH-mm"; includes menu-bar item positions; bundle check | Backup export/import, `App/AppSettings.swift:88,114`, SV:328-340 | ✅ / 🟡 | Add a timestamp to the file name. |
| "Reset all settings to defaults" / "Reset everything" / "Hard reset Droppy?" ("keep your clipboard history or clear it too", then restarts) | settings-only reset, AppSettings.swift:78, SV:342-351 | 🟡 | Add a hard reset that wipes data, with a "keep clipboard" choice. |
| About: "Version Information", "View build and version details.", "Read the full history" (changelog), privacy statement, "Replay the welcome tour", "Tap 10 times to unlock developer tools" | icon, name, version, SV:1282-1320 | 🟡 | Add a changelog link, a privacy blurb and the tour replay. |
| Crash report: "Droppy Crashed", "…copy a crash report…", "Crash Report Copied" (sanitized signature from DiagnosticReports, sent after a crashed session) | none | ❌ | Low priority. |
| Updates: "Check for Updates…", "Update & Restart", "New version available", beta channel | none | ❌ (note only) | |
| Licensing: "Activate License…", "3-Day Trial", Gumroad, 30+ trial and license messages | none | ❌ (note only; out of scope) | |

## 2. UI/UX differences seen in screenshots
- **Nav capsule** (pomodoro-screenshot, notes-screenshot-1, ai-coding-hud-screenshot-1, terminal-notch-screenshot): one small capsule, about 3×30 pt, holding 3 icons (house, tray, grid). It is translucent grey glass with a lighter "selected" disc. Ours is two opaque black capsules with a tray count badge and a calendar segment.
- **Extra buttons**: the reference puts separate **round glass buttons** beside the capsule (✕ close, ↗ open-external, ↻ restart). We have none.
- **Shelf surface**: pure black at the top, fading to Liquid Glass with a light hairline rim at the bottom (terminal-notch-screenshot, notes-screenshot-1, ai-coding-hud-screenshot-1). The bottom corner radius is about 40 pt. Ours is flat black.
- **Notch HUD shape**: the resting notch HUD is wide and shallow with tight ~10 pt bottom corners (meeting-controls-screenshot-1, notification-hud-screenshot). The notification drops as a tall black slab from the notch with no ears.
- **Floating island on notchless displays**: dark-glass capsule with artwork, title and bars (lyrics-screenshot-2). Similar to ours.
- **Droplet store rows** (thunderstorm-screenshot-3): large 44 pt icons, a two-line title/subtitle, "Installed" and "Uninstall" pill chips, and an arrow. The selected row is filled with the accent colour.

## 3. Ours only (keep)
- Motion **styles** (Dynamic Island/Snappy/Gentle/Minimal) with a Preview button.
- Notch corner-fillet slider and a live appearance preview.
- Detected-screens list with PRIMARY/NOTCH/ACTIVE badges.
- "Follow Active Window / Mouse" and All-Displays mirrors.
- Default shelf page picker and ⌘1–⌘4 page switching.
- Keep Shelf Open (pin).
- Rich status-bar menu with page shortcuts.
- Permission Reset/Relaunch flow with the Automation-reset explanation.
- Configurable global-shortcut modifier with conflict warnings.
- Scroll-on-notch volume and brightness.
- Double-click play/pause.
- Droplets listed in the Settings sidebar.

## 4. Coverage note
I went through all 236 lines of `buckets/shell.txt` and also grepped `ref_all_strings.txt` and the binary. The following lines belong to other areas or are internal, so I left them out of the table:
- **Thunderstorm** (system-settings catalog and commands): "Choose the startup disk…", "Control Center modules…", "Game Center…", "General Mac settings…", "Lock the screen…", "Lock timing…", "Preferred languages…", "Privacy permissions…", "Time Machine…", "User accounts…", "Quit every running application", "Quit running app", "Press Return to quit", "No supported app running".
- **Thaw**: Hover, Show on hover, Show on hover delay, Icon refresh interval, Custom icon as template, Toggle hidden icons, Reset Menu Bar Layout, Menu Bar Manager Settings…, "Each icon can only be Shown or Hidden."
- **LiquidMouse curves**: Ease In Out Cubic/Quartic, Ease Out Quartic, and the six "…ramp/pickup/mid-curve" descriptions.
- **Screenshot editor**: Background Style, Wallpaper, "Uses your current macOS wallpaper.", Refresh wallpaper.
- **High Alert**: Milestone haptics, "Instant expand on hover", "Instant shelf expand on hover", "Start and stop instantly…", Authorize & Restore, "The permission could not be installed", "The one-time permission could not be installed", "This macOS account name cannot receive the scoped permission."
- **Other droplets**:
  - Lock screen: "Motion behind panel".
  - Media: "Automix animation".
  - Arcade: "Choose the in-shelf game look…".
  - TermiNotch: "Edit and save your script…".
  - Alfred: "Workflow setup and install details".
  - LocalSend: "Reset to this Mac's name".
  - Basket: "Minimize to Switcher (Activate in Settings)".
  - Shelf widgets: "Rearrange widget icons".
- **AI runtime installer**: "…runtime…", Install*/Reinstall*/Uninstall runtime, Apple Silicon, "Looking up latest runtime release", "Runtime did not report…".
- **Updater and licensing** (only noted above): all Trial, License and Update strings, Donation, Support, "Faster updates".
- **Internal or dev**: "Application Support directory not found", "Compact surfaces", "Settings tab title", "Settings sidebar section header", "Extension category", "Extension subtitle", "Collapse settings", "Prompting for Accessibility permissions", "Close and Quit".
- **Unclear**: "Sunglasses" (no reference in the binary; probably an app-icon name).

## 5. Live measurement (2026-09-22, built-in display, open shelf, Home page)

Both apps were captured in the same 800×420 pt region under the notch.

| | Reference | Ours |
|---|---|---|
| Shelf width | ~562 pt | ~640 pt |
| Shelf height, Home page (media + weather) | ~215 pt | ~205 pt |
| Bottom corner radius | ~35 pt | ~30 pt |
| Surface | Black at the top, fading to Liquid Glass at the bottom edge, with a hairline rim | Flat black |
| Lane pill | One grey-glass capsule, ~95×30 pt, 3 icons, lighter disc on the selected icon, ~12 pt below the shelf | Two black capsules: home/tray/widgets, then calendar/customize |
| Player artwork | ~70 pt | ~55 pt |
| Weather card | Separate grey-glass rounded card: "Local ➤", temperature, H/L, 4-hour forecast | Text inside the black shelf: WEATHER, temperature, condition, AQI, sunset |
| Output button | AirPods icon to the right of the transport controls | Not in the row |

## Done in phase 1
- ✅ **Surface style**: set per display class (`notchedSurfaceStyle`, `notchlessSurfaceStyle`) and drawn by `IslandSurfaceFill` in `LiquidGlassTheme.swift`. Dynamic Glass keeps the area under the notch pure black and fades to glass with a bottom rim; a resting notch or a notch-high HUD stays pure black.
- ✅ **Window Tint**: `windowTint` washes the Settings window and the glass surfaces.
- ✅ **Hairline outline + Show in resting state**: `subtleOutline`, `outlineInRestingState`.
- ✅ **Auto expand Shelf**: now off by default, with a one-time migration (`didDisableShelfAutoExpandByDefault`).
- ✅ **Hide notch from screenshots**: `hideFromScreenshots` sets `sharingType = .none` on the notch and its mirrors, the Basket, the clipboard and the Live Activity panels (via `CaptureExclusion`).
  - macOS's own screenshot tools honour this. Some ScreenCaptureKit recorders on recent macOS ignore `sharingType`, and no public API can stop them.
- ✅ **Hold-modifier reveal**: `holdToReveal` with a choice of modifier combo. `NSEvent.modifierFlags` is polled only while hidden, so no Input Monitoring permission is needed.
- ✅ **Right-click menu**: a "Hide Notch/Island" item (`rightClickToHide`). While hidden, a right-click on the top-centre region reveals it (`rightClickToReveal`), and the menu-bar menu gets a "Show Notch/Island" item.
  - The hidden state is not persisted, so a relaunch always shows the island. HUDs, banners and the open shelf still appear while it is hidden.
- ✅ **Startup & Visibility labels**: shortened. Hiding the menu bar icon now shows the "Hide menu bar icon?" confirm.
- ✅ **Haptics**: moved to Accessibility.
- ✅ **Settings tabs**: regrouped to match the reference IA.
- ✅ **Search**: now a per-option index with synonyms that deep-links to the row.
- ✅ **Permissions**: shown as an overview summary row on General.
- ✅ **Onboarding**: `Windows/OnboardingWindowController.swift` shows a welcome tour on first run (`hasCompletedOnboarding`), replayable from About. It ends with a haptic finale.
- ✅ **Transfer settings**: the export file name carries a timestamp.
- ✅ **Hard reset**: optionally keeps the clipboard history, then relaunches.
- ✅ **About**: shows the changelog, the privacy statement and the tour replay.
- Shortcuts: every global shortcut can be recorded, is stored as `shortcut.<action>` (keyCode:modifiers) and registers live. The old shared modifier is now only the default.
- Skipped, left to the Shelf, HUD and multi-display phases:
  - Notch/Island on notched Macs, Hide physical notch, Shelf Size, offsets, Animation Speed.
  - Enable Shelf, Auto collapse, Auto-Expand Rules, In Fullscreen, Mission Control.
  - Gestures, nav bar and floating buttons, favorites, external display rules.
  - Solid settings background, per-droplet sidebar toggle, the droplet store redesign.
  - Crash report. Updates and licensing are out of scope.

## Done in phase 2
- ✅ **Shelf metrics**: `DroppyShelfMetrics.width`/`wideWidth` 586 pt (a ~562 pt body between the 12 pt top fillets), bottom corner 35 pt. The full player alone keeps its narrower 380 pt (ours).
- ✅ **Shelf Size**: Regular | Enlarged (×1.12) instead of S/M/L, as in the reference's Settings screen.
- ✅ **Animation Speed**: `animationSpeed` retimes every island spring in `DS.Motion` via `.speed()`; the four motion styles are kept.
- ✅ **Enable The Shelf**, **Auto collapse Shelf** (off = stays open until a click elsewhere or Esc), **Auto expand delay / collapse delay** relabelled.
- ✅ **Shelf Gestures**: two-finger swipe down on the resting notch opens the shelf, sideways on the open shelf switches pages (`ShelfGestureService`). Scroll-volume stays: "Scroll on the notch: Volume | Open shelf" decides which one the vertical scroll does. Reverse swipe direction was not added (swipes follow the physical finger direction regardless of natural scrolling).
- ✅ **Nav bar**: one capsule (Home/Tray/Widgets) or wing tabs; the lane pill no longer carries Calendar or Customize.
- ✅ **Floating buttons / Favorites / contextual buttons**: round glass buttons beside the bar — Calendar (toggle), up to 4 favorites (widget, app or Shortcut), and page buttons through `.shelfAccessories(owner, [ShelfAccessory])` (✕ on Pomodoro/Timer/High Alert/System Stats/Quick Math/Color consoles, ↗ and ↻ on TermiNotch). Hit-testing and the hover rect follow the row's width.
- Skipped: the reference's per-widget floating-button toggles (Clipboard/Files/High Alert/…), floating button size/style/colour and the all-off switch — Favorites covers pinning any widget; Auto-Expand Rules, In Fullscreen, Mission Control, Shelf Height Offset (HUD/multi-display phases).

## Done in phase 3
- ✅ In Fullscreen Show | Hide media | Hide all (detected per screen); Hide in Mission Control / App Exposé (needs Accessibility).
- ✅ External display style Notch | Island; Hide on external displays; Per-display visibility; Show when idle (`showWhenIdle`); Collapsed HUD scope.
- ⏭ Now Playing display (Under pointer / MacBook) is left to Phase 4, the media phase.

## Done in phase 10
- ✅ **Droplet store**:
  - All / Installed / AI / Productivity / Media chips.
  - A "FEATURED" hero carousel with drawn art.
  - Captions that include "Community Droplet".
  - Two-column rows.
  - Detail page with Set Up and Turn On / Turn Off pills, status chips and an illustration.
  - See 8-settings-screens › Done in phase 10.
- ✅ **"Show in Settings sidebar"**: a per-droplet switch (`sidebarHiddenDroplets`) on each droplet's page.
- ⏭ Install/Uninstall with a progress bar: built-in droplets have nothing to install, so we use Turn On / Turn Off.
- ⏭ Screenshot gallery: we use a drawn illustration instead, because the reference's screenshots can't be copied.
- ⏭ Crash report: not built. It would need to read DiagnosticReports after a crash. Diagnostic logging and Export Logs (About) cover troubleshooting instead.
- ⏭ Solid settings background: not built. The glass window follows the reference screenshots, and Window tint already adjusts it.

## Done in phase 11
- ✅ **Reverse swipe direction** (`Settings › Shelf › Behavior › Swipe direction`, `shelfSwipeReversed`): Standard | Reversed flips both the sideways page swipe and the new up-down Tray-stack swipe. `ShelfGestureService.direction(_:reversed:)` is the one rule, unit-tested.
- ✅ **Floating button size** (`floatingButtonSize`: Small 26 / Regular 30 / Large 36 pt). `DroppyShelfMetrics.floatingButton` reads it, so the SwiftUI row and `AppState.lanePillSize` stay in step.
- ✅ **Floating button style** (`floatingButtonStyle`): Glass (grey capsule, the widget's own colour on the symbol) | Colored (the widget's colour fills the circle) | Monochrome (every symbol white). Plus **Icon color** (`floatingButtonLightIcons`, Light | Dark) for colored buttons — the reference's "Set icon/text color for colored floating buttons". The per-widget tint comes from `DropletPalette`, so each favorite keeps its own colour; apps and Shortcuts keep their real icons. The Settings favorites editor previews the chosen style.
- ✅ **Solid settings background** (`Settings › Theming › Settings window`, `solidSettingsBackground`): one opaque colour instead of the translucent glass, which also fixes the washed-out text when the window sits over a bright desktop.
- ✅ **Reopen**: `applicationShouldHandleReopen` now always shows Settings. The island panels are always on screen, so `hasVisibleWindows` was true and clicking the Dock icon (or `open`) did nothing once Settings had been closed.
- ⏭ Still skipped: the reference's per-widget floating-button *toggles* (Clipboard / Files / High Alert / …) — Favorites already pins any widget, app or Shortcut to that row — and the "all floating buttons off" switch, which is emptying Favorites.

## Done in phase 13
- ✅ **Typing in the shelf holds it open, per field**: `isEditingText` was one flag that only the Calendar's new-task field, the Scratchpad and the Obsidian note editor ever set. Typing into TermiNotch (quick bar and the live shell), Thunderstorm's search, Quick Math, the OCR result editor, the Meetings task field or a Notification HUD reply left auto-collapse free to close the shelf and take the text with it. It is now derived from an owner set (`EditingOwners`, the same `OwnerSet` that backs `ModalOwners`) through `setEditing(_:owner:)`, so a console holding both a search box and an editor can't clear the hold while the person is still typing in the other. A console going away clears its own `droplet.<id>` prefix, and the shelf closing clears every field, which covers a focused field that is dismantled without reporting it.
- ✅ **Leaving the Widgets page ends rearranging**: `isRearrangingWidgets` is only drawn on the Widgets page but also blocks auto-collapse, so a page switch by the navigation bar, the calendar floating button or ⌘1–⌘4 parked the shelf open with nothing on screen explaining why and nothing able to close it (the swipe gesture already refused to leave; the other routes did not). `shelfPage`'s `didSet` now ends it, in the same place that already closes the output picker, the player panels and the home draft.


## Done in phase 15
- ✅ **Crash report** ("Droppy Crashed", "…copy a crash report…", "Crash Report Copied"): `CrashReportService` reads the newest Droppy `.ips` from `~/Library/Logs/DiagnosticReports`, summarises it (version, macOS, Mac, exception, termination, the crashed thread and any uncaught-exception backtrace), sanitises the account name, home folder and machine identifiers, and offers it on the clipboard. `CrashReportWindowController` shows it after a crash, and Settings › About › Troubleshooting has the last report and the prompt switch. It is never uploaded — the row that called this "low priority, needs a server" assumed the reference sent it; the reference copies it too.
- ✅ **Onboarding** now runs eight steps: welcome, display style, dropping files, Tray/Basket/clipboard, Widgets, permissions, the right-click menu, and the finish — with Skip on every step, dots that jump, and "Open the Guide" beside "Start Using Droppy".
- ✅ **Droplet store hero and detail art**: the row that asked for "a featured hero card" and "a screenshot gallery" is answered by `DropletShowcase`, which draws each droplet's own console — the reference's screenshots aren't ours to copy, so ours are drawn. One showcase per droplet rather than a gallery of four.
- ➕ **Ours only**: a searchable User Guide (`DroppyGuide`, `UserGuideWindowController`) with live shortcut tables and Settings deep links, listed in Settings search under "From the guide". The reference has no in-app guide; it has a Setup Guide checklist, which we already had.
- ➕ **Ours only**: `droppy://show?target=guide|tour|settings`, `droppy://settings?page=<tab>` and `&droplet=<id>`.
