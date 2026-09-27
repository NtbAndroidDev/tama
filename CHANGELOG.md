# Changelog

Tama for Mac is being brought to parity with the reference Droppy 14.2.0, one phase at a time. The plan and the audits live in `docs/parity/`.

## UI/UX pass

**Bugs**
- The automatic brightness HUD is now off by default. With macOS auto-brightness on, ambient light changes kept popping the HUD up unprompted; turn it on in Settings › HUDs.
- Dragging the scrubber on a track of unknown length no longer jumps to 0:00, and the length/remaining toggle works for sources that can't seek.
- Deleting a voice transcript from its context menu now asks first, as the trash button does; it can't be undone.
- Widget icons no longer sit tilted while rearranging with wiggle off; rearranging with no widgets shows an empty state.
- The mirrored notification banner's VoiceOver "Dismiss" no longer also runs the notification's action.
- The target-size dialog no longer suggests 1 MB for files under 2 MB (which it then rejected).
- Esc closes the Guide, What's New, the crash report and skips the tour; the tour's final check mark animates.
- The empty task list says to click +, and the Legacy clipboard's Clear dialog describes what it actually clears.

**Confirmations and states**
- Clearing logs, clipboard history, the upload list, a 0x0.st file, Claude Code hooks, a LocalSend favorite, Momentum and the Menu Bar layout now ask first.
- Greyed-out Settings rows say what they need. Settings search highlights matches, and ↑/↓ with Return picks a result.
- Droplet consoles share one header, status-badge and permission-card pattern; Quick Convert gained Choose file….

**Polish**
- DS tokens replace hard-coded spacing, type and colours; moving animations respect Reduce Motion; icon-only buttons have tooltips and VoiceOver labels; changing numbers use tabular digits; copy is sentence case.

## Performance pass

**Less work while nothing happens**
- Media: with nothing playing, the fallback poll runs every 5 s instead of 1.5 s, and players are probed when they launch or quit instead of on every tick. The probe scripts are compiled once, Up Next covers are downsampled off the main thread, and app names are cached.
- Accessibility is re-checked when it changes or when Tama comes forward, instead of being polled every 2 s. The automatic-brightness watch reads only the built-in panel, every 2 s.
- Home's System, Battery and Weather cards stop their services while the shelf is closed. Audio Control does nothing while its droplet is off, and its meters publish only real changes. The Tray's missing-file check runs every 30 s and when the shelf opens, and skips when nothing is held.

**Fewer redraws**
- The Pomodoro countdown, the playhead and the High Alert countdown no longer redraw every view that watches the app's state; only the views that show them update. The countdown timer publishes once a second instead of four times.
- Scroll-to-change-volume is coalesced to 30 updates a second, and a HUD showing the same level doesn't redraw.
- Clipboard cards and Tray tiles don't redraw on unrelated changes. The clipboard filter runs once per pass, and a card trims at most the first 2,000 characters of a long clip. Quick Math no longer writes the app's state on every keystroke.

