import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

/// Anyone in a shared group can write any record into its zone, with any name and any fields.
/// None of that may reach further than that one group.
@MainActor
@Suite("Records from other people")
struct UntrustedRecordTests {
    /// A device with its own private group, and a group shared by Mallory.
    @MainActor
    private struct Victim {
        let populated: PopulatedDevice
        let shared: SplitGroup
        let sharedZone: CKRecordZone.ID
        let expense: Expense

        var device: SyncDevice { populated.device }
        var adapter: SyncStoreAdapter { populated.device.adapter }
        var privateZone: String { populated.zone }
        var later: Date { device.clock.start.addingTimeInterval(86_400) }

        init() throws {
            populated = try PopulatedDevice()
            expense = try populated.addExpense()
            try FakeCloud().upload(from: populated.device)
            shared = SplitGroup(name: "Mallory's", currencyCode: "USD", memberIDs: [populated.me.id])
            sharedZone = CKRecordZone.ID(zoneName: shared.id.description, ownerName: "_mallory")
            let record = RecordMapper.record(
                for: SyncPayload(
                    recordType: .group, recordName: shared.id.description, zoneName: shared.id.description,
                    modifiedAt: populated.device.clock.start, fields: GroupRecord(shared).syncFields
                ), in: sharedZone
            )
            try populated.device.adapter.applyFetched(modifications: [record], deletions: [])
        }

        func crafted(_ type: SyncRecordType, name: String, in zone: CKRecordZone.ID, deletedAt: Date? = nil, fields: SyncFields) -> CKRecord {
            RecordMapper.record(
                for: SyncPayload(
                    recordType: type, recordName: name, zoneName: zone.zoneName,
                    modifiedAt: later, deletedAt: deletedAt, fields: fields
                ), in: zone
            )
        }

