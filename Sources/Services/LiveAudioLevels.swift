import AppKit
import Combine
import AudioToolbox
import CoreAudio

/// Settings › HUDs › Live audio visualizer: the music bars follow what is
/// actually playing. A Core Audio process tap on the whole system output
/// (macOS 14.2+, unmuted, so nothing changes in what you hear) is split into
/// four bands — bass, low-mid, high-mid, treble — with one-pole filters on the
/// audio thread; the main thread samples them 30 times a second and hands
/// the levels to the bars on screen.
///
/// The tap runs only while the setting is on and a playing visualizer is on
/// screen. When macOS won't allow the capture (no audio-capture permission,
/// or an older macOS) or the tap delivers nothing but silence while music
/// plays, the bars fall back to their simulated animation.
@MainActor
final class LiveAudioLevels: ObservableObject {
    static let shared = LiveAudioLevels()

    /// Smoothed band levels, 0…1: bass, low-mid, high-mid, treble.
    private(set) var bands: [CGFloat] = [0, 0, 0, 0]
    /// Real sound has arrived recently; otherwise the bars simulate.
    private(set) var isReceiving = false
    /// Creating the tap failed; don't retry until the setting is switched again.
    @Published private(set) var didFail = false

    private let subscribers = NSHashTable<WaveBarsView>.weakObjects()
    /// `SystemAudioTap` on 14.2+, typed loosely so this builds on 14.0.
    private var tap: AnyObject?
    private var timer: Timer?
    private var silentTicks = 0
    private var outputWatch: AnyCancellable?

    private init() {
        // The listening device is built on the output of the moment; follow a
        // switch to AirPods or a display.
        outputWatch = AudioOutputService.shared.$currentDeviceID
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    let levels = LiveAudioLevels.shared
                    guard levels.tap != nil else { return }
                    levels.stop()
                    levels.sync()
                }
            }
    }

    func subscribe(_ view: WaveBarsView) {
        subscribers.add(view)
        sync()
    }

    func unsubscribe(_ view: WaveBarsView) {
        subscribers.remove(view)
        sync()
    }

    /// Starts or stops the tap to match the setting and what's on screen.
    func sync() {
        let enabled = AppState.shared.liveAudioVisualizer
        if !enabled { didFail = false }
        let wanted = enabled && subscribers.count > 0 && !didFail
        if wanted, tap == nil {
            start()
        } else if !wanted, tap != nil || timer != nil {
            stop()
        }
    }

    private func start() {
        guard #available(macOS 14.2, *) else {
            didFail = true
            return
        }
        do {
            tap = try SystemAudioTap()
        } catch {
            didFail = true
            isReceiving = false
            notifySubscribers()
            return
        }
        silentTicks = 0
        let tick = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { LiveAudioLevels.shared.tick() }
        }
        tick.tolerance = 0.005
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.invalidate() }
        tap = nil
        isReceiving = false
        bands = [0, 0, 0, 0]
    }

    /// Band boosts: higher bands carry far less energy than the bass.
    private static let gains: [Float] = [1.0, 1.8, 3.2, 5.5]

    private func tick() {
        guard #available(macOS 14.2, *), let tap = tap as? SystemAudioTap else { return }
        let (rms, frames) = tap.take()
        if frames == 0 || rms.allSatisfy({ $0 < 0.000_01 }) {
            silentTicks += 1
        } else {
            silentTicks = 0
        }
        // ~2 s of pure digital silence while something "plays": no real feed.
        let receiving = silentTicks < 60
        for index in bands.indices {
            let level: CGFloat
            if frames == 0 {
                level = 0
            } else {
                let db = 20 * log10(max(rms[index] * Self.gains[index], 0.000_001))
                level = CGFloat(min(max((db + 54) / 48, 0), 1))
            }
            // Fast attack, slower release, like a VU meter.
            let previous = bands[index]
            bands[index] = level > previous ? previous + (level - previous) * 0.7 : previous + (level - previous) * 0.25
        }
        if receiving != isReceiving {
            isReceiving = receiving
        }
        notifySubscribers()
    }

    private func notifySubscribers() {
        for view in subscribers.allObjects { view.applyLiveLevels() }
    }

    /// The level for bar `index` of `count`, spread across the four bands
    /// with a little per-bar variation so neighbours don't move in lockstep.
    func level(bar index: Int, of count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let position = CGFloat(index) / CGFloat(max(count - 1, 1)) * CGFloat(bands.count - 1)
        let low = Int(position.rounded(.down))
        let high = min(low + 1, bands.count - 1)
        let t = position - CGFloat(low)
        let mixed = bands[low] * (1 - t) + bands[high] * t
        let wobble: [CGFloat] = [1.0, 0.86, 1.08, 0.93, 1.04, 0.9, 1.1]
        return min(mixed * wobble[index % wobble.count], 1)
    }
}

