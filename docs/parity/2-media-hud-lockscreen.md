# Media / HUDs / Lock screen / Weather parity audit (read-only)

Paths are under `/Users/Shared/Data/source/macos/droppy/Sources/`.

## 1. Feature table

### Now Playing player
| Ref | Ours | St | What to change |
|---|---|---|---|
| "Now Playing HUD/Media Player HUD", "Enable now-playing controls and metadata", "Hide media", "Show media controls", "Enable Media Player in HUD settings" | Always on. The only control is removing the media Home widget (Views/Notch/HomePage.swift:6) | 🟡 | Add a master media on/off switch that also drops the notch wings. |
| "Now Playing Size", "Choose Regular or Smaller Now Playing HUD layout", "Now Playing Display", "Choose your display style" | Single layout (Layout.swift:71 PlayerMetrics) | ❌ | Add a `nowPlayingSize` setting (Regular/Smaller) and a second PlayerMetrics set. |
| "Choose which playback buttons appear for Regular Now Playing, Spotify, and Apple Music.", "No playback buttons selected" | Fixed row: lyrics, heart, prev/play/next, queue, output (PlayerPage.swift:226-287) | ❌ | Per-source button picker, with an empty-state message. |
| Shuffle / repeat (spotify-screenshot, lyrics-screenshot-1) | none | ❌ | Add shuffle and repeat for Music and Spotify over AppleScript (`shuffle enabled`, `song repeat`, `repeating`). |
| Heart/love ("Add to favorites/Remove from favorites") | Music only (MediaService.swift:305) | 🟡 | Spotify can't love over AppleScript; hide the heart there (already done). |
| Source badge on the artwork | PlayerPage.swift:122; LockScreenOverlayView.swift:120 | ✅ | — |
| "Visualizer", "Regular visualizer", "Gradient visualizer / Two-tone album art ramp", "Mono spectrum bars", "Pick the Now Playing spectrum style" | `WaveBars` is a simulated animation in the accent colour (NotchComponents.swift:35) | 🟡 | Add a style picker (Regular / Gradient / Mono) and tint from the artwork's colours. |
| "Live audio visualizer", "Bounce the bars to what's actually playing.", "Visualize live audio output." | Fake animation | ❌ | Drive the bars from real levels. A CoreAudio process tap already exists in Services/AppAudioService.swift. |
| "Live album artwork", "Fullscreen animated artwork", "Close expanded artwork" | Tapping the artwork opens the source app (PlayerPage.swift:119) | ❌ | Tap to expand the artwork (animated where available), with a close button. |
| "Playing Next", "Nothing Playing Next" | UpNextPanel for Music only, folds below the player (PlayerPage.swift:597) | 🟡 | Show it as a side column with artwork thumbnails (applemusic-screenshot). Use the ref's wording for the empty state. |
| "Notch track title", "Media player text" | Title appears only on the notchless pill (IslandCompactView.swift:48) | 🟡 | Add an option to show the title/artist text in the notch wings. |
| "Fade out the mini player after a delay." | none | ❌ | Auto-hide the resting media wings after N seconds of pause. |
| "Hide Media in Fullscreen", "Hide media overlay in fullscreen contexts." | none | ❌ | Detect the fullscreen space and suppress the wings. |
| "Two-finger swipe inside the Media widget to skip tracks.", "Enable swipe gestures … skipping tracks in the compact media HUD", "Track swipe direction", "Flip the track-skip swipe…", "Reverse swipe direction" | Scrolling on the resting notch changes volume (IslandCompactView.swift:157). Horizontal swipe only switches pages (WidgetPager.swift:98) | ❌ | Horizontal two-finger swipe → next/previous, plus a reverse toggle. Keep vertical scroll for volume. |
| "Open Media HUD on Expand", "Show media controls when shelf opens.", "Open media on notch click" | `defaultShelfPage`; Home holds the media widget by default (Constants.swift:143) | 🟡 | Add an explicit toggle labelled as in the ref. |
| "Show Media HUD as a floating button", "Media HUD Button", "Media HUD position" | none | ❌ | Add a floating media button (a small panel) with a position setting. |
| "Default Music App", "Choose which app Media HUD opens by default.", "Used when Media HUD opens without an active source app", "Launches when nothing is currently playing.", "Open Music"/"Open Spotify", "Play a track" | "Not Playing" text only; play with no source posts a media key (MediaService.swift:256) | ❌ | Add a default-app picker. In the idle state show an "Open Music/Spotify" button and launch-and-play. |
| "Media key target", "Choose what Droppy handles for media keys" | MediaKeyMonitor handles only volume, brightness and mute (MediaKeyMonitor.swift:45) | ❌ | Intercept play/next/prev (NX 16/17/18/19/20) and route them to the chosen source. |
| "Filter media sources" | none | ❌ | Add a per-app allow/deny list used in `probeScriptableSources` (MediaService.swift:604). |
| "Hide Incognito media", "Hide media from private browsing windows." | none | ❌ | Check `mode of w is "incognito"` (Chromium) or Safari private windows in `probeBrowser` (MediaService.swift:725). |
| Browsers "Safari", "Google Chrome", "Arc", "Microsoft Edge", "Firefox", "Browser" | Safari, Chrome, Brave, Edge, Arc, Vivaldi, Opera, Chromium (MediaService.swift:704-712) | 🟡 | Firefox missing: it has no AppleScript, so it needs MediaRemote or the bridge. |
| "Droppy Browser Media Bridge", "Activated browser", "Fallback played active tab", "Found and played" | AppleScript plus a "Allow JavaScript from Apple Events" hint (PlayerPage.swift:211) | 🟡 | An extension bridge (native messaging) would remove the JS-from-Apple-Events requirement. Large effort. |
| "Spotify Integration", "Control Spotify playback from Droppy surfaces.", "Connection and Spotify controls" / "Apple Music Integration", "Native controls for Apple Music", "Native music controls" | Built into MediaService with no toggles or details pages | 🟡 | Optionally expose these as Droplets or extensions with detail pages. The shuffle, repeat and like rows above are the substance. |
| "Choose audio output", "No audio outputs are available right now." | Output picker (PlayerPage.swift:309). Empty state reads "No audio outputs" | ✅/🟡 | Adopt the ref's empty-state wording. |
| "Always use built-in speakers" | none | ❌ | Option to force the default output back to built-in speakers when a device connects. |
| "Media paused for meeting", "Pauses music when a meeting starts.", "Resume media after meeting", "Automatically resumes…", "Media blocked during meeting", "Meeting ended, media resuming", "Pauses media when mic is unmuted…", "Allow media while muted", "Auto-pause media" | none (MeetingControlService has no media hooks) | ❌ | Hook MeetingService start/end → `MediaService.pause` / resume. |

