# Parity audit: Tasks & Calendar, Pomodoro, High Alert, Timer, Notes/Obsidian, TermiNotch, Meetings, Notification HUD, AI agents, Notchface

I made no edits. Paths below are relative to `/Users/Shared/Data/source/macos/droppy/Sources/`. Status marks: ✅ at parity, 🟡 partial, ❌ missing.

## 1. Feature table

### Tasks & Calendar
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Tasks & Calendar" page, "Tasks and Calendar in the shelf.", "Open Tasks & Calendar" | `Views/Notch/CalendarPage.swift:5`; home card `HomePage.swift:675` | 🟡 | Rework the layout (see §2) and rename to "Tasks & Calendar". |
| "Natural-language task capture", "Date mentions like tomorrow and next Friday" | `Services/ReminderParser.swift:21` (NSDataDetector) | ✅ | — |
| "Multilingual task input" | Parser's dangling-word list is English only (`ReminderParser.swift:12`) | 🟡 | Add localized stop words and pass the detector's locale. |
| "List support with list mentions" | none. Always saves to `defaultCalendarForNewReminders` (`CalendarService.swift:240`) | ❌ | Parse `#List` / `@List` tokens and match them to EKCalendar titles. |
| "Priority levels with quick-check interactions", "Set priority", "High/Medium/Normal Priority", "Priority: X (click to change)" | none (`AgendaEntry` has no priority) | ❌ | Parse `!`/`!!`/`!!!`, set `EKReminder.priority`, add a clickable priority dot to `AgendaRow` (`CalendarPage.swift:389`). |
| "Due alerts", "Due soon notifications", "Heads-up before reminders are due.", "Chime", "Configure due reminder alerts and the optional alert chime." | none | ❌ | Add a timer that scans due reminders, posts a LiveActivity plus banner, and plays an optional chime. Add settings for both. |
| "Remove completed tasks after", "%lld tasks cleaned up" | Completing hides the row at once (`CalendarService.swift:253`) | 🟡 | Keep completed rows struck through, then remove them after a configurable delay. |
| "Hide undated tasks", "Hide tasks"/"Show tasks", "Show reminders & events" | Undated tasks always show under "Reminders" (`CalendarPage.swift:276`) | ❌ | Add toggles. |
| "Choose which Apple Calendar calendars are shown.", "Choose which Apple Reminders lists are shown in Tasks.", "No calendars found.", "No reminder lists found." | `calendars: nil` everywhere (`CalendarService.swift:127,152`) | ❌ | Add settings multiselects stored in UserDefaults. |
| "Default list for new tasks", "Default Calendar", "Choose where meeting reminders are added." | System default only | ❌ | Add pickers. |
| "Delete task", "Task deleted" | none | ❌ | Add a context-menu delete that goes through the `+Undo` banner. |
| "+1 Week" | none | ❌ | Add reschedule quick actions (for example +1 day / +1 week) to the row menu. |
| "Add a task…", "Task title", "Type above to add your first task", "No tasks yet", "No upcoming (tasks or) events", "No tasks or events" | Modal "New Task" card (`CalendarPage.swift:287`); empty state "Nothing planned" | 🟡 | Use an inline field at the top of the list and the reference empty-state copy. |
| "Event progress ring", "Show a live event progress ring in the notch.", "Show your next upcoming event or task." | Only a 10-minute meeting countdown (`Services/MeetingService.swift:36`) | 🟡 | Add a live activity with a trim ring showing how much of the current event has elapsed, plus a next-event wing. |
| "Pop out calendar", "Close calendar pop-out", "Keep calendar window on top", "Bring floating calendar to front" | none | ❌ | Add a detachable NSPanel hosting `CalendarPage` with an always-on-top toggle. |
| "Calendar + Reminders with natural language and instant join", "Join Zoom/Google Meet/Teams/Webex meeting", "Open meeting link" | `MeetingService.joinURL` `:93`; the Join button only appears in the start banner | 🟡 | Add a Join chip on event rows in the agenda and home card. |
| "Read-only (Apple Calendar)" | Events are read-only already | ✅ | Add the label. |
| "Week #" | none | ❌ | Show "(wk. N)" in headers. |
| "Syncs reminders…", "Tasks and calendar with Apple Reminders sync." | EventKit, live via `EKEventStoreChanged` | ✅ | — |
| "Show Tasks & Calendar as a floating button", "Tasks & Calendar Button" | Calendar segment in second capsule (`ShelfView.swift:149`) | 🟡 | Make it configurable (see "floating buttons" in §2). |

