import Testing
@testable import Droppy

/// The volume keys Tama takes over must land where the macOS keys would.
struct VolumeStepTests {
    private let step = MediaKeyMonitor.coarseStep

    @Test func stepsOnTheSixteenthsGrid() {
        #expect(MediaKeyMonitor.steppedVolume(0.5, by: step, step: step) == 0.5625)
        #expect(MediaKeyMonitor.steppedVolume(0.5, by: -step, step: step) == 0.4375)
    }

    @Test func snapsALevelSetElsewhereFirst() {
        // 37% sits nearest 6/16, so one press up is 7/16.
        #expect(MediaKeyMonitor.steppedVolume(0.37, by: step, step: step) == 7.0 / 16)
    }

    @Test func clampsAtTheEnds() {
        #expect(MediaKeyMonitor.steppedVolume(1, by: step, step: step) == 1)
        #expect(MediaKeyMonitor.steppedVolume(0.02, by: -step, step: step) == 0)
    }

    @Test func fineStepsAreQuarters() {
        let fine = MediaKeyMonitor.fineStep
        #expect(MediaKeyMonitor.steppedVolume(0.5, by: fine, step: fine) == 0.515625)
    }
}
