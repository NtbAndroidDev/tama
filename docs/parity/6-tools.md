## Tools-area parity audit: reference Droppy 14.2.0 vs our clone

**Bottom line:** we already have a solid screenshot editor with a Beautify panel, a corner preview, OCR, a simple Voice Transcribe, basic LiquidMouse, Mechey with synthesized sounds, a Ring, a Color Dropper and Quick Math. We are missing these entirely:
- Element (UI-element) capture
- Capture destinations and auto-compress
- Hiding the notch from screenshots
- Editor zoom
- The magnifier, curved-arrow, diamond and sticker tools
- Pointer-first Window Snap (drag to edges, action key, snap zones)
- LiquidMouse curves and per-axis settings
- A downloadable Mechey soundpack library
- Whisper/Parakeet speech models
- Invisi-record
- Thunderstorm as a floating launcher with web search and inline answers
- All of Thaw
- Recordable and per-widget shortcuts

### 1. Feature table

**Element Capture / screenshots**
| Ref | Ours | | Change |
|---|---|---|---|
| "Element", "Capture specific UI elements", "Capture any screen element instantly" | none. We only call `/usr/sbin/screencapture` (ScreenSnipperConsoleView.swift:423) | ❌ | Add an AX hit-test overlay (AXUIElementCopyElementAtPosition) plus a ScreenCaptureKit crop. |
| "Capture fullscreen, windows, or selected areas", "Fullscreen capture", "Window" | ScreenSnipperConsoleView.swift:12-16 (Area/Window/Full/Snip & OCR), with a delay timer (:32) | ✅ | Rename the droplet tag. |
| "Capture destinations", "Choose where captures go after taking a screenshot.", "Screenshot destination", "Automatically save screenshots to this folder." | only the "Save to Tray" / "Copy Image" toggles (:145-160) | 🟡 | Add a destination picker (Clipboard/Tray/Folder/Editor) and a folder chooser. |
| "Auto-compress screenshots" | none | ❌ | Add a toggle that reuses FileConverter. |
| "Hide Notch from Screenshots", "Hide from screenshots", "Hides the notch from viewers while sharing." | none (no `sharingType` anywhere) | ❌ | Set `panel.sharingType = .none` on the notch and live-activity panels behind a toggle. |
| "Open editor instantly" | "Edit after capture" (:159) | ✅ | Match the label. |
| "Default zoom level", "Open editor at native-ish zoom", "Reset Zoom", "Zoom In/Out", pinch-to-zoom | none. The editor only fits to the window. | ❌ | Add canvas zoom and pan, magnify gesture, and ⌘+/⌘−/⌘0. |
| "Screenshot preview" + quick actions (edit / copy / save / OCR / pin), "Copied" | CapturePreviewController.swift:165-174 | ✅ | See UI notes in section 2. |
| "Close pinned screenshot" | pin keeps the preview up and it has a close button (:136, :171) | 🟡 | Pin should create a separate floating, resizable always-on-top window. |
| "Edit in Screenshot Editor" | CaptureEditorWindowController.open(contentsOf:) | ✅ | Expose it in the Tray context menu if not already there. |
| "Could not encode the screenshot." | generic errors only | 🟡 | Add a specific error. |
| "Screenshot gallery coming soon" | none | – | Not needed. |
| "Configure Element Capture", "Keyboard shortcuts", "Customizable keyboard shortcut" | one fixed ⌃⌥S Quick Snip (GlobalShortcutService.swift:76) | 🟡 | Add a recordable shortcut for each capture mode. |