### Pomodoro
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Slider-based focus timer in your notch", "Set your timer with one slider directly in the shelf.", "Start the timer with the selected duration" | Ring dial plus settings steppers (`PomodoroConsoleView.swift:36`, `SettingsView.swift:823`) | ❌ | Build a horizontal ruler slider (5-minute labels, orange ticks, centre caret), a "Start Timer" capsule and a big orange mm:ss. |
| "Enable ambient sound", "Choose your preferred ambient sound" | none | ❌ | Add looping ambient audio assets, a mute toggle button and a picker. |
| "Turn on Focus during sessions", "Droppy Focus On/Off" | none | ❌ | Toggle Focus through Shortcuts ("Droppy Focus On/Off" shortcuts). |
| "Keep timer visible in notch", "Timer visibility", "Live countdown stays visible in compact HUD" | Pomodoro wing ranks below track and tray (`IslandCompactView.swift:108,142`) | 🟡 | Add a setting that gives it priority. |
| "Open the shelf the moment you hover the timer." | Generic hover-open | 🟡 | Hovering the timer should open straight to the Pomodoro page. |
| "Focus sessions, breaks, and momentum", "Focus / break timer", "Pomodoro complete/running" | Work/break cycle plus banner (`AppState+Pomodoro.swift:22`) | 🟡 | "Momentum" suggests session stats or streaks, which we don't have. |
| "Show Pomodoro controls", "Show Pomodoro as a floating button" | Ring action only (`RingAction.swift:76`) | 🟡 | Add a floating-button option. |

### High Alert
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Keep Awake Indefinitely", "Stop Keeping Awake", "High Alert active/inactive" | `SleepBlockerService.swift:16`, `HighAlertConsoleView.swift` | ✅ | — |
| "Cycles between screen awake, system awake, and lid-closed modes.", "Screen and Mac stay awake", "Mac awake, screen can turn off", "Mac stays awake with lid closed", "Lid-Closed High Alert" | Display-sleep assertion only (`SleepBlockerService.swift:33`) | ❌ | Add a mode enum: `PreventUserIdleDisplaySleep` / `PreventUserIdleSystemSleep` / lid-closed (`pmset disablesleep` via a privileged helper), plus a gear button that cycles modes. |
| "High Alert Timer", "Start High Alert with a preset duration.", "Start selected High Alert timer" | Fixed 15 min / 1 h chips | 🟡 | Use the same ruler slider as Pomodoro. |
| "Show High Alert as a floating button", "Show High Alert toggle in the shelf." | Home card and ring action | 🟡 | Add a floating button. |
| "System sleep enabled", "Put your Mac to sleep" | none | ❌ | Add a status line and a Sleep Now action. |

### Timer/stopwatch
Countdown, stopwatch and laps are in `TimerService.swift` ✅, including a notch live activity. The reference "Countdown" strings belong to the teleprompter (other area).