### Lyrics
| Ref | Ours | St | Change |
|---|---|---|---|
| "Timed lyrics beside your media widget", "Open a synced lyrics panel directly beside the media widget…" | LyricsPanel folds *below* the player (PlayerPage.swift:401), from LRCLIB and opt-in | 🟡 | Lay the lyrics card out to the right of the player (lyrics-screenshot-1). |
| Pop-out: "Close lyrics pop-out", "Keep lyrics window on top", "Bring floating lyrics to front", "Auto-expand lyrics" | none | ❌ | Floating lyrics NSPanel with pin (on top) and close buttons, plus an auto-expand option (lyrics-screenshot-2). |
| "Lyrics companion (settings)" | Player section in Settings (SettingsView.swift:1392) | 🟡 | — |
| Strings "Loading lyrics...", "No lyrics for this song", "No synced lyrics found", "Play a song to see lyrics", "Synced lyrics appear here when a song is active.", "Synced lyrics aren't available right now.", "This track doesn’t have timed lyrics…" | "Finding lyrics…", "No Lyrics Found", "No Lyrics", "Not synced" | 🟡 | Align the wording. |

### HUDs
| Ref | Ours | St | Change |
|---|---|---|---|
| "Volume HUD", "Show Volume HUD", "Enable custom volume indicator.", "Replace system OSD" | showVolumeHUD / replaceSystemVolumeHUD (AppState.swift:269-276), LevelHUDSettingsTab | ✅ | — |
| "Brightness HUD", "Replace brightness OSD", "Enable custom brightness indicator." | AppState.swift:293-299 | ✅ | — |
| "Volume slider color", "Brightness slider color" | HUDMeterStyle White/Accent/Decibel | ✅ | — |
| "Automatic brightness HUD" | Only fires on a key press (BrightnessService presentHUD) | ❌ | Watch for ambient/auto-brightness changes and show the HUD (as an option). |
| "Keyboard backlight", "Keyboard brightness keys", "Replace backlight OSD", "Press or hold to step the keyboard backlight up/down." | none | ❌ | Add an IslandHUD `.keyboard` kind using NX_KEYTYPE_ILLUMINATION_UP/DOWN (21/22) and CoreBrightness KeyboardBrightnessClient. |
| "Caps Lock HUD", "Show CapsLock HUD", "Show caps lock status popup." | none | ❌ | Handle `flagsChanged` → a brief HUD. |
| "Battery HUD", "Show Battery HUD", "Show battery state overlays." | Live activities for charging, low, full and Low Power (BatteryService.swift:57-115) | ✅ | Label the toggle "Battery HUD". |
| "AirPods HUD", "Show AirPods battery and connection HUD.", "AirPods connection", "Detects AirPods connections…", "Waiting for headphones" | The connect live activity shows only "On"/"Off" (AudioOutputService.swift:131). Battery is polled every 180 s and only for the lock screen and Home (HeadphoneBatteryService.swift:46) | 🟡 | On connect, trigger a battery read and show L/R/case in the HUD. |
| Models "AirPods", "AirPods 3", "AirPods Pro", "AirPods Max", "Beats", "Beats Studio Pro", "Earbuds", "Headphones" | Symbols for airpods, airpodspro, airpodsmax and a generic fallback (AudioOutputService.swift:146) | 🟡 | Add `airpods.gen3`, `beats.headphones`/`beats.studiobuds`, and `earbuds`. |
| "Audio Device Battery", "Show connected audio device battery percentage." | Home BatteryCard and the lock-screen item | 🟡 | Show it in the connect HUD too. |
| "Focus / DND HUD", "Show focus mode changes in HUD.", "Reads notification and Focus data…" | none | ❌ | Watch `com.apple.focus` / DND and post a LiveActivity. |
| "Compact HUD priority", "Collapsed HUD scope", "Finished HUD linger", "Keep HUD visible in notch", "Live countdown stays visible in compact HUD" | Fixed urgent/ambient priority (LiveActivityCenter.swift:7), hard-coded order in IslandCompactView | ❌ | Expose the priority order, the linger time and a keep-visible option. |
| "Choose whether built-in HUDs use Notch or Island style…", "Choose whether built-in volume and brightness HUDs use a notch or a floating island pill" | Global `islandStyle`; notched displays are always notch (SettingsView.swift:670) | 🟡 | Add a HUD-specific style setting. |
| "External display style", "Main display style", "Surface style for displays with/without a physical notch.", "Choose Notch or Island style for HUDs on external displays." | Single style | ❌ | Style per display class. |
| "Hide on external displays", "Per-display visibility", "Choose exactly which external displays show the top HUD surface.", "Disable top HUD surfaces on connected monitors.", "Keep the external notch or island surface visible when nothing is playing.", "External displays", "All displays", "Main Display", "Notchless display" | `displayTargetMode` picker (Constants.swift:40) | 🟡 | Add a per-display checklist and keep-visible-when-idle. |
| "Fine-tune how wide the physical-notch HUD surface appears…" | hudWing is a constant (Layout.swift:26) | ❌ | Add a width slider. |
| "Where volume and brightness keys apply" | Brightness applies to the built-in display only | ❌ | Target choice (built-in / display under the cursor, e.g. via DDC). |
| "Desktop volume slider", "Desktop brightness slider", "Brightness slider" | none | ❌ | Optional desktop slider widgets. Low priority. |

