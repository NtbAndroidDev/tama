import AVFoundation
import Foundation

/// Pomodoro's ambient sound, synthesised live (no bundled recordings):
/// white, pink and brown noise, rain (filtered noise with drops) and waves
/// (brown noise swelling on a slow cycle). Plays while a focus cycle runs.
@MainActor
public final class AmbientSoundService {
    public static let shared = AmbientSoundService()

    public enum Sound: String, CaseIterable, Identifiable, Sendable {
        case brown, pink, white, rain, waves
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .brown: "Brown noise"
            case .pink: "Pink noise"
            case .white: "White noise"
            case .rain: "Rain"
            case .waves: "Ocean waves"
            }
        }

        var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    private var engine: AVAudioEngine?
    private let generator = NoiseGenerator()
    private var stopWork: DispatchWorkItem?
    public private(set) var isPlaying = false

    private init() {}

    /// Starts (or retunes) playback; fades in.
    public func play(_ sound: Sound, volume: Double) {
        stopWork?.cancel()
        stopWork = nil
        generator.setSound(sound.index)
        generator.setTarget(Float(min(max(volume, 0), 1)) * 0.6)
        guard engine == nil else {
            isPlaying = true
            return
        }
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100
        generator.sampleRate = Float(sampleRate)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: mono, renderBlock: Self.renderBlock(for: generator))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        do {
            try engine.start()
            self.engine = engine
            isPlaying = true
        } catch {
            AppState.shared.showNotification(appName: "Pomodoro", title: "Couldn't play ambient sound",
                                             message: error.localizedDescription)
        }
    }

    public func setVolume(_ volume: Double) {
        guard isPlaying else { return }
        generator.setTarget(Float(min(max(volume, 0), 1)) * 0.6)
    }

    /// Fades out, then releases the audio device.
    public func stop() {
        guard engine != nil, stopWork == nil else { return }
        generator.setTarget(0)
        isPlaying = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine?.stop()
            self.engine = nil
            self.stopWork = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Built outside the main actor: the audio thread calls it, and a closure
    /// formed in a @MainActor method would trap there.
    private nonisolated static func renderBlock(for generator: NoiseGenerator) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            generator.render(into: data, count: Int(frameCount))
            if buffers.count > 1 {
                for index in 1..<buffers.count {
                    buffers[index].mData?.assumingMemoryBound(to: Float.self).update(from: data, count: Int(frameCount))
                }
            }
            return noErr
        }
    }
}

/// The DSP state, touched only by the audio thread except for the two
/// atomically-sized settings, which a torn read can't hurt.
final class NoiseGenerator: @unchecked Sendable {
    var sampleRate: Float = 44_100
    private var sound = 0
    private var target: Float = 0
    private var gain: Float = 0

    private var seed: UInt32 = 0x9E37_79B9
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var lowpass: Float = 0
    private var drop: Float = 0
    private var dropDecay: Float = 0.99
    private var phase: Float = 0

    func setSound(_ index: Int) { sound = index }
    func setTarget(_ value: Float) { target = value }

    private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    /// Paul Kellet's refined pink filter.
    private func pink(_ w: Float) -> Float {
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.11
    }

    private func brownNoise(_ w: Float) -> Float {
        brown = (brown + 0.02 * w) / 1.02
        return brown * 3.5
    }

    func render(into data: UnsafeMutablePointer<Float>, count: Int) {
        let rate = max(sampleRate, 8_000)
        let dropChance = 9 / rate
        let waveStep = 1 / (rate * 9)
        for i in 0..<count {
            // Smooth gain changes so starting, stopping and volume never click.
            gain += (target - gain) * 0.0004
            let w = white()
            var sample: Float
            switch sound {
            case 0: sample = brownNoise(w)
            case 1: sample = pink(w)
            case 2: sample = w * 0.3
            case 3:
                // Rain: soft, low-passed pink hiss with random decaying drops.
                let hiss = pink(w)
                lowpass += (hiss - lowpass) * 0.35
                if drop < 0.01, (w + 1) / 2 < dropChance {
                    drop = 0.4 + abs(white()) * 0.6
                    dropDecay = 0.985 + abs(white()) * 0.01
                }
                drop *= dropDecay
                sample = lowpass * 0.9 + white() * drop * 0.35
            default:
                // Waves: brown noise swelling and receding every ~9 s.
                phase += waveStep
                if phase > 1 { phase -= 1 }
                let swell = 0.5 + 0.5 * sin(phase * 2 * .pi)
                sample = brownNoise(w) * (0.25 + 0.75 * swell * swell) + pink(white()) * 0.15 * swell
            }
            data[i] = max(-1, min(1, sample * gain))
        }
    }
}
