import CoreGraphics
import Foundation
import Testing
@testable import Droppy

/// Window Snap geometry, LiquidMouse curves, editor tools and shortcuts.
@Suite struct Phase9aTests {
    @Test func snapLayoutsTileTheVisibleArea() {
        let area = CGRect(x: 0, y: 25, width: 1200, height: 900)
        #expect(SnapLayout.target(SnapLayout.leftHalf.fraction!, in: area) == CGRect(x: 0, y: 25, width: 600, height: 900))
        #expect(SnapLayout.target(SnapLayout.rightTwoThirds.fraction!, in: area) == CGRect(x: 400, y: 25, width: 800, height: 900))
        #expect(SnapLayout.target(SnapLayout.bottomRight.fraction!, in: area) == CGRect(x: 600, y: 475, width: 600, height: 450))
        #expect(SnapLayout.nextDisplay.fraction == nil)
        #expect(SnapLayout.bringToFront.fraction == nil)
        // Every layout has its own shortcut action, and the mapping round-trips.
        let actions = Set(SnapLayout.allCases.map(\.shortcutAction))
        #expect(actions.count == SnapLayout.allCases.count)
        for layout in SnapLayout.allCases { #expect(SnapLayout(shortcut: layout.shortcutAction) == layout) }
        // The Ring's old preset IDs still resolve.
        #expect(SnapLayout(rawValue: "leftHalf") == .leftHalf)
        #expect(SnapLayout(rawValue: "maximize") == .maximize)
    }

    @Test func movingToAnotherDisplayKeepsRelativePlace() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let destination = CGRect(x: 1000, y: 0, width: 2000, height: 1600)
        let moved = SnapLayout.moved(CGRect(x: 500, y: 0, width: 500, height: 400), from: source, to: destination)
        #expect(moved == CGRect(x: 2000, y: 0, width: 1000, height: 800))
        // Never larger than the destination, and kept on it.
        let small = CGRect(x: 0, y: 0, width: 500, height: 400)
        let clamped = SnapLayout.moved(CGRect(x: 900, y: 700, width: 1000, height: 800), from: source, to: small)
        #expect(small.contains(clamped))
    }

    @Test func scrollCurvesRunFromZeroToOne() {
        for curve in ScrollCurve.allCases {
            #expect(abs(curve.value(at: 0)) < 1e-9, "\(curve)")
            #expect(abs(curve.value(at: 1) - 1) < 1e-9, "\(curve)")
            var previous = 0.0
            for i in 1...20 {
                let v = curve.value(at: Double(i) / 20)
                #expect(v >= previous - 1e-9, "\(curve) must not scroll backwards")
                previous = v
            }
        }
        // Ease-out curves front-load the distance, ease-in ones hold it back.
        #expect(ScrollCurve.easeOutQuartic.value(at: 0.25) > ScrollCurve.linear.value(at: 0.25))
        #expect(ScrollCurve.easeInCubic.value(at: 0.25) < ScrollCurve.linear.value(at: 0.25))
    }

    @Test func externalMouseDetection() {
        #expect(ExternalMouseMonitor.isExternalMouse(product: "MX Master 3", transport: "bluetooth low energy", builtIn: false))
        #expect(ExternalMouseMonitor.isExternalMouse(product: "USB Optical Mouse", transport: "usb", builtIn: false))
        #expect(!ExternalMouseMonitor.isExternalMouse(product: "Apple Internal Keyboard / Trackpad", transport: "spi", builtIn: true))
        #expect(!ExternalMouseMonitor.isExternalMouse(product: "Magic Trackpad", transport: "bluetooth", builtIn: false))
        #expect(!ExternalMouseMonitor.isExternalMouse(product: "Virtual", transport: "", builtIn: false))
    }

    @Test func editorToolsAndShortcuts() {
        let keys = CaptureTool.allCases.compactMap(\.shortcut)
        #expect(Set(keys).count == keys.count, "single-key shortcuts must be unique")
        #expect(CaptureTool.pen.title == "Freehand")
        #expect(CaptureTool.step.title == "Number Sticker")
        // Every tool is reachable from the toolbar exactly once.
        let grouped = CaptureTool.groups.flatMap { $0 }
        #expect(grouped.count == CaptureTool.allCases.count)
        #expect(Set(grouped) == Set(CaptureTool.allCases))
    }

