# Files area parity audit: Droppy 14.2.0 vs our clone

All paths below are under `/Users/Shared/Data/source/macos/droppy/`. I did not edit anything.

## 1. Parity table

**Shelf / Tray**
| Ref | Ours | St | Change |
|---|---|---|---|
| "Files Shelf", "Temporary file storage in your notch or island", "Drag files to your notch…" | `Sources/App/AppState+Tray.swift:15` addShelfItems; files kept in App Support (`:81`) | ✅ | — |
| "Auto-Clean after dragging out" | `removeOnDragOut` `AppState.swift:307`, `TrayPage.swift:688` | ✅ | Rename the label to match. |
| "Auto-cleanup", "Auto-remove non-pinned shelf files after.", "Choose how long shelf files are kept…", "Expired", "Expires soon", "Smart expiration tracking" (ref lists 1/2/5/12/24 hours) | Capacity limit only (`AppState.swift:309`). `ShelfItem.addedAt` is not persisted: only paths go to `trayFiles` (`AppState+Persistence.swift:32,96`) | ❌ | Persist `addedAt` and `isPinned`. Add an expiry picker, prune non-pinned items on a timer, and show an "Expires soon" badge. |
| Pinning items, "Pin folders", "Tracked folder item", "No folders added", "Nothing in this folder matches.", "Unknown Folder" | `ShelfItem.isPinned` exists (`ShelfItem.swift:13`) but has no UI | ❌ | Add Pin/Unpin to the menu and a pinned-folder tile that browses the folder contents. |
| "Two Stacks"/"One Stack", "Stack 1/2", "Swipe between Stack 1 and Stack 2…", "floating 1 / 2 mouse shortcuts" | none | ❌ | Add a stack index to ShelfItem, a swipe/pill switcher and a setting. |
| "Tags", "Assign this tag to items…", "No items with this tag." | Tags exist only for clipboard pinboards (`Models/ShelfModels.swift:82`) | ❌ | Reuse Pinboard-style tags for tray files. |
| "Keyboard-first file management", "Push files via keyboard", "Choose a destination to move the selected files." | ⌘A, ⌫, Space, Return and ⌘Z in `TrayPage.swift:45-84`; shift-select at `:276` | 🟡 | Add arrow-key focus and a "Move to…" folder picker. |
| "Open tray after drop" | Island drops always `reveal:true` (`DynamicIslandView.swift:264`) | 🟡 | Add a toggle. |
| "Show Files Shelf as a floating button", "Files Button" | none | ❌ | Optional floating button. |
| "Get tactile feedback when dropping files…" | `hapticFeedback` is used only when the island opens (`AppState.swift:~432`) | 🟡 | Also fire it on a drop. |
| "After drop sessions", "Shared behavior for files dropped into Shelf and Basket", "Dropped files and folders" | `ShelfSettingsTab` (`SettingsView.swift:812`) holds 2 controls plus a stray Pomodoro section (`:823`) | 🟡 | Build a real "Shelf" / "Basket" settings pair and move Pomodoro out. |
| Context menu (screenshots): Copy, Open, Move to…, Open With…, Share ›, Quickshare, Save / "Save to Downloads", Extract Text, Remove Background, Compress ›, Create ZIP, Create Folder, Rename, Move to Shelf, "Remove from Shelf" | `TrayItemMenu` `TrayPage.swift:799` has Preview, QL, Open, Reveal, AirDrop, Convert, Edit, OCR, Copy file, Copy path, Remove | 🟡 | Add Move to…, Open With, system Share picker, Save to Downloads, Rename, Create Folder ("Create Folder Failed" / "Folder Created with Issues"), Compress ›, Remove Background. Make the menu act on the whole selection ("(3)"). |
| "Create ZIP", "ZIP creation failed", "Auto-zips multiple files or folders", "ZIP Hover" | `compressShelfItems` `AppState+Tray.swift:128`; LAN share zips folders | ✅ | "ZIP Hover" (a hover zip affordance) is missing. |

