import CloudKit
import Foundation
import SpltCore
import SwiftData
import Testing
import UIKit
@testable import Splt

/// Photos from before 1.1, when only the file name synced, are sent once without changing their records.
@MainActor
@Suite("Photos from before 1.1")
struct PhotoBackfillTests {
    private func photoFile() throws -> URL {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "backfill-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "splt-backfill-\(UUID().uuidString)") ?? .standard
    }

    /// An expense that 1.0 synced: the server has its receipt's name but no photo. The photo is on this phone.
    private func oldReceipt(on phone: PopulatedDevice, cloud: FakeCloud, fileHere: Bool = true) throws -> (Expense, String) {
        let name = UUID().uuidString + ".jpg"
        let expense = Expense(
            groupID: phone.group.id, title: "Dinner", total: usdAmount(3000), date: phone.device.clock.start,
            paidBy: phone.me.id, split: .equal(participants: [phone.me.id, phone.sam.id])
        )
        try phone.device.services.expenses.add(expense, extras: ExpenseExtras(receiptFileName: name))
        try cloud.upload(from: phone.device)
        if fileHere {
            #expect(phone.device.photos.store(.receipts).adopt(fileAt: try photoFile(), named: name))
        }
        return (expense, name)
    }

    private func expenseRecord(_ expense: Expense, on device: SyncDevice) throws -> ExpenseRecord {
        try #require(try ExpenseRecord.find(recordName: expense.id.description, in: device.tracker.context))
    }

    private func queue(_ device: SyncDevice) throws -> Int {
        try PhotoBackfill.queue(
            tracker: device.tracker, receipts: device.photos.store(.receipts), covers: device.photos.store(.covers)
        )
    }