### Lock screen
| Ref | Ours | St | Change |
|---|---|---|---|
| "Lock screen features", "Enable or disable all lock screen features." | lockScreenEnabled (AppState.swift:233) | ✅ | — |
| "Lock screen media HUD", "Show Now Playing controls on the lock screen." | LockScreenPlayer (LockScreenOverlayView.swift:105) | ✅ | — |
| "Lock screen media HUD material" | Fixed black at 0.38 opacity (LockScreenOverlayView.swift:191) | ❌ | Material picker (dark / blur / liquid glass). |
| "Status widgets row", "Show centered native widgets under the lock screen clock.", "Show Mac battery percentage widget." | LockScreenStatusRow | ✅ | — |
| "Lock screen widget style" (vertical/rounded), "Lock Screen Widget Look" (light/dark, regular/liquid), "Widget Material" | Single inline style | ❌ | Add style, look and material settings. |
| "Lock/unlock animation", "Show lock and unlock animation." | Panels just show and hide (LockScreenWindowController.swift:57) | ❌ | Animate on lock and unlock. |
| "Lock & unlock sound", "Play a subtle sound…", "Plays the moment the screen locks/unlocks." | none | ❌ | Play NSSound on the lock and unlock notifications. |
| "Droppy Lock Screen Keep Awake" | none | ❌ | Probably an internal power assertion while locked. Optional. |

