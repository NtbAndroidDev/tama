import Foundation
import Testing
@testable import Droppy

@Suite struct ShakeDetectorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// Feeds alternating deltas; returns the index of the sample that fired, if any.
    private func feed(_ detector: inout ShakeDetector, amplitude: CGFloat, count: Int,
                      spacing: TimeInterval, start: TimeInterval = 0) -> Int? {
        for i in 0..<count {
            let dx = i.isMultiple(of: 2) ? amplitude : -amplitude
            if detector.record(dx: dx, at: t0.addingTimeInterval(start + Double(i) * spacing)) { return i }
        }
        return nil
    }

    @Test func quickShakeFiresOnThirdReversal() {
        var d = ShakeDetector()
        #expect(feed(&d, amplitude: 25, count: 10, spacing: 0.08) == 3)
    }

    @Test func noiseBelowJitterIsIgnored() {
        var d = ShakeDetector()
        #expect(feed(&d, amplitude: 1, count: 50, spacing: 0.02) == nil)
        #expect(d.reversals.isEmpty)
    }

    @Test func tremorShorterThanMinimumTravelNeverFires() {
        // Regression: travel used to accumulate across turns, so this fired.
        var d = ShakeDetector()
        #expect(feed(&d, amplitude: 5, count: 60, spacing: 0.02) == nil)
    }

    @Test func legsBuiltFromSeveralSamplesCount() {
        var d = ShakeDetector()
        let steps: [CGFloat] = [10, 10, -10, -10, 10, 10, -10, -10]
        var fired: Int?
        for (i, dx) in steps.enumerated() where fired == nil {
            if d.record(dx: dx, at: t0.addingTimeInterval(Double(i) * 0.05)) { fired = i }
        }
        #expect(fired == 6)
    }

    @Test func slowSwingsFallOutOfTheWindow() {
        var d = ShakeDetector()
        #expect(feed(&d, amplitude: 40, count: 12, spacing: 0.4) == nil)
    }

    @Test func fireClearsReversalsAndResetForgetsDirection() {
        var d = ShakeDetector()
        #expect(feed(&d, amplitude: 30, count: 4, spacing: 0.05) == 3)
        d.fire(at: t0.addingTimeInterval(0.15))
        #expect(d.reversals.isEmpty)
        d.reset()
        // After reset the first sample only establishes a direction.
        let fired = d.record(dx: -30, at: t0.addingTimeInterval(0.2))
        #expect(!fired)
        #expect(d.reversals.isEmpty)
    }

    @Test func cooldownSuppressesRefire() {
        var d = ShakeDetector()
        d.cooldown = 1
        #expect(feed(&d, amplitude: 30, count: 4, spacing: 0.05) == 3)
        d.fire(at: t0.addingTimeInterval(0.15))
        #expect(feed(&d, amplitude: 30, count: 6, spacing: 0.05, start: 0.2) == nil)
        #expect(feed(&d, amplitude: 30, count: 6, spacing: 0.05, start: 2) != nil)
    }
}