    @Test func anOldReceiptIsSentWithoutChangingTheExpense() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, name) = try oldReceipt(on: phone, cloud: cloud)
        let before = try expenseRecord(expense, on: phone.device).modifiedAt
        #expect(try phone.device.outgoing().records.isEmpty)

        #expect(try queue(phone.device) == 1)
        let record = try expenseRecord(expense, on: phone.device)
        #expect(record.isDirty)
        #expect(record.modifiedAt == before)
        let sent = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == expense.id.description })
        #expect(sent["receipt"] is CKAsset)

        try cloud.upload(from: phone.device)
        #expect(try !expenseRecord(expense, on: phone.device).isDirty)
        let other = try SyncDevice()
        try cloud.download(to: other)
        #expect(other.photos.store(.receipts).exists(name))
    }

    @Test func aReceiptThatIsNotOnThisPhoneIsLeftAlone() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud, fileHere: false)
        #expect(try queue(phone.device) == 0)
        #expect(try !expenseRecord(expense, on: phone.device).isDirty)
    }

    @Test func aDeletedExpenseIsLeftAlone() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud)
        try phone.device.services.expenses.delete(id: expense.id)
        try cloud.upload(from: phone.device)
        #expect(try queue(phone.device) == 0)
    }

    @Test func aCoverIsSentToo() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        try cloud.upload(from: phone.device)
        // a cover named on the group whose photo the server never got
        let name = UUID().uuidString + ".jpg"
        let group = try #require(try GroupRecord.find(recordName: phone.zone, in: phone.device.tracker.context))
        group.coverFileName = name
        try phone.device.tracker.save()
        #expect(phone.device.photos.store(.covers).adopt(fileAt: try photoFile(), named: name))
        let before = group.modifiedAt

        #expect(try queue(phone.device) == 1)
        #expect(group.modifiedAt == before)
        let sent = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == phone.zone })
        #expect(sent["cover"] is CKAsset)
    }

    @Test func itRunsOnlyOnce() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let store = defaults()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud)
        let receipts = phone.device.photos.store(.receipts), covers = phone.device.photos.store(.covers)

        PhotoBackfill.runOnce(tracker: phone.device.tracker, receipts: receipts, covers: covers, defaults: store)
        #expect(store.bool(forKey: PhotoBackfill.doneKey))
        try cloud.upload(from: phone.device)
        #expect(try !expenseRecord(expense, on: phone.device).isDirty)

        PhotoBackfill.runOnce(tracker: phone.device.tracker, receipts: receipts, covers: covers, defaults: store)
        #expect(try !expenseRecord(expense, on: phone.device).isDirty)
    }

    @Test func aNewerEditElsewhereStillWins() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud)
        let other = try SyncDevice(start: 1_750_000_500)
        try cloud.download(to: other)
        var renamed = expense
        renamed.title = "Late dinner"
        try other.services.expenses.update(renamed)
        try cloud.upload(from: other)

        // this phone's clock is now far ahead: had the pass stamped a new edit date, its copy would win
        phone.device.clock.advance(by: 10_000)
        #expect(try queue(phone.device) == 1)
        try cloud.download(to: phone.device)
        #expect(try phone.device.services.expenses.expense(id: expense.id)?.title == "Late dinner")
    }

    /// Another phone edits the expense after 1.0 synced it. Its copy has the name but no photo.
    private func newerEditElsewhere(of expense: Expense, phone: PopulatedDevice, cloud: FakeCloud) throws -> SyncDevice {
        let other = try SyncDevice(start: 1_750_000_500)
        try cloud.download(to: other)
        var renamed = expense
        renamed.title = "Late dinner"
        try other.services.expenses.update(renamed)
        try cloud.upload(from: other)
        phone.device.clock.advance(by: 10_000)
        return other
    }

    @Test func thePhotoStillGoesUpWhenANewerEditArrives() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, name) = try oldReceipt(on: phone, cloud: cloud)
        let other = try newerEditElsewhere(of: expense, phone: phone, cloud: cloud)
        #expect(try queue(phone.device) == 1)

        let report = try cloud.download(to: phone.device)
        #expect(report.requeue.contains { $0.recordName == expense.id.description })
        #expect(try expenseRecord(expense, on: phone.device).isDirty)
        let sent = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == expense.id.description })
        #expect(sent["receipt"] is CKAsset)
        #expect(sent["title"] as? String == "Late dinner")

        try cloud.upload(from: phone.device)
        try cloud.download(to: other)
        #expect(other.photos.store(.receipts).exists(name))
        #expect(try other.services.expenses.expense(id: expense.id)?.title == "Late dinner")
    }

    @Test func thePhotoStillGoesUpWhenTheUploadLosesAConflict() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud)
        _ = try newerEditElsewhere(of: expense, phone: phone, cloud: cloud)
        #expect(try queue(phone.device) == 1)
        let sent = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == expense.id.description })
        let server = try #require(cloud.records[sent.recordID])

        let outcome = try phone.device.adapter.saveFailed(record: sent, error: CKError(.serverRecordChanged, userInfo: [
            CKRecordChangedErrorServerRecordKey: server, CKRecordChangedErrorClientRecordKey: sent,
        ]))
        #expect(outcome.requeue)
        #expect(try phone.device.services.expenses.expense(id: expense.id)?.title == "Late dinner")
        let again = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == expense.id.description })
        #expect(again["receipt"] is CKAsset)
    }

    @Test func aServerCopyWithTheSamePhotoIsNotSentAgain() throws {
        let phone = try PopulatedDevice()
        let cloud = FakeCloud()
        let (expense, _) = try oldReceipt(on: phone, cloud: cloud)
        #expect(try queue(phone.device) == 1)
        try cloud.upload(from: phone.device)
        var renamed = expense
        renamed.title = "Lunch"
        try phone.device.services.expenses.update(renamed)
        let sent = try #require(try phone.device.outgoing().records.first { $0.recordID.recordName == expense.id.description })
        let server = try #require(cloud.records[sent.recordID])
        server[RecordSchema.modifiedAtKey] = (server[RecordSchema.modifiedAtKey] as? Date)?.addingTimeInterval(100_000)

        let outcome = try phone.device.adapter.saveFailed(record: sent, error: CKError(.serverRecordChanged, userInfo: [
            CKRecordChangedErrorServerRecordKey: server, CKRecordChangedErrorClientRecordKey: sent,
        ]))
        #expect(!outcome.requeue)
        #expect(try !expenseRecord(expense, on: phone.device).isDirty)
    }
}
