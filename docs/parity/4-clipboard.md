## Clipboard parity audit: Droppy 14.2.0 reference vs our clone (read-only, no files edited)

Paths below are relative to `/Users/Shared/Data/source/macos/droppy/Sources/`. Abbreviations: **CSV** = `Views/Clipboard/ClipboardShelfView.swift`, **CWC** = `Windows/ClipboardWindowController.swift`, **CS** = `Services/ClipboardService.swift`, **CP** = `Services/ClipboardPrivacy.swift`, **SV** = `Views/Settings/SettingsView.swift`, **ASC** = `App/AppState+Clipboard.swift`.

### 1. Feature table

| Reference (quoted string) | Ours | | What to change |
|---|---|---|---|
| "Enable Clipboard Manager" / "Keep Clipboard history" / "Enable Clipboard in Settings" | none. Monitoring always runs; only Pause exists (CP:101, SV:850) | ❌ | Add a master toggle that starts/stops `ClipboardService`. When it is off, the shortcut shows a "Enable Clipboard in Settings" banner. |
| "Clipboard layout" – "Choose between the regular clipboard window and the compact clipboard layout" | Single bottom-docked horizontal card strip (CWC:123, 206pt tall) | ❌ | Reference is a vertical list with a preview pane (quickshare-screenshot-1, thumbs 3–4). Add a layout picker: regular window (list + preview) vs compact (our dock). |
| "Show Clipboard as a floating button" / "Clipboard Button" | none | ❌ | Small floating panel button that toggles the clipboard. Add the setting too. |
| "Clipboard locations" – "Use clipboard history and choose where its shortcuts appear." / "Adds \"Open Clipboard\" to right-click menu on notch/island" | Always shown: island context menu `Views/Island/DynamicIslandView.swift:308` ("Clipboard (⌥C)"), menu bar `App/AppDelegate.swift:102`, Ring `Models/RingAction.swift:69` | 🟡 | Add toggles for each location. Rename the item to "Open Clipboard". |
| "Clipboard Shortcuts" – "Configure open/paste keyboard shortcuts." / "Space shortcut for Clipboard." / "Open clipboard history from anywhere." | Fixed modifier+C (`Services/GlobalShortcutService.swift:77`), listed at SV:312. Only the modifier can change | 🟡 | Make the key recordable. Add the optional Space variant (ref shows ⇧⌘Space) and a separate paste shortcut. |
| "Auto-Focus Search" – "Automatically focuses the search bar when clipboard opens" / "Focus search input automatically on open." | Search sits behind a magnifier button or ⌘F (CSV:126, 486). On open, focus goes to the cards (CSV:80) | ❌ | Add a setting. When on, set `isSearching=true; searchFocused=true` on open. |
| "Arrow keys won't navigate list until you press Escape" | Our ↑/↓ work inside the search field (CSV:282) | ✅+ | Ours is better. Keep it. |
| "Start typing immediately to filter clipboard history" | none. `handleKey` ignores printable characters (CSV:491) | ❌ | In `handleKey` default: a printable key with no ⌘ opens search and seeds `query`. |
| Arrow-key list navigation | ←/→ on the horizontal strip (CSV:461) | 🟡 | Add ↑/↓ once there is a vertical layout. |
| "Clipboard search" / "Search clipboard" / "Search entries and extracted content." / "Search clipboard history with OCR-powered text extraction" | Placeholder "Search clipboard" (CSV:268). Matches content, title and OCR text (CSV:34-40) | ✅ | none |
| "OCR images" / "Text recognition" / "Text recognized from image" | Vision OCR runs on every image clip (CS:97), stored as `ocrText`. Menu item "Copy Text" (CSV:865) | ✅ | Optional: a toggle for OCR on images. |
| "OCR Auto-Copy" – "Auto-copy OCR text" / "Auto-copy recognized text from images." / "Auto-copy result" / "Extracted text copied to clipboard" | none in the clipboard (only the OCR droplet and capture preview copy) | ❌ | Add a setting. After `onRecognizedText`, write the text (it must not be recorded as a new clip) and show the banner. |
| "Add to favorites" / "Remove from favorites" / "Copy + Favorite" | Star hover button (CSV:572), menu (CSV:853), Favorites filter (CSV:1039), favorites sorted first | 🟡 | Add a "Copy + Favorite" action. Match the title-case strings. |
| "Take this favorite off the bar" | none | ❌ | The reference seems to have a favorites bar. Confirm what it is before building it. |
| "Create Pinboard" / "Pinboard is Empty" / "Pin items to this pinboard to see them here." / "Remove from Pinboard" | Pinboard tabs, "+" (CSV:132-170), drag onto a tab, delete with undo (ASC:115). Empty strings match exactly (CSV:441,448). Removal is via menu "Pinboard › None" (CSV:857) | 🟡 | Add an explicit "Remove from Pinboard" item. Rename the "+" help text to "Create Pinboard". |
| "Tags" / "Assign this tag to items to collect them here." / "No items with this tag." (ref menu shows "Tag ›", screenshot thumb 4) | none. Only one pinboard per clip | ❌ | Add a multi-valued `tags` field on `ClipboardItem`, a "Tag ›" submenu, tag filter views and empty states. |
| "Rename clipboard entry" | Double-click the title, or "Rename…" (CSV:726, 864; ASC:96) | ✅ | none |
| "Paste as Plain Text" | none. We store only plain strings, so rich text/HTML is lost on capture | ❌ | Capture RTF/HTML data. Paste rich by default and add a "Paste as Plain Text" action (⌥⏎ / ⇧⏎). |
| "Paste all selected items" | none. Only single selection (CSV:14) | ❌ | Add multi-select (⌘/⇧-click) and paste the items joined by newlines. |
| "Paste into the previous app" | Non-activating panel, then ⌘V is posted (CWC:8-11, 88-121) | ✅ | Add a toggle (off = copy only). |
| "Copied to Clipboard & Pasting" | Sound only (CSV:507) | 🟡 | Show a brief HUD/toast on paste. |
| "Accessibility Paste Support" – "Grant permissions for reliable paste actions." | AX prompt plus a fallback banner (CWC:98-110) | 🟡 | Add a Settings row with status and a Grant button. |
| "Clipboard Actions" – "Enable advanced actions for managing clips." | "Copy As" (upper/lower/trim/colour) always shown (CSV:871) | 🟡 | Put the extras behind this toggle. Add Preview (ref menu has "Preview"). |
| Bulk actions | none | ❌ | With multi-select: delete, favorite, pin or tag in bulk. |
| "Delete from clipboard history" / "Remove from history" | "Delete" menu item, trash hover button, ⌫ key (CSV:884, 575, 470) | ✅ | Rename the label only. |
| "Clear History" – "This will permanently remove all clipboard items." | "Clear History" with an undo toast. It keeps starred and pinboard clips (CSV:367, ASC:80). Settings button "Purge All Unstarred…" (SV:890) | 🟡 | Add a confirm alert with the reference text, or keep undo. Align the Settings wording. |
| "Clear history on quit" | none (`App/AppDelegate.swift:60`) | ❌ | Add the toggle. Call `clearClipboard()` before `flushPersistence()`. |
| "Choose how many clipboard items Droppy keeps." | Stepper 10–200 (SV:870), plus retention age and an image MB cap (CP:71-76) | ✅+ | Consider a Picker with larger values (500/1000/unlimited). |
| "Pinned items never expire from history." | Starred and pinboard clips are exempt (ASC:37, CP:201) | ✅ | Reuse this caption. |
| "Add excluded app" / "Select app to exclude" / "Currently excluded" / "Prevent selected apps from appearing in clipboard history." | Full list with Add App…, Add Running App, defaults (SV:896-937, CP:140) | ✅ | Wording only. |
| "Blur sensitive content" | We *skip* sensitive text instead ("Skip sensitive content", SV:885; `Services/SensitiveContentDetector.swift`) | 🟡 | Add a blur mode: store the clip flagged and render it blurred until hover or reveal. |
| "Show the type-filter rail in Alpha Clipboard." | Filter icon row always visible (CSV:176, 1007) | 🟡 | Add a show/hide toggle. |
| "Clipboard appearance" | none | ❌ | Add a section to hold the layout, rail and floating-button settings. |
| Empty states: "Clipboard is Empty" / "Clipboard is empty." / "Copied items will appear here." / "Things you copy will appear here." / "No clipboard matches." / "Try a different search." / "Clipboard history is empty" | "Clipboard is Empty" ✓. Subtitle "Copy something and it shows up here."; "No Matches" plus a custom line (CSV:437-449) | 🟡 | Use the reference strings. |
| "Sync preferences, clipboard history, … through your Apple iCloud account" | none | ❌ | iCloud sync (CloudKit or a ubiquity container). Large effort. |
| "Upload from Clipboard" / "Upload via Droppy Quickshare…" | none. We have no Quickshare | ❌ | Depends on the Quickshare area. |
| "Legacy clipboard" / "No readable clipboard history source was found." | none | ❌ | Probably an import from older Droppy or other managers. Low priority. |
| "Clipboard Settings" – "Manage clipboard history, size, and reuse." | `ClipboardSettingsTab` (SV:839), subtitle "Keep the things you want to use again." (SV:52) | ✅ | Subtitle wording only. |