**Basket**
| Ref | Ours | St | Change |
|---|---|---|---|
| "Floating Basket", "Enable Floating Basket", "Turn floating basket mode on or off." | `FloatingBasketController.swift`, toggle at `SettingsView.swift:828` | ✅ | — |
| Separate basket contents: "Move to Basket", "Remove from Basket", "Move to Shelf", "To Shelf" button, "Add to Basket" | The Basket is a window onto the Tray and shares its items (`FloatingBasketView.swift:189`) | 🟡 | Decide the model. The ref keeps its own `basketItems` and moves them to and from the Shelf. |
| "Single Basket"/"Multi-Basket", "Only one basket at a time", "Jiggling while a basket is open spawns another basket", "New Basket", "Slots", "Workspace", "Use multiple basket slots/workspaces.", "Open baskets and store everything, color-sorted.", "Select a basket to add" | single panel | ❌ | Add multi-basket with a colour per basket. |
| "Basket Switcher", "Shortcut to show all baskets and switch between them." | none | ❌ | — |
| "Basket Jiggle Sensitivity", "Shake sensitivity", "Adjust movement sensitivity for reveal." | Fixed thresholds (`ShakeDetector.swift:11-14`); on/off at `SettingsView.swift:1403` | 🟡 | Add a slider that maps to minimumTravel and window. |
| "Instant Basket on Drag", "Instant Appear (no shake needed)", "Instant Basket Delay", "Configure instant reveal latency." | none | ❌ | In `JiggleService`, show the basket after N ms of any file drag. |
| "Press this while dragging to reveal the basket." (⌥ Option) | none | ❌ | Add a modifier-while-dragging trigger. |
| "Basket Auto-Hide", "Hide basket when idle.", "Delay before basket hides." | none (the basket stays until closed) | ❌ | Add auto-hide with a delay once the basket is empty or idle. |
| "Summon Basket" | Modifier+B toggle (`GlobalShortcutService.swift:68`) | 🟡 | Make it configurable. |
| "Bring a Basket to your drag." | `moveNearPointer` `FloatingBasketController.swift:58` | ✅ | — |
| "Share files via Droppy Cloud from the basket.", "Quick access via basket actions" | Basket drop tiles are Drop/AirDrop/Convert (`FloatingBasketView.swift:212`) | 🟡 | Use the same configurable tiles as the notch. |
| "Basket injection", "addToBasket" | none | ❌ | This is the Services / URL entry into the basket (see below). |

**Drag & drop**
| Ref | Ours | St | Change |
|---|---|---|---|
| "Protect originals", "Move", "Move Failed", "Some items could not be moved.", "Dragging to a different disk will still copy normally", "Move files in two easy drags." | Drag-out is a bare `NSItemProvider(url)` (`TrayPage.swift:444`) with no copy/move policy | ❌ | Add a Protect originals toggle that forces a copy, and a real Move action. |
| "Droppy needs to communicate with this app to export items when you drag…", "Could not export the selected email from Mail.", "Could not receive file from Photos…" | `DragDropService.swift:22` handles only fileURL, image and text. There is no `NSFilePromiseReceiver`, so drags from Mail and Photos fail | ❌ | Add a file-promise receiver. |
| "Could not persist file" | `keepingTemporaryFile` `AppState+Tray.swift:87` fails silently | 🟡 | Show a message when it fails. |
| "Drop (active)/(idle)", "AirDrop (active)/(idle)" | Tiles have no a11y value | 🟡 | Add an accessibilityValue. |

