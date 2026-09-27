import AppKit
import AVFoundation
import Combine
import CoreGraphics

// MARK: - Key categories

/// All Mechey ever learns about a keystroke: which kind of key it was, and
/// whether it went down or up. The key itself is never read, logged or kept.
public enum MecheyKey: String, CaseIterable, Sendable {
    case letter, space, enter, backspace, modifier

    public var title: String {
        switch self {
        case .letter: "Key"
        case .space: "Space"
        case .enter: "Return"
        case .backspace: "Delete"
        case .modifier: "⌘ ⇧"
        }
    }

    /// Sorted by virtual key code only; everything unlisted counts as a letter key.
    static func from(keyCode: Int64) -> MecheyKey {
        switch keyCode {
        case 49: .space
        case 36, 76: .enter
        case 51, 117: .backspace
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: .modifier
        default: .letter
        }
    }

    /// Flag bit that a modifier key sets while held, to tell press from release
    /// in a flagsChanged event.
    static func modifierMask(keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: .maskCommand
        case 56, 60: .maskShift
        case 58, 61: .maskAlternate
        case 59, 62: .maskControl
        case 63: .maskSecondaryFn
        default: nil
        }
    }
}

// MARK: - Packs

public enum MecheyPack: String, CaseIterable, Identifiable, Sendable {
    case blue, brown, red, typewriter, bubble

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blue: "Blue clicky"
        case .brown: "Brown tactile"
        case .red: "Red linear"
        case .typewriter: "Typewriter"
        case .bubble: "Bubble"
        }
    }

    public var iconName: String {
        switch self {
        case .blue: "bolt.fill"
        case .brown: "hand.tap.fill"
        case .red: "arrow.down.to.line"
        case .typewriter: "doc.plaintext.fill"
        case .bubble: "drop.fill"
        }
    }
}

// MARK: - Synthesis

/// Builds switch sounds from filtered noise and damped sine partials, since no
/// recorded samples ship with Tama. Every key category gets a few takes with
/// slightly different pitch so fast typing doesn't sound like a machine gun.
enum MecheySynth {
    static let sampleRate: Double = 48_000
    static let takes = 4

    struct Partial { let freq: Double; let amp: Double; let decay: Double }

    struct Voice {
        var clickFreq: Double, clickQ: Double, clickDecay: Double, clickGain: Double
        var partials: [Partial]
        var thumpFreq: Double, thumpGain: Double, thumpDecay: Double
        /// Clicky switches snap a second time a few ms after the first.
        var secondClickDelay: Double?
        /// Bubble: a sine sweeping up, like a drop hitting water.
        var sweep: (from: Double, to: Double, decay: Double)?
        var length: Double
    }

    static func voice(_ pack: MecheyPack) -> Voice {
        switch pack {
        case .blue:
            Voice(clickFreq: 4_200, clickQ: 1.4, clickDecay: 0.0035, clickGain: 1.0,
                  partials: [Partial(freq: 2_150, amp: 0.25, decay: 0.012), Partial(freq: 3_400, amp: 0.14, decay: 0.008)],
                  thumpFreq: 190, thumpGain: 0.35, thumpDecay: 0.018, secondClickDelay: 0.006, sweep: nil, length: 0.09)
        case .brown:
            Voice(clickFreq: 2_600, clickQ: 0.9, clickDecay: 0.005, clickGain: 0.75,
                  partials: [Partial(freq: 1_250, amp: 0.30, decay: 0.015), Partial(freq: 2_450, amp: 0.12, decay: 0.010)],
                  thumpFreq: 150, thumpGain: 0.55, thumpDecay: 0.024, secondClickDelay: nil, sweep: nil, length: 0.09)
        case .red:
            Voice(clickFreq: 1_700, clickQ: 0.7, clickDecay: 0.006, clickGain: 0.55,
                  partials: [Partial(freq: 880, amp: 0.30, decay: 0.020), Partial(freq: 1_900, amp: 0.08, decay: 0.010)],
                  thumpFreq: 115, thumpGain: 0.70, thumpDecay: 0.030, secondClickDelay: nil, sweep: nil, length: 0.1)
        case .typewriter:
            Voice(clickFreq: 3_000, clickQ: 0.6, clickDecay: 0.009, clickGain: 1.0,
                  partials: [Partial(freq: 1_650, amp: 0.35, decay: 0.05), Partial(freq: 2_730, amp: 0.25, decay: 0.04), Partial(freq: 4_100, amp: 0.15, decay: 0.03)],
                  thumpFreq: 90, thumpGain: 0.75, thumpDecay: 0.04, secondClickDelay: 0.011, sweep: nil, length: 0.18)
        case .bubble:
            Voice(clickFreq: 5_000, clickQ: 2.0, clickDecay: 0.0015, clickGain: 0.15,
                  partials: [], thumpFreq: 0, thumpGain: 0, thumpDecay: 0.01,
                  secondClickDelay: nil, sweep: (from: 480, to: 1_150, decay: 0.035), length: 0.12)
        }
    }

