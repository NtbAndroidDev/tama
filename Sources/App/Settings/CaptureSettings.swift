import SwiftUI

/// Settings › Droplets › Element Capture and Window Snap, and the screenshot preview.
@MainActor
public final class CaptureSettings: SettingsStore {
    public static let shared = CaptureSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "snipperAutoCopy", "snipperAutoTray", "snipperSaveToFolder", "snipperFolderPath",
        "snipperEditAfterCapture", "snipperAutoCompress", "captureExcludeDroppy",
        "captureEditorDefaultZoom", "captureAnnotationColor", "captureEditorFont",
        "screenshotRadius", "windowSnapShowPreview", "capturePreviewPlacement",
        "showCapturePreview"
    ]

    /// Capture destinations. The console's checkboxes use the same keys.
    @AppStorage("snipperAutoCopy") public var toClipboard: Bool = true
    @AppStorage("snipperAutoTray") public var toTray: Bool = true
    @AppStorage("snipperSaveToFolder") public var toFolder: Bool = false
    /// Empty: the Desktop.
    @AppStorage("snipperFolderPath") public var folderPath: String = ""
    /// "Open editor instantly": the editor takes over delivery.
    @AppStorage("snipperEditAfterCapture") public var opensEditor: Bool = true
    /// Screenshots are saved at point resolution and run through the image compressor.
    @AppStorage("snipperAutoCompress") public var autoCompress: Bool = false
    /// Tama's own windows are left out of its captures.
    @AppStorage("captureExcludeDroppy") public var excludesDroppy: Bool = true
    @AppStorage("captureEditorDefaultZoom") public var editorDefaultZoom: CaptureEditorZoomDefault = .fit
    /// A swatch name from `RGBAColor.swatches`.
    @AppStorage("captureAnnotationColor") public var annotationColor: String = "red"
    @AppStorage("captureEditorFont") public var editorFont: String = CaptureFont.system.rawValue
    /// Corner radius (pt) the Beautify backdrop starts with.
    @AppStorage("screenshotRadius") public var screenshotRadius: Double = 12
    /// Flash the target zone when a snap comes from a shortcut.
    @AppStorage("windowSnapShowPreview") public var windowSnapShowPreview: Bool = true
    /// A fresh screenshot leaves a thumbnail in the corner for a few seconds.
    /// Settings › Shelf › Tray & screenshots › Preview placement.
    @AppStorage("capturePreviewPlacement") public var previewPlacement: CapturePreviewPlacement = .bottomRight
    @AppStorage("showCapturePreview") public var showsPreview: Bool = true

    private init() { super.init(keys: Self.keys) }
}
