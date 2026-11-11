import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Keeps photos as files in Application Support, never inside the database: receipts of expenses and
/// cover photos of groups, each in their own folder. A record stores only the file name, and sync
/// carries the file itself next to the record. A small thumbnail sits next to each photo for lists.
struct PhotoStore: Sendable {
    let directory: URL

    static let maximumPixels = 2_000
    static let thumbnailPixels = 360

    /// The largest photo taken from a synced record. Others in a shared group can upload anything,
    /// and a photo saved by this app is far smaller.
    static let maximumIncomingBytes = 20_000_000

    /// The app's own receipt folder.
    static var receipts: PhotoStore {
        PhotoStore(directory: URL.applicationSupportDirectory.appending(path: "Receipts", directoryHint: .isDirectory))
    }

    /// The app's own folder of group cover photos.
    static var covers: PhotoStore {
        PhotoStore(directory: URL.applicationSupportDirectory.appending(path: "Covers", directoryHint: .isDirectory))
    }

    private var thumbnails: URL { directory.appending(path: "Thumbnails", directoryHint: .isDirectory) }

    /// Re-encodes the photo as a JPEG no larger than `maximumPixels`, so a 12 megapixel scan stays small.
    static func compressed(_ data: Data) -> Data? {
        jpeg(from: data, maximumPixels: maximumPixels, quality: 0.8)
    }

    /// Joins the pages of one scan, top to bottom, into a single photo, as an expense keeps one receipt.
    /// Every page is drawn as wide as the widest. Together they hold no more pixels than one photo may
    /// (`maximumPixels` squared), so a long scan is scaled down rather than squeezed to an unreadable strip.
    /// Nil when no page can be read.
    static func stitched(_ pages: [Data]) -> Data? {
        let readable = pages.compactMap { data -> (data: Data, image: CGImage)? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else { return nil }
            return (data, image)
        }
        guard readable.count > 1 else { return readable.first?.data }
        let images = readable.map(\.image)

        var width = Double(images.map(\.width).max() ?? 0)
        var heights = images.map { Double($0.height) * width / Double($0.width) }
        let pixels = width * heights.reduce(0, +)
        let limit = Double(maximumPixels * maximumPixels)
        if pixels > limit {
            let factor = (limit / pixels).squareRoot()
            width *= factor
            heights = heights.map { $0 * factor }
        }
        let rows = heights.map { max(Int($0), 1) }
        let size = (width: max(Int(width), 1), height: rows.reduce(0, +))
        guard let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // The context counts up from the bottom, and the first page goes at the top.
        var top = size.height
        for (image, row) in zip(images, rows) {
            top -= row
            context.draw(image, in: CGRect(x: 0, y: top, width: size.width, height: row))
        }
        return context.makeImage().flatMap { encoded($0, quality: 0.8) }
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

    /// Keeps a photo that arrived with a synced record under the name the record gives it, with a fresh
    /// thumbnail. Returns false, keeping nothing, when the file is too large or not a readable image.
    /// A photo already here is left as it is: names are unique, so it is the same photo.
    @discardableResult
    func adopt(fileAt source: URL, named fileName: String) -> Bool {
        guard Self.safeName(fileName) == (fileName as NSString).lastPathComponent else { return false }
        if exists(fileName) { return true }
        guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumIncomingBytes,
              let data = try? Data(contentsOf: source) else { return false }
        return keep(data, named: fileName)
    }

    /// Keeps a photo from a file that cannot be trusted, such as a backup, under a name the app chose.
    /// Returns false, keeping nothing, when it is too large or not a readable image. A photo already
    /// here under that name is left as it is.
    @discardableResult
    func keep(_ data: Data, named fileName: String) -> Bool {
        guard Self.safeName(fileName) == (fileName as NSString).lastPathComponent else { return false }
        if exists(fileName) { return true }
        guard data.count <= Self.maximumIncomingBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return false }
        do {
            try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
            try data.write(to: url(for: fileName), options: .atomic)
            if let thumbnail = Self.jpeg(from: data, maximumPixels: Self.thumbnailPixels, quality: 0.7) {
                try thumbnail.write(to: thumbnailURL(for: fileName), options: .atomic)
            }
            return true
        } catch {
            return false
        }
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

    /// Removes the receipts no expense can show again, because the expense or its whole group is gone.
    /// A deleted expense in a live group keeps its photo, as an undo can bring it back.
    @MainActor
    func removeUnreferenced(in context: ModelContext) throws {
        let groups = Set(try context.fetch(FetchDescriptor<GroupRecord>(predicate: #Predicate { $0.deletedAt == nil })).map(\.id))
        let expenses = try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.receiptFileName != nil }))
        let kept = Set(expenses
            .filter { $0.deletedAt == nil || $0.groupID.map(groups.contains) == true }
            .compactMap(\.receiptFileName))
        removeAll(except: kept)
    }

    /// Removes the cover photos no live group shows.
    @MainActor
    func removeUnreferencedCovers(in context: ModelContext) throws {
        let groups = try context.fetch(FetchDescriptor<GroupRecord>(predicate: #Predicate { $0.deletedAt == nil }))
        removeAll(except: Set(groups.compactMap(\.coverFileName)))
    }

    private func removeAll(except kept: Set<String>) {
        for folder in [directory, thumbnails] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jpg" && !kept.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// The name comes from a synced record, so it can be anything. A last path component can still be `..`,
    /// which is Application Support with the store in it, so only a photo's name gets through.
    private static func safeName(_ fileName: String) -> String {
        let name = (fileName as NSString).lastPathComponent
        return name.hasSuffix(".jpg") ? name : "missing.jpg"
    }

    private static func jpeg(from data: Data, maximumPixels: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encoded(image, quality: quality)
    }

    private static func encoded(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