### 2. UI/UX differences
- **Form factor** (quickshare-screenshot-1, thumbs 3–4): the reference is a dark window with "Search clipboard" at the top and a vertical list of rows. Each row has a title, "Source · App · 1 min ago" and coloured tag chips on the right, plus a preview pane. Its bottom bar has Copy, ★ and other icons. Its context menu has Paste, Copy, Unfavorite, Pin, Tag ›, Preview, Delete. Ours is a black dock at the bottom of the screen with 164×132 cards in a row, pinboard tabs and an icon filter rail.
- **Keyboard:** the reference focuses search on open and filters as soon as you type. Ours needs a click or ⌘F.
- **Feedback:** the reference shows a "Copied to Clipboard & Pasting" HUD and "Text Copied" banners. Ours plays sounds only.
- **Clearing:** the reference clears everything after a confirmation. Ours keeps starred and pinboard clips and offers undo.

### 3. Ours only
- Pause recording for 5 min, 1 h or until resumed, with a header pill (CP:5, CSV:332).
- Retention by age and an image storage cap with a usage readout.
- Skips concealed/transient pasteboard types.
- Filters card numbers, private keys and tokens.
- Undo on delete, clear, limit changes and pinboard delete.
- Colour swatches and "Copy As" (RGB/SwiftUI/NSColor).
- Duplicate-image hashing.
- Source-app icon on cards.
- Drag a card out as the real file or image.
- Drag a card onto a pinboard tab.
- ⌘C, ⌘Z, ⌫ and ⏎ on cards.
- Image pixel size and character/line counts on cards.
- VoiceOver actions.