### Weather
| Ref | Ours | St | Change |
|---|---|---|---|
| "Live weather widget", "Show live weather widget.", "Current location weather" | Home WeatherCard (HomePage.swift:798) and the lock-screen item; WeatherService uses Open-Meteo | ✅ | — |
| "Weather Style", "Card style…", "Choose a colorful, dark, or native macOS liquid glass look…" | Single style | ❌ | Style picker. |
| "Weather Button", "Show Weather as a floating button", "Weather Button Content", "Choose what the floating weather button shows" | none | ❌ | Floating button with a content choice. |
| "Weather Location", "Automatic location", "Selected location", "Pick the location…", "Shows which fixed place…", "Couldn't load locations. Try again.", "Allow automatic location lookup…" | Automatic via CoreLocation only (WeatherService.swift:109) | 🟡 | Add a fixed-city search using the Open-Meteo geocoding API. |
| "Weather refresh interval", "How often weather data refreshes." | Fixed 30 min (WeatherService.swift:96) | ❌ | Interval picker. |
| "Show AQI and air quality category." | Always shown | 🟡 | Add a toggle. |
| "Sunrise & sunset", "Show sunrise and sunset times." | Always shown | 🟡 | Add a toggle. |
| "Thunderstorm" = the ref's weather extension ("Change weather variables inside Thunderstorm") | Our `ThunderstormConsoleView` is Spotlight search | 🟡 | Naming clash. Consider renaming ours or moving the weather settings under that name. |

### Misc in bucket
| Ref | Ours | St |
|---|---|---|
| "Stay silent while Music or Spotify is playing." | `mecheyMuteWhileMediaPlays` (MecheyService.swift:460) | ✅ (the ref variant also covers VLC) |
| "Media & HUDs" settings pane, "Volume & brightness", "Now Playing plus system HUDs, all in one place", "Volume and brightness replace the default macOS overlays…" | Split across Sound, Display and Shelf › Player | 🟡: consider a single "Media & HUDs" tab |

