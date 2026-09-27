# Driving the app for a visual check (2026-09-23)

The reference app lives at `/Applications/Droppy.app` (bundle `iordv.Droppy`) and is usually running. Quit it before running ours and relaunch it afterwards with `open -b iordv.Droppy`.

## Build and sign without the keychain prompt

`codesign` with the "Droppy Local Signing" identity hangs here because the login keychain is locked for it, so sign ad-hoc instead:

```bash
swift build -c release
cp .build/release/Droppy Droppy.app/Contents/MacOS/Droppy
cp .build/release/libDroppyMediaRemoteAdapter.dylib Droppy.app/Contents/Frameworks/
cp Info.plist Droppy.app/Contents/Info.plist
codesign --force --sign - Droppy.app/Contents/Frameworks/libDroppyMediaRemoteAdapter.dylib
codesign --force --sign - Droppy.app
open ./Droppy.app
```

Ad-hoc signing means macOS drops the TCC grants on every rebuild, so permission-dependent features need granting again.

## Opening the shelf

Two traps cost time here:

- **`open "droppy://…"` goes to the reference app.** Both bundles register the
  `droppy` scheme and LaunchServices prefers `/Applications/Droppy.app`
  (`iordv.Droppy`), so the URL silently launches the reference instead of our
  build (`app.getdroppy.macos`). Quit it again before carrying on.
- **Clicking the resting wings is unreliable.** The wings carry live
  activities, so a click often runs one of those instead of expanding, and the
  physical notch between them passes clicks straight through.

The menu-bar icon is the dependable route: it is the droplet in the status
bar, and its menu has Open Shelf (⌘D), Now Playing (⌘M), Tray (⌘S), Widgets
(⌘W) and Tasks & Calendar (⌘K). Clicking one opens the shelf on that page.
Otherwise walk the pointer onto the notch in a few steps with `mouse move`,
which fires the hover open when Auto-expand is on.

Watch `defaults read app.getdroppy.macos autoHideDelay` before blaming the
code for a shelf that vanishes: at its lowest (0.1) the shelf closes 100 ms
after the pointer leaves the island.

## Pointer and screenshots

`SP=/private/tmp/claude-501/-Users-Shared-Data-source-macos-droppy/a9707a50-3595-43fc-a8ec-8b834cfe4ff3/scratchpad` holds a small `mouse` helper (source `mouse.swift`): `"$SP/mouse" move X Y` and `"$SP/mouse" click X Y`, in points on the main display.

Built-in display: 2056×1329 pt, so the notch centre is around x=1028, y=0…33.

- **Clicking x=1028 (dead centre) does nothing** — that is the physical notch cut-out, which passes clicks through.
- **Click a wing instead**, for example `mouse click 950 12`. That opens the shelf.
- Hover no longer opens the shelf: auto-expand on hover now defaults to off.
- The resting wings only appear when something is playing.

Capture just the notch area and downscale, so the screenshots stay small:

```bash
screencapture -x -R 628,0,800,420 /tmp/out.png && sips --resampleWidth 760 /tmp/out.png --out /tmp/out.png
```

`$SP/wins` (source `wins.swift`) lists Droppy's on-screen windows with their frames, which tells a missing window apart from one that draws nothing.

## First visual check, 2026-09-23

Open shelf, Home page, with a Chrome tab playing: the single glass lane capsule plus the round calendar button, the glass weather card (Local, 26°, Drizzle, H/L, AQI, sunset, four hourly columns) and the player all render, and the shelf matches the reference's proportions. Not yet checked: every Settings page, the Tray, Widgets, Calendar, the clipboard, the Basket, the droplet consoles, HUDs and the lock screen.