### Notes / Obsidian
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Quick notes that live in your notch", "Tasks & Notes" | A single plain-text scratchpad (`ScratchpadConsoleView.swift:63`) | 🟡 | Support multiple notes: a list with title, time and preview, pin/copy/delete, and a new-note button. |
| "Show formatting toolbar" (B/I/U/H1–H3/lists) | Monospaced TextEditor | ❌ | Rich text (NSTextView/AttributedString) with a floating toolbar. |
| "Sync with Apple Notes", "Syncing with Apple Notes.", "Couldn't reach Apple Notes…", "Notes script failed" | none | ❌ | AppleScript sync to a Notes folder. |
| "Grow canvas with longer notes" | Fixed 140pt (`:70`) | ❌ | Let the canvas grow up to the maximum shelf height. |
| "Your vault, live on the shelf", "Refreshing vault notes." | Capture/append only (`ObsidianConsoleView.swift`) | 🟡 | List vault notes (sorted by modified time) and open or edit them inline. |
| "Open this vault in Obsidian", "Choose the vault again…", "Vault unavailable" | `openNote`, `pickVault`, `detectedVaults` | ✅/🟡 | Add a vault-unavailable state. |

### TermiNotch
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Full terminal emulation in the notch" | One-shot `zsh -c` with a 30 s timeout (`TermiNotchConsoleView.swift:66`) | ❌ | Persistent PTY session (forkpty) with ANSI rendering; drop the timeout. |
| "Quick command & expanded modes", "Quick command bar", "Show TermiNotch bar" | Single console | 🟡 | Add a compact one-line bar mode, and an expanded full-shelf mode. |
| "Quick shell commands and tabs." | none | ❌ | Tabs (multiple sessions). |
| "Choose which app opens when you use "Open in Terminal"", "Ghostty", "iTerm" | Terminal.app is hard-coded (`:285`) | ❌ | Add an app picker. |
| "Clear terminal output" | `session.clear()` | ✅ | — |
| "Show TermiNotch as a floating button", "Enable Termi-Notch" | Droplet only | 🟡 | Add a floating button. |