## 2. UI/UX differences seen in screenshots
- **applemusic-screenshot.jpg:** Playing Next is a **right-hand column** separated by a divider, and each queue row has an **artwork thumbnail**, title and artist. Ours folds a text-only list below the player. The queue toggle sits **left of the transport** and the output button (laptop icon) **right of it**, all in one row. Ours puts lyrics and heart far left and queue and output far right. The artwork is noticeably bigger (about 64–70 pt vs our 48). The visualizer is grey/tinted, not accent-coloured.
- **spotify-screenshot.jpg:** **Shuffle and repeat** sit in green-tinted circular buttons flanking the transport, which we don't have. The visualizer bars take their colour from the artwork (orange). The right-hand time shows the total duration ("2:32") where we show negative remaining. The shelf has a top chevron (collapse) button and a gear button.
- **lyrics-screenshot-1.jpg:** One transport row: shuffle, prev, play, next, repeat, heart, lyrics. The active lyrics button is tinted with the artwork colour. The lyrics are a **card beside the player** with a "Lyrics" header and an expand (pop-out) button. The whole island background takes an **artwork-derived gradient tint**; ours is flat black.
- **lyrics-screenshot-2.jpg:** A **floating lyrics window** (header "Lyrics", pin and close buttons, 3 centred lines, warm artwork gradient). The notchless pill shows art, artist/title text and bars, like ours.
- lyrics.jpg, apple-music.jpg and spotify.jpg are app icons only.

## 3. Ours only (keep)
- Scroll on the notch for volume, ⌥-scroll for brightness.
- HUD per kind: duration, animation (Smooth/Fast/Instant), show-percentage, hide-label, and a "Show device" leading option.
- Decibel meter style, ⌥⇧ fine volume steps, and a muted state that keeps the level visible.
- Double-tap the notch to play/pause; the right wing is a play/pause button.
- Scrubber with VoiceOver adjustable action and a hint for browser JS-from-Apple-Events.
- Tap a lyric line to seek, with an LRCLIB privacy opt-in and cache.
- Tap a queue row to play it, with a shuffle-order caveat.
- Output picker with per-device volume fill.
- Lock screen next-event item.
- Low Power Mode live activity and action.
- Brave, Vivaldi, Opera and Chromium browser sources.
- Home Battery card showing Mac and headphone battery.

## 4. Coverage note
I checked all 309 lines of buckets/media.txt. The in-area lines are all covered above, sometimes grouped by feature. I also grepped ref_all_strings.txt and folded in these extras: "Audio Device Battery", "Choose what Droppy handles for media keys", "Droppy Browser Media Bridge", "Droppy Lock Screen Keep Awake", "Reverse swipe direction", "Show connected audio device battery percentage.", "Show Mac battery percentage widget.", "Add/Remove from favorites", and the Spotify/Apple Music control descriptions.

Out of area or irrelevant (bucketed by regex):
- **Thaw:** Thaw icon/ThawBar/"LCS sorting…"/"Thaw Bar…".
- **BetterDisplay:** all 4 lines.
- **Window Snap:** "Manage window layouts…", "Live snap zones…".
- **Terminal:** "Open a terminal…".
- **Pomodoro:** "Run focused work timers…", "Play calming background sound…".
- **Notification HUD:** "Auto-dismiss paused…", "Bring notifications…", "Don't show selected apps…", "Display body text in the HUD", "Live notification HUD", "Notification display in the notch", "This runs through the live notification HUD queue.", "Transitioning to next queued notification", "Notification HUD".
- **Capture:** "Capture UI elements…".
- **Mechey:** "Play keyboard sounds", "Also play sounds for left and right mouse buttons.", "Skip modifier keys", "Only click when headphones are connected.", "Auto-enable on headphones", "Auto-mute on music", "Mechey trackers started/stopped", "Stay silent… VLC".
- **LiquidMouse:** "Liquid mode…", "Trackpad-like inertial flow…", "Trackpad scrolling stays untouched", "Direct and immediate…".
- **Island/display geometry:** "Adjust the floating island height…", "Choose which displays keep auto-hide active.", "Enable or disable auto-hide per display.", "Display-specific rules", "External display rules", "Fine-tune hover behavior…", "Connect an external display to enable External Hover.".
- **ToDo/editor:** "Open the ToDo input…", "Track focused editor", "Use trackpad pinch gesture…".
- **System Settings pane descriptions:** "Battery health…", "Keyboard behavior…", "Mouse tracking…", "Trackpad gestures…", "Touch ID…", "Disc insertion…".
- **Meeting-only:** "Show active call HUD", "Showing live microphone activity…", "Mute/Unmute audio".
- **Dev/internal:** "No runtime artifact available for architecture '", "Replay the demo phrase", "Replay the welcome tour", "Drive the compact media HUDs with explicit values." (debug harness), "Media" / "Archive" / "Display Only" (generic labels), "This track doesn" (truncated duplicate).

