import AVFoundation
import AppKit
import Combine

/// Notchface: a live camera preview in the notch. The camera starts only
/// when you press Start (or open the droplet with it already started) and
/// stops when the shelf closes; nothing is recorded.
@MainActor
public final class NotchfaceCamera: ObservableObject {
    public static let shared = NotchfaceCamera()

    public enum Access: Equatable { case notDetermined, denied, restricted, granted }

    public struct Camera: Identifiable, Equatable {
        public let id: String
        public let name: String
    }

    @Published public private(set) var access: Access = .notDetermined
    @Published public private(set) var cameras: [Camera] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var errorMessage: String?

    let pipeline = CameraPipeline()
    private var observers: [NSObjectProtocol] = []

    private init() {
        refreshAccess()
        refreshCameras()
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { NotchfaceCamera.shared.devicesChanged() }
            })
        }
    }

    public func refreshAccess() {
        access = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    private static var discovery: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
    }

    public func refreshCameras() {
        cameras = Self.discovery.devices.map { Camera(id: $0.uniqueID, name: $0.localizedName) }
    }

    private func devicesChanged() {
        refreshCameras()
        // The camera in use went away: stop rather than show a frozen frame.
        if isRunning, !cameras.contains(where: { $0.id == pipeline.currentDeviceID }) {
            stop()
            errorMessage = "The camera was disconnected."
        }
    }

    /// The camera Settings picked, or the system default, or the first one.
    private var selectedDevice: AVCaptureDevice? {
        let wanted = NotchfaceSettings.shared.camera
        let devices = Self.discovery.devices
        if !wanted.isEmpty, let device = devices.first(where: { $0.uniqueID == wanted }) { return device }
        return AVCaptureDevice.default(for: .video) ?? devices.first
    }

    public func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let camera = NotchfaceCamera.shared
                    camera.refreshAccess()
                    if camera.access == .granted { camera.start() }
                }
            }
        }
    }

    public func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    public func start() {
        refreshAccess()
        guard access == .granted else {
            if access == .notDetermined { requestAccess() }
            return
        }
        guard let device = selectedDevice else {
            errorMessage = "No camera found."
            return
        }
        errorMessage = nil
        isStarting = true
        pipeline.start(deviceID: device.uniqueID) { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let camera = NotchfaceCamera.shared
                    camera.isStarting = false
                    camera.isRunning = error == nil
                    camera.errorMessage = error
                }
            }
        }
    }

    public func stop() {
        guard isRunning || isStarting else { return }
        pipeline.stop()
        isRunning = false
        isStarting = false
    }

    public func toggle() { isRunning ? stop() : start() }

    /// Picking another camera while live switches to it straight away.
    public func select(_ id: String) {
        NotchfaceSettings.shared.camera = id
        if isRunning || isStarting {
            pipeline.stop()
            isRunning = false
            start()
        }
    }
}

/// The capture session, run on its own queue (starting a camera blocks).
final class CameraPipeline: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.tama.notchface")
    private let lock = NSLock()
    private var deviceID: String?

    var currentDeviceID: String? {
        lock.lock()
        defer { lock.unlock() }
        return deviceID
    }

    func start(deviceID: String, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                completion("The camera isn't available.")
                return
            }
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.sessionPreset = session.canSetSessionPreset(.high) ? .high : .medium
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion("\(device.localizedName) is busy.")
                    return
                }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                completion(error.localizedDescription)
                return
            }
            session.commitConfiguration()
            session.startRunning()
            lock.lock()
            self.deviceID = device.uniqueID
            lock.unlock()
            completion(session.isRunning ? nil : "\(device.localizedName) didn't start.")
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            session.inputs.forEach { session.removeInput($0) }
            lock.lock()
            deviceID = nil
            lock.unlock()
        }
    }
}