**Smart Export / conversion / compression**
| Ref | Ours | St | Change |
|---|---|---|---|
| "Convert files on your Mac, never in the cloud", "Conversion options", "Selects this format and starts conversion", "Dismiss file conversion", "Conversion progress", "Conversion Failed", "These files do not share a supported conversion format." | ConvertBar `TrayPage.swift:562`, JobCenter, Quick Convert droplet | ✅ | Copy the ref's error string. |
| Formats: WebP native, audio→WAV, Office/rich-text/web→PDF, PDF→images | `FileConverter.swift:458`: image→PNG/JPEG/HEIC/GIF/TIFF/PDF, and WEBP only if `cwebp` is installed (`:61`); PDF→PNG/JPEG/TXT; video→MP4/MOV/GIF/M4A; audio→M4A; docs→PDF/TXT/RTF/HTML/DOCX | 🟡 | Add audio→WAV, Office .docx/.pptx/.xlsx→PDF, HTML/webarchive→PDF, and a WebP path that does not need cwebp. |
| "Converted file save location", "Choose where converted files are saved", "Converted files go to Downloads.", "Converted files saved to Downloads. Show in Finder", "Destination folder", "After converting", "Open the destination folder after saving.", "Conversion complete. Show converted files in Finder" | Output goes to tmp, then into the Tray (`FileConverter.swift:112`, `:501`); the banner action opens the Tray | ❌ | Add a destination picker (default Downloads) and an after-converting option (reveal / open folder / add to shelf). |
| "Enable Smart Export", "Auto-route and export dropped content.", "Auto-save compressed files", "Processed files will be saved automatically.", "Automatically save processed files to designated folders", "Auto-compress screenshots", "Compressed images, videos, and PDFs", "Converted files (PNG → JPEG, etc.)" | none | ❌ | Build a Smart Export settings page with per-type auto-save rules. |
| Compress › "Low (Smaller)/Medium (Balanced)/High (Minimal Loss)" | Only the conversion Quality (Lossless/High/Compact, `FileConverter.swift:12`) | ❌ | Add an in-place Compress action for images, PDF and video. |
| "Compression failed or no size reduction (Size Guard)" | none | ❌ | Discard a result that is larger than the input. |
| "Video Target Size", "Compress videos to exact file sizes", "Target size in megabytes" (dialog with Current Size and Target MB) | none | ❌ | Add FFmpeg two-pass encoding to a target bitrate, with the dialog. |
| "Deep PDF compression with Ghostscript" | none | ❌ | Run `gs -dPDFSETTINGS`. |
| Homebrew flows: "Checking Homebrew…", "Homebrew Detected/Required", "Visit brew.sh…", "Ready to install / Installing FFmpeg / Ghostscript via Homebrew", "Downloading and installing…", "After installing Homebrew, click 'Install …'" | Only a cwebp error string ("brew install webp") | ❌ | Add a shared Homebrew detect-and-install helper. |

**AI background removal**
| Ref | Ours | St | Change |
|---|---|---|---|
| "Remove Background", "Remove backgrounds instantly", "KB (PNG, transparency kept)", "Background Removal Failed/Completed with Issues", "Item is not an image." | Vision `VNGenerateForegroundInstanceMaskRequest` in the Cutout droplet only (`AICutoutConsoleView.swift:335`); result added to the Tray (`:396`) | 🟡 | Add "Remove Background (N)" to the Tray/Basket menu as a batch job. |
| "BiRefNet - External Runtime", "Installing background removal runtime", "Verifying external runtime and model files", "AI model files are invalid…", "The downloaded archive is missing required model files." | We use Vision and download nothing | 🟡 (by design) | Keep Vision. BiRefNet is optional. |

