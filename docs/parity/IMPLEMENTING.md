# Parity implementation: rules for every phase

**Goal:** match the reference Droppy 14.2.0 in features, UX and Settings. The evidence is in `docs/parity/1-7*.md` (audits), `8-settings-screens.md` (Settings as seen) and the screenshots in `/private/tmp/claude-501/-Users-Shared-Data-source-macos-droppy/a9707a50-3595-43fc-a8ec-8b834cfe4ff3/images/*.png` and `…/scratchpad/shots/*.jpg`.

## Rules
1. Read `CLAUDE.md` first and follow its architecture:
   - Stored settings are `@AppStorage` in the `AppState` class body, and every new key is added to `AppState.settingsKeys` (`AppSettings.swift`) so reset, export and import cover it.
   - Sizes go in `Layout.swift`; UI uses the `DS` tokens and primitives.
   - Persisted data must be handled in both places listed under Persistence.
2. Swift 6 strict concurrency: the app is `@MainActor`, so hop back explicitly after background work.
3. **`swift build` must pass at the end of your phase.** Fix every error and every new warning in files you touched. Never leave the tree broken.
4. Use real, working implementations only; no stubs, no TODOs. When a feature can't be done properly with public or stable APIs, implement the closest honest version, then say so in your report.
5. Do not copy the reference app's assets (images, sounds, videos, icons). Use SF Symbols, system sounds, or synthesize.
6. Out of scope, don't build: licensing/trial, the updater/beta channel, the Droppy Cloud server, the app-icon picker, installing third-party apps (Thaw, BetterDisplay; a "Get app" link is fine).
7. Preserve every "Ours only" feature listed in the audits.
8. Don't edit `*.swift.orig`. Don't touch areas owned by other phases unless necessary; when you must, keep the change minimal.
9. When you finish, append a `## Done in phase N` list to the audit file(s) you worked from. Mark the rows you completed and list anything skipped with the reason.
10. Final report: at most 250 words. Cover what was built, what was skipped and why, and the `swift build` result.