**Screenshot editor**
| Ref | Ours | | Change |
|---|---|---|---|
| "Arrow", "Line", "Rectangle", "Ellipse", "Freehand", "Highlighter", "Text", "Blur", "Number Sticker" | CaptureEditorModel.swift:6 (also has Pixelate, Crop and Select) | ✅ | Rename "Pen" to "Freehand" and "Step Number" to "Number Sticker". |
| "Curved Arrow" | none | ❌ | Add a quadratic arrow with a control handle. |
| "Diamond", "Square", "Circle" | Shift already constrains shapes to square/circle (:379) | 🟡 | Add a Diamond shape and add Square/Circle as explicit presets. |
| "Magnifier", "Drag the magnifier edge to resize and zoom" | none | ❌ | Add a loupe annotation that renders a zoomed crop of the original. |
| "Pointer Sticker", "Pointer Sticker (Circle)", "Cursor Sticker", "Cursor Sticker (Circle)" | none | ❌ | Add stamp annotations. |
| "Small / Medium / Large Stroke" | StrokeSize S/M/L (:62) | ✅ | – |
| "Font" | fixed system font; size only (textPoints) | 🟡 | Add a font family picker. |
| "Default annotation color", "Highlight Color" | defaults to red, not persisted (:86) | 🟡 | Add a setting and persist it. |
| "Screenshot Radius", background padding / beautify | CaptureStylePanel.swift:1-44 (presets, Padding, Corners, Shadow, aspect ratio) | ✅ | Add a "Screenshot Radius" default in Settings. |
| "Drag the screenshot into any app", "Drag to copy the screenshot into another app" | CaptureEditorView.swift:197; preview `.onDrag` (CapturePreviewController.swift:120) | ✅ | – |
| "Editor shortcuts" | hard-coded single-key tools (CaptureEditorWindowController.swift:145-195) | 🟡 | Add a cheat sheet or settings list. |
| "Annotate with arrows, shapes & text" | ✅ | ✅ | – |

**OCR**
| Ref | Ours | | Change |
|---|---|---|---|
| OCR on a snip / in the preview | Snip & OCR mode; preview OCR (CapturePreviewController.swift:218); OCRConsoleView | ✅ | – |
| "OCR Auto-Copy", "Auto-copy OCR text" | the preview copies automatically; the console does not | 🟡 | Add a toggle. |
| "No text detected in the selected area." | "No text found" | ✅ | Match the wording. |

**Window Snap**
| Ref | Ours | | Change |
|---|---|---|---|
| "Pointer-first + keyboard window management", "Arrange windows with quick snapping tools." | click-only preset buttons (WindowSnapperConsoleView.swift:66; WindowSnapService.swift:43) | 🟡 | Rebuild as a drag-driven service. |
| Drag to edges, "Live snap zones with edge/corner previews", "Show snap preview" | none | ❌ | Watch window drags globally; show an overlay zone panel. |
| "Action-key drag", "Move", "Resize", "Resize needs at least one action key." | none | ❌ | Add a modifier + drag event tap to move/resize the window under the pointer. |
| "Require Action Key To Snap", "When off, dragging a window title bar… snaps without holding a key" | none | ❌ | Add a toggle. |
| "Snap with shortcuts", "Configure Window Snap" | Ring Snap Left/Right/Maximize only (RingAction.swift:7) | 🟡 | Add a hotkey per layout. |
| "Right Two Thirds", quarters | halves, thirds and center only (:45-52) | 🟡 | Add two-thirds and quarters. |
| "Bring Window To Front" | `app.activate()` after a snap | 🟡 | Make it its own action. |
| Multi-display moves | none | ❌ | Add next/previous display actions. |

**LiquidMouse**
| Ref | Ours | | Change |
|---|---|---|---|
| "Smooth Scrolling", "Interpolates non-continuous…", "Turns wheel steps into a continuous…" | LiquidMouseService.swift:5-17; console :55 | ✅ | – |
| "Reverse Scroll Direction", "Invert external wheel direction…" | "Reverse mouse wheel" (:56) | ✅ | – |
| "Choose which wheel axis to configure", "Invert this axis…", "Restore the balanced… preset for this direction" | both axes use one global setting | ❌ | Add vertical/horizontal tabs, each with its own config. |
| Curve presets (Linear, "Balanced", Ease In/Out Cubic/Quartic, "Soft start…", "Stable and fluid…") | Speed and Glide sliders only | 🟡 | Add a curve picker. |
| "Adjust scroll speed from slower to faster" | Speed 0.5–3× | ✅ | – |
| "Liquid Mode", "trackpad-like inertial flow" | the glide is a single ease-out | 🟡 | Add a separate momentum mode. |
| "Shows whether LiquidMouse currently sees a connected external mouse." | none | ❌ | Detect the mouse via IOHID and show a status chip. |

