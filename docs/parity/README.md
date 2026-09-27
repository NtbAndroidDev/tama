# Parity audit vs Droppy 14.2.0 (2026-09-22)

Reference: the commercial `/Applications/Droppy.app` (`iordv.Droppy`), compared through its 2,645 UI strings and bundled promo screenshots. No source or assets were copied.

The ❌ / 🟡 / ✅ columns count table rows: missing, partial or different, matching.

| File | Area | ❌ | 🟡 | ✅ |
|---|---|---|---|---|
| [1-shell-settings](1-shell-settings.md) | Notch surface, shelf behaviour, lane pill, floating buttons, multi-display, Settings, onboarding, droplet store | 20 | 23 | 6 |
| [2-media-hud-lockscreen](2-media-hud-lockscreen.md) | Player, lyrics, HUDs, lock screen, weather | 33 | 23 | 11 |
| [3-files-basket-share](3-files-basket-share.md) | Tray, Basket, drag & drop, conversion and compression, sharing, Finder, Alfred | 29 | 18 | 7 |
| [4-clipboard](4-clipboard.md) | Clipboard manager | 16 | 12 | 10 |
| [5-productivity](5-productivity.md) | Tasks and calendar, Pomodoro, High Alert, Notes, TermiNotch, Meetings, Notification HUD, AI agents, Notchface | 32 | 22 | 11 |
| [6-tools](6-tools.md) | Capture and editor, OCR, Window Snap, LiquidMouse, Mechey, Voice Transcribe, Thunderstorm, Thaw, shortcuts | 28 | 25 | 23 |
| [7-leftovers](7-leftovers.md) | Strings that fit no other area: menu bar manager, launcher commands, LocalSend, and similar | 24 | 23 | 5 |

Out of scope: licensing and trial, the updater, the Droppy Cloud backend, and the reference app's bundled media.

## Final status (counts as of phase 10; phases 11-13 are listed below)

Counts are approximate. They come from each file's "Done in phase N" sections, and one bullet often closes several audit rows. "Done" includes rows that now match; "partial" means the closest honest version, limited by public APIs; "skipped" rows each have a reason in their file.

| File | Area | Originally ❌ / 🟡 | Done | Partial | Skipped (with reason) |
|---|---|---|---|---|---|
| [1-shell-settings](1-shell-settings.md) | Shell, Settings, onboarding, droplet store | 20 / 23 | ~29 | 2 | ~11 |
| [2-media-hud-lockscreen](2-media-hud-lockscreen.md) | Player, lyrics, HUDs, lock screen, weather | 33 / 23 | ~34 | 4 | ~7 |
| [3-files-basket-share](3-files-basket-share.md) | Tray, Basket, conversion, sharing, LocalSend | 29 / 18 | ~41 | 1 | 5 |
| [4-clipboard](4-clipboard.md) | Clipboard manager | 16 / 12 | ~22 | 0 | 6 |
| [5-productivity](5-productivity.md) | Tasks, Pomodoro, Notes, TermiNotch, Meetings, Notification HUD, Agents | 32 / 22 | ~29 | 5 | ~4 |
| [6-tools](6-tools.md) | Capture, OCR, Window Snap, LiquidMouse, Voice, Thunderstorm, Menu Bar | 28 / 25 | ~25 | 1 | ~5 groups |
| [7-leftovers](7-leftovers.md) | Cross-cutting strings | 24 / 23 | ~27 | 3 | ~7 |
| [8-settings-screens](8-settings-screens.md) | Settings as seen in the screenshots | (bullets) | ~38 | 0 | ~6 |

`swift build` is clean and `swift test` passes (209 tests in 52 suites) as of 2026-09-23.

## Remaining / out of scope

**Out of scope (IMPLEMENTING.md rule 6)**
- Licensing, trial, activation and the License tab.
- The updater, the beta channel and the "Droppy updates" HUD card.
- Droppy Cloud upload and its manager (no server).
- The app-icon picker, which uses the reference's own assets.
- Installing third-party apps (Thaw, BetterDisplay). A "Get app" link is shown instead.
- Copying the reference's images, screenshots, sounds or videos. We draw our own art instead.

