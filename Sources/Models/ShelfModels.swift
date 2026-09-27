import SwiftUI

/// Tiles the notch, the island and the Basket offer while a file drag hovers
/// them (Settings › General › Quick Actions). Keep is always the first tile;
/// up to three of the others follow it.
public enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case keep
    /// Tama's own LAN link with a QR code.
    case share
    case airDrop
    case convert
    /// Upload to 0x0.st and copy the link.
    case quickshare
    case iCloud
    case mail
    case messages
    /// Nearby devices running LocalSend (the LocalSend droplet).
    case localSend
    /// "ZIP Hover": hover this tile with a drag and the files land as one archive.
    case zip

    public var id: String { rawValue }

    /// The tiles that can join Keep.
    public static let choosable: [QuickAction] = [.airDrop, .convert, .zip, .share, .quickshare, .iCloud, .mail, .messages, .localSend]
    /// Keep plus this many.
    public static let slots = 3
    public static let defaultTiles: [QuickAction] = [.share, .airDrop, .convert]

    public var title: String {
        switch self {
        case .keep: return "Keep"
        case .share: return "Share Link"
        case .airDrop: return "AirDrop"
        case .convert: return "Convert"
        case .quickshare: return "Quickshare"
        case .iCloud: return "iCloud Drive"
        case .mail: return "Mail"
        case .messages: return "Messages"
        case .localSend: return "LocalSend"
        case .zip: return "ZIP Hover"
        }
    }

    public var subtitle: String {
        switch self {
        case .keep: return "Drop the files on the Shelf or Basket"
        case .share: return "A link and QR code for devices on your network"
        case .airDrop: return "Send files wirelessly to nearby Apple devices"
        case .convert: return "Convert files on your Mac, never in the cloud"
        case .quickshare: return "Upload to 0x0.st and copy a shareable link"
        case .iCloud: return "Copy to iCloud Drive › Tama, ready to share a link"
        case .mail: return "Attach files to a new email"
        case .messages: return "Share files via Messages"
        case .localSend: return "Send to any nearby device running LocalSend"
        case .zip: return "Hover to drop the files in as one ZIP archive"
        }
    }

    public var iconName: String {
        switch self {
        case .keep: return "tray.and.arrow.down.fill"
        case .share: return "qrcode"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .convert: return "arrow.triangle.2.circlepath"
        case .quickshare: return "link.icloud.fill"
        case .iCloud: return "icloud.and.arrow.up.fill"
        case .mail: return "envelope.fill"
        case .messages: return "message.fill"
        case .localSend: return "dot.radiowaves.left.and.right.circle.fill"
        case .zip: return "doc.zipper"
        }
    }

    /// "share,airDrop" → [.share, .airDrop], without Keep or repeats.
    public static func tiles(from storage: String) -> [QuickAction] {
        var seen = Set<QuickAction>()
        return storage.split(separator: ",")
            .compactMap { QuickAction(rawValue: String($0)) }
            .filter { $0 != .keep && seen.insert($0).inserted }
            .prefix(slots)
            .map { $0 }
    }

    public static func storage(for tiles: [QuickAction]) -> String {
        tiles.filter { $0 != .keep }.prefix(slots).map(\.rawValue).joined(separator: ",")
    }
}

/// A floating Basket: its own files, a colour, open or put away.
public struct Basket: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var tint: Int
    public var items: [ShelfItem]
    public var isOpen: Bool

    public init(id: UUID = UUID(), tint: Int = 0, items: [ShelfItem] = [], isOpen: Bool = true) {
        self.id = id
        self.tint = tint
        self.items = items
        self.isOpen = isOpen
    }

    public static let tints: [Color] = [
        Color(red: 0.62, green: 0.40, blue: 0.98),
        Color(red: 0.31, green: 0.62, blue: 0.99),
        Color(red: 0.19, green: 0.78, blue: 0.55),
        Color(red: 0.98, green: 0.62, blue: 0.19),
        Color(red: 0.96, green: 0.36, blue: 0.52),
        Color(red: 0.30, green: 0.80, blue: 0.86)
    ]
    public static let tintNames = ["Violet", "Blue", "Green", "Orange", "Pink", "Teal"]

    public var color: Color { Self.tints[tint % Self.tints.count] }
    public var colorName: String { Self.tintNames[tint % Self.tintNames.count] }
    public var totalSize: Int64 { items.reduce(0) { $0 + $1.fileSize } }
}

/// A Basket as saved between launches.
struct BasketRecord: Codable, Sendable {
    var id: UUID
    var tint: Int
    var isOpen: Bool
    var items: [HeldFileRecord]

    init(_ basket: Basket) {
        id = basket.id
        tint = basket.tint
        isOpen = basket.isOpen
        items = basket.items.map(HeldFileRecord.init)
    }

    var basket: Basket {
        Basket(id: id, tint: tint, items: items.compactMap(\.item), isOpen: isOpen)
    }
}

/// A transient level readout in the notch wings.
public struct IslandHUD: Equatable, Sendable {
    public enum Kind: Sendable {
        case volume
        case brightness
        /// The keyboard backlight.
        case keyboard

        public var label: String {
            switch self {
            case .volume: return "Sound"
            case .brightness: return "Display"
            case .keyboard: return "Keyboard"
            }
        }

        /// Read by VoiceOver on the meter.
        public var accessibilityName: String {
            switch self {
            case .volume: return "Volume"
            case .brightness: return "Brightness"
            case .keyboard: return "Keyboard brightness"
            }
        }

        public func iconName(for value: Double, isMuted: Bool = false) -> String {
            switch self {
            case .brightness:
                return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
            case .keyboard:
                return value < 0.5 ? "light.min" : "light.max"
            case .volume:
                if isMuted || value <= 0.01 { return "speaker.slash.fill" }
                if value < 0.34 { return "speaker.wave.1.fill" }
                if value < 0.67 { return "speaker.wave.2.fill" }
                return "speaker.wave.3.fill"
            }
        }
    }

    public var kind: Kind
    public var value: Double
    /// Muted keeps `value` (the level sound comes back at) and dims the meter.
    public var isMuted: Bool
    /// The output the sound goes to, for "Show device" (volume only).
    public var device: Device?

    public struct Device: Equatable, Sendable {
        public var name: String
        public var symbol: String
        public init(name: String, symbol: String) {
            self.name = name
            self.symbol = symbol
        }
    }

    public init(kind: Kind, value: Double, isMuted: Bool = false, device: Device? = nil) {
        self.kind = kind
        self.value = value
        self.isMuted = isMuted
        self.device = device
    }
}

/// A named clipboard board. Clips assigned to it survive "Clear".
public struct Pinboard: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public var name: String
    public var tint: Int

    public init(name: String, tint: Int) {
        self.name = name
        self.tint = tint
    }

    public static let tints: [Color] = [
        Color(red: 0.35, green: 0.62, blue: 1.00),
        Color(red: 0.75, green: 0.45, blue: 0.98),
        Color(red: 0.19, green: 0.82, blue: 0.45),
        Color(red: 0.98, green: 0.65, blue: 0.19),
        Color(red: 0.96, green: 0.33, blue: 0.46)
    ]

    public var color: Color { Self.tints[tint % Self.tints.count] }
}
