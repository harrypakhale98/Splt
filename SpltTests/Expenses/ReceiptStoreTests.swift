import Foundation
import SpltCore
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

    private func page(width: CGFloat, height: CGFloat, color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).jpegData(withCompressionQuality: 0.9) { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The red, green and blue of the pixel at a point counted from the top left, each 0 to 255.
    private func color(of image: CGImage, x: Int, y: Int) throws -> [Int] {
        let pixel = try #require(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Int(bytes[$0]) }
    }

    @Test func pagesOfAScanAreJoinedTopToBottom() throws {
        let first = page(width: 400, height: 600, color: .red)
        let second = page(width: 200, height: 150, color: .blue)
        let data = try #require(ReceiptStore.stitched([first, second]))
        let image = try #require(UIImage(data: data)?.cgImage)
        // the narrow page is drawn as wide as the first, so it is 300 tall
        #expect(image.width == 400)
        #expect(image.height == 900)
        let top = try color(of: image, x: 200, y: 300)
        let bottom = try color(of: image, x: 200, y: 750)
        #expect(top[0] > 200 && top[2] < 60)
        #expect(bottom[2] > 200 && bottom[0] < 60)
    }

    @Test func aLongScanIsScaledDownToWhatOnePhotoMayHold() throws {
        let pages = (0..<3).map { _ in page(width: 2_000, height: 2_000, color: .orange) }
        let data = try #require(ReceiptStore.stitched(pages))
        let image = try #require(UIImage(data: data)?.cgImage)
        #expect(image.width * image.height <= ReceiptStore.maximumPixels * ReceiptStore.maximumPixels)
        #expect(image.width > 1_100)
        #expect(abs(image.height - image.width * 3) <= 3)
    }

    @Test func oneReadablePageIsKeptAsItIs() {
        let only = page(width: 300, height: 400, color: .orange)
        #expect(ReceiptStore.stitched([only]) == only)
        #expect(ReceiptStore.stitched([Data("not an image".utf8), only]) == only)
        #expect(ReceiptStore.stitched([Data("not an image".utf8)]) == nil)
        #expect(ReceiptStore.stitched([]) == nil)
    }

    @Test func unreadableDataIsRejected() {
        #expect(ReceiptStore.compressed(Data("not an image".utf8)) == nil)
    }

    @Test func namesCannotEscapeTheFolder() {
        let store = store()
        let url = store.url(for: "../../secret.jpg")
        #expect(url.deletingLastPathComponent().lastPathComponent == store.directory.lastPathComponent)
    }

    @Test(arguments: ["..", ".", "", "/", "../..", "Thumbnails", "../Thumbnails", "secret.sqlite"])
    func aNameFromAnotherDeviceCannotReachOtherFiles(name: String) throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "splt-base-\(UUID().uuidString)")
        let store = ReceiptStore(directory: base.appending(path: "Receipts"))
        let kept = try store.save(photo(side: 50))
        let beside = base.appending(path: "default.store")
        try Data("store".utf8).write(to: beside)
        try Data("other".utf8).write(to: store.directory.appending(path: "secret.sqlite"))

        #expect(store.image(named: name) == nil)
        store.delete(name)
        #expect(store.exists(kept))
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: kept).path))
        #expect(FileManager.default.fileExists(atPath: beside.path))
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "secret.sqlite").path))
        try FileManager.default.removeItem(at: base)
    }

    @MainActor
    @Test func photosOfGroupsThatAreGoneAreRemoved() throws {
        let fixture = try Fixture()
        let store = store()
        let kept = try store.save(photo(side: 50))
        let softDeleted = try store.save(photo(side: 50))
        let inGoneGroup = try store.save(photo(side: 50))
        let unknown = try store.save(photo(side: 50))

        let live = fixture.expense("Live")
        try fixture.services.expenses.add(live, extras: ExpenseExtras(receiptFileName: kept))
        let removed = fixture.expense("Removed")
        try fixture.services.expenses.add(removed, extras: ExpenseExtras(receiptFileName: softDeleted))
        try fixture.services.expenses.delete(id: removed.id)

        let other = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id])
        try fixture.services.groups.create(other)
        let gone = Expense(
            groupID: other.id, title: "Gone", total: usdAmount(100), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .equal(participants: [fixture.me.id])
        )
        try fixture.services.expenses.add(gone, extras: ExpenseExtras(receiptFileName: inGoneGroup))
        // the way a delete that has reached the server looks: a tombstone, not a removed row
        let context = fixture.services.environment.context
        try #require(try GroupRecord.find(recordName: other.id.description, in: context)).deletedAt = fixture.clock.start
        try #require(try ExpenseRecord.find(recordName: gone.id.description, in: context)).deletedAt = fixture.clock.start
        try context.save()

        try store.removeUnreferenced(in: context)

        #expect(store.exists(kept))
        #expect(store.exists(softDeleted), "an undo can still bring it back")
        #expect(!store.exists(inGoneGroup))
        #expect(!store.exists(unknown))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: unknown).path))
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: kept).path))
    }

    @MainActor
    @Test func cleaningUpWithNoFolderDoesNothing() throws {
        let fixture = try Fixture()
        try store().removeUnreferenced(in: fixture.services.environment.context)
    }

    @Test func thumbnailsFallBackToThePhoto() throws {
        let store = store()
        let name = try store.save(photo(side: 200))
        try FileManager.default.removeItem(at: store.thumbnailURL(for: name))
        #expect(store.thumbnail(named: name) != nil)
    }
}