**Off the main thread**
- Fullscreen detection (with a 0.2 s Accessibility timeout, so a hung app can't stall Tama), folder sizes in the Tray, moving, copying and Create Folder, saving notes, calendar, meeting and reminder fetches, the Agents log and the capture editor's PNG export.
- Copying an image clip puts the stored PNG on the pasteboard and makes TIFF only if the pasting app asks for it.

## Phase 15: The guide, the tour, the store, and a crash that nobody saw

**A guide you can read**
- **Tama Guide** is a new window: fifteen articles across Start here, The notch, Files, Clipboard, Media, Productivity, Tools and Reference, with a search field that reads every word of every article and picks the matches out in the body. It opens from Settings › About, the menu bar (⌘?), the notch's right-click menu — where it lands on the article for the page you are looking at — and ⌘? in the open shelf.
- Every shortcut it names is read from `GlobalShortcutService`, so the keys on the page are the keys that are set; one that has never been recorded says so and offers the recorder. Every "Open in Settings" link is a real Settings anchor, scrolled to and highlighted the way a search hit is, and a test fails if one of the 78 links stops resolving.
- Settings' own search now answers "how do I…" as well as "where is…": matching guide articles are listed under **From the guide**, and a search that finds no option offers to search the guide instead.

**The welcome tour**
- Two new steps: what the Tray, a Basket and the clipboard are for — with the shortcuts you actually have — and what the Widgets page holds. **Skip** ends the tour from any step, the dots are buttons that jump to a step, and the last step offers the guide as well as the door.

**Explore shows what a droplet does**
- The store's hero card and each droplet's page used to be a gradient with a faded glyph, and a mock shelf holding three grey placeholder bars. Somebody deciding whether to turn a droplet on learned nothing from either.
- All 28 droplets now draw their own console — the Pomodoro ring at 18:04 with the day's sessions, LocalSend's transfer in flight, Thunderstorm's results, the capture selection with its size readout, Window Snap's tiled screen, the waveform Voice Transcribe shows while it records — inside a miniature shelf with the notch's own bottom corners. The reference puts a screenshot there; we draw ours, since its images aren't ours to copy. A test keeps the drawings and the droplet list together.

**A crash report to copy**
- Tama reads the newest `.ips` macOS wrote for it, turns it into a summary a person can read — version, macOS, the exception, the crashed thread — and offers it on the clipboard. Nothing is uploaded: there is no server, and there is no analytics in Tama. The account name, the home folder and the identifiers macOS uses to recognise this Mac are taken out first, and only the values from the report are rewritten, so an account called "Mac" can't turn the headings into nonsense.
- Settings › About › Troubleshooting has the last report and a switch for the prompt.

**Fixed**
- **Tama could deadlock on launch.** `AppState`'s stored `mediaService` property builds `MediaService.shared` while `AppState.shared`'s own one-time initialiser is still running, and `MediaService.init` reached back for `AppState.shared` to filter media sources — `dispatch_once` waiting on itself, `EXC_BREAKPOINT` before the first window. The expansion watch was already deferred for this reason; the first fetch and the poll now are too.

**Smaller things**
- The empty Tray says what to do with it, and says "Release to keep them here" while a drag is over it.
- `tama://` gained `show?target=guide|tour|settings`, `settings?page=<tab>` and `settings?page=droplets&droplet=<id>`, for scripts, Shortcuts and launchers.

## Phase 14: Keyboard in the Basket, and a pass over what redraws

**The Basket answers the keyboard**
- A Basket now takes the same keys the Tray does: the arrows move through its files (⇧ extends the selection, and all four arrows step in order — the grid's columns depend on the width it is given, so pretending to know where a row ends would only be right by accident), ⌘A selects all, Space is Quick Look, Return opens, ⌘C copies, ⌫ removes with an Undo banner and ⌘Z takes it back, ⇧⌘M moves the files somewhere. ⌘↑ sends the selection to the Shelf, ⌘M minimises the Basket to its pill and ⌘W puts it away.
- ⌫ keeps the keyboard on the nearest file that survives, so pressing it again carries on down the list. A file that goes without anyone pressing a key — pruned when it vanishes from Finder, or moved to the Shelf from a menu — steps the keyboard to its neighbour instead of leaving a dead anchor, which used to send the next arrow key back to the first file. The Tray and the clipboard already did both.
- Shift-click in a Basket selects the run from the last plainly clicked file, as it does in the Tray.
- A Basket takes the keys when it is clicked and its outline brightens to say so; clicking any other app takes them straight back. It takes them on mouse-up, not mouse-down, so a file dragged out of a Basket and into the editor somebody is writing in doesn't take the keyboard away from it.

**What gets done while drawing**
- Finder icons are cached app-wide (`FileIcon`). The Tray's tiles, a Basket's rows, the Shelf's app favorites, the folder browser, Thunderstorm's results and the tracked-folder list each asked LaunchServices for the same icon again on every redraw — a hover, a keystroke in a search field, a drag in flight. The clipboard's own icon cache now shares it.
- The Tray's rail is lazy, like the clipboard's: a Tray holding dozens of files only builds the tiles on screen, so their thumbnails are decoded as they're scrolled to rather than all at once when the shelf opens.
- The folder browser reads the folder off the main thread and settles each row's kind and size when it does. It used to `stat` every visible file again on every redraw — once per keystroke in its search field — and `contentsOfDirectory` blocked the shelf on a large or networked folder. A slow folder now shows a spinner instead of reading as empty.
- The clipboard's Legacy layout drew its image preview by loading the stored full-size PNG inside `body`, decoding a screen-sized image again on every redraw. It uses the shared downsampled thumbnail now.
- The clipboard history is encoded and written off the main thread, through one serial queue so two changes close together can't land out of order; the quit flush goes through the same queue and waits, so a write in flight can't undo it. The Tray's list is debounced like the Baskets' — dropping twenty files used to re-encode the whole list once per file.
- LocalSend's staged files add themselves up when they're picked. The console's summary is redrawn on every progress tick of a transfer, and it used to `stat` every staged file per tick.

**Sleep, and not cooking in a bag**
- Lid-Closed High Alert ends itself when the charger comes out. It is the one thing in Tama that can stop a Mac sleeping with the lid shut (`pmset -a disablesleep 1`), and a Mac that can't sleep, on battery, in a closed bag, gets hot and flat. Unplugging now puts system sleep back and says so. Starting it while already on battery warns.
- `PowerStateService` follows sleep and screen-off (`willSleep` / `didWake`, `screensDidSleep` / `screensDidWake`). The pollers that exist only to keep the notch current stand down while nothing can be seen: the Basket's auto-hide countdown, the fullscreen watch, the automatic-brightness watch and the Agents poll — which reads each agent's log and Cursor's database every two seconds and is the busiest thing Tama does at rest. The Agents pause keeps the sessions it has found, so the notch comes back showing what it showed before. A locked screen is deliberately not counted: Tama draws its own lock screen, and what is behind it has to stay current.
- Waking refreshes the player, battery, headphones, system stats and the external-display link in one sweep, instead of showing what was true when the screen went off until each poller's next tick came round.
- The Basket's auto-hide countdown only runs while a Basket is actually out. It used to be started at launch and left running for the life of the process — two wake-ups a second, for ever, to find there was nothing to hide.
- The **Agents** Droplet is off until it is switched on. It was the one Droplet that arrived enabled, so a glyph and a spinner appeared in the notch for a Codex or Cursor session nobody had asked Tama to follow — and its two-second poll, which reads each agent's log and Cursor's database, ran from the first launch. Menu Bar Manager already started switched off.


## Phase 13: UI/UX logic fixes and tracked-folder actions

**Typing in the shelf**
- The shelf no longer collapses under a half-typed line. "Someone is typing" used to be a single flag that only the Calendar's new-task field, the Scratchpad and the Obsidian note editor ever set, so typing into TermiNotch, Thunderstorm's search, Quick Math, the OCR result, the Meetings task field or a notification reply left the shelf free to close and take the text with it. Every text field in the shelf now holds it open, the live shell included.
- The hold is per field, like modals are per surface. Moving from a console's editor to one of its settings fields used to clear the flag while the person was still typing; the last field to be left is now the one that releases it.
- A console torn down with its field focused never reports losing focus, so closing a droplet clears that droplet's fields, and closing the shelf clears all of them.

**Shelf modes**
- Leaving the Widgets page ends rearranging. It is only drawn on that page but it also keeps the shelf open, so switching away with the navigation bar, the calendar button or ⌘1–⌘4 parked the shelf open with nothing on screen explaining why and no way for it to close itself.

**Tray keyboard**
- The arrow keys keep the file they land on in view. The rail scrolls, so the focus could walk off the end of what was on screen — the clipboard already scrolled, the Tray didn't.
- A file added while the rail is scrolled deep into the list brings the rail back to it. A file that expires does not.
- ⌫ keeps the keyboard on the nearest file that survives, so pressing it again carries on down the rail instead of doing nothing. The clipboard already did this.
- ⌘C copies the selected files, as Finder does and as the clipboard shelf already did.

**Tracked folders**
- Each watched folder now says what a new file does: **Add to Tray**, **Add to Basket**, or **Add and compress**. Until now every folder could only add to the Shelf, although the picker already promised "Watch and process files from selected folders". Folders set to compress share one level, since there is nobody to ask while it runs.
- Arrivals are gathered per action, so a folder filling up is one job rather than one per file. Folders saved by earlier versions keep working and keep adding to the Tray.

## Phase 12: UI/UX logic fixes, accessibility and LocalSend sharing

**Shelf behaviour**
- The collapse delay now defaults to 0.40s, up from 0.15s. Anything much shorter and the shelf is gone before a deliberate move can land on a control just outside it. A delay already set shorter than that is raised once, so it takes effect on machines that had tuned it down; set it back and it stays.
- An open menu now keeps the shelf open. A context menu is drawn outside the island, so reaching for it read as having left: with the collapse delay at its lowest the shelf closed after 100 ms, before "Customize Home…" could be clicked. Any AppKit menu now counts as a modal.
- Auto-collapse arms itself again once whatever held the shelf open lets go — a sheet dismissed, a pin removed, a task field left. It used to give up if the pointer had stopped moving, leaving the shelf open until the pointer visited it again.
- Modal state is per-surface. The Tray, each floating Basket and a service alert can each have a sheet up at once; closing one no longer clears the others' protection and lets the island collapse over an open sheet.
- Switching pages no longer closes the shelf. A shorter page shrinks the island, and a pointer standing still could be left outside it; the island moving away now counts as the island moving, not as the person leaving.
- A drag called off while still over the island (Esc, or the source app cancelling) no longer leaves the drop tiles showing and auto-collapse switched off.
- Leaving an Obsidian note with the editor focused no longer leaves "someone is typing" set for the rest of the session, which kept the shelf from ever collapsing on its own again.

**Clipboard and Tray**
- Deleting a clip from its own menu keeps the keyboard on the neighbouring clip. It used to jump to the newest clip and scroll the shelf back to the front, so the next Delete took a clip nobody meant to touch. The Tray does the same when a file expires or is trashed in Finder.
- ⇧-click works again after the clip it would have measured from was deleted; it used to do nothing at all, not even select.
- Renaming a clip that then leaves the list — pruned, deleted, or just filtered out by a board or tag — no longer leaves the clipboard's keyboard dead until it is closed and reopened.

**Accessibility**
- The shelf's round icon buttons (transport, Tray actions, headers) speak their name to VoiceOver instead of a raw SF Symbol id, and say when they're selected. Tooltips are a hint, and Settings › Accessibility › Show tooltips can switch them off entirely.
- Labels for the snip console's Keep in Tray and Reveal in Finder, TermiNotch's close-tab and the droplet store's carousel arrows.

**LocalSend**
- **Share in a browser**: staged files can be held behind a plain web page on the same port, so a device with no LocalSend installed — a phone, a Windows PC — can download them by typing this Mac's address. The page is self-contained, reads on a phone and follows the browser's light/dark setting. The receiving PIN guards it too, and files stream in chunks rather than being held in memory.
- Tama answers LocalSend's older **v1 API**, so devices still running LocalSend 1.x can send to this Mac.

**Other**
- Copying to iCloud Drive says when only some of the files made it, instead of reporting the smaller number as if it were everything.
- "Reset all settings" clears the one-shot Home tip again.

## Phase 10: Droplet store, LocalSend and finishing touches

**Droplet store**
- Settings › Droplets is now a store: All / Installed / AI / Productivity / Media chips, an "Explore" title, a hero carousel of featured droplets with drawn art (arrows, page dots, auto-advance that pauses on hover) and a two-column list with category captions, including "Community Droplet".
- Each droplet's page has a back button, a large title, Set Up and Turn On / Turn Off pills, a big icon with its tagline, category and status chips (Needs Setup, Installed), an illustration, the description, then all of its settings.
- New "Show in Settings sidebar" switch per droplet.

**LocalSend**
- A new LocalSend droplet sends and receives files with any device running LocalSend (phones, Windows, Linux and Macs). It speaks protocol v2: multicast discovery, a network scan, and HTTPS with a certificate made on this Mac. A plain HTTP mode is also available.
- Send from the Tray or Basket menu ("Send with LocalSend"), from a LocalSend Quick Action tile, or by dropping files on the widget.
- Receiving can be set to Off, Favorites or Anyone. Each transfer asks first ("Incoming requests"), and you can add an optional PIN. Quick Save covers favorites.
- Choose where received files are saved, and whether they are added to the shelf. The device name is editable, with "Reset to this Mac's name". Forget a device you no longer trust.

**Polish**
- Diagnostic logging ("Write detailed logs for troubleshooting") and Export Logs… in About › Troubleshooting.
- Show tooltips switch in Accessibility.
- This What's New window after an update, plus a Setup Guide checklist ("Recommended setup").
- Read Aloud for clipboard text and text files in the Tray.
- Lyrics and Quickshare say "No Internet Connection" when offline, and lyrics retry once you're back online.

## Phase 1: Settings, theming, accessibility and onboarding

**Settings window**
- A new glass Settings window with a search field and a grouped sidebar: General and Droplets; Workspace (Shelf, Basket, Clipboard, Lock screen); System (HUDs, Theming, Accessibility); and About. Enabled Droplets still get their own sidebar rows.
- Search covers every option, including synonyms such as "external monitor" or "hide icon". Picking a result opens its page, scrolls to the row and briefly highlights it.
- A shared set of building blocks for every page: section cards, toggle and choice tiles, preview cards, sliders with value pills and reset buttons, shortcut recorders and expandable summary rows.

**General**
- Startup & visibility tiles: Menu bar icon, Dock icon and Launch at login. Hiding the menu bar icon asks first.
- A permissions overview that shows how many permissions are granted and expands in place.
- File actions:
  - Auto-remove.
  - Protect originals, which is on by default. Drags out of the Tray and Basket are then copies. With it off, multi-file drags can move files.
- Auto-copy OCR text: text read by the OCR droplet or a Tray preview goes straight to the clipboard.
- Every global shortcut can now be recorded and reset, and a new shortcut takes effect immediately.

**Theming**
- Surface styles for each kind of display:
  - Notched displays: Dynamic Glass or Black.
  - Notchless displays: Dynamic Glass, Black or Liquid Glass.
  - Dynamic Glass stays black under the notch and fades into glass at the bottom edge, with a hairline rim.
- A subtle outline, which can also be shown in the resting state.
- Color tapes for the highlight color (new presets plus any custom hex), the window tint, and the volume and brightness meter colors.
- A Media HUD vertical position slider for the floating island.

**Accessibility**
- Right-click to hide: a "Hide Notch/Island" item in the island's right-click menu.
- Right-click to reveal, and Hold to reveal with a modifier combo.
- Haptic feedback and sound effects.
- Hide from screenshots, which covers the island, shelf, Basket, clipboard and Live Activity panels.

**About**
- Version, this changelog, the welcome tour and privacy notes.
- Hard reset: reset settings only, or reset everything and relaunch, optionally keeping the clipboard history.
- Settings export file names now carry a timestamp: "Tama Settings yyyy-MM-dd HH-mm".

**Onboarding**
- A first-run welcome tour: welcome, choose a display style, drag files, grant permissions, and "Right-click the Notch or Island to access Settings anytime", ending with "You're All Set!".

**Changed defaults**
- Auto-expand on hover is now off by default. Existing installs are switched off once.

## Before parity work

- Notch shelf with Player, Tray, Widgets and Calendar pages, the clipboard shelf, the Floating Basket, Live Activities, level HUDs, the lock screen and more than 20 Droplets. See README.md.
