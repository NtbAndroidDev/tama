# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tama is a native macOS 14+ menu-bar app (Swift 6 / SwiftUI + AppKit, no third-party dependencies) that turns the notch into a "Dynamic Island" shelf: Player, Tray, Widgets (Droplets) and Calendar pages, a clipboard shelf docked to the bottom of the screen, a floating Basket, and Live Activities in the resting notch. README.md describes user-facing behaviour, shortcuts and permissions in detail.

**The product is Tama; the code is not.** Types, files and the SwiftPM *targets* keep the
`Droppy` prefix from the app's former name — `DroppyApp`, `DroppyDesign`, `DroppyShelfMetrics`,
target `Droppy`, `Tests/DroppyTests`. Only the *products* in `Package.swift` (`Tama`,
`TamaMediaRemoteAdapter`), the bundle (`app.tama.macos`, `tama://`, Finder Services), every
user-visible string and the docs say Tama. Don't "fix" a `DroppyXxx` symbol to match the
product name; the two are deliberately apart. `Sources/App/LegacyRename.swift` carries
settings and stored files across from the old bundle identifier and the old Application
Support folder on first launch. That folder, `~/Library/Application Support/Droppy`, is
shared with the commercial Droppy this project is audited against (`docs/parity/`), so the
migration copies the items this app owns rather than moving the folder — and `docs/parity/`
says "Droppy" about that other app, never about this one.

## Build & run

```bash
swift build                    # debug build (compile check)
./build_app.sh                 # release build → packages ./Tama.app and code-signs it
./build_app.sh --install       # also kills the running copy, installs to /Applications and launches it
scripts/setup_signing.sh       # one-time: creates the "Tama Local Signing" identity
```

- It is a single SwiftPM `executableTarget` rooted at `Sources/`, with a `DroppyTests` test target
  (`Tests/DroppyTests/`, run with `swift test`) and no linter.
- Run the app from the `.app` bundle, not `swift run`. `Info.plist` (LSUIElement, usage strings, `NSServices`) only takes effect inside the bundle, and notifications, TCC permissions and Finder Services depend on it.
- Without the local signing identity, builds are ad-hoc signed. macOS then drops Accessibility, Automation and Screen Recording grants on every rebuild. If a permission-dependent feature "stops working" after a rebuild, check signing before debugging the code.
- `swift-tools-version: 6.0` means Swift 6 language mode with strict concurrency. Almost all app code is `@MainActor`, so background work (OCR, conversion, file I/O) must hop back explicitly.
- `*.swift.orig` files in `Sources/` are stale merge leftovers, not live code. Don't edit them.

## Architecture

**Lifecycle.** `DroppyApp` only declares a `Settings` scene. All real UI is custom `NSPanel`s created in `AppDelegate.applicationDidFinishLaunching`, which also starts every long-lived service (`XxxService.shared.start()`) and installs `ServicesProvider` (Finder › Services handlers; the selector names must match `NSMessage` in `Info.plist`).

**State.** `AppState.shared` (`App/AppState.swift`) is the `ObservableObject` that nearly every view and service reads and mutates. It holds:
- UI state: `isIslandExpanded`, `shelfPage`, `hud`, drag and quick-action state, `activeDropletID`, and similar.
- Content: `shelfItems` (Tray), `baskets` (each floating Basket with its own files), `clipboardItems`, `pinboards`, `droplets`.
- Island geometry (`islandSize`, `islandTopOffset`, `lanePillSize`, `showsLanePill`). This geometry is computed here, so the SwiftUI layout and the `NSPanel` frame and hit-testing agree.

Stored properties (`@Published`) must live in the class body in `AppState.swift`, because extensions can't hold them. Behaviour is split into extensions by area: `AppState+Geometry` (island shapes, screens), `+Persistence`, `+Tray`, `+Basket` (Baskets, and helpers that find held files on the Shelf or in any Basket), `+Clipboard` (history, pinboards), `+Undo` (undo banners), `+Notifications`, `+Pomodoro`, `+Droplets`. The level-HUD style accessor `hudStyle(for:)` is in `AppSettings.swift`.

