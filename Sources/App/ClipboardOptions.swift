import Foundation

/// Settings › Clipboard › Clipboard layout.
public enum ClipboardLayout: String, CaseIterable, Identifiable, Sendable {
    /// The card strip docked at the bottom of the screen.
    case alpha
    /// A list window with a preview pane, centred on the screen.
    case legacy

    public var id: Self { self }

    public var title: String {
        switch self {
        case .alpha: "Alpha clipboard"
        case .legacy: "Legacy clipboard"
        }
    }
}