**Sharing**
| Ref | Ours | St | Change |
|---|---|---|---|
| Quick Action tiles "Choose 3 from Quickshare, iCloud, AirDrop, Mail, and Messages" (Keep plus 3) | Fixed Keep / Share Link / AirDrop / Convert (`ShelfModels.swift:4`) | 🟡 | Make the 3 slots configurable. |
| "AirDrop", "Send files wirelessly to nearby Apple devices" | `TrayActions.airDrop` `TrayPage.swift:655` | ✅ | — |
| "Mail", "Attach files to a new email", "Quick Actions mail app", "Mail App", "Choose which app opens for the Mail quick action" | none | ❌ | Use `NSSharingService(.composeEmail)` plus an app picker. |
| "Messages", "Share files via Messages" | none | ❌ | Use `.composeMessage`. |
| "iCloud Drive", "Upload to iCloud Drive and share a link", "iCloud Drive Unavailable / Permission Required", "Could Not Prepare iCloud Drive Folder" | none | ❌ | Copy the files into the iCloud Drive container and open the share sheet. |
| "Quickshare", "Share files via 0x0.st", "Files expire automatically (30-365 days…)", "Upload failed/cancelled", "Select File to Upload…" | LAN link + QR code with 15 min / 1 h / until-quit expiry (`LANShareService.swift:14`, `DroppyCloudShareView.swift`) | 🟡 | Add a 0x0.st upload, which copies the link. Keep the LAN share. |
| "Quickshare Upload Manager", "Recent Uploads", "Manage Uploads…", "No shared files yet", "Require upload confirmation" / "Ask before uploading" | Single active share, no history | ❌ | Keep an upload history and add a confirm toggle. |
| Droppy Cloud (proprietary getdroppy.app, 1 GB rolling 24 h, manager, "Delete from Droppy Cloud") | none | ❌ | Needs a server we don't have. Out of scope. |
| Dropbox ("Connect Dropbox first", OAuth, "Could not create a Dropbox share link", "Quick Actions cloud provider") | none | ❌ | OAuth PKCE upload plus a provider picker. |
| LocalSend ("Send with LocalSend", "Save received files to", "Add received files to the shelf", "Visible to other devices", PIN, fingerprint, "Forget this device", receiver errors) | none | ❌ | Implement the LocalSend v2 protocol (multicast discovery plus HTTPS). |

**Integrations**
| Ref | Ours | St | Change |
|---|---|---|---|
| Finder Services "Add to Droppy Shelf" / "Add to Droppy Basket" | Only "Add to Droppy Tray" (`Info.plist:61`, `ServicesProvider.swift:16`) | 🟡 | Rename it to Shelf and add a Basket service. |
| "Enable Finder Services", "Finder and setup guide", "In the left sidebar, select Services", "Then open Files and Folders", "In Finder: right-click…" | none | ❌ | Add a setup guide in Settings. |
| "Alfred", "Integrate Droppy actions into Alfred." (Add to Shelf ⌘2 / Basket ⌘3) | No URL scheme, no workflow | ❌ | Add a `droppy://add?target=shelf|basket&path=` scheme and ship an .alfredworkflow. |
| "Watched Folder", "Watch folders and auto-add new files.", "Watch and process files from selected folders." | `DownloadWatcher.swift` watches ~/Downloads partial downloads only | 🟡 | Add user-chosen watched folders with auto-add or auto-process. |

## 2. UI/UX differences seen in screenshots
- **converter-screenshot-1**: the drag-hover tiles are Keep / Droppy Cloud / AirDrop / Convert, and the drag badge shows a count ("+3"). Ours use the same 4-tile layout, but tile 2 is "Share Link" (LAN QR).
- **converter-screenshot-2**: after dropping on Convert, the island shows a header with the thumbnail stack, "file and 2 more", total size and an ✕, then large format tiles with icons (JPEG / WEBP / PDF). Ours shows a bottom ConvertBar with text chips and a "More" menu, and no thumbnail header.
- **converter-screenshot-3**: completion shows "Completed · 3 converted files" with a sparkle thumbnail and a round blue Finder-folder button. Ours shows a banner, and its "Show" button opens the Tray, not Finder.
- **quickshare-screenshot-2/3**: tile set Keep / Droppy Cloud / iCloud Drive / Mail. When the upload finishes, the island shows a "Droppy Cloud Share (5 items)" row with a big ✓, and the link lands in the clipboard.
- **quickshare-screenshot-4**: Settings has "Workspace: Shelf, Basket, Clipboard" and a separate Droppy Cloud page with usage, share rows ("Expires in 23 hours", copy button) and toggles. Ours has one "Tray & Basket" tab.
- **pdf-compress-1 / ai-bg-screenshot**: the basket has a back chevron, a "N Files / size" header, grid/list toggle buttons, a grab handle and white-check multi-select circles. Its selection-aware menu shows counts ("Save All (3)", "Compress All (3)", "Create Folder (3)", "Move to Shelf (3)").
- **pdf-compress-2**: a big green ✓ over the tile when compression succeeds.
- **video-target-size-screenshot**: the basket shows "1 item", a blue "To Shelf" pill and an eraser (clear) button with a dashed border. The "Compress File" window shows Current Size and Target Size in MB.
- **finder-screenshot / alfred-screenshot**: Services entries are "Add to Droppy Basket" and "Add to Droppy Shelf". Alfred actions are Add to Shelf ⌘2 and Add to Basket ⌘3.

