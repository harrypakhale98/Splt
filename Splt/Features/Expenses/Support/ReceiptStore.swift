import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps receipt photos as files in Application Support, never inside the database. An expense
/// stores only the file name. A small thumbnail sits next to each photo for lists.
struct ReceiptStore: Sendable {
    let directory: URL

    static let maximumPixels = 2_000
    static let thumbnailPixels = 360

    /// The app's own receipt folder.
    static var standard: ReceiptStore {
        let base = URL.applicationSupportDirectory
        return ReceiptStore(directory: base.appending(path: "Receipts", directoryHint: .isDirectory))
    }

    private var thumbnails: URL { directory.appending(path: "Thumbnails", directoryHint: .isDirectory) }

    /// Re-encodes the photo as a JPEG no larger than `maximumPixels`, so a 12 megapixel scan stays small.
    static func compressed(_ data: Data) -> Data? {
        jpeg(from: data, maximumPixels: maximumPixels, quality: 0.8)
    }

    /// Writes already compressed image data and its thumbnail. Returns the file name to store on the expense.
    func save(_ imageData: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try imageData.write(to: url(for: name), options: .atomic)
        if let thumbnail = Self.jpeg(from: imageData, maximumPixels: Self.thumbnailPixels, quality: 0.7) {
            try thumbnail.write(to: thumbnailURL(for: name), options: .atomic)
        }
        return name
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: Self.safeName(fileName), directoryHint: .notDirectory)
    }

    func thumbnailURL(for fileName: String) -> URL {
        thumbnails.appending(path: Self.safeName(fileName), directoryHint: .notDirectory)
    }

    func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    func image(named fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    /// The thumbnail, or the photo itself when the thumbnail is missing.
    func thumbnail(named fileName: String) -> Data? {
        (try? Data(contentsOf: thumbnailURL(for: fileName))) ?? image(named: fileName)
    }

    func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
        try? FileManager.default.removeItem(at: thumbnailURL(for: fileName))
    }

    /// Strips any folder part so a stored name can never point outside the receipt folder.
    private static func safeName(_ fileName: String) -> String {
        (fileName as NSString).lastPathComponent
    }

    private static func jpeg(from data: Data, maximumPixels: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
