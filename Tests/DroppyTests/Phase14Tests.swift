import AppKit
import Foundation
import Testing
@testable import Droppy

/// Finder icons are asked for while drawing — a Tray tile, a Basket row, a
/// folder-browser line — so the same path must never cost a second trip into
/// LaunchServices.
@MainActor
@Suite struct FileIconCacheTests {
    @Test func theSamePathHandsBackTheSameImage() {
        let first = FileIcon.image(for: "/Applications")
        let second = FileIcon.image(for: "/Applications")
        #expect(first === second)
    }

    /// Keyed by path, not by type: a custom icon somebody set in Finder stays
    /// on the one file that has it.
    @Test func differentPathsAreCachedApart() {
        let folder = FileIcon.image(for: "/Applications")
        let system = FileIcon.image(for: "/System")
        #expect(folder !== system)
    }

    @Test func aURLAndItsPathAgree() {
        let byPath = FileIcon.image(for: "/Library")
        let byURL = FileIcon.image(for: URL(fileURLWithPath: "/Library"))
        #expect(byPath === byURL)
    }
}

/// The LocalSend console's summary is redrawn on every progress tick of a
/// transfer, so what the staged files add up to is worked out when they are
/// picked rather than while drawing.
@MainActor
@Suite struct StagedBytesTests {
    @Test func stagingFilesAddsUpTheirSizes() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("droppy-staged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let small = dir.appendingPathComponent("small.bin")
        let large = dir.appendingPathComponent("large.bin")
        try Data(count: 128).write(to: small)
        try Data(count: 1024).write(to: large)

        let service = LocalSendService.shared
        let previous = service.staged
        defer { service.staged = previous }

        service.staged = [small, large]
        #expect(service.stagedBytes == 1152)

        service.staged = []
        #expect(service.stagedBytes == 0)
    }

    /// Setting the same list again must not make it recount.
    @Test func restagingTheSameFilesLeavesTheTotalAlone() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("droppy-staged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("one.bin")
        try Data(count: 512).write(to: file)

        let service = LocalSendService.shared
        let previous = service.staged
        defer { service.staged = previous }

        service.staged = [file]
        #expect(service.stagedBytes == 512)
        // The file grows, but nothing restaged it: the total is the one taken
        // when it was picked.
        try Data(count: 2048).write(to: file)
        service.staged = [file]
        #expect(service.stagedBytes == 512)
    }
}

/// Sleep and screen-off arrive as separate notifications and overlap, so the
/// last one to end is the one that wakes the pollers.
@Suite struct DormancyReasonsTests {
    @Test func oneReasonIsEnoughAndEndingItIsEnough() {
        var reasons = DormancyReasons()
        #expect(!reasons.isDormant)
        reasons.set(true, reason: .displaySleep)
        #expect(reasons.isDormant)
        reasons.set(false, reason: .displaySleep)
        #expect(!reasons.isDormant)
    }

    /// Closing a lid sends both, and they are not answered in a fixed order:
    /// the screen waking must not restart the pollers while the Mac is still
    /// on its way into sleep.
    @Test func overlappingReasonsHoldUntilTheLastOneEnds() {
        var reasons = DormancyReasons()
        reasons.set(true, reason: .displaySleep)
        reasons.set(true, reason: .systemSleep)
        reasons.set(false, reason: .displaySleep)
        #expect(reasons.isDormant)
        reasons.set(false, reason: .systemSleep)
        #expect(!reasons.isDormant)
    }

    /// The same notification twice must not need two answers to clear.
    @Test func repeatingAReasonIsNotCounted() {
        var reasons = DormancyReasons()
        reasons.set(true, reason: .systemSleep)
        reasons.set(true, reason: .systemSleep)
        reasons.set(false, reason: .systemSleep)
        #expect(!reasons.isDormant)
    }
}

/// The Basket's auto-hide countdown used to be started at launch and left
/// running for the life of the process — two wake-ups a second, for ever, to
/// find there was nothing to hide.
@MainActor
@Suite struct BasketAutoHideWatchTests {
    @Test func theCountdownOnlyRunsWhileABasketIsOut() {
        let state = AppState.shared
        let autoHide = state.basketAutoHide
        let visible = state.isBasketVisible
        defer {
            state.basketAutoHide = autoHide
            state.isBasketVisible = visible
            JiggleService.shared.syncIdleWatch()
        }

        state.basketAutoHide = false
        state.isBasketVisible = false
        JiggleService.shared.syncIdleWatch()
        #expect(!JiggleService.shared.isWatchingIdle)

        // The setting on its own isn't enough: there has to be a Basket.
        state.basketAutoHide = true
        JiggleService.shared.syncIdleWatch()
        #expect(!JiggleService.shared.isWatchingIdle)

        state.isBasketVisible = true
        JiggleService.shared.syncIdleWatch()
        #expect(JiggleService.shared.isWatchingIdle)

        // And switching auto-hide off while it's out disarms it again.
        state.basketAutoHide = false
        JiggleService.shared.syncIdleWatch()
        #expect(!JiggleService.shared.isWatchingIdle)
    }
}
