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