### Meetings
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Detecting meetings in Zoom, Google Meet, Teams, and WhatsApp.", "Watching for meetings…", "Sleeping until a supported meeting app launches.", "Meeting app launched/Last meeting app quit" | App list refreshes on launch/quit, and mic in use is detected (`MeetingControlService.swift:63,121`) | 🟡 | Add a meeting state machine (app running + mic in use), and add WhatsApp and FaceTime. |
| "Pauses music when a meeting starts.", "Resume media after meeting", "Media paused for meeting" | none | ❌ | Hook into `MediaService`. |
| "Show active call HUD" (meeting-controls-screenshot-1: phone icon + elapsed time + mic level bars) | Only a "Muted" wing (`:154`) | ❌ | Add a call live activity with timer and mic metering. |
| "Mute microphone"/"Unmute", "Turn on/off camera", "Leave meeting/call", "End call" | `MeetingsConsoleView.swift:54` (mic, camera, share, leave) | ✅ | Show red "off" fills for mic/camera state as in screenshot-2 (we can't read camera state). |
| "Capture reminders mid-call.", "Meeting Notes" | none | ❌ | Add a quick task field in the call HUD. |
| "Screen sharing not available in Google Meet" | Share button disabled | ✅ | — |

### Notification HUD
| Ref | Ours | Status | Change |
|---|---|---|---|
| "Surface incoming notifications in the notch", "Checking the macOS notification store", "Required to read notifications." | In-app banners only (`NotchNotificationHUDView.swift`) | ❌ | Read the usernoted DB (`~/Library/Group Containers/group.com.apple.usernoted/db2`), which needs Full Disk Access. |
| "Per-app notification filtering", "Don't show selected apps…", "Shows filter choices above the notifications" | none | ❌ | — |
| "Quick reply for supported messaging apps", "Reply to WhatsApp/Telegram", "Auto-hide after replying" | none | ❌ | Inline composer; send via AppleScript (Messages) or web automation. |
| "Hide native banners", "Option to replace system notifications" | none | ❌ | — |
| "How long a notification stays visible…" | Fixed 4.5 s (`AppState+Notifications.swift:14`); pause on hover ✅ `:29` | 🟡 | Add a duration setting. |
| "Burst notifications", "Recent notifications", "Clear all", "No recent notifications yet" | none | ❌ | Add a queue and a history list. |
| "App icon and notification preview" | SF Symbol in an accent circle (`:24`) | 🟡 | Show the real app icon. |

### AI coding agents / Notchface
| Ref | Ours | Status |
|---|---|---|
| "Live Claude, Codex & Cursor progress", "Coding agent working", "Working on your task", "Running a command", "Waiting on shell", "Writing to terminal", "Background task completed/failed", pets | none | ❌ Add agent hooks (Claude Code hooks / Codex logs) feeding a live activity and an expanded card. |
| "Notchface", "Live notch camera preview", "Choose which connected camera to use.", "Camera stays off until you start it", camera permission strings | none | ❌ Add an AVCaptureSession preview droplet plus a floating button. |

## 2. UI/UX differences in the screenshots
- **reminders-screenshot-poster:** Left column is "Sunday (wk. 9)" in red, a huge day numeral and today's items. The right column holds grouped upcoming items ("Tomorrow (wk. 10)"). Tasks are orange ring rows; events are tinted cards with a colour bar and time. The "+" is a floating circle at bottom right. Ours has a month grid on the left and a modal add card, and no week numbers.
- **pomodoro-screenshot / -2, high-alert-screenshot-poster / -2:** Short, wide shelf. An orange ruler slider sits on top. Below it, left to right: "Start Timer" orange capsule, an ambient mute button, a mode button, and a big orange mm:ss on the right. While running: an orange pause/stop circle, an ✕ or "System" mode pill, and "Timer"/"High Alert" + time. Our consoles are tall cards with rings and header text.
- **notes-screenshot-1/2/3:** Editor with back button, "Edited 22:42", copy and delete buttons, and a floating glass format bar. The list page has a pin/copy/delete context menu. Notes can sit as a home card next to the player. Ours is a single monospaced editor with character and word counts.
- **obsidian-screenshot-1:** A note list (title, time, preview) with a compose button. Beside the lane pill is a second capsule of floating buttons (calendar, cup). Ours is an append composer.
- **terminal-notch-screenshot:** The whole shelf is a terminal: `user@host ~` prompt, green `$`, no header chrome. "Open externally" and "restart" buttons float beside the lane pill. Ours has a 95pt output box, chips and a header.
- **meeting-controls-screenshot-1/2:** In the compact notch, a green phone icon + elapsed time + mic waveform. Expanded, four large circles, red when off. Our row matches roughly but has labels and no call HUD.
- **notification-hud-screenshot:** Real app icon; app name / title / body; "now" on the right; no buttons. Ours adds an accent circle and ✕.
- **ai-coding-hud-screenshot-1/2:** Claude glyph, a task line, "Running …" with ▶, and an assistant text card. The compact state is a glyph plus a spinner ring. We have nothing equivalent.
- **Floating buttons (shared pattern):** Tasks, Pomodoro, High Alert, TermiNotch, Notchface and Notifications can each be pinned as a button in a second capsule by the lane pill. Ours hard-codes Calendar plus Customize (`ShelfView.swift:149`).

## 3. Ours only
- Month grid with busy-day dots and "Today" jump (`CalendarPage.swift`).
- Lock-screen next event and Pomodoro ring (`LockScreenLiveActivityView.swift`).
- Stopwatch laps and ±1 min adjust.
- Meetings: system-wide mic mute with a volume fallback, Slack Huddle and Webex shortcuts, Meet tab focusing via AppleScript.
- Obsidian: daily note/inbox targets, clipboard/scratchpad/tray-file capture, custom daily date format.
- Scratchpad "Add to Tray" as .txt, and Undo on clear.
- Ring radial actions for High Alert and Pomodoro.
- TermiNotch remembers `cd` and kills the process group on timeout.

## 4. Coverage
All 351 lines of `buckets/productivity.txt` are accounted for; each maps to a table row or group above. Those it covers only indirectly:
- **Permission and settings-pane strings, handled by the same features:** 6–9, 27–39, 159, 235, 243–244, 328, 29–31, 182.
- **Meeting apps:** 91, 106, 163.
- **AI HUD statuses:** 21–23, 58–60, 247, 316, 338, 343–344.
- **Notes/terminal/meeting errors:** 62–64, 184, 183, 334–335, 43.
- **Quick-reply errors:** 13–14, 193–194, 240, 311–312, 341–342, 326, 199, 256, 19.

Judged irrelevant or another area:
- **Accessibility, Settings search and system pane descriptions:** 2, 10–12, 74, 77, 186.
- **Clipboard / shelf:** 16, 17, 18, 90.
- **Appearance:** 50, 81–83, 288.
- **Liquid Mouse:** 201, 287.
- **Mechey keyboard sounds:** 120, 295, 351, 284 ("Silence during Focus", ambiguous: Mechey or notifications).
- **Cursor Sticker:** 66–67.
- **Teleprompter:** 65, 135, 162, 221, 291 (ambiguous: meetings mic), 321, 72, 195, 245, 348–349.
- **Ring / row builder:** 203.
- **Menu-bar hider:** 226.
- **Updates, licence and AI runtime:** 78, 105, 122–123, 140–141, 164–165, 172, 228–229, 233, 248–253, 318, 330–333, 336.
- **Voice Transcribe / mic errors:** 101, 160–161, 337, 92, 98 ("Focus Loss", unclear).

## Done in phase 8a

Tasks & Calendar, Pomodoro, High Alert, Timer, Notes/Obsidian (TermiNotch, Meetings, Notification HUD, AI agents and Notchface are left for later phases).

- ✅ **Tasks & Calendar page** (`Views/Notch/CalendarPage.swift`): the reference layout, with the weekday in red plus "(wk. N)", a huge day number and the day's items on the left, and upcoming items grouped "Tomorrow (wk. 10)" on the right. Tasks are list-coloured ring rows and events are tinted cards with a colour bar and time. A floating "+" opens an inline field ("Add a task…", with a Task/Event switch and a live parse preview). The month grid is an alternate layout behind the grid button (`calendarLayout`). The reference's empty-state copy is used. The page, the home card, the menu item and the ⌘4 button are renamed "Tasks & Calendar".
- ✅ **Parser** (`ReminderParser.swift`): `#List` / `@List` / `#"Two words"` mentions matched to Reminders lists, `!`/`!!`/`!!!` priorities, and stop words and time words in DE/NL/FR/ES/PT/IT/Scandinavian languages. Tests are in `ReminderParserTests`.
- ✅ **Priority, delete and reschedule**: clicking the priority marks changes the priority ("Priority: X (click to change)"). The context menu has Set priority, +1 Day, +1 Week, Remove Due Date, Open in Reminders and Delete Task. Delete shows a "Task deleted" banner with Undo, which recreates the task.
- ✅ **Completed tasks** stay struck through (and can be unticked) until "Remove completed tasks after" runs out, then leave with "N tasks cleaned up".
- ✅ **Settings › Shelf › Tasks & Calendar**: Tasks / Events toggles, Hide undated tasks, Week numbers, and calendar and reminder-list multiselects ("No calendars found." / "No reminder lists found."). Also Default list and Default Calendar pickers, Due alerts with a heads-up lead time and Chime, Event progress ring, Next up in the notch, and Keep calendar window on top.
- ✅ **Due alerts, event ring and next-up** (`Services/TaskAlertService.swift`): a heads-up banner plus a notch countdown before a timed task is due, and a banner with a Complete action and an optional chime at the due time. The event under way gets an ambient progress-ring live activity, and the next event or task can sit in the wings.
- ✅ **Pop-out calendar** (`Windows/CalendarPopoutController.swift`): a resizable panel with pin (keep on top) and close buttons.
- ✅ Join chips on event rows (Zoom/Meet/Teams/Webex) and "Read-only (Apple Calendar)" help. `droppy://show?target=calendar|<droplet id>` opens these pages.
- ✅ **Pomodoro**: a ruler slider (`Views/Droplets/RulerSlider.swift`) with 5-minute labels, orange ticks, a centre caret, drag with fling and scroll-wheel input, plus the "Start Timer" capsule, the ambient mute button and a Focus/Break button beside the big orange mm:ss. While running it shows orange pause, ✕ and "Focus 44:58". The console is short and headerless, with the ✕ accessory.
- ✅ **Ambient sound** (`AmbientSoundService.swift`): brown, pink or white noise, rain and ocean waves, synthesised with AVAudioSourceNode (no assets). It has a picker and a volume slider, and plays only during focus cycles.
- ✅ **Focus**: "Turn on Focus during sessions" runs the "Droppy Focus On/Off" Shortcuts. Settings explains how to create them and warns when they're missing; a failed run shows a banner.
- ✅ **Pomodoro in the notch**: "Keep timer visible in notch" puts the countdown ahead of music and the Tray (wings and secondary pill). "Open on hover" opens the shelf straight onto Pomodoro when you hover the timer.
- ✅ **High Alert**: the same ruler (5 min to 24 h), a mode button that cycles Screen / System / Lid Closed, ∞ for indefinite, and a running state of stop, mode pill and "High Alert 54:57". The status line reads "System sleep enabled/disabled" with Sleep Now (`pmset sleepnow`).
- ✅ **Lid Closed** runs `pmset -a disablesleep 1` through an AppleScript administrator prompt and restores it on stop and quit (another prompt). A launch check offers to restore after a crash. Settings shows a clear warning.
- ✅ **Timer**: ruler + Start Timer + big orange time. Running it shows pause, ✕ and ±1 min; the stopwatch has Lap and lap capsules.
- ✅ **Notes** (the Scratchpad droplet, renamed "Notes"; `Services/NotesStore.swift`, `Views/Droplets/RichTextEditor.swift`):
  - Multiple notes, stored in `Application Support/Droppy/notes.json` and flushed on quit. The old scratchpad text is migrated into the first note.
  - A list with title, time and preview. Pin, copy and delete appear on hover and in the context menu, and the pencil makes a new note.
  - An NSTextView rich-text editor with a floating glass bar (B/I/U, H1–H3, bullets, numbers; lists continue on Return), plus "Edited HH:mm" and copy/delete.
  - Grow canvas: the console grows up to 440 pt.
  - The home card lists notes, like notes-screenshot-3.
- ✅ **Apple Notes sync** (AppleScript via `osascript`, into a "Droppy" folder): pushes 2 s after an edit, pulls whenever Notes opens, imports notes made in Notes, and deletes the Notes copy on delete. Error states: "Couldn't reach Apple Notes…" (with Automation settings) and "Notes script failed" (with Retry).
- ✅ **Kept**: Add to Tray (.txt), Clear with Undo (trash-button context menu) and Finder › Services "Send to Scratchpad", which now appends to the latest note.
- ✅ **Obsidian**:
  - A vault note list sorted by modified time (title, time, first line), with "Refreshing vault notes." while it loads.
  - Notes open and edit inline (plain Markdown, autosaved), and the pencil makes a new note.
  - A "Vault unavailable" state with "Choose the vault again…", plus "Open this vault in Obsidian".
  - Capture (daily/inbox, clipboard, tray file, recent) moved behind the capture button. Its Scratchpad button now appends the latest note.
- Settings keys are registered in `settingsKeys`, and every new option has a search entry (`shelf.tasks.*`, `shelf.pomodoro.*`, `shelf.highAlert.*`, `shelf.notes.*`).

Skipped or limited:
- **Focus**: switched through user-made Shortcuts, because there is no public API for it.
- **Lid Closed**: asks for the admin password at start and again at stop. The reference's installed sudoers "scoped permission" was not built, because it widens privileges.
- **Apple Notes sync**: best effort. Conflicts resolve to the newer side. Formatting that goes through HTML is limited to bold, italic, underline, headings and lists. A note deleted in Notes is kept locally and re-pushed on its next edit.
- **Obsidian**: the inline editor is plain Markdown, not rendered.
- **Pomodoro**: "Momentum" (session streaks) wasn't built. Floating-button toggles for Tasks, Pomodoro and High Alert are covered by Favorites (phase 1).

## Done in phase 8b

TermiNotch, Meetings, Notification HUD, AI coding agents and Notchface.

- ✅ **TermiNotch: full terminal emulation** (`Services/Terminal/`): a real login shell on a pty (`forkpty`; signal mask and dispositions reset in the child, so Ctrl-C works), with no timeout. It keeps running while the shelf is closed. `TerminalScreen` is an xterm subset: SGR with 16, 256 and truecolour; cursor movement; erase, insert and delete; scroll regions; the alternate screen (vim, less, top); bracketed paste; DECCKM; DSR/DA replies; OSC title and directory; UTF-8; and 3,000 lines of scrollback. `TerminalCanvasView` draws the cells and maps keys to bytes (arrows, ⌥-word moves, ^A–^Z, Esc, Tab, ⇧Tab). You can drag to select, and ⌘C, ⌘V, ⌘A and ⌘K work, plus ⌘T and ⌘W for tabs and ⌘+ / ⌘− for text size. The context menu copies all output.
- ✅ **Quick command & expanded modes**: the expanded mode fills the shelf with the terminal, with no chrome. zsh gets the `user@host ~` / green `$` prompt from a ZDOTDIR shim that runs your own startup files first and keeps your history file. The quick command bar shows the last four output lines and a one-line field, plus Ctrl-C/stop. "Show TermiNotch bar" sets which mode opens. ↗ (Open in Terminal), ↻ (Restart session) and ✕ sit beside the nav bar.
- ✅ **Tabs**: several sessions, each started in the current tab's folder. The folder you `cd` to is read from the shell (`proc_pidinfo`) and remembered across restarts and relaunches.
- ✅ **Open-in-Terminal app picker**: Terminal, iTerm, Ghostty or Warp (via the `warp://` URL). If the picked app isn't installed, the folder opens in Terminal and a note says so.
- ✅ **Meetings**:
  - A state machine: "Sleeping until a supported meeting app launches." → "Watching for meetings…" → in a call. On macOS 14.2+, CoreAudio's process list shows which app records, so helpers, avconferenced (FaceTime) and browsers (Meet) are mapped. WhatsApp and FaceTime were added. A call starts after 1.5 s of mic use and ends 3 s after the mic is released.
  - "Pause media during meetings" pauses either when the call starts or only while the mic is unmuted. "Resume media after meeting" is a separate option, and a "Media paused for meeting" banner appears.
  - The call HUD in the notch shows a green phone, the elapsed time and live mic-level bars (`MicLevelMeter`, used only during a call and only with Microphone access already granted). Clicking it opens the call controls.
  - The controls use red fills for a muted mic and a camera that is off (camera state comes from CoreMediaIO). Hang up uses a shortcut, or the app's menu through Accessibility (`MenuPresser`) for FaceTime and WhatsApp.
  - Mid-call there's a quick task field (the Tasks parser writes to Reminders) and a "Meeting Notes" button that makes a note.
- ✅ **Notification HUD** (`NotificationHUDService`, droplet `notifications`, off by default):
  - It reads usernoted's SQLite store read-only: the Sequoia+ group container first, then the older `DARWIN_USER_DIR` path. It checks the schema and reports anything unsupported. It watches the WAL with a file-system source and falls back to a 10 s poll.
  - Without Full Disk Access it shows a guide and an "Open Full Disk Access" button, and checks again when you come back to Droppy.
  - Banners show the real app icon, app name, title and "subtitle · body" with "now", like the screenshot. Hovering holds a banner, and clicking opens the app.
  - Options: auto-dismiss duration, burst folding (three or more at once), a queue, the preview toggle, per-app filtering (a list of known apps plus "Add App…") and filter chips.
  - The recent list (in memory) has a context menu and "Clear all".
- ✅ **Quick reply** (`QuickReplyService`): iMessage/SMS replies go through Messages AppleScript to the chat GUID. The GUID is resolved from chat.db (by text, then by time) or from the notification's thread ID. WhatsApp and Telegram copy the reply and open the app, with an honest note. "Auto-hide after replying" is an option.
- ✅ **Agents** (`Services/Agents/`):
  - Claude Code hooks are installed into `~/.claude/settings.json` only after an explicit click and a preview alert showing the exact JSON. A backup is written to `settings.json.droppy-backup`, the install is idempotent, and Remove is available. Each hook appends the event to a JSONL file that Droppy watches, and the latest reply is read from the transcript's tail.
  - Codex rollout logs are tailed. Cursor's newest composer (name and whether it's generating) is read from `state.vscdb` only while Cursor runs and its DB changes.
  - In the notch: the agent's SF Symbol glyph plus a spinner. The expanded card shows the glyph, name, "• task", "▶ Running …" and an assistant-text card. A "finished / stopped / needs you" banner is optional.
