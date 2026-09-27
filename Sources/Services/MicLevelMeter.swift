import AVFoundation
import Combine

/// The default microphone's level, for the call HUD's bars. It listens only
/// during a call, only with Microphone access already given (it never asks
/// in the middle of a call), and keeps nothing: each buffer becomes one
/// number and is dropped.
@MainActor
final class MicLevelMeter: ObservableObject {
    static let shared = MicLevelMeter()

    /// Recent levels, 0…1, newest last.
    @Published private(set) var history: [Double] = Array(repeating: 0, count: 12)
    /// Bumped with every sample so the bars animate.
    @Published private(set) var tick = 0
    @Published private(set) var isRunning = false

    private var engine: AVAudioEngine?
    private var timer: Timer?
    private let latest = LevelBox()

    private init() {}

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    func start() {
        guard !isRunning, Self.isAuthorized else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        // Built outside the main actor: the tap runs on the audio thread.
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(latest))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        self.engine = engine
        isRunning = true
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { _ in
            MainActor.assumeIsolated { MicLevelMeter.shared.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        history = Array(repeating: 0, count: history.count)
        tick &+= 1
    }

    nonisolated private static func makeTap(_ box: LevelBox) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            let rms = (sum / Float(count)).squareRoot()
            // -50 dB … -10 dB onto 0…1.
            let decibels = 20 * log10(max(rms, 0.000_01))
            box.set(Double(min(max((decibels + 50) / 40, 0), 1)))
        }
    }

    private func sample() {
        let value = latest.get()
        // Fall slower than rise, like a VU meter.
        let smoothed = max(value, (history.last ?? 0) * 0.7)
        history.removeFirst()
        history.append(smoothed)
        tick &+= 1
    }

    /// A bar's level: bars read different moments of the recent history, so
    /// they ripple instead of moving as one block.
    func level(bar index: Int, of count: Int) -> Double {
        guard isRunning, !history.isEmpty else { return 0 }
        let offset = abs(index - count / 2)
        let position = max(history.count - 1 - offset, 0)
        return history[position]
    }
}

private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0

    func set(_ next: Double) {
        lock.lock()
        value = next
        lock.unlock()
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