        func expenseFields(title: String, groupID: UUID?) throws -> SyncFields {
            let stored = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: device.tracker.context))
            var fields = stored.syncFields
            fields.set("title", title)
            fields.set("groupID", groupID)
            return fields
        }

        func storedExpense() throws -> ExpenseRecord {
            try #require(try ExpenseRecord.find(recordName: expense.id.description, in: device.tracker.context))
        }
    }

    // MARK: Between groups

    @Test func aRecordCannotTakeOverOneFromAnotherGroup() throws {
        let victim = try Victim()
        let record = victim.crafted(
            .expense, name: victim.expense.id.description, in: victim.sharedZone,
            fields: try victim.expenseFields(title: "Hijacked", groupID: victim.shared.id.rawValue)
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        let stored = try victim.storedExpense()
        #expect(stored.title == "Dinner")
        #expect(stored.zoneName == victim.privateZone)
        #expect(stored.groupID == victim.populated.group.id.rawValue)
    }

    @Test func aGroupRecordCannotTakeOverAnotherGroup() throws {
        let victim = try Victim()
        var fields = GroupRecord(victim.populated.group).syncFields
        fields.set("name", "Hijacked")
        let record = victim.crafted(.group, name: victim.populated.group.id.description, in: victim.sharedZone, fields: fields)
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        let stored = try #require(try victim.device.services.groups.group(id: victim.populated.group.id))
        #expect(stored.name == "Flat")
        let model = try #require(try GroupRecord.find(recordName: stored.id.description, in: victim.device.tracker.context))
        #expect(model.zoneName == victim.privateZone)
    }

    @Test(arguments: [SyncRecordType.expense, .payment, .comment, .activity, .recurringExpense])
    func aNewRecordCannotClaimAnotherGroup(type: SyncRecordType) throws {
        let victim = try Victim()
        let source = try #require(try sampleFields(type: type, on: victim))
        var fields = source
        fields.set("groupID", victim.populated.group.id.rawValue)
        let name = UUID().uuidString
        let record = victim.crafted(type, name: name, in: victim.sharedZone, fields: fields)
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(try type.modelType.find(recordName: name, in: victim.device.tracker.context) == nil)
    }

    @Test func aRecordWithTheGroupOfItsOwnZoneIsApplied() throws {
        let victim = try Victim()
        let name = UUID().uuidString
        let record = victim.crafted(
            .expense, name: name, in: victim.sharedZone,
            fields: try victim.expenseFields(title: "Lunch", groupID: victim.shared.id.rawValue)
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        let stored = try #require(try ExpenseRecord.find(recordName: name, in: victim.device.tracker.context))
        #expect(stored.zoneName == victim.shared.id.description)
    }

    @Test func aDeleteInOneZoneLeavesARecordOfAnotherGroup() throws {
        let victim = try Victim()
        let id = CKRecord.ID(recordName: victim.expense.id.description, zoneID: victim.sharedZone)
        try victim.adapter.applyFetched(modifications: [], deletions: [(id, "Expense")])
        #expect(try victim.storedExpense().deletedAt == nil)
    }

    @Test func aCommentOnAnExpenseOfAnotherGroupIsNotShown() throws {
        let victim = try Victim()
        var fields = SyncFields()
        fields.set("groupID", victim.shared.id.rawValue)
        fields.set("expenseID", victim.expense.id.rawValue)
        fields.set("authorID", victim.populated.sam.id.rawValue)
        fields.set("text", "Planted")
        fields.set("createdAt", victim.later)
        let record = victim.crafted(.comment, name: UUID().uuidString, in: victim.sharedZone, fields: fields)
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(try victim.device.services.comments.comments(on: victim.expense.id).isEmpty)
    }

    private func sampleFields(type: SyncRecordType, on victim: Victim) throws -> SyncFields? {
        try victim.populated.addEverythingElse()
        let context = victim.device.tracker.context
        for change in try victim.device.tracker.pendingChanges() where change.recordType == type {
            return try type.modelType.find(recordName: change.recordName, in: context)?.syncFields
        }
        return nil
    }

    // MARK: A zone with the name of a group on this device

    @Test func anotherOwnersZoneWithTheSameNameIsNotThatGroup() throws {
        let victim = try Victim()
        let group = victim.populated.group
        let impostor = CKRecordZone.ID(zoneName: victim.privateZone, ownerName: "_mallory")
        victim.adapter.registerZone(impostor)
        #expect(victim.adapter.metadata.zoneID(forZoneName: victim.privateZone).ownerName == CKCurrentUserDefaultName)

        let record = victim.crafted(
            .expense, name: victim.expense.id.description, in: impostor,
            fields: try victim.expenseFields(title: "Hijacked", groupID: group.id.rawValue)
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [(
            CKRecord.ID(recordName: victim.expense.id.description, zoneID: impostor), "Expense"
        )])
        let stored = try victim.storedExpense()
        #expect(stored.title == "Dinner")
        #expect(stored.deletedAt == nil)
        #expect(victim.adapter.metadata.zoneID(forZoneName: victim.privateZone).ownerName == CKCurrentUserDefaultName)

        // later edits still go to the real zone
        var edited = victim.expense
        edited.title = "Supper"
        try victim.device.services.expenses.update(edited, extras: nil)
        let plan = try victim.adapter.collectOutgoing()
        #expect(!plan.saves.isEmpty)
        #expect(plan.saves.allSatisfy { $0.zoneID.ownerName == CKCurrentUserDefaultName })
    }

    @Test func deletingAZoneWithTheSameNameLeavesTheGroupAlone() throws {
        let victim = try Victim()
        let impostor = CKRecordZone.ID(zoneName: victim.privateZone, ownerName: "_mallory")
        let needsSend = try victim.adapter.zoneDeleted(impostor, reason: .deleted)
        #expect(!needsSend)
        #expect(try victim.storedExpense().deletedAt == nil)
        #expect(try victim.device.services.groups.group(id: victim.populated.group.id) != nil)
        #expect(victim.adapter.metadata.isKnown(zoneName: victim.privateZone))
    }

    @Test func theRealZoneOfAKnownGroupIsStillApplied() throws {
        let victim = try Victim()
        let name = UUID().uuidString
        let record = victim.crafted(
            .expense, name: name, in: victim.sharedZone,
            fields: try victim.expenseFields(title: "Lunch", groupID: victim.shared.id.rawValue)
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(try ExpenseRecord.find(recordName: name, in: victim.device.tracker.context) != nil)
    }

    // MARK: People

    private func personFields(_ person: Person, name: String) -> SyncFields {
        var fields = PersonRecord(person).syncFields
        fields.set("name", name)
        return fields
    }

    @Test func aRecordCannotDeleteAPerson() throws {
        let victim = try Victim()
        let sam = victim.populated.sam
        let record = victim.crafted(
            .person, name: sam.id.description, in: victim.sharedZone, deletedAt: victim.later,
            fields: personFields(sam, name: "Sam")
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(try victim.device.services.people.person(id: sam.id) != nil)
    }

    @Test func aRecordCannotDeleteYourOwnProfile() throws {
        let victim = try Victim()
        let me = victim.populated.me
        let record = victim.crafted(
            .person, name: me.id.description, in: victim.sharedZone, deletedAt: victim.later,
            fields: personFields(me, name: "Me")
        )
        try victim.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(try victim.device.services.people.me()?.id == me.id)
    }

    @Test func onlyYourOwnDevicesCanRenameYou() throws {
        let victim = try Victim()
        let me = victim.populated.me
        victim.adapter.updateMetadata { $0.userRecordName = "_me" }
        var author = "_mallory"
        victim.adapter.lastModifier = { _ in author }
        let renamed = victim.crafted(.person, name: me.id.description, in: victim.sharedZone, fields: personFields(me, name: "Clown"))
        try victim.adapter.applyFetched(modifications: [renamed], deletions: [])
        #expect(try victim.device.services.people.me()?.name == "Me")

        author = "_me"
        let mine = victim.crafted(.person, name: me.id.description, in: victim.sharedZone, fields: personFields(me, name: "Mia"))
        try victim.adapter.applyFetched(modifications: [mine], deletions: [])
        #expect(try victim.device.services.people.me()?.name == "Mia")

        author = CKCurrentUserDefaultName
        let again = victim.crafted(.person, name: me.id.description, in: victim.sharedZone, fields: personFields(me, name: "Max"))
        try victim.adapter.applyFetched(modifications: [again], deletions: [])
        #expect(try victim.device.services.people.me()?.name == "Max")
    }

    @Test func aPersonCopyDeletedInASharedZoneStaysOnThisDevice() throws {
        let victim = try Victim()
        let sam = victim.populated.sam
        let copy = victim.crafted(.person, name: sam.id.description, in: victim.sharedZone, fields: personFields(sam, name: "Sam"))
        try victim.adapter.applyFetched(modifications: [copy], deletions: [])
        victim.adapter.updateMetadata { $0.setCopy(nil, zoneName: victim.privateZone, recordName: sam.id.description) }
        try victim.adapter.applyFetched(modifications: [], deletions: [(copy.recordID, "Person")])
        #expect(try victim.device.services.people.person(id: sam.id) != nil)
    }

    // MARK: Amounts

    @Test(arguments: [Int64.max, Int64.min, MoneyParser.maximumMinorUnits + 1])
    func anAmountNobodyCanEnterIsRefused(amount: Int64) throws {
        let victim = try Victim()
        var expense = try victim.expenseFields(title: "Big", groupID: victim.shared.id.rawValue)
        expense.set("totalMinorUnits", amount)
        var payment = SyncFields()
        payment.set("groupID", victim.shared.id.rawValue)
        payment.set("amountMinorUnits", amount)
        payment.set("currencyCode", "USD")
        let records = [
            victim.crafted(.expense, name: UUID().uuidString, in: victim.sharedZone, fields: expense),
            victim.crafted(.payment, name: UUID().uuidString, in: victim.sharedZone, fields: payment),
        ]
        try victim.adapter.applyFetched(modifications: records, deletions: [])
        let context = victim.device.tracker.context
        #expect(try ExpenseRecord.find(recordName: records[0].recordID.recordName, in: context) == nil)
        #expect(try PaymentRecord.find(recordName: records[1].recordID.recordName, in: context) == nil)
    }

    @Test func aHugeAmountInsideTheSplitOrThePayersIsRefused() throws {
        let victim = try Victim()
        let huge = Money(minorUnits: .max, currencyCode: "USD")
        let me = victim.populated.me.id
        var payers = try victim.expenseFields(title: "Payers", groupID: victim.shared.id.rawValue)
        payers.set("payers", RecordCoding.encode([me: huge]))
        var split = try victim.expenseFields(title: "Split", groupID: victim.shared.id.rawValue)
        split.set("split", RecordCoding.encode(SplitDefinition.exact(amounts: [me: huge])))
        let records = [
            victim.crafted(.expense, name: UUID().uuidString, in: victim.sharedZone, fields: payers),
            victim.crafted(.expense, name: UUID().uuidString, in: victim.sharedZone, fields: split),
        ]
        try victim.adapter.applyFetched(modifications: records, deletions: [])
        let context = victim.device.tracker.context
        #expect(try ExpenseRecord.find(recordName: records[0].recordID.recordName, in: context) == nil)
        #expect(try ExpenseRecord.find(recordName: records[1].recordID.recordName, in: context) == nil)
    }
}
