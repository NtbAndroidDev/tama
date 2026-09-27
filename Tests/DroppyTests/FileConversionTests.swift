import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Droppy

@Suite struct FileConversionMatrixTests {
    @Test(arguments: [
        ("png", FileConverter.Kind.image), ("JPG", .image), ("heic", .image), ("gif", .image), ("webp", .image),
        ("pdf", .pdf), ("mov", .video), ("mp4", .video), ("m4a", .audio), ("mp3", .audio),
        ("txt", .document), ("rtf", .document), ("html", .document), ("docx", .document), ("md", .document),
        ("zip", .unsupported), ("", .unsupported), ("dmg", .unsupported),
        // Regression: SVG conforms to public.image but ImageIO can't decode it.
        ("svg", .unsupported),
    ])
    func routing(_ ext: String, _ kind: FileConverter.Kind) {
        #expect(FileConversionMatrix.kind(forExtension: ext) == kind)
    }

    @Test func targetsPerKind() {
        #expect(FileConversionMatrix.targets(for: .image, webpAvailable: false) == ["PNG", "JPEG", "HEIC", "GIF", "TIFF", "PDF"])
        #expect(FileConversionMatrix.targets(for: .image, webpAvailable: true) == ["PNG", "JPEG", "WEBP", "HEIC", "GIF", "TIFF", "PDF"])
        #expect(FileConversionMatrix.targets(for: .pdf, webpAvailable: true) == ["PNG", "JPEG", "TXT"])
        #expect(FileConversionMatrix.targets(for: .video, webpAvailable: false).contains("GIF"))
        #expect(FileConversionMatrix.targets(for: .audio, webpAvailable: false) == ["M4A", "WAV"])
        #expect(FileConversionMatrix.targets(for: .unsupported, webpAvailable: true).isEmpty)
    }

    @Test func commonTargetsIntersectAndIgnoreUnsupported() {
        let image = FileConversionMatrix.targets(for: .image, webpAvailable: false)
        let pdf = FileConversionMatrix.targets(for: .pdf, webpAvailable: false)
        #expect(FileConversionMatrix.common([image, pdf]) == ["PNG", "JPEG"])
        #expect(FileConversionMatrix.common([image, []]) == image)
        #expect(FileConversionMatrix.common([[], []]).isEmpty)
        #expect(FileConverter.commonTargets(for: [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.mov")]) == ["GIF"])
    }
}

@Suite struct UniqueFileNamerTests {
    let dir = URL(fileURLWithPath: "/tmp/out", isDirectory: true)

    @Test func freeNameIsUsedAsIs() {
        #expect(UniqueFileNamer.url(in: dir, base: "photo", ext: "png") { _ in false }.lastPathComponent == "photo.png")
    }

    @Test func collisionsCountFromTwo() {
        let taken: Set<String> = ["photo.png", "photo 2.png", "photo 3.png"]
        let url = UniqueFileNamer.url(in: dir, base: "photo", ext: "png") { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "photo 4.png")
        #expect(url.deletingLastPathComponent().path == "/tmp/out")
    }

    @Test func extensionIsCheckedToo() {
        let taken: Set<String> = ["photo.png"]
        #expect(UniqueFileNamer.url(in: dir, base: "photo", ext: "jpeg") { taken.contains($0.lastPathComponent) }
            .lastPathComponent == "photo.jpeg")
        #expect(UniqueFileNamer.url(in: dir, base: "notes", ext: "") { _ in false }.lastPathComponent == "notes")
    }

    @Test func realOutputURLAvoidsExistingFiles() throws {
        let source = URL(fileURLWithPath: "/nowhere/namer-\(UUID().uuidString).png")
        let first = FileConverter.outputURL(for: source, ext: "jpg")
        try Data().write(to: first)
        defer { try? FileManager.default.removeItem(at: first) }
        let second = FileConverter.outputURL(for: source, ext: "jpg")
        #expect(second.lastPathComponent == first.deletingPathExtension().lastPathComponent + " 2.jpg")
    }
}

// MARK: - Real conversions