**Mechey**
| Ref | Ours | | Change |
|---|---|---|---|
| "Keyboard soundpacks", "downloadable soundpacks", "Install a soundpack", "Loading soundpack library", "Tap refresh…", "No soundpacks loaded", "Soundpack credits" | 5 synthesized packs (MecheyService.swift:51) | 🟡 | Build a remote library with install/refresh/credits, or keep ours and add the empty/loading states. |
| "Pick a soundpack with a keycap grid", "Preview this soundpack without switching" | pack list plus a test-key row (MecheyConsoleView.swift:98, :138) | 🟡 | Show a keycap tile grid (clicky-screenshot-2) and add a hover-preview button. |
| "Master switch for Mechey clicks." | isOn toggle (:69) | ✅ | – |
| "Mouse click sounds" | none | ❌ | Add mouseDown to the tap. |
| "Skip modifier keys" | modifiers always click | ❌ | Add a toggle. |
| "Silence during music" | "Silent while music or video is playing" (:40) | ✅ | – |
| "Silence during Focus" | none | ❌ | Add a toggle. |
| "Only click when headphones are connected.", "Waiting for headphones", "Auto-enable on headphones" | none | ❌ | Use AudioOutputService to detect the output route. |
| "Input Monitoring", "Open Input Monitoring" | console :82 | ✅ | – |

**Voice Transcribe**
| Ref | Ours | | Change |
|---|---|---|---|
| "OpenAI Whisper models", Parakeet, "Install once… offline", downloading the model | Apple Speech only (VoiceTranscribeService.swift:57) | ❌ | Add a pluggable model backend and a download UI (big job). Alternatively, mark Apple on-device as the engine. |
| "Live Transcription", "Live transcription" | streaming SFSpeech while recording | ✅ | Add the missing-model states only if we add models. |
| "Invisi-Record", "Background recording (no window)", "Start or stop invisible background voice transcription" | none. Recording is inside the console only. | ❌ | Add a hotkey that records headless and copies the result. |
| "Quick Record", "Record with visible window", "Start or stop a visible… session" | record button in the console | 🟡 | Add a global hotkey (the ref uses ⇧⌘R). |
| "Recordings are kept until you delete them" vs "Audio is deleted right after transcription" | saved recents, trimmed at recentsLimit (:591) | 🟡 | Add a retention setting. |
| "Delete recording", "No recordings yet", "Transcribe this recording" | delete (:418); list | 🟡 | Add an empty state and re-transcribe. |
| Upload an audio file ("Select Audio File to Transcribe") | transcribeFile plus NSOpenPanel and drop (:45, :231, :345) | ✅ | – |
| "Skip result window and copy transcription instantly", "Stop & Use Transcript" | none | ❌ | Add a toggle. |
| "Show recording icon in menu bar" | Live Activity only (:349) | 🟡 | Add a status item while recording. |
| "Still transcribing…", "Transcribing audio", "No speech detected…" | messages exist in part | 🟡 | Show a % progress view (see section 2). |
| "External Recorder", "Use the floating panel instead of inline expansion" | none | ❌ | Add a floating recorder panel option. |

**Thunderstorm**
| Ref | Ours | | Change |
|---|---|---|---|
| Mac search launcher (floating) | a console inside the Widgets page (ThunderstormConsoleView.swift:56) | 🟡 | Add a hotkey-summoned floating panel. |
| Web search / "Google Search", "Web Result", "Inline website preview", "Looking up an inline answer...", "No inline answer…" | none | ❌ | Add web rows plus answer lookup. |
| "Open Droppy settings inside Thunderstorm", "See every droplet…" (install/uninstall rows) | none | ❌ | Index settings and droplets as results. |
| "Change weather variables inside Thunderstorm" | WeatherService exists, not wired in | ❌ | Add commands. |
| App actions: "Move app to Trash", "Press Return to move to Trash", "Move to Shelf", "Move Failed", "Some items could not be moved." | open / reveal / Quick Look / Tray / copy path (:173) | 🟡 | Add move-to-Trash and move actions. |
| System Settings pane results (Family / Siri / Keyboard Shortcuts / Spotlight Shortcuts…) | none | ❌ | Index the panes. |
| Droppy commands (Quick Record, Invisi-record, Voice Transcribe) | none | ❌ | Add command results. |