## 3. Ours only (keep)
- A LAN share link with a QR code, expiry chips and a download counter.
- The Basket minimises to a pill that still accepts drops.
- The Basket turns into Drop/AirDrop/Convert tiles while a file hovers over it.
- A "Drag all" / "N selected" multi-file drag chip.
- Undo toasts for removals and trims, plus ⌘Z.
- A tray capacity limit with "Keep All".
- Missing files are pruned every 5 s.
- Snip to Tray (the empty-state button plus a shortcut) and the capture preview's "Keep in Tray".
- OCR "Extract Text with Droppy" and "Send to Droppy Scratchpad" as Finder Services.
- Video→GIF and document→DOCX/HTML/RTF conversion.
- Conversion jobs that can be cancelled and survive the shelf closing (JobCenter live activity).
- Cutout background styles (Neon, Pastel, White, Black).
- A download-progress live activity.
- Text and images dropped from apps are turned into files.

## 4. Coverage
I went through all 575 lines of `buckets/files.txt`, and grepped `ref_all_strings.txt` for extra file-area strings. I added "Pin folders", "Move to Shelf", "Remove from Shelf", the Low/Medium/High compress levels, "Move Failed", "Dragging to a different disk…", "Save", "Upload via Droppy Quickshare / to your Dropbox / to Droppy Cloud and copy a shareable link", "Upload from Clipboard", "Configure instant reveal latency", "Adjust movement sensitivity for reveal", the 1/2/5/12/24-hour options, and "Sync … Quickshare history, and current Shelf/Basket state through … iCloud".

Some lines belong to another area or aren't relevant:
- **Licensing / trial / updates:** 5,7,8,76,179,196,211,226-228,239,264-266,278,310,323,331,349,363,406,418,433,444,497,501,530,564.
- **Droplet install and enable:** 90,173-176,245,247-249,253-258,260,271,307-309,312-321,358,395,434,448,459,460,466,472,534.
- **Permissions / System Settings panes / onboarding:** 27-29,31,62,153,154,229-236,238,240,250,279,290,300,322,369,440,441,445,558.
- **Other feature areas:**
  - Thaw / menu bar: 241,293,437,475,514.
  - Window snap: 6,231,294,295,560.
  - Audio / voice transcribe / analyzer: 35,36,37,117,122-124,131,132,139,140,206,207,209,216,372,384,385,401,424,425,446,449,487,524,526,538,540,541.
  - Obsidian: 77,141,399,453,454.
  - Reminders, Calendar, Pomodoro: 66,67,284,403,503.
  - Meetings: 203,348,392.
  - Messages reply: 435,482.
  - High Alert: 200,202,221-223,344.
  - Camera: 351,491,493,533,535.
  - Media and browser bridge: 103,104,180,181,244.
  - LiquidMouse: 109,303.
  - Element Capture / screenshots: 65,82,159,160,230,234,398,447.
  - App settings and visibility: 64,80,81,85,86,269,270,302,346,389,397,476-478,490,513,515.
  - Misc: 49,161,174,197-199,208,288,306,382,400,420,474.

  Some of these, such as "Drag the screenshot into any app", overlap with ours but belong to the capture area.
