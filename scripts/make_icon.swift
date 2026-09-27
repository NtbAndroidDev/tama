#!/usr/bin/env swift
//
//  make_icon.swift — draws Tama's app icon and packs it into AppIcon.icns.
//
//  Run from the repo root:   swift scripts/make_icon.swift
//  Output:                   AppIcon.iconset/  and  AppIcon.icns
//
//  The icon is drawn, not exported from a design tool, so it stays editable
//  here and renders crisply at every size: each size is drawn natively in a
//  1024-point design space rather than downscaled from one bitmap.
//
//  The subject is Tama — a periwinkle glass orb with a small face, cradled
//  under a notch. Periwinkle is the app's own accent (the music wave), the
//  notch is where the app lives, and the face is the point: a small soul.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

enum Ink {
    static let shellTop     = rgb(0x2C3158)     // obsidian, lit from above
    static let shellBottom  = rgb(0x07080F)
    static let notchVoid    = rgb(0x030408)
    static let ambient      = rgb(0x4B52C8)     // the orb's light on the shell
    static let glowUnder    = rgb(0x7C86FF)
    static let orbCore      = rgb(0xEAEEFF)
    static let orbMid       = rgb(0x9FA7F8)
    static let orbEdge      = rgb(0x4F55D4)
    static let orbDeep      = rgb(0x3A3FAE)
    static let fresnel      = rgb(0xB6A2FF)
    static let face         = rgb(0x1C2047)
    static let blush        = rgb(0xFF8FB4)
    static let white        = rgb(0xFFFFFF)
    static let black        = rgb(0x000000)
}

// MARK: - Drawing helpers

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map { $0.0 } as CFArray,
               locations: stops.map { $0.1 })!
}

