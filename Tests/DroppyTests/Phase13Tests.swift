import AppKit
import Foundation
import Testing
@testable import Droppy

/// Settings › General › Automation › Tracked folders: each folder carries what
/// it does with an arrival, stored beside its path.
@Suite struct TrackedFolderTests {
    @Test func tokenCarriesTheAction() {
        let folder = TrackedFolder(path: "/Users/me/Drops", action: .compress)
        #expect(folder.token == "compress:/Users/me/Drops")
        #expect(TrackedFolder(token: folder.token) == folder)
    }

    /// Earlier versions wrote bare paths. They must keep working, doing what
    /// they always did.
    @Test func aBarePathStillReadsAsAddToTray() {
        let folder = TrackedFolder(token: "/Users/me/Inbox")
        #expect(folder?.path == "/Users/me/Inbox")
        #expect(folder?.action == .tray)
    }

    /// A folder name may hold a colon of its own, so only a known action counts
    /// as one — otherwise "Notes: 2026/" would lose its first word.
    @Test func aColonThatIsNotAnActionStaysPartOfThePath() {
        let folder = TrackedFolder(token: "/Users/me/Notes: 2026")
        #expect(folder?.path == "/Users/me/Notes: 2026")
        #expect(folder?.action == .tray)
    }

    @Test func emptyTokensAndEmptyPathsAreDropped() {
        #expect(TrackedFolder(token: "") == nil)
        #expect(TrackedFolder(token: "basket:") == nil)
        #expect(TrackedFolder.decode("") .isEmpty)
    }

    @Test func aListRoundTrips() {
        let list = [
            TrackedFolder(path: "/a", action: .tray),
            TrackedFolder(path: "/b", action: .basket),
            TrackedFolder(path: "/c", action: .compress),
        ]
        #expect(TrackedFolder.decode(TrackedFolder.encode(list)) == list)
    }

    @Test func mixedOldAndNewLinesDecodeTogether() {
        let list = TrackedFolder.decode("/old/path\nbasket:/new/path")
        #expect(list.map(\.action) == [.tray, .basket])
        #expect(list.map(\.path) == ["/old/path", "/new/path"])
    }
}

/// Who is holding the island open. The same set now backs both the modals and
/// the text fields being typed into.
@Suite struct EditingOwnersTests {
    /// The bug this covers: a console holds a search box and an editor, and
    /// moving between them used to clear the one flag while the person was
    /// still typing — the shelf then collapsed and took the draft with it.
    @Test func leavingOneFieldForAnotherKeepsTheHold() {
        var owners = EditingOwners()
        owners.set(true, owner: "droplet.obsidian.editor")
        owners.set(true, owner: "droplet.obsidian.settings")
        owners.set(false, owner: "droplet.obsidian.editor")
        #expect(owners.isPresenting)
        owners.set(false, owner: "droplet.obsidian.settings")
        #expect(!owners.isPresenting)
    }

    /// A console torn down with its field focused never reports losing focus,
    /// so the surface clears its own prefix as it goes.
    @Test func aConsoleClearsOnlyItsOwnFields() {
        var owners = EditingOwners()
        owners.set(true, owner: "droplet.terminotch.terminal")
        owners.set(true, owner: "calendar.newTask")
        owners.clear(withPrefix: "droplet.terminotch")
        #expect(owners.isPresenting)
        owners.clear(withPrefix: "calendar.")
        #expect(!owners.isPresenting)
    }

    /// The shelf closing clears every field at once: nothing in a closed shelf
    /// can be typed into.
    @Test func anEmptyPrefixClearsEverything() {
        var owners = EditingOwners()
        owners.set(true, owner: "droplet.quickMath.field")
        owners.set(true, owner: "droplet.ocr.editor")
        owners.clear(withPrefix: "")
        #expect(!owners.isPresenting)
    }
}

@MainActor
@Suite struct ShelfModeTests {
    /// Rearranging is only drawn on the Widgets page, but it also holds the
    /// shelf open. Left set, a page switch parked the shelf open with nothing
    /// on screen explaining why and no way for it to close itself.
    @Test func leavingTheWidgetsPageEndsRearranging() {
        let state = AppState.shared
        let page = state.shelfPage
        let rearranging = state.isRearrangingWidgets
        defer {
            state.shelfPage = page
            state.isRearrangingWidgets = rearranging
        }

        state.shelfPage = .widgets
        state.isRearrangingWidgets = true
        state.shelfPage = .calendar
        #expect(!state.isRearrangingWidgets)
    }

    /// Typing holds the shelf open; the hold is per field, and the last one to
    /// let go releases it.
    @Test func typingBlocksAutoCollapseUntilEveryFieldIsLeft() {
        let state = AppState.shared
        defer { state.clearEditing(withPrefix: "") }
        state.clearEditing(withPrefix: "")

        state.setEditing(true, owner: "droplet.obsidian.editor")
        #expect(state.isEditingText)
        #expect(!state.canAutoCollapse)
        state.setEditing(true, owner: "calendar.newTask")
        state.setEditing(false, owner: "droplet.obsidian.editor")
        #expect(state.isEditingText)
        state.setEditing(false, owner: "calendar.newTask")
        #expect(!state.isEditingText)
    }

    /// A console going away takes its fields with it, focused or not.
    @Test func closingADropletConsoleClearsItsFields() {
        let state = AppState.shared
        let droplet = state.activeDropletID
        defer {
            state.activeDropletID = droplet
            state.clearEditing(withPrefix: "")
        }

        state.activeDropletID = "terminotch"
        state.setEditing(true, owner: "droplet.terminotch.terminal")
        #expect(state.isEditingText)
        state.activeDropletID = nil
        #expect(!state.isEditingText)
    }
}
