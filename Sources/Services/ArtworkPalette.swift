import AppKit
import SwiftUI

/// Two colours taken from the album art — a bright one and a deeper one — for
/// the gradient visualizer, the player's background wash and the lyrics
/// panels. Worked out once per cover on a 12 × 12 thumbnail and cached.
public struct ArtworkPalette: Equatable, Sendable {
    public var primary: Color
    public var secondary: Color

    /// Without art: the accent, lighter and deeper.
    @MainActor public static var fallback: ArtworkPalette {
        let colors = NotchPalette.waveColors
        return ArtworkPalette(primary: colors.first ?? .white, secondary: colors.last ?? .gray)
    }

    @MainActor private static var cache: (data: Data, palette: ArtworkPalette?)?

    /// The palette of the playing track's cover; nil without one.
    @MainActor public static func current(_ track: MediaTrack) -> ArtworkPalette? {
        guard let data = track.artworkData, !data.isEmpty else { return nil }
        if let cache, cache.data.isSameArtwork(as: data) { return cache.palette }
        let palette = track.artworkImage.flatMap(extract)
        cache = (data, palette)
        return palette
    }

    /// Averages the pixels into a handful of hue buckets, then picks the most
    /// colourful well-lit bucket and a darker companion.
    @MainActor private static func extract(_ image: NSImage) -> ArtworkPalette? {
        let side = 12
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = context.data else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)

        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, count = 0.0, score = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        var all = Bucket()
        for i in 0..<(side * side) {
            let r = Double(pixels[i * 4]) / 255, g = Double(pixels[i * 4 + 1]) / 255, b = Double(pixels[i * 4 + 2]) / 255
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, sat: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &sat, brightness: &v, alpha: &a)
            all.r += r; all.g += g; all.b += b; all.count += 1
            guard v > 0.18 else { continue }
            let index = min(Int(h * 12), 11)
            buckets[index].r += r; buckets[index].g += g; buckets[index].b += b
            buckets[index].count += 1
            buckets[index].score += Double(sat) * Double(v)
        }
        func color(_ bucket: Bucket) -> NSColor {
            NSColor(srgbRed: bucket.r / bucket.count, green: bucket.g / bucket.count, blue: bucket.b / bucket.count, alpha: 1)
        }
        let ranked = buckets.filter { $0.count > 0 }.sorted { $0.score > $1.score }
        let base = ranked.first.map(color) ?? color(all)
        let second = ranked.dropFirst().first.map(color) ?? base
        // Lift the lead colour so it reads on black; sink the companion.
        let primary = base.adjusted(minBrightness: 0.72, minSaturation: 0.35)
        let secondary = (second == base ? base : second).adjusted(minBrightness: 0.4, minSaturation: 0.3)
            .blended(withFraction: 0.35, of: .black) ?? second
        return ArtworkPalette(primary: Color(nsColor: primary), secondary: Color(nsColor: secondary))
    }
}

private extension NSColor {
    func adjusted(minBrightness: CGFloat, minSaturation: CGFloat) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (usingColorSpace(.sRGB) ?? self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Greys stay grey: only a colour that has some hue is pushed.
        let saturation = s < 0.08 ? s : max(s, minSaturation)
        return NSColor(hue: h, saturation: saturation, brightness: max(b, minBrightness), alpha: 1)
    }
}
