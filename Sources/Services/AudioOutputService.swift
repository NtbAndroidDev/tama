import AppKit
import CoreAudio
import AudioToolbox

/// One place a Mac can send its sound: the built-in speakers, headphones,
/// an AirPlay speaker, a display.
public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let transport: UInt32

    public var iconName: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeAirPlay: return "homepod.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}

/// Lists the system's audio outputs, switches between them and reads / writes
/// the system volume — the data behind the player's output picker and the
/// volume HUD.
@MainActor
public final class AudioOutputService: ObservableObject {
    public static let shared = AudioOutputService()

    @Published public private(set) var devices: [AudioOutputDevice] = []
    @Published public private(set) var currentDeviceID: AudioDeviceID = 0
    @Published public private(set) var volume: Double = 0.5
    @Published public private(set) var isMuted = false
    /// False for outputs without a software volume (HDMI, some USB DACs).
    @Published public private(set) var canSetVolume = true

    /// Device whose volume and mute are being watched, with the listener block,
    /// so keyboard / Control Center changes reach the HUD before the next scroll.
    private var watchedDevice: AudioDeviceID = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private init() {
        refresh()
        listen(kAudioHardwarePropertyDevices)
        listen(kAudioHardwarePropertyDefaultOutputDevice)
    }

    // MARK: Devices

    public func refresh() {
        currentDeviceID = Self.defaultOutputDevice()
        devices = Self.allDeviceIDs()
            .filter(Self.hasOutput)
            .compactMap { id in
                guard let name = Self.name(of: id) else { return nil }
                return AudioOutputDevice(id: id, name: name, transport: Self.transport(of: id))
            }
        announceWirelessChanges()
        keepSoundOnThisMac()
        readVolume()
        watchCurrentDevice()
    }

    private func readVolume() {
        // Each write republishes this object; the HUD reads it on every scroll step.
        let level = Self.volume(of: currentDeviceID)
        if canSetVolume != (level != nil) { canSetVolume = level != nil }
        if let level, level != volume { volume = level }
        let muted = Self.isMuted(currentDeviceID)
        if isMuted != muted { isMuted = muted }
    }

    /// Volume or mute changed from outside the notch (keys, Control Center,
    /// another app): echo it in the HUD.
    private func systemVolumeChanged() {
        let before = (volume, isMuted)
        readVolume()
        guard canSetVolume, abs(volume - before.0) > 0.001 || isMuted != before.1 else { return }
        presentHUD()
    }

    /// Shows the current level; muted crosses the icon out and dims the meter.
    public func presentHUD() {
        guard AppState.shared.showVolumeHUD else { return }
        readVolume()
        guard canSetVolume else { return }
        let device = devices.first { $0.id == currentDeviceID }
            .map { IslandHUD.Device(name: $0.name, symbol: Self.deviceSymbol($0)) }
        AppState.shared.showHUD(.volume, value: volume, isMuted: isMuted, device: device)
    }