**Thaw menu bar manager**
| Ref | Ours | | Change |
|---|---|---|---|
| All of it: "Hide and manage menu bar items", "Always Hidden", "Always-hidden section", Show on click / hover / scroll / double-click, "Option-click to reveal", "Rehide when you click outside…", "Only hide when you click the toggle", "Enable Thaw Bar", "Where to anchor the Thaw Bar", "Thaw Bar at pointer on hotkey", "Toggle ThawBar", "Show Thaw icon", "Render… as a template", "Show hover tooltips…", install/approval/errors, "Runs inside Thaw" | none | ❌ | The reference installs the external Thaw.app from GitHub and bridges to it over IPC. Either build a droplet that installs and controls Thaw, or skip it. |

**Shortcuts, Ring, Color Dropper, Quick Math**
| Ref | Ours | | Change |
|---|---|---|---|
| "Keyboard Shortcuts" page, "Change Shortcut", "Add Shortcut to Open", "Reset all shortcuts", "No shortcuts found", "Loading shortcuts" | a shared modifier plus fixed keys (SettingsView.swift:291-317) | 🟡 | Add a key recorder per action and a reset. |
| "Widget shortcuts", "Install and enable widgets to record per-widget shortcuts here." | none | ❌ | Add an optional hotkey per droplet that opens its console. |
| Ring / radial menu | RingAction.swift, RingMenuView, ⌃⌥R | ✅ (ours) | – |
| Color picker | NSColorSampler plus HEX/RGB and swatches (ColorPickerConsoleView.swift:120) | ✅ | – |
| Calculator | QuickMath + MathEvaluator | ✅ | – |

### 2. UI/UX differences in the screenshots
- **element-capture-screenshot-poster.jpg:** the reference preview is a glass card with a "Screenshot / Quick actions" header, a green "Copied" pill at top right, the image inset in a rounded well, and 5 large circular buttons (edit, copy, save, OCR, pin; pin is red). Ours is a bare 280pt thumbnail with a hover-only capsule toolbar. Restyle it to match.
- **clicky-screenshot-1/2.jpg:** Mechey has a full keycap keyboard visualizer with keys that animate on press, and soundpacks shown as coloured keycap tiles ("SKCM Blue", "Black ABS", "Black PBT", "Blue PBT"…). Ours is a text pack list and a 5-key test row.
- **voice-transcribe-screenshot.jpg to -4.jpg:** it runs inline in the expanded island. The idle state is a large red record button with a recordings list (date, time, duration). Recording shows a red live waveform, a timer and a stop ring. Transcribing shows a spinner with "Transcribing… 20%". The result is a "Transcription / N words" card with Close and a white Copy pill. Ours has locale menus, REC text and pill rows. Add the % progress and the word count.
- **thunderstorm-screenshot-1 to 4.jpg:** a free-floating, Spotlight-style black glass bar ("Search your Mac" with a storm icon). Results have a blue selected row, a ↵ hint and a back chevron. It shows droplet rows with Installed/Uninstall buttons, and Droppy commands with their shortcut ("Quick Record · ⇧⌘R", "Invisi-record"). Ours lives inside the notch widget page.
- **thaw-screenshot-1/2.jpg:** a separate Thaw app with Always Hidden, Hidden and Visible sections, and a floating ThawBar strip below the menu bar.
- **window-snap-screenshot.jpg:** a translucent blue snap-zone preview covers the target half while the window is dragged. We have nothing like it.
- **element-capture.jpg, liquidmouse.jpg:** these are droplet icons only (gold capture brackets; a Magic Mouse).

### 3. Ours only
- A Crop tool and a Pixelate redaction style.
- Beautify extras: gradient presets, aspect ratios (16:9 / 4:3 / 1:1) and a shadow toggle.
- Editor undo/redo, nudging with the arrow keys, Save As PNG/JPEG, and "Add to Tray".
- Preview "Keep in Tray".
- A capture delay timer.
- OCR on PDFs and the clipboard, with language detection.
- Voice Transcribe: locale picker, recording → Tray, transcript .txt → Tray, playback.
- Thunderstorm: `kind:`/`ext:` filters, whole-Mac scope, Quick Look.
- A Glide slider in LiquidMouse.
- The Ring radial menu with numbered actions.
- Colour-dropper swatch history.