## Done in phase 3
- ✅ Automatic brightness HUD: the built-in brightness is sampled once a second, and a change made outside Droppy shows the HUD.
- ✅ Keyboard backlight: `IslandHUD.Kind.keyboard`. It uses illumination keys 21/22/23, taken by the event tap when "Keyboard brightness keys" is on, otherwise observed. `KeyboardBacklightService` loads CoreBrightness `KeyboardBrightnessClient` at runtime with `responds(to:)` guards; without it the HUD stays quiet.
- ✅ Caps Lock HUD: `flagsChanged` monitors, polled until Accessibility is granted.
- ✅ AirPods: on connect, a battery read (one retry) puts the level in the wings and L/R/Case in the banner. Symbols: gen3/4 (by product ID), Pro, Max, Beats Studio Buds, Fit Pro, Powerbeats, Beats headphones, earbuds, with a fallback when a symbol is missing.
- ✅ Focus HUD: reads `~/Library/DoNotDisturb/DB/Assertions.json`. 🟡 This needs Full Disk Access (Settings says so and offers Check Again), and scheduled Focus isn't seen.
- ✅ Compact HUD priority, Collapsed HUD scope, Finished HUD linger, and keep-while-hovered.
- ✅ HUD style per display class, Hide on external, Per-display visibility, Show when idle, Notch width/height sliders.
- ✅ Where the brightness keys apply: Under pointer (DisplayServices for the built-in and Apple displays, BetterDisplay for others, otherwise macOS) | Main MacBook.
- ✅ Desktop volume/brightness sliders: desktop-level panels whose position is saved with the frame autosave.
- 🟡 Recording status: every microphone via CoreAudio `DeviceIsRunningSomewhere`. The screen is detected only for macOS's own recorder (the `screencaptureui` stop button); third-party capture can't be detected.

## Done in phase 4
- ✅ Now Playing master switch (`nowPlayingEnabled`): off keeps music out of the resting wings and the secondary pill.
- ✅ "Fade out the mini player after a delay": Auto-hide preview with a 2–30 s delay.
- ✅ Now Playing display: Under pointer | MacBook.
- ✅ Notch track title: the wings widen to 112 pt and show the title and the artist.
- ✅ Visualizer: Mono | Gradient. Gradient uses a two-tone palette taken from the album art (`ArtworkPalette`), and the accent when there's no art.
- ✅ Live audio visualizer: an unmuted global Core Audio process tap (`LiveAudioLevels`) split into 4 bands at 30 Hz. It falls back to the simulated bars when the tap fails (macOS 14.2 or later and the System Audio Recording permission are needed) or delivers only silence.
- ✅ Live album artwork: clicking the cover opens a floating panel with the large art, a slow drift, ✕ and Esc. 🟡 Music's animated covers aren't available to other apps.
- ✅ Shuffle and repeat for Music and Spotify over AppleScript. The heart is Music only; it can also be placed in a button slot.
- ✅ Playing Next is a right-hand column with cover thumbnails, loaded from Music per persistent ID. Empty state: "Nothing Playing Next".
- ✅ Player layout: 70 pt cover with a source badge, one centred transport row (left slot, ⏮ ⏯ ⏭, right slot, then favourite, lyrics, queue and the output glyph). Clicking the right time switches between remaining and total. Optional artwork-gradient wash behind the shelf.
- ✅ Playback buttons per source (Regular / Spotify / Apple Music), with a "No playback buttons selected" note.
- ✅ Default music app: the idle player shows "Open Music/Spotify", and Play launches the app and plays.
- ✅ Track swipe On/Off and Standard/Reversed. It works on the resting music wings and over the player or media card, is folded into `ShelfGestureService`, and takes precedence over the page swipe there.
- ✅ On notch click: Media widget | Default.
- ✅ Filter media sources: a per-app checklist, applied to the MediaRemote, Music, Spotify and browser probes.
- ✅ Hide Incognito media: skips Chromium windows whose `mode` is incognito. 🟡 Safari doesn't expose private windows to AppleScript.
- ✅ Media keys › Playback keys: macOS | Now Playing | Default app. Keys 16–20 are taken by the existing event tap. Droppy's own posted keys carry a marker so they pass through. Browser tabs stay with macOS.
- ✅ Output picker empty state now uses the reference wording.
- ✅ Lyrics: a card beside the player with a "Lyrics" header, "Found by artist/title" and a pop-out button. The floating lyrics window has pin (on top) and close, three centred lines and an artwork gradient. Auto-expand lyrics (Shelf › Player) is added, and the states use the reference wording.
- ✅ Weather:
  - Grey liquid-glass card (210 pt beside another widget) showing "Local ➤" or the city, a thin temperature, the condition, H/L and 4 hourly columns from Open-Meteo hourly data.
  - Styles: Colorful | Dark | Liquid Glass.
  - Fixed city search through Open-Meteo geocoding ("Couldn't load locations. Try again.") or automatic location.
  - Refresh interval 15 min, 30 min, 1 h or 2 h. AQI and Sunrise & sunset toggles.
  - The settings live on the new Weather droplet's page, and its console shows the large card.