- **Generic words:** 162,178,301,350,368,539,569.

I treated 1-4, 42, 45, 46, 96, 114, 118-121, 125-130, 133-138 and 142-152 as in-area and folded them into the table rows above, except for Droppy Cloud and Dropbox error strings. Those are grouped into their rows as "error handling".
## Done in phase 5
- ✅ **Shelf / Tray**: `addedAt`, pin, stack and tags persist (`trayItems` JSON; the old `trayFiles` list is still written and read). Auto-cleanup picker (1/2/5/12/24 h/Never) prunes unpinned files every 5 s ("Expired" banner), with an orange "Expires soon" clock badge. Pin/Unpin with a pin badge; pinned files never expire or make room. A pinned folder opens in a folder browser (search, subfolders, drag out, + to Shelf, "Nothing in this folder matches.", "Unknown Folder"). Two Stacks setting with a 1 | 2 pill. Tags (shared with the clipboard boards) with a filter menu and "No items with this tag." Arrow keys move the focus (⇧ extends), ⇧⌘M runs Move to…. A haptic fires on every drop. "Open tray after drop" is kept.
- ✅ **Context menu** (AppKit, acts on the selection with counts): Preview, Quick Look, Browse Folder, Open, Open With ›, Reveal, Copy, Copy Path, Move to › (Desktop/Documents/Downloads/Choose…; "Move Failed"), Save to Downloads, the system Share ›, AirDrop, Droppy Quickshare, Share Link, iCloud Drive, Mail, Messages, Convert ›, Compress › Low/Medium/High (+ Target Size… for a video), Create ZIP ("ZIP creation failed"), Create Folder ("Create Folder Failed", "Folder Created with Issues"), Extract Text, Remove Background (N), Edit Screenshot, Rename…, Pin, Tags ›, Move to Stack, Move to Basket/Shelf, Remove.
- ✅ **Basket**: each Basket has its own files (`baskets`, persisted), with Move to Basket/Shelf and a "To Shelf" pill. The header shows "N Files" and the size (drag the title to take everything out), a grid/list toggle, an eraser clear button and selection circles. Instant appear (with a delay), Auto-hide (with a delay), Shake sensitivity (mapped onto ShakeDetector), a recordable modifier Drag shortcut, Single | Multi-Basket (a shake while one is out spawns another in the next colour), a Basket Switcher shortcut (a menu at the pointer), and an optional second bucket. The drop tiles are the configured Quick Actions.
- ✅ **Drag & drop**: every tile drag is an AppKit drag source, so Protect originals applies (copy only) and Auto-remove only fires when another app really took the file. Mail and Photos promises are received through NSItemProvider file representations, which is SwiftUI's bridge to file promises; there is no separate NSFilePromiseReceiver because the drop targets are SwiftUI. The reference's error strings are used, and "Could not persist file" is reported.
- ✅ **Quick Actions**: Keep plus up to 3 of AirDrop, Convert, Share Link (LAN), Quickshare (0x0.st, link copied, with a server token so an upload can be deleted), iCloud Drive, Mail (Default | Mail | Outlook) and Messages. The notch, island and Basket all use them, with accessibility values "active"/"idle". Recent Uploads manager and "Require upload confirmation".
- ✅ **Conversion / compression**: destination folder (Downloads by default) and After converting (Show in Finder / Open folder / Add to Shelf / nothing), with a "Completed · N converted files" banner and a Show in Finder button. New: audio→WAV (afconvert), HTML/webarchive→PDF (WebKit, one continuous page), Office files→PDF through LibreOffice when it's installed, and WebP through ImageIO when the system can write it (it can't on this Mac, so cwebp stays). Compress Low/Medium/High for images, PDFs (Ghostscript when installed, otherwise the Quartz Reduce File Size filter or PDFKit JPEG options) and videos (AVFoundation presets), all with the Size Guard. Video Target Size dialog runs a two-pass FFmpeg encode. A shared Homebrew helper checks for and installs FFmpeg, Ghostscript, WebP and LibreOffice (`brew install` in the background, with a job in the notch, or a brew.sh prompt). Smart Export saves to per-type folders. Tracked folders add new files once they have finished writing.
- ✅ **Integrations**: Finder Services "Add to Droppy Shelf" and "Add to Droppy Basket" (the old `addToTray` selector still works; Extract Text and Scratchpad are kept), plus a setup guide. `droppy://add?target=shelf|basket&path=…` and `droppy://show?target=…`. Our own Alfred workflow (`Resources/Integrations/Alfred`, packed by `scripts/build_alfred_workflow.sh` and bundled by build_app.sh), installed from Settings.
- ✅ **AI background removal**: a batch Remove Background (N) job (Vision). Backdrop, padding (trims to the subject), corner radius and shadow are set in Settings › General.
- ⏭ Skipped: Droppy Cloud (no server), Dropbox (needs an OAuth app registration), LocalSend (Phase 10), the "ZIP Hover" affordance, the "Files Button" floating shelf button, and swiping between Stack 1 and 2 (sideways swipes already switch shelf pages, so the pill does it). iCloud Drive can't mint a share link through a public API, so files are copied to iCloud Drive › Droppy and revealed for Share › Copy Link.