enum Fixtures {
    static let dir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DroppyTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func png(width: Int = 32, height: Int = 24) throws -> URL {
        let url = dir.appendingPathComponent("img-\(UUID().uuidString).png")
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    static func pdf(pages: Int) throws -> URL {
        let url = dir.appendingPathComponent("doc-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 10, y: 10, width: 50, height: 50))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// Files FileConverter wrote for `source`, found by its unique base name.
    static func outputs(for source: URL) -> [URL] {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("Droppy Converted")
        let base = source.deletingPathExtension().lastPathComponent
        return ((try? FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(base) }
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

@Suite struct FileConverterTests {
    @Test func pngToJPEG() async throws {
        let source = try Fixtures.png()
        let outputs = try await FileConverter.convert(source, to: "JPEG")
        defer { FileConverter.removePartial(outputs) }
        let out = try #require(outputs.first)
        #expect(outputs.count == 1 && out.pathExtension == "jpeg")
        let image = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetType(image) as String? == UTType.jpeg.identifier)
    }

    @Test func multiPagePDFReportsPerPageProgress() async throws {
        let source = try Fixtures.pdf(pages: 4)
        let log = ProgressLog()
        let outputs = try await FileConverter.convert(source, to: "PNG", progress: { log.add($0) })
        defer { FileConverter.removePartial(outputs) }
        #expect(outputs.count == 4)
        #expect(outputs.map(\.lastPathComponent).allSatisfy { $0.contains("page") })
        #expect(log.all == [0.25, 0.5, 0.75, 1])
    }

    @Test func cancellingMidPDFRemovesWrittenPages() async throws {
        let source = try Fixtures.pdf(pages: 6)
        let holder = TaskHolder()
        let task = Task {
            try await FileConverter.convert(source, to: "PNG", progress: { value in
                if value >= 1.0 / 6 { holder.cancel() }
            })
        }
        holder.task = task
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Fixtures.outputs(for: source).isEmpty)
    }

    @Test func alreadyCancelledTaskWritesNothing() async throws {
        let source = try Fixtures.png()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileConverter.convert(source, to: "PNG")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Fixtures.outputs(for: source).isEmpty)
    }

    @Test func unsupportedFileThrowsReadableError() async throws {
        let source = Fixtures.dir.appendingPathComponent("archive.zip")
        await #expect(throws: FileConverter.ConversionError.self) { try await FileConverter.convert(source, to: "PNG") }
        do { _ = try await FileConverter.convert(source, to: "PNG") } catch {
            #expect(error.localizedDescription == "archive.zip can't be converted.")
        }
    }
}

final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<[URL], Error>?
    var task: Task<[URL], Error>? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); _task = newValue; lock.unlock() }
    }
    func cancel() { task?.cancel() }
}

@Suite struct BatchConversionTests {
    /// Writes a real temp file per input so cleanup can be observed.
    private static func fakeConvert(failing: Set<String> = []) -> BatchConversion.Convert {
        { url, report in
            report(0.5)
            if failing.contains(url.lastPathComponent) { throw FileConverter.ConversionError("bad file") }
            let out = Fixtures.dir.appendingPathComponent("out-\(UUID().uuidString)")
            try Data("x".utf8).write(to: out)
            report(1)
            return [out]
        }
    }

    private let inputs = ["a.png", "b.png", "c.png", "d.png"].map { URL(fileURLWithPath: "/in/\($0)") }

    @Test func progressIsSpreadAcrossFiles() async throws {
        let log = ProgressLog()
        let result = try await BatchConversion.run(inputs, to: "PNG", quality: .high, progress: { log.add($0) },
                                                   convert: Self.fakeConvert())
        defer { FileConverter.removePartial(result.outputs) }
        #expect(result.outputs.count == 4 && result.failures.isEmpty)
        #expect(log.all == [0, 0.125, 0.25, 0.25, 0.375, 0.5, 0.5, 0.625, 0.75, 0.75, 0.875, 1, 1])
    }

    @Test func partialFailureKeepsSuccesses() async throws {
        let result = try await BatchConversion.run(inputs, to: "PNG", quality: .high, progress: { _ in },
                                                   convert: Self.fakeConvert(failing: ["b.png"]))
        defer { FileConverter.removePartial(result.outputs) }
        #expect(result.outputs.count == 3)
        #expect(result.failures == ["b.png: bad file"])
    }

    @Test func totalFailureThrowsFirstReason() async {
        await #expect(throws: FileConverter.ConversionError.self) {
            try await BatchConversion.run(inputs, to: "PNG", quality: .high, progress: { _ in },
                                          convert: Self.fakeConvert(failing: Set(inputs.map(\.lastPathComponent))))
        }
    }

    @Test func cancelDiscardsWholeBatch() async throws {
        let written = ProgressLog()   // reused as a counter of files written
        let paths = PathLog()
        let convert: BatchConversion.Convert = { url, _ in
            let out = Fixtures.dir.appendingPathComponent("cancel-\(UUID().uuidString)")
            try Data("x".utf8).write(to: out)
            paths.add(out)
            written.add(1)
            if url.lastPathComponent == "b.png" { withUnsafeCurrentTask { $0?.cancel() } }
            return [out]
        }
        let task = Task { try await BatchConversion.run(inputs, to: "PNG", quality: .high, progress: { _ in }, convert: convert) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(written.all.count == 2)
        #expect(paths.all.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}

final class PathLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}
