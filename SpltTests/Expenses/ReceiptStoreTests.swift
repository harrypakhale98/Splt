import Foundation
import Testing
import UIKit
@testable import Splt

@Suite("Receipt store")
struct ReceiptStoreTests {
    private func store() -> ReceiptStore {
        ReceiptStore(directory: FileManager.default.temporaryDirectory.appending(path: "splt-store-\(UUID().uuidString)"))
    }

    private func photo(side: CGFloat) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side * 1.5)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side * 1.5))
        }
    }

    @Test func savesPhotoAndThumbnailThenDeletesBoth() throws {
        let store = store()
        let name = try store.save(photo(side: 400))
        #expect(name.hasSuffix(".jpg"))
        #expect(store.exists(name))
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: name).path))
        #expect(store.image(named: name) != nil)

        store.delete(name)
        #expect(!store.exists(name))
        #expect(store.thumbnail(named: name) == nil)
    }

    @Test func compressionShrinksLargeImages() throws {
        let big = photo(side: 3_000)
        let small = try #require(ReceiptStore.compressed(big))
        #expect(small.count < big.count)
        let image = try #require(UIImage(data: small))
        #expect(max(image.size.width, image.size.height) * image.scale <= CGFloat(ReceiptStore.maximumPixels))
    }

    @Test func unreadableDataIsRejected() {
        #expect(ReceiptStore.compressed(Data("not an image".utf8)) == nil)
    }

    @Test func namesCannotEscapeTheFolder() {
        let store = store()
        let url = store.url(for: "../../secret.jpg")
        #expect(url.deletingLastPathComponent().lastPathComponent == store.directory.lastPathComponent)
    }

    @Test func thumbnailsFallBackToThePhoto() throws {
        let store = store()
        let name = try store.save(photo(side: 200))
        try FileManager.default.removeItem(at: store.thumbnailURL(for: name))
        #expect(store.thumbnail(named: name) != nil)
    }
}