## Done in phase 10
- ✅ **LocalSend** (the "LocalSend" droplet, off by default; `Services/LocalSend/`). It is compatible with LocalSend protocol v2.
  - **Discovery**: UDP multicast on 224.0.0.167:53317, using BSD sockets with SO_REUSEPORT on every IPv4 interface. Droppy announces this Mac every 30 s and on changes, answers announcements with `/register` (falling back to a multicast reply), and offers "Scanning network" (a /24 `/register` sweep over HTTPS, then HTTP).
  - **Receiver**: an HTTP/1.1 server on TCP 53317 (Network framework).
    - Encryption: "Encrypted (HTTPS)" uses TLS with an EC P-256 self-signed certificate. Droppy builds it in DER with the Security framework and stores it in the login keychain as "Droppy LocalSend TLS". The fingerprint is the SHA-256 of that DER. An HTTP mode is also available.
    - Endpoints: `register`, `info`, `prepare-upload` (PIN via `?pin=`; 401/403/409/429), `upload` (streamed to disk, bound to the session's token and IP; Content-Length or chunked) and `cancel`.
    - Text messages: they are shown, copied on "Copy", and answered with 204.
  - **Receive settings**:
    - Receive from Off / Favorites / Anyone, with an accept prompt (a floating "Incoming requests" panel that declines after 60 s). Quick Save for favorites skips the prompt.
    - A PIN, with 5 tries a minute.
    - Save received files to (Downloads by default). A sender's folders are kept, and paths are sanitised.
    - Add received files to the shelf.
    - An editable device name with "Reset to this Mac's name".
    - Favorites with "Forget this device".
    - A notch live activity with progress while receiving.
  - **Send**: "Send with LocalSend" in the Tray/Basket menu, a LocalSend Quick Action tile, and dropping files on the widget. Folders are expanded to relative paths. A peer list shows device-type icons. HTTPS peers are pinned to their announced fingerprint. Progress and Cancel are shown. PIN entry happens on 401.
  - **Error strings** follow the reference: "This device asks for a PIN", "The receiver declined the transfer", "The receiver is busy with another transfer", "The receiver reported an error (…)", "The receiver sent an invalid response", "This device can no longer be reached", "The sender cancelled the transfer", "The sender stopped responding", "LocalSend was turned off".
  - **Tests**: the TLS server and fingerprint pinning were checked end to end with a temporary keychain. The HTTP server round trip, the chunked decoder, the DER output and path sanitising are in the unit tests.
  - **Entitlements**: a non-sandboxed Mac app needs no multicast entitlement (`com.apple.developer.networking.multicast` is for iOS). macOS 15+ shows the Local Network prompt once; `NSLocalNetworkUsageDescription` now mentions LocalSend.
  - **Limits**:
    - Only one app can own TCP 53317, so the real LocalSend app on the same Mac must be quit ("Port 53317 is in use…").
    - The TLS key lives in the login keychain, because macOS 14 has no public in-memory `SecIdentity`. After an ad-hoc rebuild, macOS may ask once before Droppy can use it again.
    - Not yet tried against physical phones in this environment.
    - The v1 API and LocalSend's "download" (web share) mode aren't served.
- ✅ **Offline**: Quickshare says "No Internet Connection" before uploading. The LAN share link already reports when there's no network.

## Done in phase 11
- ✅ **ZIP Hover**: a new Quick Action tile (`QuickAction.zip`, "ZIP Hover" — "Hover to drop the files in as one ZIP archive"). Hovering it during a drag runs the existing `createArchive(of:into:)`, so the files land on the Shelf (or that Basket) as one archive instead of loose. It is choosable in `Settings › General › Quick Action tiles` alongside AirDrop and Convert, and works from the notch, the Basket and the context menus.
- ✅ **Swiping between Tray stacks**: with `Two Stacks` on, a two-finger swipe **up or down** on the open Tray moves between Stack 1 and Stack 2. Vertical is unused on the open shelf, so it never fights the sideways page swipe (which the Tray already gives up once it holds files). `Settings › Shelf › Swipe direction` flips it.
- ✅ **Upload from Clipboard**: `QuickshareService.uploadFromClipboard()` takes whatever is on the pasteboard — the files themselves, an image written as a PNG, or the text as a `.txt` — uploads it and copies the link. It is a button beside "Upload File…" in `Settings › General › Recent Uploads` and an item in the clipboard shelf's ⋯ menu. It says "Nothing to upload" on an empty pasteboard.
- ✅ **Screenshot preview placement**: `Settings › Shelf › Tray & screenshots › Preview placement` — Bottom right | Closest corner (the reference's "Closest Corner"). `CapturePreviewController.origin(for:on:pointer:placement:)` is pure and unit-tested; the card always stays inside the visible frame.

## Done in phase 13
- ✅ **"Watched Folder" — "Watch and process files from selected folders."** (the 🟡 row above): tracked folders watched the folders but could only ever add to the Shelf, so the "process" half of the reference's own wording was missing. Each folder now carries a `TrackedFolderAction` — **Add to Tray**, **Add to Basket** or **Add and compress** — stored beside its path in `trackedFolders` as `action:path`. A bare path, which is what earlier versions wrote, still reads as Add to Tray, so saved folders keep working unchanged. `TrackedFolderService.settle()` gathers arrivals by action, so a folder filling up is one batch rather than one job per file; "Add and compress" holds the file on the Shelf first so the compressed result takes the original's place, and uses `Settings › General › Automation › Compression level` (`trackedFoldersCompressionLevel`), since an unattended run has nobody to ask. Basket arrivals open a Basket to land in, and fall back to the Shelf if none can be opened.
- ✅ **Tray keyboard, the half the clipboard already had**: the rail scrolls, so the arrow keys could walk the focus off the end of what was on screen — it now scrolls the tile they land on into view. A file added while the rail is scrolled deep into the list brings the rail back to it (a file that expires does not, which was the phase-12 rule for the clipboard). ⌫ leaves the keyboard on the nearest surviving file instead of nothing, so a second ⌫ carries on. ⌘C copies the selection, as Finder does and as the clipboard shelf already did.
- ⏭ Still skipped, unchanged: Droppy Cloud (no server), Dropbox (needs an OAuth app), and the rest listed in phases 10–12.
