import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Darwin

/// One app that is (or recently was) playing sound. Helper processes — a
/// browser's audio service, an Electron renderer — are folded into their app.
public struct AppAudioEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleURL: URL?
    public let pid: pid_t
    public var isPlaying: Bool
    /// CoreAudio process objects that make up this app's sound.
    var processObjects: [AudioObjectID]

    @MainActor public var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon { return icon }
        if let bundleURL { return NSWorkspace.shared.icon(forFile: bundleURL.path) }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// Per-app volume. Apps playing sound are found through CoreAudio's process
/// objects; an app turned away from 100% gets a Core Audio process tap that
/// mutes its normal output and replays it, scaled, through a private aggregate
/// device. Needs macOS 14.2 for process taps.
@MainActor
public final class AppAudioService: ObservableObject {
    public static let shared = AppAudioService()

    @Published public private(set) var apps: [AppAudioEntry] = []
    /// 0…1.5 per app id; missing means 100%.
    @Published public private(set) var gains: [String: Double] = [:]
    @Published public private(set) var muted: Set<String> = []
    /// Input level per tapped app, 0…1, for the activity meter.
    @Published public private(set) var levels: [String: Double] = [:]
    /// Set when macOS won't let Tama capture app audio.
    @Published public private(set) var captureError: String?