    /// Every take of every key of a pack, keyed "category.down" / "category.up".
    static func render(_ pack: MecheyPack) -> [String: [[Float]]] {
        var rng = SystemRandomNumberGenerator()
        var bank: [String: [[Float]]] = [:]
        for key in MecheyKey.allCases {
            for down in [true, false] {
                bank[bankKey(key, down: down)] = (0..<takes).map { _ in
                    render(pack, key: key, down: down, rng: &rng)
                }
            }
        }
        return bank
    }

    static func bankKey(_ key: MecheyKey, down: Bool) -> String { "\(key.rawValue).\(down ? "down" : "up")" }

    private static func render(_ pack: MecheyPack, key: MecheyKey, down: Bool, rng: inout SystemRandomNumberGenerator) -> [Float] {
        var v = voice(pack)
        // Bigger keys are lower and longer; modifiers are quieter.
        var pitch: Double
        var gain: Double
        switch key {
        case .letter: pitch = 1.0; gain = 0.8
        case .space: pitch = 0.72; gain = 0.95; v.length *= 1.5
        case .enter: pitch = 0.84; gain = 1.0; v.length *= 1.3
        case .backspace: pitch = 0.93; gain = 0.85
        case .modifier: pitch = 1.06; gain = 0.6
        }
        if !down {
            // Release: the top-out is lighter and a touch higher than the bottom-out.
            pitch *= 1.14
            gain *= pack == .typewriter ? 0.3 : 0.45
            v.thumpGain *= 0.3
            v.length *= 0.7
            if pack != .blue { v.secondClickDelay = nil }
        }
        pitch *= Double.random(in: 0.96...1.04, using: &rng)

        let count = Int(v.length * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var click = Biquad.bandpass(freq: v.clickFreq * pitch, q: v.clickQ, sampleRate: sampleRate)
        var lowNoise = Biquad.bandpass(freq: 420 * pitch, q: 0.8, sampleRate: sampleRate)
        var phases = [Double](repeating: 0, count: v.partials.count)
        var thumpPhase = 0.0
        var sweepPhase = 0.0

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.0004)
            let noise = Double.random(in: -1...1, using: &rng)
            var s = click.process(noise) * exp(-t / v.clickDecay) * v.clickGain * attack * 3
            if let delay = v.secondClickDelay, t >= delay {
                let td = t - delay
                s += click.process(noise * 0.8) * exp(-td / (v.clickDecay * 0.8)) * v.clickGain * 2
            }
            // Space bars rattle: a low, noisy body on top of the click.
            if key == .space { s += lowNoise.process(noise) * exp(-t / 0.03) * 0.9 }
            for (index, partial) in v.partials.enumerated() {
                phases[index] += 2 * .pi * partial.freq * pitch / sampleRate
                s += sin(phases[index]) * partial.amp * exp(-t / partial.decay) * attack
            }
            if v.thumpGain > 0 {
                // The bottom-out drops in pitch as the energy dies, like a real case thud.
                let freq = v.thumpFreq * pitch * (1 + 0.6 * exp(-t / 0.006))
                thumpPhase += 2 * .pi * freq / sampleRate
                s += sin(thumpPhase) * v.thumpGain * exp(-t / v.thumpDecay) * attack
            }
            if let sweep = v.sweep {
                let progress = min(1, t / 0.03)
                let freq = (sweep.from + (sweep.to - sweep.from) * progress) * pitch
                sweepPhase += 2 * .pi * freq / sampleRate
                s += sin(sweepPhase) * exp(-t / sweep.decay) * min(1, t / 0.002)
            }
            out[i] = Float(s)
        }

        if pack == .typewriter, key == .enter, down { addBell(&out, pitch: pitch) }

