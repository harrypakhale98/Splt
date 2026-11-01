import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads the text of one image, line by line, with positions.
protocol ReceiptTextRecognizing: Sendable {
    func recognizeLines(in image: CGImage) async throws -> [ReceiptTextLine]
}

/// Turns photos of a receipt into a `ParsedReceipt`. Never throws: when nothing can be read the
/// result simply has no items, and the caller falls back to manual entry.
protocol ReceiptScanning: Sendable {
    func scan(_ images: [CGImage]) async -> ParsedReceipt
}

/// Recognises text with the Vision document request and falls back to the plain text request.
struct VisionTextRecognizer: ReceiptTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [ReceiptTextLine] {
        let handler = ImageRequestHandler(image)
        do {
            let documents = try await handler.perform(RecognizeDocumentsRequest())
            let lines = documents.flatMap { Self.lines(in: $0.document) }
            if !lines.isEmpty { return lines }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // the plain text request below covers documents the structured request cannot read
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let observations = try await handler.perform(request)
        return observations.compactMap(Self.line)
    }

    private static func lines(in container: DocumentObservation.Container) -> [ReceiptTextLine] {
        var observations = container.text.lines
        if observations.isEmpty {
            observations = container.paragraphs.flatMap(\.lines)
        }
        return observations.compactMap(line)
    }

    private static func line(from observation: RecognizedTextObservation) -> ReceiptTextLine? {
        let text = observation.transcript.tidied
        guard !text.isEmpty else { return nil }
        return ReceiptTextLine(
            text: text,
            boundingBox: observation.boundingBox.cgRect,
            confidence: observation.confidence
        )
    }
}

/// Scans receipts fully on the device: Vision reads the text, a plain row parser understands it,
/// and the language model optionally tidies names when it is available.
struct VisionReceiptScanner: ReceiptScanning {
    var recognizer: any ReceiptTextRecognizing = VisionTextRecognizer()
    var repairer: (any ReceiptNameRepairing)? = FoundationModelsNameRepairer()
    var defaultCurrencyCode = "USD"
    var locale = Locale.current

    /// One image per page, in reading order. A document camera result gives them in that order.
    func scan(_ images: [CGImage]) async -> ParsedReceipt {
        var pages: [[ReceiptTextLine]] = []
        for image in images {
            if Task.isCancelled { break }
            if let lines = try? await recognizer.recognizeLines(in: image), !lines.isEmpty {
                pages.append(lines)
            }
        }
        let options = ReceiptParsingOptions(defaultCurrencyCode: defaultCurrencyCode, locale: locale, referenceDate: Date())
        let parsed = ReceiptRowParser.parse(pages: pages, options: options)
        guard let repairer, !parsed.items.isEmpty else { return parsed }
        return await repairer.repairNames(in: parsed)
    }

    /// A photo from the library or the camera, as encoded image data. Orientation is applied.
    func scan(photoData: Data) async -> ParsedReceipt {
        guard let image = Self.upright(photoData) else { return await scan([]) }
        return await scan([image])
    }

    private static func upright(_ data: Data, maximumPixels: Int = 4000) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