    @Test func newAnnotationsHitTestAndMove() {
        let curved = Annotation(kind: .curvedArrow(from: CGPoint(x: 0, y: 0), control: CGPoint(x: 50, y: -50), to: CGPoint(x: 100, y: 0)),
                                color: .red, lineWidth: 4)
        #expect(curved.hitTest(CGPoint(x: 50, y: -25), tolerance: 3))
        #expect(!curved.hitTest(CGPoint(x: 50, y: 20), tolerance: 3))

        let diamond = Annotation(kind: .diamond(CGRect(x: 0, y: 0, width: 100, height: 100)), color: .blue, lineWidth: 4)
        #expect(diamond.hitTest(CGPoint(x: 25, y: 25), tolerance: 3))
        #expect(!diamond.hitTest(CGPoint(x: 50, y: 50), tolerance: 3))

        let loupe = Annotation(kind: .magnifier(center: CGPoint(x: 100, y: 100), radius: 40, zoom: 2), color: .red, lineWidth: 4)
        #expect(loupe.hitTest(CGPoint(x: 110, y: 110), tolerance: 2))
        #expect(loupe.bounds.contains(CGRect(x: 60, y: 60, width: 80, height: 80)))
        let moved = loupe.translated(by: CGSize(width: 10, height: 5))
        if case let .magnifier(center, radius, zoom) = moved.kind {
            #expect(center == CGPoint(x: 110, y: 105) && radius == 40 && zoom == 2)
        } else {
            Issue.record("translation changed the annotation kind")
        }

        let sticker = Annotation(kind: .sticker(.cursorCircle, tip: CGPoint(x: 200, y: 200)), color: .red, lineWidth: 4)
        #expect(sticker.bounds.contains(CGPoint(x: 200, y: 200)))
        #expect(sticker.hitTest(CGPoint(x: 205, y: 210), tolerance: 2))
    }

    @Test func renderingNewAnnotations() throws {
        let ctx = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let original = try #require(ctx.makeImage())
        var edits = CaptureEdits()
        edits.annotations = [
            Annotation(kind: .curvedArrow(from: CGPoint(x: 4, y: 4), control: CGPoint(x: 30, y: 4), to: CGPoint(x: 60, y: 40)), color: .red, lineWidth: 2),
            Annotation(kind: .diamond(CGRect(x: 10, y: 10, width: 20, height: 20)), color: .blue, lineWidth: 2),
            Annotation(kind: .magnifier(center: CGPoint(x: 32, y: 32), radius: 12, zoom: 2), color: .green, lineWidth: 2),
            Annotation(kind: .sticker(.pointerCircle, tip: CGPoint(x: 48, y: 48)), color: .orange, lineWidth: 2),
            Annotation(kind: .text("Hi", origin: CGPoint(x: 2, y: 40), fontSize: 12), color: .black, lineWidth: 2, font: .mono),
        ]
        let rendered = CaptureRenderer.render(original: original, edits: edits, backdrop: CaptureBackdrop(), pixelScale: 1)
        #expect(rendered?.width == 64)
        #expect(CaptureRenderer.textSize("Hi", fontSize: 12, font: .serif).width > 0)
    }

    @Test @MainActor func captureAndSnapShortcutsStartUnset() {
        let service = GlobalShortcutService.shared
        for mode in CaptureMode.allCases { #expect(service.defaultCombo(for: mode.shortcutAction) == nil) }
        for layout in SnapLayout.allCases { #expect(service.defaultCombo(for: layout.shortcutAction) == nil) }
        let titles = ShortcutAction.allCases.map(\.title)
        #expect(Set(titles).count == titles.count, "every shortcut needs a distinct title")
        #expect(AppState.settingsKeys.contains("captureAnnotationColor"))
        #expect(AppState.settingsKeys.contains(LiquidMouseService.Keys.curveHorizontal))
    }

    @Test func swatchNamesRoundTrip() {
        for (index, name) in RGBAColor.swatchNames.enumerated() {
            #expect(RGBAColor.named(name) == RGBAColor.swatches[index])
            #expect(RGBAColor.swatches[index].swatchName == name)
        }
        #expect(RGBAColor.named("nonsense") == .red)
    }

    @Test func screenshotFileName() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 22
        components.hour = 14; components.minute = 3; components.second = 11
        let date = Calendar.current.date(from: components)!
        #expect(ScreenCaptureService.fileName(date: date) == "Screenshot 2026-09-22 at 14.03.11")
    }
}