### 4. Coverage
All 255 lines of buckets/tools.txt are accounted for, either mapped above or judged other-area/irrelevant as follows:
- **Appearance/tint:** 7, 15, 32, 33, 42, 193, 194, 256
- **Island right-click hide:** 9, 180-186, 192, 195, 197
- **License:** 101, 102, 164
- **Permissions onboarding:** 8, 37-39, 147, 188, 227
- **Bluetooth:** 151, 161
- **Other areas:**
  - 21 (Brighten shortcut)
  - 48 (accessibility indicator)
  - 95 (screensaver)
  - 146 (Pop up when offline)
  - 178 (Reverse swipe direction)
  - 221 (Start Auto Scroll)
- **Mapped to Thunderstorm System Settings results:** 14, 67, 73, 140, 208, 218, 224
- **Keystroke action feedback:** 1-2 ("Activate target app… sent key combo")
- **Thaw hover/IPC:** 5, 46, 236-238
- **Voice UI placeholder:** 239 (sample transcription)
- **Ours n/a:** 190 (gallery coming soon)

## Done in phase 9a
Scope set by the user: no new system-wide mouse or keyboard monitoring and no event taps. Everything below starts from a shortcut or a click inside Droppy's own windows.

**Element Capture / screenshots**
- ✅ `ScreenCaptureService`: ScreenCaptureKit (`SCScreenshotManager`) for area, window, full screen, element and Snip & OCR, with `/usr/sbin/screencapture -R/-l` as the fallback. The Tray's Quick Snip, the Ring and the console all use it.
- ✅ Element capture: our own full-screen overlay (`CaptureSelectionController`) hit-tests the app under the pointer with `AXUIElementCopyElementAtPosition`, using the overlay's own mouse-moved events. Scroll widens the pick to the parent element, a click captures it, and a drag falls back to an area. Without Accessibility access it picks whole windows.
- ✅ A recordable shortcut for each capture mode (none by default), plus Quick Snip to Tray.
- ✅ Capture destinations Clipboard / Tray / Folder / Editor (several at once), a folder chooser (default Desktop), "Open editor instantly", Auto-compress screenshots (point resolution plus FileCompressor), and "Leave Droppy out of captures" (an SCContentFilter excluding our windows; the overlay is always excluded). Specific error: "Could not encode the screenshot."
- ✅ Preview card restyled: glass card, "Screenshot / Quick actions" header, green "Copied" pill, inset image well, 5 round buttons (edit, copy, save, OCR, red pin). Keep in Tray stays on hover and in the context menu.
- ✅ Pin opens a separate floating, resizable, always-on-top window with its own close button (also Esc, ⌘W and the context menu). Any number can be open.
- ✅ OCR honours OCR Auto-Copy. When it's off, a banner offers Copy. The console, preview and Snip & OCR share the service. "No text detected in the selected area."

**Screenshot editor**
- ✅ Zoom: fit or chosen, ⌘+ ⌘− ⌘0 ⌘1, pinch, a zoom menu, pan by scrolling, and a Default zoom level setting.
- ✅ Tools: Curved Arrow (with a bend handle), Diamond, Square and Circle presets, Magnifier loupe (drag its edge to resize; S/M/L sets the zoom), Pointer and Cursor stickers plus their Circle variants (vector-drawn, no assets). Renamed to Freehand and Number Sticker. The toolbar groups the variants.
- ✅ Font family picker for text. Persisted Default annotation color and font. Screenshot Radius default. An editor shortcuts cheat sheet (the ⌨ button or ?) and the same list in Settings.

**Window Snap**
- ✅ A recordable shortcut for each layout: halves, thirds, two-thirds, quarters, center, maximize, next and previous display (multi-display, keeping the relative frame), and Bring Window To Front (raises the window under the pointer). A blue snap-preview zone flashes on shortcut snaps ("Show snap preview"). The console lists every layout.
- ⏭ Skipped by user decision (it would need global drag monitoring or event taps): drag-to-edge snapping, live snap zones during drags, action-key move/resize, and "Require Action Key To Snap".

**LiquidMouse**
- ✅ Per-axis (Vertical | Horizontal) reverse, speed and curve. Curve presets: Linear, Balanced, Ease In, Out and In Out for Cubic and Quartic, Soft Start, Stable & Fluid, each with a plot and a description. Liquid Mode momentum. Restore Balanced per direction. External-mouse status from IOHID device enumeration (properties only, nothing opened). All of this runs inside the existing scroll tap; no new tap.

**Mechey**
- ⏭ Skipped by user decision for this phase.