    private func watchCurrentDevice() {
        guard watchedDevice != currentDeviceID else { return }
        if let deviceListener, watchedDevice != 0 {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
                AudioObjectRemovePropertyListenerBlock(watchedDevice, &address, DispatchQueue.main, deviceListener)
            }
        }
        watchedDevice = currentDeviceID
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in AudioOutputService.shared.systemVolumeChanged() }
        }
        deviceListener = block
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if AudioObjectHasProperty(currentDeviceID, &address) {
                AudioObjectAddPropertyListenerBlock(currentDeviceID, &address, DispatchQueue.main, block)
            }
        }
    }

    public func select(_ device: AudioOutputDevice) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        refresh()
    }

    /// Headphones and speakers that just connected or left, shown in the notch.
    /// The first refresh only records what's already there.
    private var knownDevices: [AudioDeviceID: AudioOutputDevice]?
    /// The outputs the last refresh saw, so a new arrival can be told apart
    /// from the user picking one by hand.
    private var knownDeviceIDs: Set<AudioDeviceID>?

    /// Settings › HUDs › Media Controls › Always use built-in speakers. macOS
    /// hands the sound to a headset the moment it connects; this hands it
    /// straight back. Choosing an output by hand still works, because only a
    /// device that just turned up triggers it.
    private func keepSoundOnThisMac() {
        let ids = Set(devices.map(\.id))
        defer { knownDeviceIDs = ids }
        guard AppState.shared.alwaysUseBuiltInSpeakers, let known = knownDeviceIDs,
              !ids.subtracting(known).isEmpty,
              let builtIn = devices.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }),
              currentDeviceID != builtIn.id else { return }
        select(builtIn)
        AppState.shared.showNotification(appName: "Sound", title: builtIn.name,
                                         message: "Tama kept the sound on this Mac.",
                                         icon: "laptopcomputer")
    }

    private func announceWirelessChanges() {
        let current = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        defer { knownDevices = current }
        guard let known = knownDevices, AppState.shared.showDeviceAlerts else { return }
        let wireless: Set<UInt32> = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeAirPlay]
        if let joined = devices.first(where: { known[$0.id] == nil && wireless.contains($0.transport) }) {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "audioDevice", icon: Self.deviceSymbol(joined), tint: .white,
                trailing: .text("On"), priority: .urgent,
                label: "\(joined.name) connected", expiresAt: Date().addingTimeInterval(3.5)
            ))
            guard joined.transport != kAudioDeviceTransportTypeAirPlay else {
                AppState.shared.showNotification(appName: "Sound", title: joined.name, message: "Connected")
                return
            }
            announceBattery(of: joined, retries: 1)
        } else if let left = known.values.first(where: { current[$0.id] == nil && wireless.contains($0.transport) }) {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "audioDevice", icon: Self.deviceSymbol(left), tint: .white.opacity(0.6),
                trailing: .text("Off"), priority: .urgent,
                label: "\(left.name) disconnected", expiresAt: Date().addingTimeInterval(3)
            ))
        }
    }

    /// Settings › HUDs › AirPods & headphones: headphones that just joined
    /// get a fresh battery read, and the connect HUD and banner show it —
    /// L / R / case for buds, one level for over-ears. Right after pairing the
    /// levels may not be reported yet, so it tries once more.
    private func announceBattery(of device: AudioOutputDevice, retries: Int) {
        HeadphoneBatteryService.shared.refresh { battery in
            let service = AudioOutputService.shared
            // Only the device that joined, and only while it's still here.
            guard service.devices.contains(where: { $0.id == device.id }) else { return }
            let matches = battery.map { Self.sameDevice($0.name, device.name) } ?? false
            guard let battery, matches, let level = battery.level else {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        service.announceBattery(of: device, retries: retries - 1)
                    }
                } else {
                    AppState.shared.showNotification(appName: "Sound", title: device.name, message: "Connected")
                }
                return
            }
            LiveActivityCenter.shared.post(LiveActivity(
                id: "audioDevice", icon: battery.symbol, tint: level <= 20 ? DS.Palette.danger : DS.Palette.success,
                trailing: .text("\(level)%"), priority: .urgent,
                label: "\(device.name) connected, \(battery.fullDetail ?? "\(level)%")",
                expiresAt: Date().addingTimeInterval(3.5)
            ))
            AppState.shared.showNotification(appName: "Sound", title: device.name,
                                             message: "Connected · \(battery.fullDetail ?? "\(level)%")",
                                             icon: battery.symbol)
        }
    }

    /// CoreAudio and Bluetooth may name the same headphones slightly differently.
    private static func sameDevice(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        return x == y || x.contains(y) || y.contains(x)
    }

    static func deviceSymbol(_ device: AudioOutputDevice) -> String {
        if device.name.lowercased().contains("homepod") { return "homepod.fill" }
        return HeadphoneSymbol.forName(device.name) ?? device.iconName
    }

    // MARK: Volume

    /// Nudges the system output volume, the way the volume keys do.
    public func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        var scalar = Float32(clamped)
        var address = Self.address(
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput
        )
        guard AudioObjectHasProperty(currentDeviceID, &address) else {
            canSetVolume = false
            return
        }
        AudioObjectSetPropertyData(
            currentDeviceID, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &scalar
        )
        volume = clamped
        // Turning the volume up from mute should be heard, like the volume keys.
        if isMuted, clamped > 0 { setMuted(false) }
    }

    public func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(currentDeviceID, &address) else { return }
        AudioObjectSetPropertyData(currentDeviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
    }

    public func volume(for device: AudioOutputDevice) -> Double {
        Self.volume(of: device.id) ?? 0
    }

    // MARK: CoreAudio helpers

    private func listen(_ selector: AudioObjectPropertySelector) {
        var address = Self.address(selector)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }

    private static func isMuted(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value != 0
    }

    private static func volume(of id: AudioDeviceID) -> Double? {
        var address = address(
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput
        )
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var scalar: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &scalar) == noErr else { return nil }
        return Double(scalar)
    }
}