- ✅ **Notchface** (`NotchfaceCamera`): an AVCaptureSession preview, mirrored by default, with a camera picker (built-in, external and Continuity). The camera starts only on Start and stops when the shelf closes. Permission states are not determined, denied and restricted, with an "Open Camera Settings" button. `NSCameraUsageDescription` was added.
- ✅ Floating-button toggles for TermiNotch, Notifications and Notchface add a Favorites entry. Every new option has a `droplet.<id>.*` search entry, and new keys are in `settingsKeys`. The HUDs › Droplets "Set up" cards for Notifications and Agents now open real droplet pages.
- Tests: `Tests/DroppyTests/Phase8bTests.swift` covers the screen model, a real pty with Ctrl-C, the agent parsers, the hook merge, notification plist parsing, Messages targets and meeting detection.

Skipped or limited:
- **Hide native banners**: not built. It would mean editing other apps' private notification preferences or killing NotificationCenter. Settings explains how to set the alert style to None instead, and Droppy still mirrors those notifications.
- **WhatsApp/Telegram reply**: can't be sent programmatically. The reply is copied and the app (or its web version) opens.
- **Cursor**: only the newest chat's title and generating state; Cursor exposes nothing richer. Agent pets and vendor artwork are not used; the glyphs are SF Symbols.
- **Call detection before macOS 14.2** falls back to "mic busy while a meeting app runs", and the live mic level needs 14.2.
- **Camera "off" state** means no camera is streaming at all; Droppy can't read a single app's own toggle.
- **TermiNotch**: wide (CJK/emoji) glyphs take one cell, and there's no mouse reporting or sixel.

## Done in phase 11
- ✅ **Pomodoro Momentum** (`Settings › Shelf › Pomodoro › Momentum`, `pomodoroMomentum`, on): finished focus sessions today and the day-by-day streak. `PomodoroMomentum` is a plain value with the rollover rules (`recording`, `currentStreak`, `sessions`, `summary`) and its own tests: more sessions on one day don't grow the streak, consecutive days do, yesterday still counts, a whole missed day starts over and the best streak is kept. Only a cycle that runs out counts, so a reset session doesn't inflate it. The console shows "3 today · 5-day streak" under the timer, Settings shows the same line plus the best streak and a Reset, and a new streak of two or more days gets a banner.