**Search**
- 23 new `droplet.snipper/ocr/windowSnapper/liquidMouse.*` entries.

## Done in phase 9b
Scope set by the user: no new system-wide mouse or keyboard monitoring, no event taps, and recording is always visibly indicated.

**Voice Transcribe**
- ✅ Inline island UI as in the screenshots. Idle shows the recordings list (weekday and time, date, duration) over a big red record button, or "No recordings yet". Recording shows a red live waveform with dots for the rest of the strip, the red timer and a white stop ring. Then "Transcribing… N%", a spinner with Cancel. The result is a "Transcription · N words" card with Close, a white Copy pill, and .txt → Tray. The locale picker, file transcription (pick or drop), playback and Tray actions are kept.
- ✅ Live transcription toggle. When off (the default), Stop runs the saved file through Speech with a real percentage: segment timestamps, plus a capped time estimate until those arrive.
- ✅ Quick Record: a recordable shortcut (none by default). It opens the recorder (inline, or the floating panel) and starts recording, or stops the current one. "Skip result window and copy transcription instantly". When the shelf has closed, a "Transcription ready" banner offers Copy.
- ✅ "Show recording icon in menu bar": a red mic with the time; click it to stop. It is also forced on while the island is hidden. The notch live activity always shows too.
- ✅ Retention: Keep until deleted (default), Keep the last 5 (the old behaviour), or Delete audio after transcription (the text stays). Re-transcribe a saved recording from its row or context menu. "Show Transcription" reopens the card.
- ✅ Engine picker for Apple Speech: Auto, On-device only, or Server allowed.
- ✅ External Recorder: a floating, draggable recorder panel. It can't close while recording.
- ⏭ Whisper/Parakeet models: they need large model downloads and a third-party inference runtime, and the project ships no third-party code.
- ⏭ Invisi-Record: skipped by user decision; no hidden recording.

**Thunderstorm**
- ✅ A floating Spotlight-style launcher, summoned by a recordable shortcut (default: shared modifier + T) or the console's new button. It is a black glass bar showing "Search your Mac" with a storm glyph, and grows with its results. The selected row is blue with a ↵ hint. Esc steps back, then clears, then closes. The widget console is kept.
- ✅ Sections:
  - Calculator
  - Applications and Files (Spotlight, with ⌘↩ ⌘Y ⌘T ⌘C)
  - Droppy commands with their shortcuts (Quick Record, clipboard, capture modes, Menu Bar Manager…)
  - Droppy settings (SettingsSearch index; opens Settings at the row)
  - Droplets with Enabled / Enable / Disable and →, plus "See Every Droplet" (a list mode with a back chevron)
  - 46 System Settings panes (name, keywords, description, URL)
  - System commands: Lock Screen, Sleep, Restart, Shut Down, Log Out, Eject All Disks, Quit All Apps. The destructive ones ask for a second Return ("Press Return to …"). Empty Trash is not included.
  - Weather quick info
  - Google, DuckDuckGo and Wikipedia search rows
- ✅ Move app or file to Trash with ⌘⌫, then Return to confirm. Running apps are refused. On error it shows "Move Failed / Some items could not be moved."
- ✅ Inline web answers come from DuckDuckGo's keyless Instant Answer API: "Looking up an inline answer…" and "No inline answer…". Lookups as you type are opt-in (they send the query to DuckDuckGo). Otherwise a "Look Up an Inline Answer" row asks on demand.
- 🟡 Lock Screen uses the private `SACLockScreenImmediate` (looked up at run time), falling back to display sleep. Restart, Shut Down and Log Out go through System Events and need Automation access.

**Menu bar manager (own implementation):** see 7-leftovers › Done in phase 9b.

**Shortcuts**
- ✅ Settings › Keyboard Shortcuts page: every recordable shortcut grouped by area, a filter ("No shortcuts found"), Reset all shortcuts (with confirmation), and the built-in keys.
- ✅ Widget shortcuts: an optional recordable shortcut per droplet that opens its console (press it again to close). They are listed on that page ("Install and enable widgets to record per-widget shortcuts here.") and on each droplet's page. They are registered only while the droplet is on.
- 30+ new search entries (`droplet.voiceTranscribe/thunderstorm/menuBar.*`, `shortcuts.*`, `droplet.<id>.openShortcut`).