/// Apple's icon silhouette is a superellipse, not a rounded rectangle. The
/// difference is the whole reason the shape reads as "made for macOS".
func squircle(in rect: CGRect, n: Double = 5.0, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let e = 2.0 / n
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(ct), e), ct))
        let y = cy + b * CGFloat(copysign(pow(abs(st), e), st))
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// A soft blob: a radial gradient squashed and turned, used for glows,
/// highlights and blush. `scaleY` under 1 flattens it into an ellipse.
func blob(_ ctx: CGContext, at c: CGPoint, radius: CGFloat,
          _ stops: [(CGColor, CGFloat)], scaleY: CGFloat = 1, rotation: CGFloat = 0) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: rotation)
    ctx.scaleBy(x: 1, y: scaleY)
    ctx.drawRadialGradient(gradient(stops), startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Strokes a path with a gradient — CoreGraphics has no gradient pen, so the
/// stroke is turned into a shape, clipped, and the gradient drawn through it.
func strokeGradient(_ ctx: CGContext, _ path: CGPath, width: CGFloat,
                    _ stops: [(CGColor, CGFloat)], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: from, end: to,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// The four-point glint on the glass.
func twinkle(at c: CGPoint, radius r: CGFloat) -> CGPath {
    let w = r * 0.18
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
    p.closeSubpath()
    return p
}

// MARK: - The icon

/// Everything is laid out in a 1024-point square with the origin top-left, so
/// the numbers below read like a design grid regardless of the rendered size.
func drawTama(in ctx: CGContext, pixelSize: CGFloat) {
    let scale = pixelSize / 1024
    ctx.translateBy(x: 0, y: pixelSize)
    ctx.scaleBy(x: scale, y: -scale)

    // Below ~40 px the fine passes turn to mud, so they are dropped and the
    // face is opened up instead. The icon still has to read in the Dock.
    let tiny = pixelSize <= 40
    let faceGain: CGFloat = tiny ? 1.18 : 1.0

    // Apple's grid leaves the tile at 824 of 1024, but at 16 px that rounds to
    // a 13 px tile with half-covered edges. The small sizes are scaled up to
    // the ~14 px Apple's own small icons fill.
    if tiny {
        ctx.translateBy(x: 512, y: 512)
        ctx.scaleBy(x: 1.09, y: 1.09)
        ctx.translateBy(x: -512, y: -512)
    }

    let shell = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: shell)

    let orbC = CGPoint(x: 512, y: 556)
    let orbR: CGFloat = 222

    // Drop shadow, so the tile sits on the desktop rather than floating. At
    // 16 and 32 px it is under a pixel wide and only blurs the silhouette.
    if !tiny {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 46, color: Ink.black.copy(alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(Ink.black)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // 1. Obsidian shell, lit from the top.
    ctx.drawLinearGradient(gradient([(Ink.shellTop, 0), (Ink.shellBottom, 1)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 2. The orb's own light, spilling onto the shell around it.
    blob(ctx, at: orbC, radius: 520, [(Ink.ambient.copy(alpha: 0.52)!, 0),
                                      (Ink.ambient.copy(alpha: 0.2)!, 0.55),
                                      (Ink.ambient.copy(alpha: 0)!, 1)])

    // 3. Vignette — the corners fall away so the centre holds the eye.
    blob(ctx, at: CGPoint(x: 512, y: 512), radius: 640,
         [(Ink.black.copy(alpha: 0)!, 0.35), (Ink.black.copy(alpha: 0.34)!, 1)])

    if !tiny {
        blob(ctx, at: CGPoint(x: 250, y: 210), radius: 560,
             [(Ink.white.copy(alpha: 0.055)!, 0), (Ink.white.copy(alpha: 0)!, 1)])
    }

    // 4. The notch. Its top corners are drawn above the shell and clipped off,
    //    so it reads as cut into the top edge rather than pasted on.
    let notchW: CGFloat = 336, notchH: CGFloat = 82, notchR: CGFloat = 34
    let notch = CGPath(roundedRect: CGRect(x: 512 - notchW / 2, y: 100 - notchR * 2,
                                           width: notchW, height: notchH + notchR * 2),
                       cornerWidth: notchR, cornerHeight: notchR, transform: nil)
    ctx.addPath(notch)
    ctx.setFillColor(Ink.notchVoid)
    ctx.fillPath()

    if !tiny {
        // Light from the orb catching the notch's lower lip.
        strokeGradient(ctx, notch, width: 5,
                       [(Ink.glowUnder.copy(alpha: 0)!, 0.3), (Ink.glowUnder.copy(alpha: 0.22)!, 1)],
                       from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 100 + notchH))

        // Rim light along the shell's top edge.
        strokeGradient(ctx, shape, width: 3.5,
                       [(Ink.white.copy(alpha: 0.24)!, 0), (Ink.white.copy(alpha: 0)!, 1)],
                       from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 430))
    }

    // 5. Contact shadow first, then the pool of light the orb casts, so the
    //    orb sits on the shell instead of hovering over it.
    blob(ctx, at: CGPoint(x: 512, y: 806), radius: 190,
         [(Ink.black.copy(alpha: 0.38)!, 0), (Ink.black.copy(alpha: 0)!, 1)], scaleY: 0.19)
    blob(ctx, at: CGPoint(x: 512, y: 812), radius: 262,
         [(Ink.glowUnder.copy(alpha: 0.5)!, 0), (Ink.glowUnder.copy(alpha: 0)!, 1)], scaleY: 0.26)

    // 6. Tama. The gradient's origin sits up and to the left of the sphere's
    //    centre, which is what makes a flat circle read as glass.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: orbC.x - orbR, y: orbC.y - orbR, width: orbR * 2, height: orbR * 2))
    ctx.clip()
    ctx.drawRadialGradient(gradient([(Ink.orbCore, 0), (Ink.orbMid, 0.46), (Ink.orbEdge, 0.86), (Ink.orbDeep, 1)]),
                           startCenter: CGPoint(x: orbC.x - 82, y: orbC.y - 98), startRadius: 0,
                           endCenter: orbC, endRadius: orbR * 1.16,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    let orbPath = CGPath(ellipseIn: CGRect(x: orbC.x - orbR, y: orbC.y - orbR,
                                           width: orbR * 2, height: orbR * 2), transform: nil)

    // Fresnel: glass is brightest where it turns away from you.
    strokeGradient(ctx, orbPath, width: 11,
                   [(Ink.fresnel.copy(alpha: 0)!, 0.42), (Ink.fresnel.copy(alpha: 0.55)!, 1)],
                   from: CGPoint(x: orbC.x - orbR, y: orbC.y - orbR),
                   to: CGPoint(x: orbC.x + orbR * 0.7, y: orbC.y + orbR))
    strokeGradient(ctx, orbPath, width: 5,
                   [(Ink.white.copy(alpha: 0.44)!, 0), (Ink.white.copy(alpha: 0)!, 0.45)],
                   from: CGPoint(x: orbC.x - orbR * 0.8, y: orbC.y - orbR),
                   to: CGPoint(x: orbC.x + orbR * 0.4, y: orbC.y + orbR * 0.2))

    // 7. The face, suspended inside the glass rather than painted on it:
    //    soft-edged, never fully opaque, and set low the way a young face is.
    ctx.saveGState()
    ctx.addPath(orbPath)
    ctx.clip()

    if !tiny {
        for side in [-CGFloat(1), 1] {
            blob(ctx, at: CGPoint(x: orbC.x + side * 118, y: orbC.y + 66), radius: 54,
                 [(Ink.blush.copy(alpha: 0.36)!, 0), (Ink.blush.copy(alpha: 0)!, 1)], scaleY: 0.74)
        }
    }

    let eyeW = 33 * faceGain, eyeH = 43 * faceGain
    let eyeY = orbC.y + 24
    for side in [-CGFloat(1), 1] {
        let x = orbC.x + side * 69 * faceGain
        let r = CGRect(x: x - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: eyeW / 2, cornerHeight: eyeW / 2, transform: nil))
        ctx.setFillColor(Ink.face.copy(alpha: tiny ? 0.96 : 0.86)!)
        ctx.fillPath()
        if !tiny {
            ctx.setFillColor(Ink.white.copy(alpha: 0.82)!)
            ctx.fillEllipse(in: CGRect(x: x - eyeW / 2 + 4, y: eyeY - eyeH / 2 + 5, width: 11.5, height: 11.5))
        }
    }

    // The smile. In this flipped space a positive angle sweeps downward, so
    // this arc bulges below its centre.
    let mouth = CGMutablePath()
    mouth.addArc(center: CGPoint(x: orbC.x, y: orbC.y + 38 * faceGain), radius: 35 * faceGain,
                 startAngle: 26 * .pi / 180, endAngle: 154 * .pi / 180, clockwise: false)
    ctx.addPath(mouth)
    ctx.setStrokeColor(Ink.face.copy(alpha: tiny ? 0.94 : 0.78)!)
    ctx.setLineWidth(11 * faceGain)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // 8. Specular highlight, over the face — it is the outside of the glass.
    blob(ctx, at: CGPoint(x: orbC.x - 88, y: orbC.y - (tiny ? 124 : 104)), radius: tiny ? 82 : 108,
         [(Ink.white.copy(alpha: tiny ? 0.34 : 0.5)!, 0), (Ink.white.copy(alpha: 0)!, 1)],
         scaleY: 0.58, rotation: -0.42)
    if !tiny {
        blob(ctx, at: CGPoint(x: orbC.x - 96, y: orbC.y - 116), radius: 50,
             [(Ink.white.copy(alpha: 0.72)!, 0), (Ink.white.copy(alpha: 0)!, 1)],
             scaleY: 0.62, rotation: -0.42)
    }
    ctx.restoreGState()

    if !tiny {
        ctx.addPath(twinkle(at: CGPoint(x: orbC.x + 112, y: orbC.y - 132), radius: 31))
        ctx.setFillColor(Ink.white.copy(alpha: 0.78)!)
        ctx.fillPath()
    }

    ctx.restoreGState()
}

// MARK: - Render

func render(_ pixelSize: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawTama(in: ctx, pixelSize: CGFloat(pixelSize))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten files `iconutil` expects, by name.
let faces: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in faces {
    try render(px).write(to: iconset.appendingPathComponent("\(name).png"))
    print("  \(name).png  (\(px)px)")
}

// A loose copy at full size, for README shots and quick eyeballing.
try render(1024).write(to: root.appendingPathComponent("AppIcon-preview.png"))

let icns = Process()
icns.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icns.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try icns.run()
icns.waitUntilExit()
guard icns.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("\nAppIcon.icns written.")