- ⏭ Skipped:
  - Meeting auto-pause/resume, which belongs to phase 8.
  - The Regular/Smaller size, floating Media HUD button, Hide Media in Fullscreen (phase 3 already has "Hide media"), Firefox and the browser extension bridge, and Always use built-in speakers: all out of this phase's list.
  - Weather floating button.

## Done in phase 7
- ✅ Lock screen media HUD material (Dark / Regular blur / Liquid glass), widget style (Inline / Vertical / Rounded), look (Light / Dark) and material.
- ✅ Lock/unlock animation (panels fade and rise in, fade out on unlock); Lock & unlock sound (`LockSound`: system padlock sounds as Default, or /System/Library/Sounds), played on the lock/unlock notifications.
- ✅ Keep awake while locked (`PreventUserIdleDisplaySleep` assertion "Droppy Lock Screen Keep Awake", released on unlock or after the chosen time).
- ✅ Volume and Brightness sliders on the lock screen (own click-through-safe panel); Keep visible during screensaver (panels raised above the screen saver; off, they hide while it runs, via `com.apple.screensaver.didstart/didstop`); Status widgets row toggle.
- ⏭ Not verified on a real lock screen in this session (needs locking the Mac).

## Done in phase 11
- ✅ **Now Playing Size** (`Settings › HUDs › Media`, `nowPlayingSize`): Regular | Smaller. `PlayerMetrics` became computed from `NowPlayingSize.scale` (0.86 for Smaller), so the cover, scrubber, transport, side panel and `DroppyShelfMetrics.playerWidth` / `playerHeight` all shrink together and the panel frame follows.
- ✅ **Always use built-in speakers** (`Settings › HUDs › Media Controls`, `alwaysUseBuiltInSpeakers`): when a *new* output turns up and macOS hands it the sound, `AudioOutputService.keepSoundOnThisMac()` sets the default back to the built-in device and says so in a banner. Only an arrival triggers it, so picking an output by hand still works.
- ✅ **Resting notch width** (bug): `Notch track title` was growing each resting wing to 112 pt, so a notched Mac drew a ~460 pt black bar across the menu bar instead of hugging the cut-out. The resting wing is now `AppState.restingNotchWing(isActive:wide:)` — 0 when nothing is live, `miniWing` for music or the Tray, `activityWing` for a wide live activity — and never the title. The title shows where there is room: the floating pill on a notchless display, and the open player. `titledWing` and the titled wing views are gone; `RestingNotchGeometryTests` pins the widths and `showsTrackTitle` down.
- ✅ **Lock screen › Widgets layout** (bug): the status-row preview used `.frame(width: 1100)` with `scaleEffect`, which doesn't shrink the layout, so the whole Widgets card claimed 1100 pt and its choice tiles and switches were clipped off the right edge of the page. It is measured and scaled in a reader now.
