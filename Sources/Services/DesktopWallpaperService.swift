import AppKit
import ImageIO

/// The current desktop picture, small, for the Settings previews.
///
/// Every preview card draws its miniature on the real wallpaper of the screen
/// the island lives on, so a card shows what the notch will actually look
/// like. `NSWorkspace` hands over the picture's URL and ImageIO builds a
/// preview-sized thumbnail off the main actor; the result is kept until the
/// picture changes, so calling `refresh()` from a view costs nothing. Video
/// wallpapers ("Aerials") have no still to read, so `image` stays nil and the
/// previews fall back to a plain gradient.
@MainActor
public final class DesktopWallpaperService: ObservableObject {
    public static let shared = DesktopWallpaperService()

    /// The desktop picture, downsampled. Nil until it has been read, and when
    /// it can't be read at all.
    @Published public private(set) var image: NSImage?

    /// What `image` was built from, so an unchanged picture is never re-read.
    private var source: (url: URL, modified: Date?)?
    private var isLoading = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Reads the desktop picture unless it is already loaded.
    public func refresh() {
        observeChanges()
        guard !isLoading, let url = currentPictureURL() else { return }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let source, source.url == url, source.modified == modified, image != nil { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let thumbnail = Self.thumbnail(at: url)
            await MainActor.run {
                let service = DesktopWallpaperService.shared
                service.isLoading = false
                guard let thumbnail else {
                    service.source = nil
                    service.image = nil
                    return
                }
                service.source = (url, modified)
                service.image = NSImage(cgImage: thumbnail,
                                        size: NSSize(width: thumbnail.width, height: thumbnail.height))
            }
        }
    }

    /// The shape of the screen the island lives on, so a preview can crop the
    /// picture the way macOS fills that screen with it.
    public var screenAspect: CGFloat {
        let screen = AppState.shared.getTargetScreen() ?? NSScreen.main
        guard let frame = screen?.frame, frame.width > 0, frame.height > 0 else { return 16.0 / 10.0 }
        return frame.width / frame.height
    }

    /// The picture behind the island, falling back to any screen that has one
    /// (a Space or a screen can be missing its URL right after a switch).
    private func currentPictureURL() -> URL? {
        let workspace = NSWorkspace.shared
        let preferred = [AppState.shared.getTargetScreen(), NSScreen.main].compactMap { $0 }
        for screen in preferred + NSScreen.screens {
            if let url = workspace.desktopImageURL(for: screen) { return url }
        }
        return nil
    }

    private nonisolated static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Wide enough for the widest preview on a Retina screen.
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        // A dynamic .heic desktop holds one image per appearance; its primary
        // image is the one Finder shows, which is close enough for a preview.
        let index = CGImageSourceGetPrimaryImageIndex(source)
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// A new Space, a new screen arrangement or coming back from System
    /// Settings can all mean a different picture. The cache check above makes
    /// these cheap, so they just ask for a refresh.
    private func observeChanges() {
        guard observers.isEmpty else { return }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DesktopWallpaperService.shared.refresh() }
            })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { DesktopWallpaperService.shared.refresh() }
                })
        }
    }
}