### 4. Coverage
I accounted for all 146 lines of `buckets/clipboard.txt` (`wc -l` reports 145 because the last line has no trailing newline). The table covers the clipboard lines. Taglines and marketing lines (1, 17, 47, 74, 99, 108, 146) are covered by the rows above. I also pulled extra clipboard strings from `ref_all_strings` (Tags, "No items with this tag.", "Arrow keys won't navigate…").

These lines belong to other areas: license 22, 88, 135 · crash report 45, 53, 76, 133 · Thaw/menu bar 46, 86, 111 · Quickshare/cloud 50, 69, 75, 81, 140–144, 14 · capture/screenshot 51, 57, 63, 64 · basket 58 · OCR droplet/generic (shared with ours via Vision) 52, 65–68, 128–132 · web/AI search 71, 82, 104, 105, 113 · permissions/HUD 73, 90 · Finder/Spotlight 93, 114–115, 123–124 · weather 106, 110 · settings search 117, 139 · shortcuts search 112 · voice transcribe 120, 122, 137 · changelog 98.
## Done in phase 6
- ✅ **Enable Clipboard Manager**: `clipboardEnabled` starts/stops `ClipboardService`; with it off the shortcut, menus and Ring show a "Clipboard is off · Enable Clipboard in Settings" banner that opens Settings › Clipboard.
- ✅ **Clipboard locations**: Menu bar and Shelf right-click menu tiles; both items renamed "Open Clipboard".
- ✅ **Clipboard layout**: Alpha (our dock, restyled: header tinted by the source app's icon colour, title, "2 min ago", app icon on the corner, footer chip "66 characters ≡ 2" / "1728 × 1117", ★) | Legacy (`LegacyClipboardView`: centred list window with search, rows "Type · App · 1 min ago" + tag chips, preview pane, bottom bar Paste/Copy/★/Preview/Delete, ↑/↓ navigation).
- ✅ **Type filters** toggle; **Shortcut** recordable, default ⇧⌘Space (falls back to modifier+C when the shared modifier is ⌘⇧, where ⌘⇧Space is the island's).
- ✅ **History limit** slider (10…2500 stops, "N of M items saved", applied on release); **Skip passwords**; **Blur sensitive content** (kept, flagged, blurred until hover / Reveal); **Clear history on quit**; **Reject duplicates** (on: a repeat is ignored; off keeps our move-to-front).
- ✅ **Clipboard actions** tiles: Tags (multi-valued `tags`, Tag › submenu with New Tag…, tag tabs/filters, "No items with this tag." empty state, tag management in Settings), Copy + Favorite, Auto-Focus Search. Start typing to filter (both layouts).
- ✅ **Paste as Plain Text**: RTF/HTML captured (≤512 KB) and pasted by default; ⌥⏎/⇧⏎ and menu item paste plain.
- ✅ **Multi-select** (⌘/⇧-click, ⇧-arrows, ⌘A), "Paste all selected items", bulk Copy/Favorite/Pin/Tag/Delete (bar in Alpha, menu in both); **Remove from Pinboard**; context menu Paste/Copy/Favorite/Pin/Tag ›/Preview (Quick Look)/Delete.
- ✅ **"Copied to Clipboard & Pasting"** HUD banner; **Paste into the previous app** toggle; Accessibility Paste Support row.
- ✅ **OCR auto-copy** for image clips (only if the pasteboard hasn't changed since; written as our own copy, not re-recorded).
- ✅ Reference empty-state strings; excluded apps as chips / "No apps added" + "Add app…"; "Create Pinboard"; Clear History confirm (Legacy).
- ⏭ Skipped: floating clipboard button and favorites bar (not in this phase's brief / unconfirmed), separate paste shortcut, iCloud sync (large, needs CloudKit entitlement), Upload via Quickshare, Legacy history import.

## Done in phase 11
- ✅ **Favorites bar** (`Settings › Clipboard › Clipboard appearance › Favorites bar`, `clipboardFavoritesBar`, on): starred clips get a strip of chips between the header and the cards in the Alpha clipboard, so they stay one click away whatever the search or the pinboard tab shows. A chip pastes its clip; its menu has Paste, Copy and the reference's "Take this favorite off the bar".
- ✅ **Separate paste shortcut** (`Settings › Clipboard › Shortcuts › Paste shortcut`, `ShortcutAction.pasteFromClipboard`, none by default): opens the clipboard in paste mode, so the clip you pick goes straight into the app you came from even with "Paste into the previous app" off. The mode is read before the panel hides and is cleared when the clipboard closes.
- ✅ **Upload from Clipboard**: in the clipboard's ⋯ menu and in Settings; see 3-files-basket-share › Done in phase 11.
- ⏭ Still skipped: iCloud sync (needs a CloudKit entitlement) and the legacy history import (no documented format for the reference's store).
