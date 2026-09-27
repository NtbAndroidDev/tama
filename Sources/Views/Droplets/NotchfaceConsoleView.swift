import AVFoundation
import SwiftUI

// Notchface — a mirror in the notch: a live preview from the camera you
// pick. The camera stays off until you start it, and goes off with the shelf.

struct NotchfaceConsoleView: View {
    @ObservedObject private var camera = NotchfaceCamera.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: DS.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Palette.surface1)
                if camera.isRunning {
                    CameraPreview(session: camera.pipeline.session, mirrored: state.notchfaceMirror)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .accessibilityElement()
                        .accessibilityLabel("Live camera preview")
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: DS.Space.sm) {
                if camera.access == .granted {
                    DroppyPillButton(camera.isRunning ? "Stop" : "Start", systemName: camera.isRunning ? "stop.fill" : "video.fill",
                                     tone: camera.isRunning ? .tonal : .accent,
                                     help: camera.isRunning ? "Turn the camera off" : "Turn the camera on") { camera.toggle() }
                        .disabled(camera.isStarting)
                    if camera.cameras.count > 1 {
                        Menu {
                            ForEach(camera.cameras) { device in
                                Button {
                                    camera.select(device.id)
                                } label: {
                                    if device.id == selectedID { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                                }
                            }
                        } label: {
                            Label(selectedName, systemImage: "web.camera").font(DS.Typo.label)
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Choose which connected camera to use")
                        .accessibilityLabel("Camera: \(selectedName)")
                    }
                }
                Spacer(minLength: 0)
                DroppyIconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", size: 26,
                                 isActive: state.notchfaceMirror,
                                 help: state.notchfaceMirror ? "Show unmirrored" : "Mirror the preview") {
                    state.notchfaceMirror.toggle()
                }
            }
        }
        .onAppear {
            camera.refreshAccess()
            camera.refreshCameras()
        }
        .onDisappear { camera.stop() }
        .onChange(of: state.isIslandExpanded) { _, expanded in
            if !expanded { camera.stop() }
        }
    }

    private var selectedID: String {
        let wanted = state.notchfaceCamera
        if camera.cameras.contains(where: { $0.id == wanted }) { return wanted }
        return AVCaptureDevice.default(for: .video)?.uniqueID ?? camera.cameras.first?.id ?? ""
    }

    private var selectedName: String {
        camera.cameras.first { $0.id == selectedID }?.name ?? "Camera"
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: DS.Space.sm) {
            switch camera.access {
            case .granted:
                if camera.isStarting {
                    ProgressView().controlSize(.small).accessibilityLabel("Starting the camera")
                } else if camera.cameras.isEmpty {
                    Image(systemName: "video.slash").font(.system(size: 24, weight: .light)).foregroundStyle(DS.Palette.textSecondary)
                        .accessibilityHidden(true)
                    Text("No camera found").font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                    // The list follows cameras being plugged in, so no button is needed.
                    Text("Connect a camera and it shows up here.")
                        .font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                } else {
                    Image(systemName: "web.camera").font(.system(size: 24, weight: .light)).foregroundStyle(DS.Palette.textSecondary)
                        .accessibilityHidden(true)
                    Text("Camera stays off until you start it").font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                    if let error = camera.errorMessage {
                        Text(error).font(DS.Typo.caption).foregroundStyle(DS.Palette.danger)
                            .lineLimit(3)
                    }
                }
            case .notDetermined:
                Image(systemName: "web.camera").font(.system(size: 24, weight: .light)).foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityHidden(true)
                Text("Live notch camera preview").font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                Text("Tama needs camera access to show the preview.").font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                DroppyPillButton("Allow camera access", systemName: "video", tone: .accent,
                                 help: "Ask macOS for camera access") { camera.requestAccess() }
            case .denied, .restricted:
                Image(systemName: "video.slash.fill").font(.system(size: 24, weight: .light)).foregroundStyle(DS.Palette.danger)
                    .accessibilityHidden(true)
                Text("Camera access is off").font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary)
                Text(camera.access == .restricted
                     ? "Camera access is restricted on this Mac."
                     : "Allow Tama in System Settings › Privacy & Security › Camera.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                if camera.access == .denied {
                    DroppyPillButton("Open Camera settings", systemName: "gearshape", tone: .accent,
                                     help: "Open Privacy & Security › Camera in System Settings") { camera.openCameraSettings() }
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(DS.Space.md)
    }
}

/// AVCaptureVideoPreviewLayer in a view, mirrored like a mirror by default.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        apply(to: view)
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) { apply(to: view) }

    private func apply(to view: PreviewView) {
        guard let connection = view.previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