**No public API, or would need privileges we don't take**
- iCloud Drive share links: files are copied to iCloud Drive and revealed.
- Focus toggling: works through user-made Shortcuts.
- Hiding native notification banners.
- WhatsApp and Telegram replies: the reply is copied and the app opens.
- Per-app camera "off" state.
- Richer Cursor data.
- Speaker diarization.
- Safari incognito detection.
- Scheduled Focus.
- Screen recording by third-party recorders.
- Screenshot exclusion from some ScreenCaptureKit recorders.
- Lid Closed sudoers scope: an admin prompt is used instead.
- An in-memory TLS identity before macOS 15: LocalSend keeps its key in the login keychain.

**User decisions (no global input monitoring, no hidden recording)**
- Mechey's extras.
- Window Snap drag-to-edge, snap zones and action-key resize.
- Pointer-first mode.
- Menu Bar Manager hover, scroll and double-click reveal, and per-app rules.
- Invisi-Record.

**Third-party code, models or services**
- Whisper and Parakeet ASR.
- Kokoro and PocketTTS voices and voice cloning (Read Aloud uses the system voice).
- Dropbox (needs an OAuth app).
- Clipboard iCloud sync (needs a CloudKit entitlement).
- A browser extension bridge.
- An in-app AI agent with an API key.

**Built in phase 11** (each has a "Done in phase 11" entry in its audit file)
- "ZIP Hover" — a Quick Action tile that zips the drop.
- Swiping between Tray stacks — an up-down swipe on the open Tray, which the page swipe doesn't use.
- The clipboard favorites bar.
- A separate paste shortcut.
- Upload from Clipboard.
- Pomodoro Momentum streaks.
- HUD "Closest Corner" placement (the screenshot preview card).
- Now Playing Size (Regular / Smaller).
- Always use built-in speakers.
- Reverse swipe direction.
- Per-widget floating-button size, style and tint, plus the icon colour.
- A solid Settings background.

**Built in phase 12**
- LocalSend's v1 API and web "download" mode ("Share in a browser").

**Built in phase 13**
- Tracked folders now process as well as add: each watched folder picks Add to Tray, Add to Basket or Add and compress.
- UI/UX logic: typing anywhere in the shelf holds it open (owner-tracked, like modals); leaving the Widgets page ends rearranging; the Tray's keyboard scrolls, keeps its place after ⌫ and answers ⌘C.

**Built in phase 14**
- The Basket answers the same keyboard the Tray does (arrows, ⇧ to extend, ⌘A, Space, Return, ⌘C, ⌫ with Undo, ⇧⌘M, ⌘↑ to the Shelf, ⌘M, ⌘W), keeps its place after ⌫, and shows when it holds the keys.
- Sleep behaviour: Lid-Closed High Alert ends itself when the charger comes out, and a new `PowerStateService` stands the notch's pollers down while the screen is off and refreshes everything on wake.
- A pass over what the shelf does while drawing: a shared Finder-icon cache, a lazy Tray rail, the folder browser read off the main thread, the Legacy clipboard preview downsampled, clipboard writes moved off the main thread and Tray writes debounced, and LocalSend's staged total worked out when the files are picked.

**Built in phase 15**
- **Droppy Guide**: fifteen searchable articles, live shortcut tables, Settings deep links, reachable from About, the menu bar (⌘?), the notch menu and ⌘? in the shelf. Guide articles also appear in Settings search under "From the guide".
- The welcome tour gained a Tray/Basket/clipboard step and a Widgets step, Skip, jumpable dots and a link to the guide at the end.
- The Droplets store's hero and detail pages draw each droplet's own console instead of a gradient and grey placeholder bars — all 28, kept in step with the droplet list by a test.
- The crash report: the newest `.ips` macOS wrote, summarised, sanitised and copied to the clipboard. Nothing is sent; the earlier note assumed a reporter had to upload somewhere, and the reference's own flow is "Crash Report Copied".
- Fixed a launch deadlock: `MediaService.init` reached for `AppState.shared` while `AppState`'s own one-time initialiser was still running.

**Still not built**
- Legacy clipboard import: the reference's store format isn't documented and we have no sample to read.
- Thunderstorm Empty Trash: a launcher command that empties the user's Trash irreversibly; left out on purpose.
- The rest of the "Settings window" options, which weren't captured. The one we could infer, a solid background, is built.
- Recent Cursor/VS Code projects in the launcher: the evidence ties that data to the Agents droplet, not a launcher.
