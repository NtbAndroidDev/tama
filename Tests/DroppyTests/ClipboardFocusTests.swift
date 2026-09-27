import Foundation
import Testing
@testable import Droppy

/// Where the keyboard lands when the clip it was on disappears without going
/// through the Delete key — deleted from its own menu, or pruned by retention.
@Suite struct ClipboardFocusTests {
    private let order: [UUID] = (0..<5).map { _ in UUID() }

    @Test func focusMovesToTheClipAfterTheDeletedOne() {
        var surviving = Set(order)
        surviving.remove(order[2])
        #expect(FocusAfterRemoval.next(after: order[2], in: order, surviving: surviving) == order[3])
    }

    /// Deleting the last clip has nothing after it, so it steps back.
    @Test func focusStepsBackAtTheEndOfTheList() {
        var surviving = Set(order)
        surviving.remove(order[4])
        #expect(FocusAfterRemoval.next(after: order[4], in: order, surviving: surviving) == order[3])
    }

    /// A run of clips going at once skips over all of them.
    @Test func focusSkipsEveryClipThatWentWithIt() {
        let surviving: Set<UUID> = [order[0], order[4]]
        #expect(FocusAfterRemoval.next(after: order[1], in: order, surviving: surviving) == order[4])
        #expect(FocusAfterRemoval.next(after: order[3], in: order, surviving: surviving) == order[4])
    }

    @Test func nothingSurvivingLeavesNoReplacement() {
        #expect(FocusAfterRemoval.next(after: order[2], in: order, surviving: []) == nil)
    }

    /// The very first call has no remembered order, so there is nothing to
    /// step to and the caller falls back to the front of the list.
    @Test func anUnknownClipHasNoNeighbour() {
        #expect(FocusAfterRemoval.next(after: UUID(), in: order, surviving: Set(order)) == nil)
        #expect(FocusAfterRemoval.next(after: order[0], in: [], surviving: Set(order)) == nil)
    }
}
