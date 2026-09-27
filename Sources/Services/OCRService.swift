import AppKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision

/// On-device text extraction for images and PDFs. Everything heavy runs on a
/// detached task; callers await the result from any actor.
enum OCRService {
    struct Barcode: Hashable, Sendable {
        let payload: String
        let symbology: String

        /// Web links and other openable schemes, so the console can offer "Open".
        var url: URL? {
            guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto", "tel", "sms", "facetime", "maps"].contains(scheme) else { return nil }
            return url
        }
    }

    struct Result: Sendable {
        var text: String
        /// BCP-47 code of the dominant language, e.g. "vi" or "en".
        var languageCode: String?
        var barcodes: [Barcode]
        var pageCount: Int

        var languageName: String? {
            guard let languageCode else { return nil }
            return Locale.current.localizedString(forLanguageCode: languageCode)
        }
    }

    enum OCRError: LocalizedError {
        case unsupported
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupported: return "Only images and PDFs can be read."
            case .unreadable: return "The file couldn't be opened."
            }
        }
    }

    /// Progress is reported from a background thread as 0...1.
    typealias Progress = @Sendable (Double) -> Void

    static func canRead(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    static func recognize(url: URL, progress: Progress? = nil) async throws -> Result {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { throw OCRError.unsupported }
        if type.conforms(to: .pdf) {
            return try await offMain {
                try recognizePDF(url, progress: progress)
            }
        }
        guard type.conforms(to: .image) else { throw OCRError.unsupported }
        return try await offMain {
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw OCRError.unreadable }
            // The URL handler honours EXIF orientation, which a bare CGImage would lose.
            let page = try recognizePage(VNImageRequestHandler(url: url, options: [:]))
            progress?(1)
            return finish(texts: [page.text], barcodes: page.barcodes, pages: 1)
        }
    }

    static func recognize(image: NSImage) async throws -> Result {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw OCRError.unreadable }
        return try await recognize(cgImage: cgImage)
    }

    static func recognize(cgImage: CGImage) async throws -> Result {
        try await offMain {
            let page = try recognizePage(VNImageRequestHandler(cgImage: cgImage, options: [:]))
            return finish(texts: [page.text], barcodes: page.barcodes, pages: 1)
        }
    }

    /// Detached so Vision never runs on the caller's actor, while still passing
    /// the caller's cancellation through to the page loop.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    // MARK: - PDF

    private static func recognizePDF(_ url: URL, progress: Progress?) throws -> Result {
        guard let document = PDFDocument(url: url) else { throw OCRError.unreadable }
        let count = document.pageCount
        var texts: [String] = []
        var barcodes: [Barcode] = []
        for index in 0..<count {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            // A real text layer is exact and instant; only scanned pages need Vision.
            let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if embedded.filter({ !$0.isWhitespace }).count >= 16 {
                texts.append(embedded)
            } else if let image = render(page) {
                let recognized = try recognizePage(VNImageRequestHandler(cgImage: image, options: [:]))
                texts.append(recognized.text)
                barcodes.append(contentsOf: recognized.barcodes)
            }
            progress?(Double(index + 1) / Double(max(count, 1)))
        }
        let pages = texts.enumerated().map { count > 1 && !$0.element.isEmpty ? "— Page \($0.offset + 1) —\n\($0.element)" : $0.element }
        return finish(texts: pages, barcodes: barcodes, pages: count)
    }

    /// Renders at 2x so small print survives; thumbnails also apply the page rotation.
    private static func render(_ page: PDFPage) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let scale = min(2, 6000 / max(size.width, size.height, 1))
        let image = page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Vision

    private static func recognizePage(_ handler: VNImageRequestHandler) throws -> (text: String, barcodes: [Barcode]) {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let supported = (try? textRequest.supportedRecognitionLanguages()) ?? []
        let wanted = ["vi-VN", "en-US"].filter(supported.contains)
        if !wanted.isEmpty { textRequest.recognitionLanguages = wanted }
        textRequest.automaticallyDetectsLanguage = true

        let barcodeRequest = VNDetectBarcodesRequest()
        try handler.perform([textRequest, barcodeRequest])

        let text = layout(textRequest.results ?? [])
        var seen = Set<String>()
        let barcodes = (barcodeRequest.results ?? []).compactMap { obs -> Barcode? in
            guard let payload = obs.payloadStringValue, seen.insert(payload).inserted else { return nil }
            let name = obs.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            return Barcode(payload: payload, symbology: name)
        }
        return (text, barcodes)
    }

    /// Vision returns observations in no guaranteed order. Group them into rows
    /// by vertical overlap, read rows top to bottom and left to right, and keep
    /// a blank line where the vertical gap suggests a new paragraph.
    private static func layout(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Row { var minY: CGFloat; var maxY: CGFloat; var items: [(x: CGFloat, text: String)] }
        let boxes = observations.compactMap { obs -> (CGRect, String)? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return (obs.boundingBox, text)
        }.sorted { $0.0.midY > $1.0.midY }

        var rows: [Row] = []
        for (box, text) in boxes {
            if let i = rows.indices.last, box.midY >= rows[i].minY, box.midY <= rows[i].maxY {
                rows[i].items.append((box.minX, text))
                rows[i].minY = min(rows[i].minY, box.minY)
                rows[i].maxY = max(rows[i].maxY, box.maxY)
            } else {
                rows.append(Row(minY: box.minY, maxY: box.maxY, items: [(box.minX, text)]))
            }
        }

        var lines: [String] = []
        var previous: Row?
        for row in rows {
            if let previous {
                let height = max(previous.maxY - previous.minY, row.maxY - row.minY)
                if previous.minY - row.maxY > height * 1.2 { lines.append("") }
            }
            lines.append(row.items.sorted { $0.x < $1.x }.map(\.text).joined(separator: " "))
            previous = row
        }
        return lines.joined(separator: "\n")
    }

    private static func finish(texts: [String], barcodes: [Barcode], pages: Int) -> Result {
        let text = texts.filter { !$0.isEmpty }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return Result(text: text, languageCode: recognizer.dominantLanguage?.rawValue, barcodes: barcodes, pageCount: pages)
    }
}