**Settings** are not in `AppState`. Each area has its own store in `App/Settings/` (`ShelfSettings`, `ClipboardSettings`, `HUDSettings`, `MediaSettings`, `PomodoroSettings`, one per Droplet with settings, …), a `SettingsStore` subclass holding `@AppStorage` properties whose `didSet` hooks switch services on or off. A view reads a store through its own `@ObservedObject private var xxxSettings = XxxSettings.shared`, not through `AppState`, so it only redraws when that area changes. Non-view code uses `XxxSettings.shared`. To add a setting, put the property in its area's store and add its key to the store's `keys` and to `AppState.settingsKeys` (Reset, Export and Import walk that list; `SettingsStoreTests` checks the two agree). A new feature with preferences gets its own store and a line in `SettingsStoreTests.storeKeys`. `AppState` still republishes on every setting change for the views that haven't moved to the stores yet, so don't rely on that in new code.

**Sizes** all live in `App/Layout.swift`:
- `DroppyShelfMetrics`: shelf and player widths, page heights, pill, HUD and banner sizes.
- `PlayerMetrics`: the full player's internals. `playerHeight` is derived from them.
- `DroppyLayout`: the island-level springs.

To rescale the shelf, change these values rather than literals in views.

**Persistence** is in `AppState.restorePersistedState()` (`AppState+Persistence.swift`). It uses Combine sinks (some debounced) that write to UserDefaults (`trayFiles`, `scratchpadText`, droplet enable/disable lists, `pinboards`) and to `~/Library/Application Support/Tama/` (`clipboard.json`, `Clipboard/` images, `Tray/` files). `flushPersistence()` runs on quit to catch pending debounced writes. If you add persisted state, update both places.

**Windows** (`Sources/Windows/`) are singleton controllers that own `NSPanel`s:

Every `NSHostingView` installed as a window's or panel's `contentView` sets
`sizingOptions = []` first. These windows all set their own frame, and the resizable
ones their own `minSize`, so SwiftUI contributing content-size extrema on top of that
feeds back into the layout pass and AppKit aborts it with an "Update Constraints in
Window" exception — a launch crash, and an intermittent one. Adding a window without
that line is how it comes back.

- `NotchWindowController` hosts `DynamicIslandView` in a transparent canvas much larger than the island, so the spring animation can overshoot. `IslandHostingView.hitTest` passes clicks through everywhere except the island and lane-pill rects. The hosting view sits inside a plain `IslandCanvasView` container to avoid an AppKit constraint-update loop. Read the comments there before changing the window or sizing code.
- `ClipboardWindowController`, `FloatingBasketController`, `LiveActivityWindowController`, `SettingsWindowController` and the capture/ring controllers follow the same pattern.

**Views** (`Sources/Views/`):
- `Island/DynamicIslandView` is the morphing container. `Island/IslandCompactView` draws the resting wings and the floating pill.
- `Notch/ShelfView` switches pages. Each page lives in its own `*Page.swift` file.
- `Theme/DroppyDesign.swift` holds the `DS` design tokens: spacing, radii, type, colours and `DS.Motion` springs such as `morphOpen`/`morphClose`. It also holds the shared primitives (`DroppyIconButton`, `DroppyChip`, and others). Build new UI from these tokens and primitives, resolve the accent colour at draw time, and honour `accessibilityReduceMotion`.

**Droplets (widgets).** A droplet is a `DropletModel` in `AppState.loadDefaultDroplets()`, identified by a string `id`. The same `id` is matched in several `switch`es in `Views/Notch/WidgetsPage.swift`: the console view (`Views/Droplets/*ConsoleView.swift`), the tint colour, and the live badge text. Adding a droplet means touching all of these.

**Services** (`Sources/Services/`) are mostly `@MainActor` singletons (`.shared`) wrapping one system API each: EventKit, CoreAudio, Vision OCR, IOPM sleep assertions, Carbon hot keys (`GlobalShortcutService`), Accessibility, AppleScript media control, and so on. Transient status in the resting notch goes through `LiveActivityCenter.shared.post(LiveActivity(...))` / `end(id)`, which uses priorities; see `BatteryService` or `AudioOutputService` for examples. Banners go through `AppState.showNotification(...)`.

**Media.** macOS 15.4+ blocks the system Now Playing API for ordinary apps. `MediaService` loads the private MediaRemote framework at runtime and uses it first where it still returns data. Otherwise it reads Music, Spotify and browser tabs over Apple Events, and falls back to media keys, which need Accessibility access.