        // Normalise so packs sit at a similar loudness, then fade the tail to avoid a click.
        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0 {
            let scale = Float(gain * 0.85) / peak
            for i in out.indices { out[i] *= scale }
        }
        let fade = min(count, Int(0.004 * sampleRate))
        for i in 0..<fade { out[count - 1 - i] *= Float(i) / Float(fade) }
        return out
    }

    /// The typewriter's end-of-line bell, rung by Return.
    private static func addBell(_ out: inout [Float], pitch: Double) {
        let extra = Int(0.6 * sampleRate)
        let start = Int(0.02 * sampleRate)
        out.append(contentsOf: [Float](repeating: 0, count: extra))
        for i in 0..<(out.count - start) {
            let t = Double(i) / sampleRate
            let env = exp(-t / 0.25) * min(1, t / 0.001)
            let s = sin(2 * .pi * 2_093 * t) * 0.5 + sin(2 * .pi * 5_230 * t) * 0.18 + sin(2 * .pi * 7_910 * t) * 0.07
            out[start + i] += Float(s * env * 0.3 / max(pitch, 0.5))
        }
    }

    /// RBJ cookbook band-pass (constant 0 dB peak gain).
    struct Biquad {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        static func bandpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
            let w = 2 * .pi * min(freq, sampleRate * 0.45) / sampleRate
            let alpha = sin(w) / (2 * q)
            let a0 = 1 + alpha
            var f = Biquad()
            f.b0 = alpha / a0
            f.b1 = 0
            f.b2 = -alpha / a0
            f.a1 = -2 * cos(w) / a0
            f.a2 = (1 - alpha) / a0
            return f
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}

// MARK: - Player

/// A small AVAudioEngine with a pool of player nodes, so overlapping keys ring
/// together and a keystroke is heard within one IO buffer. Called from the
/// event tap thread and the main thread, hence the lock.
final class MecheyPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [String: [AVAudioPCMBuffer]] = [:]
    private var nextNode = 0
    private let lock = NSLock()
    private let format = AVAudioFormat(standardFormatWithSampleRate: MecheySynth.sampleRate, channels: 1)!
    private var configObserver: NSObjectProtocol?

    /// Set from the main thread; read on every keystroke.
    var volume: Float = 0.6 {
        didSet { lock.withLock { engine.mainMixerNode.outputVolume = volume } }
    }
    var isSuppressed = false

    init() {
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
        }
        engine.mainMixerNode.outputVolume = volume
        // A new output device stops the engine; bring it back on the new one.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                guard self.wantsRunning else { return }
                self.startLocked()
            }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    private var wantsRunning = false

    func load(_ bank: [String: [[Float]]]) {
        var built: [String: [AVAudioPCMBuffer]] = [:]
        for (key, takes) in bank {
            built[key] = takes.compactMap { samples in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                      let channel = buffer.floatChannelData?[0] else { return nil }
                samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                return buffer
            }
        }
        lock.withLock { buffers = built }
    }

    func start() {
        lock.withLock {
            wantsRunning = true
            startLocked()
        }
    }

    func stop() {
        lock.withLock {
            wantsRunning = false
            nodes.forEach { $0.stop() }
            engine.stop()
        }
    }

    private func startLocked() {
        if !engine.isRunning {
            engine.prepare()
            shortenIOBuffer()
            do { try engine.start() } catch { return }
        }
        for node in nodes where !node.isPlaying { node.play() }
    }

    /// The default 512-frame buffer adds ~11 ms; 128 frames keeps keys tight.
    private func shortenIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 128
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    func play(_ key: MecheyKey, down: Bool) {
        guard !isSuppressed else { return }
        lock.withLock {
            guard wantsRunning, engine.isRunning,
                  let takes = buffers[MecheySynth.bankKey(key, down: down)], !takes.isEmpty else { return }
            let node = nodes[nextNode]
            nextNode = (nextNode + 1) % nodes.count
            // Slight level variation on top of the pitch variation baked into the takes.
            node.volume = Float.random(in: 0.82...1.0)
            node.scheduleBuffer(takes.randomElement()!, at: nil, options: .interrupts, completionHandler: nil)
            if !node.isPlaying { node.play() }
        }
    }
}

// MARK: - Event tap

/// A listen-only keyboard tap on its own thread and run loop, so key sounds
/// never wait on the main thread. It only reads the key code and the down / up
/// direction of each event.
final class MecheyKeyTap: @unchecked Sendable {
    private let player: MecheyPlayer
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(player: MecheyPlayer) { self.player = player }

