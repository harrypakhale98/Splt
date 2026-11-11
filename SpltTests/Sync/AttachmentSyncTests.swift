import CloudKit
import Foundation
import SpltCore
import SwiftData
import Testing
import UIKit
@testable import Splt

@MainActor
@Suite("Photos carried by sync")
struct AttachmentSyncTests {
    private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
    }

    private func expenseWithReceipt(on phone: PopulatedDevice) throws -> (Expense, String) {
        let name = try phone.device.photos.store(.receipts).save(photo())
        let expense = Expense(
            groupID: phone.group.id, title: "Dinner", total: usdAmount(3000), date: phone.device.clock.start,
            paidBy: phone.me.id, split: .equal(participants: [phone.me.id, phone.sam.id])
        )
        try phone.device.services.expenses.add(expense, extras: ExpenseExtras(receiptFileName: name))
        return (expense, name)
    }

    private func sentExpense(_ records: [CKRecord], _ expense: Expense) throws -> CKRecord {
        try #require(records.first { $0.recordID.recordName == expense.id.description })
    }

    @Test func aReceiptReachesTheOtherPhone() throws {
        let phone = try PopulatedDevice()
        let (_, name) = try expenseWithReceipt(on: phone)
        let cloud = FakeCloud()
        try cloud.upload(from: phone.device)

        let other = try SyncDevice()
        try cloud.download(to: other)
        #expect(other.photos.store(.receipts).exists(name))
        #expect(other.photos.store(.receipts).thumbnail(named: name) != nil)
    }

    @Test func anUnchangedReceiptIsNotSentAgain() throws {
        let phone = try PopulatedDevice()
        let (expense, name) = try expenseWithReceipt(on: phone)
        let first = try sentExpense(phone.device.outgoing().records, expense)
        #expect(first["receipt"] is CKAsset)
        try FakeCloud().upload(from: phone.device)

        phone.device.clock.advance(by: 60)
        var renamed = expense
        renamed.title = "Late dinner"
        try phone.device.services.expenses.update(renamed, extras: ExpenseExtras(receiptFileName: name))
        let second = try sentExpense(phone.device.outgoing().records, expense)
        #expect(second["receipt"] == nil)
        #expect(!second.changedKeys().contains("receipt"))
    }

    @Test func removingAReceiptEmptiesTheAssetField() throws {
        let phone = try PopulatedDevice()
        let (expense, _) = try expenseWithReceipt(on: phone)
        try FakeCloud().upload(from: phone.device)

        phone.device.clock.advance(by: 60)
        try phone.device.services.expenses.update(expense, extras: ExpenseExtras(receiptFileName: nil))
        let sent = try sentExpense(phone.device.outgoing().records, expense)
        #expect(sent.changedKeys().contains("receipt"))
        #expect(sent["receipt"] == nil)
    }

    @Test func aReceiptThisPhoneLacksIsNeverPairedWithAnotherName() throws {
        let phone = try PopulatedDevice()
        let expense = Expense(
            groupID: phone.group.id, title: "Dinner", total: usdAmount(3000), date: phone.device.clock.start,
            paidBy: phone.me.id, split: .equal(participants: [phone.me.id, phone.sam.id])
        )
        try phone.device.services.expenses.add(expense, extras: ExpenseExtras(receiptFileName: "elsewhere.jpg"))
        try FakeCloud().upload(from: phone.device)

        phone.device.clock.advance(by: 60)
        var renamed = expense
        renamed.title = "Late dinner"
        try phone.device.services.expenses.update(renamed, extras: ExpenseExtras(receiptFileName: "elsewhere.jpg"))
        let sent = try sentExpense(phone.device.outgoing().records, expense)
        #expect(sent.changedKeys().contains("receipt"))
        #expect(sent["receipt"] == nil)
    }

    @Test func aCoverPhotoReachesTheOtherPhone() throws {
        let phone = try PopulatedDevice()
        let name = try phone.device.photos.store(.covers).save(photo())
        let tracker = phone.device.tracker
        let group = try #require(try GroupRecord.find(recordName: phone.zone, in: tracker.context))
        phone.device.clock.advance(by: 60)
        group.coverFileName = name
        tracker.recordEdit(group)
        try tracker.save()
        let cloud = FakeCloud()
        try cloud.upload(from: phone.device)

        let other = try SyncDevice()
        try cloud.download(to: other)
        #expect(other.photos.store(.covers).exists(name))
        let received = try #require(try GroupRecord.find(recordName: phone.zone, in: other.tracker.context))
        #expect(received.coverFileName == name)
    }

    @Test func somethingThatIsNotAPhotoIsNotKept() throws {
        let store = PhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: "adopt-" + UUID().uuidString))
        let text = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".txt")
        try Data("not a photo".utf8).write(to: text)
        #expect(!store.adopt(fileAt: text, named: "a.jpg"))
        #expect(!store.exists("a.jpg"))
        #expect(!store.adopt(fileAt: text, named: "../escape.jpg"))
    }
}

@MainActor
@Suite("Item claims")
struct ItemClaimTests {
    @Test func aPersonHasOneClaimPerExpenseOnEveryDevice() {
        let expense = UUID()
        let sam = UUID()
        let priya = UUID()
        #expect(ItemClaimRecord.claimID(expenseID: expense, personID: sam) == ItemClaimRecord.claimID(expenseID: expense, personID: sam))
        #expect(ItemClaimRecord.claimID(expenseID: expense, personID: sam) != ItemClaimRecord.claimID(expenseID: expense, personID: priya))
        #expect(ItemClaimRecord.claimID(expenseID: expense, personID: sam) != ItemClaimRecord.claimID(expenseID: UUID(), personID: sam))
    }

    @Test func aClaimSyncsToTheOtherPhone() throws {
        let phone = try PopulatedDevice()
        let expense = try phone.addExpense()
        let item = UUID()
        let tracker = phone.device.tracker
        let claim = ItemClaimRecord(
            groupID: phone.group.id.rawValue, expenseID: expense.id.rawValue, personID: phone.sam.id.rawValue,
            itemIDs: [item], createdAt: phone.device.clock.start
        )
        tracker.context.insert(claim)
        tracker.recordEdit(claim)
        try tracker.save()
        let cloud = FakeCloud()
        try cloud.upload(from: phone.device)

        let other = try SyncDevice()
        try cloud.download(to: other)
        let received = try #require(try ItemClaimRecord.find(recordName: claim.recordName, in: other.tracker.context))
        #expect(received.itemIDs == [item])
        #expect(received.personID == phone.sam.id.rawValue)
    }
}

@MainActor
@Suite("Store upgrade")
struct StoreUpgradeTests {
    @Test func aStoreSavedByVersionOneOpensWithItsData() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "upgrade-\(UUID().uuidString).store")
        let groupID = UUID()
        do {
            let schema = Schema(versionedSchema: SpltSchemaV1.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let group = SpltSchemaV1.GroupRecord()
            group.id = groupID
            group.name = "Flat"
            group.currencyCode = "USD"
            group.recordName = groupID.uuidString
            old.mainContext.insert(group)
            try old.mainContext.save()
        }
        let current = try ModelContainerFactory.make(url: url)
        let group = try #require(try GroupRecord.find(recordName: groupID.uuidString, in: current.mainContext))
        #expect(group.name == "Flat")
        #expect(group.coverFileName == nil)
        #expect(group.defaultSplitData == nil)
        #expect(try current.mainContext.fetch(FetchDescriptor<ItemClaimRecord>()).isEmpty)
    }
}
