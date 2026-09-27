import SwiftUI
import AppKit

// Settings for files: the Shelf's clean-up, the Basket, Quick Actions,
// conversion, compression, Smart Export and background removal. The stored
// values are @AppStorage properties in AppState's class body.

/// Settings › Shelf › Auto-cleanup: how long unpinned Shelf files stay.
public enum TrayExpiry: String, CaseIterable, Identifiable, Sendable {
    case oneHour, twoHours, fiveHours, twelveHours, oneDay, never

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fiveHours: "5 hours"
        case .twelveHours: "12 hours"
        case .oneDay: "24 hours"
        case .never: "Never"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .oneHour: 3600
        case .twoHours: 2 * 3600
        case .fiveHours: 5 * 3600
        case .twelveHours: 12 * 3600
        case .oneDay: 24 * 3600
        case .never: nil
        }
    }
}

/// Settings › Basket › Basket mode.
public enum BasketMode: String, CaseIterable, Identifiable, Sendable {
    /// Only one basket at a time.
    case single
    /// Jiggling while a basket is open spawns another, each with its own colour.
    case multi

    public var id: String { rawValue }
}

/// How a Basket lays out its files.
public enum BasketLayout: String, CaseIterable, Identifiable, Sendable {
    case grid, list
    public var id: String { rawValue }
}

/// Settings › General › Quick Action mail app.
public enum QuickActionMailApp: String, CaseIterable, Identifiable, Sendable {
    /// The system's compose-email sharing service (the default mail app).
    case systemDefault
    case mail
    case outlook

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .systemDefault: "Default"
        case .mail: "Mail"
        case .outlook: "Outlook"
        }
    }

    public var icon: String {
        switch self {
        case .systemDefault: "gearshape.fill"
        case .mail: "applelogo"
        case .outlook: "envelope.badge.fill"
        }
    }

    var bundleID: String? {
        switch self {
        case .systemDefault: nil
        case .mail: "com.apple.mail"
        case .outlook: "com.microsoft.Outlook"
        }
    }
}

/// Settings › General › Conversion › After converting.
public enum AfterConvertAction: String, CaseIterable, Identifiable, Sendable {
    /// Select the new files in Finder.
    case reveal
    /// Open the destination folder.
    case openFolder
    /// Put the new files on the Shelf (they stay in the destination too).
    case addToShelf
    /// Only the completion banner.
    case nothing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reveal: "Show in Finder"
        case .openFolder: "Open folder"
        case .addToShelf: "Add to Shelf"
        case .nothing: "Do nothing"
        }
    }
}

/// Settings › General › Automation › Tracked folders: what happens to a file
/// that lands in a watched folder.
public enum TrackedFolderAction: String, CaseIterable, Identifiable, Sendable {
    /// Held on the Shelf, like a drop on the notch.
    case tray
    /// Held in a floating Basket instead, which opens to take it.
    case basket
    /// Held on the Shelf and compressed there, at the level picked below.
    case compress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tray: "Add to Tray"
        case .basket: "Add to Basket"
        case .compress: "Add and compress"
        }
    }

    public var icon: String {
        switch self {
        case .tray: "tray.and.arrow.down"
        case .basket: "basket"
        case .compress: "arrow.down.right.and.arrow.up.left"
        }
    }
}

/// One watched folder and what it does with an arrival. Stored in
/// `trackedFolders`, one per line, as "action:path" — a bare path (what earlier
/// versions wrote) still reads as Add to Tray.
public struct TrackedFolder: Hashable, Identifiable, Sendable {
    public var path: String
    public var action: TrackedFolderAction

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var name: String { url.lastPathComponent }

    public init(path: String, action: TrackedFolderAction = .tray) {
        self.path = path
        self.action = action
    }

    /// A path may hold colons of its own, so only a known action counts as one.
    public init?(token: String) {
        guard !token.isEmpty else { return nil }
        if let colon = token.firstIndex(of: ":"),
           let action = TrackedFolderAction(rawValue: String(token[..<colon])) {
            let path = String(token[token.index(after: colon)...])
            guard !path.isEmpty else { return nil }
            self.init(path: path, action: action)
        } else {
            self.init(path: token, action: .tray)
        }
    }

    public var token: String { "\(action.rawValue):\(path)" }

    public static func decode(_ stored: String) -> [TrackedFolder] {
        stored.split(separator: "\n").compactMap { TrackedFolder(token: String($0)) }
    }

    public static func encode(_ folders: [TrackedFolder]) -> String {
        folders.map(\.token).joined(separator: "\n")
    }
}

/// Compress › Low / Medium / High.
public enum CompressionLevel: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: "Low (Smaller)"
        case .medium: "Medium (Balanced)"
        case .high: "High (Minimal Loss)"
        }
    }

    /// JPEG / HEIC quality.
    var imageQuality: Double {
        switch self {
        case .low: 0.45
        case .medium: 0.65
        case .high: 0.82
        }
    }

    /// Longest side an image is scaled down to (nil keeps it).
    var imageMaxPixels: Int? {
        switch self {
        case .low: 2048
        case .medium: 3072
        case .high: nil
        }
    }

    /// Ghostscript's `-dPDFSETTINGS`.
    var ghostscriptPreset: String {
        switch self {
        case .low: "/screen"
        case .medium: "/ebook"
        case .high: "/printer"
        }
    }
}

/// The backdrop behind a background-removed subject.
public enum CutoutBackground: String, CaseIterable, Identifiable, Sendable {
    case transparent, white, black, neon, pastel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transparent: "Transparent"
        case .white: "White"
        case .black: "Black"
        case .neon: "Neon"
        case .pastel: "Pastel"
        }
    }

    /// One colour fills; two make a diagonal gradient; none keeps the alpha.
    var colors: [NSColor] {
        switch self {
        case .transparent: []
        case .white: [.white]
        case .black: [.black]
        case .neon: [NSColor.systemPurple.withAlphaComponent(0.85), NSColor.systemBlue.withAlphaComponent(0.85)]
        case .pastel: [NSColor.systemPink.withAlphaComponent(0.6), NSColor.systemOrange.withAlphaComponent(0.6)]
        }
    }
}

/// Settings › General › Automation › Smart Export: where each kind of
/// processed file is saved automatically.
public enum SmartExportKind: String, CaseIterable, Sendable {
    case compressed, converted, cutouts

    var folderName: String {
        switch self {
        case .compressed: "Compressed"
        case .converted: "Converted"
        case .cutouts: "Background Removed"
        }
    }
}