    /// Returns false when macOS refuses the tap (Input Monitoring not granted).
    func start() -> Bool {
        guard thread == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var created = false
        let thread = Thread { [self] in
            let mask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: CGEventMask(mask), callback: mecheyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self.port = port
            self.runLoop = loop
            created = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Tama Mechey tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if created { self.thread = thread }
        return created
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        port = nil
        runLoop = nil
        thread = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            player.play(.from(keyCode: event.getIntegerValueField(.keyboardEventKeycode)), down: true)
        case .keyUp:
            player.play(.from(keyCode: event.getIntegerValueField(.keyboardEventKeycode)), down: false)
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard MecheyKey.from(keyCode: code) == .modifier else { return }
            // Caps Lock toggles its flag on every press, so it always counts as a press.
            let down = MecheyKey.modifierMask(keyCode: code).map { event.flags.contains($0) } ?? true
            player.play(.modifier, down: down)
        default:
            break
        }
    }
}

private func mecheyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<MecheyKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - Service

/// Mechey: switch sounds for every keystroke. Listens only while the Droplet is
/// enabled and its switch is on, and needs Input Monitoring to see keys at all.
@MainActor
public final class MecheyService: ObservableObject {
    public static let shared = MecheyService()

    /// UserDefaults keys, shared with the console's @AppStorage.
    public enum Keys {
        public static let isOn = "mecheyOn"
        public static let pack = "mecheyPack"
        public static let volume = "mecheyVolume"
        public static let muteWhilePlaying = "mecheyMuteWhileMediaPlays"

        public static let all = [isOn, pack, volume, muteWhilePlaying]
    }

    @Published public private(set) var hasPermission = CGPreflightListenEventAccess()
    @Published public private(set) var isListening = false
    /// True while the switch sounds for a newly picked pack are being built.
    @Published public private(set) var isRendering = false

    private let player = MecheyPlayer()
    private lazy var tap = MecheyKeyTap(player: player)
    private var loadedPack: MecheyPack?
    private var isPreviewing = false
    private var previewStop: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Called once at launch; from then on the tap follows the settings.
    public func start() {
        guard !started else { return }
        started = true
        UserDefaults.standard.register(defaults: [Keys.volume: 0.6, Keys.pack: MecheyPack.brown.rawValue])
        AppState.shared.$droplets
            .map { $0.first(where: { $0.id == "mechey" })?.isEnabled ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        MediaService.shared.$currentTrack
            .map(\.isPlaying)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyMediaMute() }
            .store(in: &cancellables)
        apply()
    }

    private var defaults: UserDefaults { .standard }
    private var isDropletEnabled: Bool {
        AppState.shared.droplets.first(where: { $0.id == "mechey" })?.isEnabled ?? false
    }
    private var pack: MecheyPack { MecheyPack(rawValue: defaults.string(forKey: Keys.pack) ?? "") ?? .brown }

    public func refreshPermission() {
        let granted = CGPreflightListenEventAccess()
        if granted != hasPermission { hasPermission = granted }
        apply()
    }

    /// Shows the macOS prompt the first time; after that only System Settings can grant it.
    public func requestPermission() {
        if !CGRequestListenEventAccess() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
        refreshPermission()
    }

    /// Plays a key through the current pack, even while listening is off.
    public func preview(_ key: MecheyKey, down: Bool) {
        ensurePackLoaded()
        if !isListening {
            isPreviewing = true
            player.start()
            // Stop the engine again once the preview pad goes quiet.
            previewStop?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isListening else { return }
                self.isPreviewing = false
                self.player.stop()
            }
            previewStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
        player.play(key, down: down)
    }

    private func apply() {
        player.volume = Float(defaults.object(forKey: Keys.volume) as? Double ?? 0.6)
        applyMediaMute()
        ensurePackLoaded()
        let wanted = started && isDropletEnabled && defaults.bool(forKey: Keys.isOn)
        if wanted, !isListening {
            hasPermission = CGPreflightListenEventAccess()
            guard hasPermission else { return }
            player.start()
            if tap.start() {
                isListening = true
            } else {
                // Preflight can say yes for a stale grant; the tap is the real answer.
                hasPermission = false
                if !isPreviewing { player.stop() }
            }
        } else if !wanted, isListening {
            tap.stop()
            isListening = false
            if !isPreviewing { player.stop() }
        }
    }

    private func applyMediaMute() {
        player.isSuppressed = defaults.bool(forKey: Keys.muteWhilePlaying) && MediaService.shared.isPlaying
    }

    private func ensurePackLoaded() {
        let pack = pack
        guard loadedPack != pack else { return }
        loadedPack = pack
        isRendering = true
        let player = player
        Task.detached(priority: .userInitiated) {
            let bank = MecheySynth.render(pack)
            player.load(bank)
            await MainActor.run { MecheyService.shared.isRendering = false }
        }
    }

    /// Releases the tap on quit so the run loop thread doesn't outlive the app's state.
    public func shutdown() {
        tap.stop()
        player.stop()
        isListening = false
    }
}