// MARK: - The tap

/// Values shared with the real-time IOProc: plain pointers, allocated once,
/// so the audio thread never locks, allocates or retains.
struct SystemAudioTapShared: @unchecked Sendable {
    /// Sum of squares per band since the last read, then the frame count.
    let sums: UnsafeMutablePointer<Float>
    let frames: UnsafeMutablePointer<Float>
    /// Filter memory: three one-pole low-passes.
    let filters: UnsafeMutablePointer<Float>

    init() {
        sums = .allocate(capacity: 4); sums.initialize(repeating: 0, count: 4)
        frames = .allocate(capacity: 1); frames.initialize(to: 0)
        filters = .allocate(capacity: 3); filters.initialize(repeating: 0, count: 3)
    }

    func deallocate() {
        sums.deallocate(); frames.deallocate(); filters.deallocate()
    }
}

/// An unmuted tap on everything the Mac plays, read through a private
/// aggregate device whose output is left silent.
@available(macOS 14.2, *)
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let shared = SystemAudioTapShared()
    private var invalidated = false

    init() throws {
        do {
            try build()
        } catch {
            invalidate()
            throw error
        }
    }

    private func build() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Tama – Visualizer"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AppAudioTapError.status("Creating the tap", status) }

        guard let outputUID = Self.defaultOutputUID() else { throw AppAudioTapError.noOutput }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tama Visualizer",
            kAudioAggregateDeviceUIDKey: "app.tama.visualizer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID)
        guard status == noErr else { throw AppAudioTapError.status("Creating the listening device", status) }
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, Self.makeIOBlock(shared))
        guard status == noErr else { throw AppAudioTapError.status("Listening", status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw AppAudioTapError.status("Listening", status) }
    }

    /// Per-band RMS since the last call, and how many frames it covers.
    func take() -> (rms: [Float], frames: Int) {
        let frames = shared.frames.pointee
        var rms = [Float](repeating: 0, count: 4)
        if frames > 0 {
            for index in 0..<4 { rms[index] = (shared.sums[index] / frames).squareRoot() }
        }
        for index in 0..<4 { shared.sums[index] = 0 }
        shared.frames.pointee = 0
        return (rms, Int(frames))
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                // Synchronous: the IOProc has returned before the pointers go.
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        shared.deallocate()
    }

    deinit { invalidate() }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let string = uid?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    /// Built outside any actor so the block carries no isolation check onto the audio thread.
    private nonisolated static func makeIOBlock(_ shared: SystemAudioTapShared) -> AudioDeviceIOBlock {
        // Cut-offs of ~200 Hz, ~1 kHz and ~4 kHz at 48 kHz.
        let a1: Float = 0.026, a2: Float = 0.123, a3: Float = 0.41
        return { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            var lp1 = shared.filters[0], lp2 = shared.filters[1], lp3 = shared.filters[2]
            var s0 = shared.sums[0], s1 = shared.sums[1], s2 = shared.sums[2], s3 = shared.sums[3]
            var counted: Float = 0
            // Only the first buffer: the tap is a stereo mixdown, interleaved or not.
            if let buffer = input.first, let data = buffer.mData, buffer.mNumberChannels > 0 {
                let channels = Int(buffer.mNumberChannels)
                let samples = data.assumingMemoryBound(to: Float.self)
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                for frame in 0..<frames {
                    var mono: Float = 0
                    for channel in 0..<min(channels, 2) { mono += samples[frame * channels + channel] }
                    mono /= Float(min(channels, 2))
                    lp1 += a1 * (mono - lp1)
                    lp2 += a2 * (mono - lp2)
                    lp3 += a3 * (mono - lp3)
                    let b0 = lp1, b1 = lp2 - lp1, b2 = lp3 - lp2, b3 = mono - lp3
                    s0 += b0 * b0; s1 += b1 * b1; s2 += b2 * b2; s3 += b3 * b3
                }
                counted = Float(frames)
            }
            shared.filters[0] = lp1; shared.filters[1] = lp2; shared.filters[2] = lp3
            shared.sums[0] = s0; shared.sums[1] = s1; shared.sums[2] = s2; shared.sums[3] = s3
            shared.frames.pointee += counted
            // Leave the real output silent: the sound already plays untouched.
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in output {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
    }
}