    public static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    private var started = false
    private var listObserved = false
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    /// Taps are `AppAudioTap` on 14.2+; typed loosely so this class builds on 14.0.
    private var taps: [String: AnyObject] = [:]
    private var tappedProcesses: [String: [AudioObjectID]] = [:]
    private var silenceTicks: [String: Int] = [:]
    private var meterTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private static let gainsKey = "audioControlGains"
    private static let mutedKey = "audioControlMuted"

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: Self.gainsKey) as? [String: Double] { gains = saved }
        muted = Set(defaults.stringArray(forKey: Self.mutedKey) ?? [])
    }

    /// Begins following the apps playing sound and applies saved volumes.
    /// Only while the Droplet is enabled: turning it off hands every app its sound back.
    public func start() {
        guard !started, Self.isSupported else { return }
        started = true
        AppState.shared.$droplets
            .map { $0.first(where: { $0.id == "audioControl" })?.isEnabled ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.refresh() } else { self.removeAllTaps() }
            }
            .store(in: &cancellables)
        observeSystem()
        refresh()
    }

    private var isEnabled: Bool {
        AppState.shared.droplets.first(where: { $0.id == "audioControl" })?.isEnabled ?? false
    }

    // MARK: Controls

    public func gain(for id: String) -> Double { gains[id] ?? 1 }
    public func isMuted(_ id: String) -> Bool { muted.contains(id) }

    public func setGain(_ value: Double, for id: String) {
        let clamped = min(max(value, 0), 1.5)
        // Snap near 100% so the tap can be removed and the app plays untouched.
        gains[id] = abs(clamped - 1) < 0.02 ? nil : clamped
        persist()
        apply(id)
    }

    public func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        persist()
        apply(id)
    }

    public func resetAll() {
        gains.removeAll()
        muted.removeAll()
        captureError = nil
        persist()
        removeAllTaps()
    }

    /// Re-reads the saved per-app volumes after Reset to Defaults or Import
    /// Settings, then rebuilds the taps so what you hear matches the list.
    public func reloadFromDefaults() {
        let defaults = UserDefaults.standard
        gains = defaults.dictionary(forKey: Self.gainsKey) as? [String: Double] ?? [:]
        muted = Set(defaults.stringArray(forKey: Self.mutedKey) ?? [])
        removeAllTaps()
        refresh()
    }

    /// Clears the capture error so the next change tries the tap again.
    public func retryCapture() {
        captureError = nil
        refresh()
    }

    private func persist() {
        UserDefaults.standard.set(gains, forKey: Self.gainsKey)
        UserDefaults.standard.set(Array(muted), forKey: Self.mutedKey)
    }

    // MARK: Process list

    private func observeSystem() {
        guard #available(macOS 14.2, *), !listObserved else { return }
        listObserved = true
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in
                MainActor.assumeIsolated {
                    let service = AppAudioService.shared
                    if selector == kAudioHardwarePropertyDefaultOutputDevice { service.rebuildAllTaps() }
                    service.refresh()
                }
            }
        }
    }

    public func refresh() {
        guard #available(macOS 14.2, *) else { return }
        // With the Droplet off nothing is listed or tapped, so don't walk every
        // audio process (and hear every app's play/pause) for nobody; turning
        // it back on refreshes from the droplet watch in `start()`.
        guard isEnabled else {
            watchRunningState([])
            removeAllTaps()
            if !apps.isEmpty { apps = [] }
            return
        }
        let objects = CA.objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        watchRunningState(objects)

        let own = getpid()
        var grouped: [String: AppAudioEntry] = [:]
        var order: [String] = []
        for object in objects {
            let pid: pid_t = CA.value(object, kAudioProcessPropertyPID) ?? -1
            guard pid > 0, pid != own else { continue }
            let running = (CA.value(object, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0
            let bundleID = CA.string(object, kAudioProcessPropertyBundleID)
            let owner = Self.owner(pid: pid, bundleID: bundleID)
            if var entry = grouped[owner.id] {
                entry.processObjects.append(object)
                entry.isPlaying = entry.isPlaying || running
                grouped[owner.id] = entry
            } else {
                grouped[owner.id] = AppAudioEntry(
                    id: owner.id, name: owner.name, bundleURL: owner.url, pid: owner.pid,
                    isPlaying: running, processObjects: [object]
                )
                order.append(owner.id)
            }
        }

        // Paused apps with a custom volume stay listed so they can be put back.
        apps = order.compactMap { grouped[$0] }
            .filter { $0.isPlaying || gains[$0.id] != nil || muted.contains($0.id) }
            .sorted { ($0.isPlaying ? 0 : 1, $0.name.localizedLowercase) < ($1.isPlaying ? 0 : 1, $1.name.localizedLowercase) }

        // Taps whose app quit go away; the rest follow the app's current processes.
        for id in taps.keys where grouped[id] == nil { removeTap(id) }
        for id in grouped.keys { apply(id, processes: grouped[id]?.processObjects) }
    }

    /// Listens to each process's "is playing" flag so the activity dots stay live.
    private func watchRunningState(_ objects: [AudioObjectID]) {
        let current = Set(objects)
        for (object, block) in processListeners where !current.contains(object) {
            var address = CA.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
            processListeners[object] = nil
        }
        for object in objects where processListeners[object] == nil {
            var address = CA.address(kAudioProcessPropertyIsRunningOutput)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { AppAudioService.shared.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
                processListeners[object] = block
            }
        }
    }

    /// Which app a process belongs to: itself when it's a regular app, else the
    /// app whose bundle ID prefixes it or that launched it.
    private static func owner(pid: pid_t, bundleID: String?) -> (id: String, name: String, url: URL?, pid: pid_t) {
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        func describe(_ app: NSRunningApplication) -> (String, String, URL?, pid_t) {
            (app.bundleIdentifier ?? "pid.\(app.processIdentifier)", app.localizedName ?? app.bundleIdentifier ?? "App",
             app.bundleURL, app.processIdentifier)
        }
        if let app = regular.first(where: { $0.processIdentifier == pid }) { return describe(app) }
        // Walk up the parent chain: Chrome's and Electron's audio helpers are children of the app.
        var parent = parentPID(pid)
        var hops = 0
        while parent > 1, hops < 6 {
            if let app = regular.first(where: { $0.processIdentifier == parent }) { return describe(app) }
            parent = parentPID(parent)
            hops += 1
        }
        if let bundleID {
            let match = regular
                .filter { app in app.bundleIdentifier.map { bundleID.hasPrefix($0 + ".") || bundleID == $0 } ?? false }
                .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
            if let match { return describe(match) }
            // WebKit's shared media process plays for Safari and other WebKit apps.
            if bundleID.hasPrefix("com.apple.WebKit"),
               let safari = regular.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
                return describe(safari)
            }
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let name = app?.localizedName ?? bundleID?.components(separatedBy: ".").last ?? "Process \(pid)"
        return (bundleID ?? "pid.\(pid)", name, app?.bundleURL, pid)
    }

    private static func parentPID(_ pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    // MARK: Taps

    private func targetGain(_ id: String) -> Float {
        muted.contains(id) ? 0 : Float(gains[id] ?? 1)
    }

    /// Creates, updates or removes the tap for an app to match its setting.
    private func apply(_ id: String, processes: [AudioObjectID]? = nil) {
        guard #available(macOS 14.2, *) else { return }
        let gain = targetGain(id)
        let needsTap = isEnabled && gain != 1
        let processes = processes ?? apps.first(where: { $0.id == id })?.processObjects ?? tappedProcesses[id] ?? []
        guard needsTap, !processes.isEmpty else { return removeTap(id) }

        if let tap = taps[id] as? AppAudioTap, Set(tappedProcesses[id] ?? []) == Set(processes) {
            tap.gain = gain
            return
        }
        // A capture failure was already reported; don't mute apps again until retried.
        guard captureError == nil else { return }
        removeTap(id)
        do {
            let name = apps.first(where: { $0.id == id })?.name ?? id
            let tap = try AppAudioTap(processes: processes, name: name, gain: gain)
            taps[id] = tap
            tappedProcesses[id] = processes
            silenceTicks[id] = 0
            startMeter()
        } catch {
            captureError = "Couldn't take over \(apps.first(where: { $0.id == id })?.name ?? "this app")'s sound (\(error.localizedDescription))."
        }
    }

    private func removeTap(_ id: String) {
        guard let tap = taps.removeValue(forKey: id) else { return }
        if #available(macOS 14.2, *) { (tap as? AppAudioTap)?.invalidate() }
        tappedProcesses[id] = nil
        silenceTicks[id] = nil
        levels[id] = nil
        if taps.isEmpty { stopMeter() }
    }

    private func removeAllTaps() {
        for id in Array(taps.keys) { removeTap(id) }
    }

    /// The aggregate device is built on the output that was current; a new one needs a new tap.
    private func rebuildAllTaps() {
        let ids = Array(taps.keys)
        removeAllTaps()
        for id in ids { apply(id) }
    }

    /// Called on quit so no app is left muted behind a dead tap.
    public func shutdown() {
        removeAllTaps()
    }

    // MARK: Meter and capture watchdog

    private func startMeter() {
        guard meterTimer == nil else { return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { AppAudioService.shared.tickMeter() }
        }
        meterTimer?.tolerance = 0.05
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tickMeter() {
        guard #available(macOS 14.2, *) else { return }
        for (id, object) in taps {
            guard let tap = object as? AppAudioTap else { continue }
            let peak = Double(tap.takePeak())
            // Four times a second per app: only a step the meter would show
            // republishes (and redraws the console).
            let level = min(1, peak)
            let old = levels[id] ?? -1
            if abs(old - level) >= 0.02 || (old == 0) != (level == 0) { levels[id] = level }
            // Without audio-capture permission a tap delivers pure silence while
            // the app is still muted. Several seconds of that while the app says
            // it's playing means access was refused, so give the app its sound back.
            let playing = apps.first(where: { $0.id == id })?.isPlaying ?? false
            if playing, peak == 0 {
                silenceTicks[id, default: 0] += 1
                if silenceTicks[id, default: 0] >= 24 {
                    captureError = "macOS isn't letting Tama capture app audio. Allow Tama under Privacy & Security › Screen & System Audio Recording, then try again."
                    removeAllTaps()
                    return
                }
            } else if peak > 0 {
                silenceTicks[id] = -1_000_000
            }
        }
    }
}

// MARK: - Process tap

enum AppAudioTapError: LocalizedError {
    case status(String, OSStatus)
    case noOutput

    var errorDescription: String? {
        switch self {
        case let .status(step, status): "\(step) failed: \(status)"
        case .noOutput: "no output device"
        }
    }
}

/// Values shared with the real-time IOProc. Plain pointers, allocated once:
/// the audio thread must not lock, allocate or touch Swift reference counting.
/// Aligned 32-bit float loads and stores are atomic on Apple silicon and Intel.
struct AppAudioTapShared: @unchecked Sendable {
    let target: UnsafeMutablePointer<Float>
    let current: UnsafeMutablePointer<Float>
    let peak: UnsafeMutablePointer<Float>

    init(gain: Float) {
        target = .allocate(capacity: 1); target.initialize(to: gain)
        current = .allocate(capacity: 1); current.initialize(to: gain)
        peak = .allocate(capacity: 1); peak.initialize(to: 0)
    }

    func deallocate() {
        target.deallocate(); current.deallocate(); peak.deallocate()
    }
}

/// One app's process tap, the private aggregate device that plays it back on
/// the current output, and the IOProc that applies the gain.
@available(macOS 14.2, *)
final class AppAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let shared: AppAudioTapShared

    var gain: Float {
        get { shared.target.pointee }
        set { shared.target.pointee = newValue }
    }

    init(processes: [AudioObjectID], name: String, gain: Float) throws {
        shared = AppAudioTapShared(gain: gain)
        do {
            try build(processes: processes, name: name)
        } catch {
            invalidate()
            throw error
        }
    }

    private func build(processes: [AudioObjectID], name: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Tama – \(name)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AppAudioTapError.status("Creating the tap", status) }

        let output: AudioDeviceID = CA.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        guard output != 0, let outputUID = CA.string(output, kAudioDevicePropertyDeviceUID) else { throw AppAudioTapError.noOutput }

        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tama Audio Control",
            kAudioAggregateDeviceUIDKey: "app.tama.audiocontrol.\(UUID().uuidString)",
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
        guard status == noErr else { throw AppAudioTapError.status("Creating the output device", status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, Self.makeIOBlock(shared))
        guard status == noErr else { throw AppAudioTapError.status("Starting playback", status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw AppAudioTapError.status("Starting playback", status) }
    }

    /// Loudest input sample since the last call, before gain.
    func takePeak() -> Float {
        let value = shared.peak.pointee
        shared.peak.pointee = 0
        return value
    }

    private var invalidated = false

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                // Stop is synchronous: the IOProc has returned before the pointers go.
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

    /// Built outside any actor so the block carries no isolation check onto the audio thread.
    private nonisolated static func makeIOBlock(_ shared: AppAudioTapShared) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let output = UnsafeMutableAudioBufferListPointer(outputData)

            var inChannels = 0
            for buffer in input { inChannels += Int(buffer.mNumberChannels) }
            var outChannels = 0
            for buffer in output { outChannels += Int(buffer.mNumberChannels) }

            let target = shared.target.pointee
            let start = shared.current.pointee
            var peak = shared.peak.pointee
            var base = 0
            for buffer in output {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0, let data = buffer.mData else { base += channels; continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                let step = frames > 0 ? (target - start) / Float(frames) : 0
                for frame in 0..<frames {
                    // Ramp across the buffer so slider moves don't click.
                    let g = start + step * Float(frame)
                    for channel in 0..<channels {
                        let global = base + channel
                        var s: Float = 0
                        if inChannels > 0 {
                            if outChannels == 1 {
                                s = (sample(input, 0, frame) + sample(input, min(1, inChannels - 1), frame)) * 0.5
                            } else if global < 2 {
                                s = sample(input, min(global, inChannels - 1), frame)
                            }
                        }
                        let magnitude = abs(s)
                        if magnitude > peak { peak = magnitude }
                        samples[frame * channels + channel] = softClip(s * g)
                    }
                }
                base += channels
            }
            shared.current.pointee = target
            shared.peak.pointee = peak
        }
    }

    @inline(__always)
    private nonisolated static func sample(_ list: UnsafeMutableAudioBufferListPointer, _ channel: Int, _ frame: Int) -> Float {
        var base = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            if channel < base + channels {
                guard let data = buffer.mData,
                      frame < Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels) else { return 0 }
                return data.assumingMemoryBound(to: Float.self)[frame * channels + channel - base]
            }
            base += channels
        }
        return 0
    }

    /// Transparent below 0.9, then bends smoothly toward 1 so boosts above 100% don't crackle.
    @inline(__always)
    private nonisolated static func softClip(_ x: Float) -> Float {
        let m = abs(x)
        guard m > 0.9 else { return x }
        let bent = 0.9 + 0.1 * tanh((m - 0.9) / 0.1)
        return x < 0 ? -bent : bent
    }
}

// MARK: - CoreAudio helpers

private enum CA {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
