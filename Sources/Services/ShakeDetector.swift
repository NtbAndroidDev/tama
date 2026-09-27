import CoreGraphics
import Foundation

/// Pure side-to-side shake recognizer fed with horizontal pointer deltas.
/// Kept free of AppKit so the thresholds can be unit tested.
struct ShakeDetector: Sendable {
    /// Deltas this small are sensor noise and never count as movement.
    var jitter: CGFloat = 1
    /// Distance a leg must cover in one direction before turning counts as a
    /// reversal, so trembling hands don't read as a shake.
    var minimumTravel: CGFloat = 18
    /// Reversals older than this are forgotten.
    var window: TimeInterval = 0.7
    var requiredReversals = 3
    /// Quiet period after a shake fires.
    var cooldown: TimeInterval = 0

    private(set) var reversals: [Date] = []
    private var lastDirection: CGFloat = 0
    private var travel: CGFloat = 0
    private var cooldownUntil: Date?

    mutating func reset() {
        reversals.removeAll()
        lastDirection = 0
        travel = 0
    }

    /// Feeds one sample; true when enough quick reversals have piled up.
    /// The caller decides whether to act and then calls `fire(at:)`.
    mutating func record(dx: CGFloat, at now: Date) -> Bool {
        guard abs(dx) > jitter else { return false }
        let direction: CGFloat = dx > 0 ? 1 : -1
        if lastDirection != 0, direction != lastDirection {
            // Only a full leg counts. Travel used to carry over across turns,
            // so a 5-pt tremor added up to "reversals" and opened the Basket.
            if travel > minimumTravel { reversals.append(now) }
            travel = abs(dx)
        } else {
            travel += abs(dx)
        }
        lastDirection = direction
        reversals.removeAll { now.timeIntervalSince($0) > window }
        if let cooldownUntil, now < cooldownUntil { return false }
        return reversals.count >= requiredReversals
    }

    mutating func fire(at now: Date) {
        reversals.removeAll()
        cooldownUntil = cooldown > 0 ? now.addingTimeInterval(cooldown) : nil
    }
}
