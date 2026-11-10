import CloudKit
import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Sync store adapter")
struct SyncStoreAdapterTests {
    private func names(_ ids: [CKRecord.ID], _ device: SyncDevice, of type: SyncRecordType) throws -> [String] {
        try ids.filter { try device.adapter.resolveType(of: $0) == type }.map(\.recordName)
    }

    @Test func aNewGroupPlansItsZoneAndItsRecords() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let plan = try populated.device.adapter.collectOutgoing()
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        #expect(plan.zonesToSave == [zone])
        #expect(plan.zonesToDelete.isEmpty)
        #expect(plan.saves.allSatisfy { $0.zoneID == zone })
        let device = populated.device
        #expect(try names(plan.saves, device, of: .group) == [populated.zone])
        #expect(try names(plan.saves, device, of: .expense).count == 1)
        let copies = Set(try names(plan.saves, device, of: .person))
        #expect(copies == Set([populated.me.id, populated.sam.id, populated.priya.id].map(\.description)))
    }

    @Test func uploadedRecordsAreMarkedSyncedAndNothingIsLeft() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        let plan = try cloud.upload(from: populated.device)
        #expect(!plan.saves.isEmpty)
        let after = try populated.device.adapter.collectOutgoing()
        #expect(after.isEmpty)
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
        #expect(populated.device.adapter.metadata.zones[populated.zone]?.scope == .privateDatabase)
        #expect(populated.device.adapter.metadata.personQueue.isEmpty)
    }

    @Test func aSecondDeviceReceivesEverythingWithoutMarkingItDirty() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let other = try SyncDevice()
        let report = try cloud.download(to: other)
        #expect(report.requeue.isEmpty)
        #expect(!report.inserted.isEmpty)
        #expect(try other.tracker.pendingChanges().isEmpty)
        let services = other.services
        let group = try #require(try services.groups.group(id: populated.group.id))
        #expect(group.name == "Flat")
        #expect(try services.expenses.expenses(in: group.id).count == 1)
        #expect(try services.payments.payments(in: group.id).count == 1)
        #expect(try services.recurring.templates(in: group.id).count == 1)
        #expect(try services.people.person(id: populated.sam.id)?.name == "Sam")
        let person = try #require(try PersonRecord.find(recordName: populated.sam.id.description, in: other.tracker.context))
        #expect(person.zoneName == nil)
        #expect(person.systemFields == nil)
        #expect(other.adapter.metadata.copy(zoneName: populated.zone, recordName: person.recordName) != nil)
    }

    @Test func editsUploadOnlyTheChangedRecord() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var edited = expense
        edited.title = "Dinner at Maria's"
        try populated.device.services.expenses.update(edited)
        let plan = try populated.device.adapter.collectOutgoing()
        let changed = try plan.saves.filter { try populated.device.adapter.resolveType(of: $0) == .expense }
        #expect(changed.map(\.recordName) == [expense.id.description])
        #expect(plan.zonesToSave.isEmpty)
        let record = try #require(try populated.device.adapter.outgoingRecord(for: changed[0]))
        #expect(record["title"] as? String == "Dinner at Maria's")
    }

    @Test func renamingAPersonResendsOnlyTheirCopies() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var renamed = populated.sam
        renamed.name = "Samuel"
        try populated.device.services.people.update(renamed)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.saves.map(\.recordName) == [populated.sam.id.description])
        try cloud.upload(from: populated.device)
        #expect(try populated.device.adapter.collectOutgoing().isEmpty)
        let record = try #require(cloud.records.values.first { $0.recordID.recordName == populated.sam.id.description })
        #expect(record["name"] as? String == "Samuel")
    }

    @Test func aPersonInTwoGroupsIsCopiedIntoBothZones() throws {
        let populated = try PopulatedDevice()
        let second = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [populated.me.id, populated.sam.id])
        try populated.device.services.groups.create(second)
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let metadata = populated.device.adapter.metadata
        #expect(metadata.zonesHoldingCopy(of: populated.sam.id.description).count == 2)
        #expect(metadata.zonesHoldingCopy(of: populated.priya.id.description) == [populated.zone])

        var renamed = populated.sam
        renamed.name = "Samuel"
        try populated.device.services.people.update(renamed)
        let plan = try cloud.upload(from: populated.device)
        #expect(plan.saves.count == 2)
        #expect(plan.saves.allSatisfy { $0.recordName == populated.sam.id.description })

        try populated.device.services.removePerson(populated.sam.id)
        let deletion = try cloud.upload(from: populated.device)
        #expect(deletion.deletes.count == 2)
        #expect(try populated.device.adapter.collectOutgoing().isEmpty)
        #expect(populated.device.adapter.metadata.zonesHoldingCopy(of: populated.sam.id.description).isEmpty)
    }

    @Test func aFriendAddedToAnExistingGroupIsCopiedWhenTheGroupChanges() throws {
        let populated = try PopulatedDevice()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let maya = Person(name: "Maya", avatarSeed: 3, createdAt: populated.device.clock.start)
        try populated.device.services.people.add(maya)
        try populated.device.services.groups.addMember(maya.id, to: populated.group.id)
        let plan = try cloud.upload(from: populated.device)
        #expect(plan.saves.map(\.recordName).contains(maya.id.description))
        #expect(populated.device.adapter.metadata.copy(zoneName: populated.zone, recordName: maya.id.description) != nil)
    }

    @Test func aPersonOutsideEveryGroupIsSettledWithoutUploading() throws {
        let populated = try PopulatedDevice()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let loner = Person(name: "Loner", avatarSeed: 4, createdAt: populated.device.clock.start)
        try populated.device.services.people.add(loner)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.isEmpty)
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
    }

    @Test func hardDeletedRecordsAreDeletedOnTheServerAndConfirmed() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let comment = ExpenseComment(
            groupID: populated.group.id, expenseID: expense.id, authorID: populated.me.id, text: "hi",
            createdAt: populated.device.clock.start
        )
        try populated.device.services.comments.add(comment)
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try populated.device.services.comments.delete(id: comment.id)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.deletes.map(\.recordName) == [comment.id.uuidString])
        try cloud.upload(from: populated.device)
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
        #expect(cloud.records.keys.allSatisfy { $0.recordName != comment.id.uuidString })
    }

    @Test func softDeletedExpensesUploadAsSavesWithTheTombstone() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try populated.device.services.expenses.delete(id: expense.id)
        let plan = try cloud.upload(from: populated.device)
        #expect(plan.deletes.isEmpty)
        let record = try #require(cloud.records.values.first { $0.recordID.recordName == expense.id.description })
        #expect(record[RecordSchema.deletedAtKey] as? Date != nil)
    }

    @Test func deletingAGroupDeletesItsZoneInsteadOfEveryRecord() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try populated.device.services.groups.delete(id: populated.group.id)
        let plan = try populated.device.adapter.collectOutgoing()
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        #expect(plan.zonesToDelete == [zone])
        #expect(plan.deletes.isEmpty)
        try cloud.upload(from: populated.device)
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
        #expect(populated.device.adapter.metadata.zones[populated.zone] == nil)
        let remaining = try populated.device.tracker.context.fetch(FetchDescriptor<ExpenseRecord>())
        #expect(remaining.isEmpty)
    }

    @Test func removingASharedGroupLeavesTheShareInsteadOfDeletingForEveryone() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let owner = CKRecordZone.ID(zoneName: populated.zone, ownerName: "_ownerRecord")
        populated.device.adapter.registerZone(owner)
        let stored = try #require(try GroupRecord.find(recordName: populated.zone, in: populated.device.tracker.context))
        stored.systemFields = Data([1])
        try populated.device.services.groups.delete(id: populated.group.id)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.zonesToLeave == [owner])
        #expect(plan.zonesToDelete.isEmpty)
        #expect(plan.deletes.isEmpty)
        #expect(plan.part(for: .sharedDatabase).zonesToLeave == [owner])
        #expect(plan.part(for: .privateDatabase).isEmpty)
    }

    @Test func recordsInASharedZoneUseTheOwnersZoneID() throws {
        let populated = try PopulatedDevice()
        let owner = CKRecordZone.ID(zoneName: populated.zone, ownerName: "_ownerRecord")
        populated.device.adapter.registerZone(owner)
        let expense = try populated.addExpense()
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.zonesToSave.isEmpty)
        #expect(plan.saves.allSatisfy { $0.zoneID == owner })
        #expect(plan.part(for: .privateDatabase).saves.isEmpty)
        #expect(plan.part(for: .sharedDatabase).saves.count == plan.saves.count)
        #expect(plan.saves.map(\.recordName).contains(expense.id.description))
    }

    // MARK: Conflicts

    private func serverVersion(of record: CKRecord, device: SyncDevice, edit: (inout SyncPayload) -> Void) throws -> CKRecord {
        var payload = try RecordMapper.payload(from: record)
        edit(&payload)
        return RecordMapper.record(for: payload, in: record.recordID.zoneID, systemFields: payload.systemFields)
    }

    private func conflictError(server: CKRecord, client: CKRecord) -> CKError {
        CKError(.serverRecordChanged, userInfo: [
            CKRecordChangedErrorServerRecordKey: server,
            CKRecordChangedErrorClientRecordKey: client,
        ])
    }

    @Test func uploadsThatComeBackCutToMillisecondsAreNotSentAgain() throws {
        let device = try SyncDevice(start: 1_750_000_000.123_456_7)
        let me = try device.services.people.ensureMe(name: "Me")
        try device.services.groups.create(SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id]))
        let (_, records) = try device.outgoing()
        for record in records {
            let sent = try #require(record[RecordSchema.modifiedAtKey] as? Date)
            let cut = (sent.timeIntervalSince1970 * 1000).rounded(.down) / 1000
            record[RecordSchema.modifiedAtKey] = Date(timeIntervalSince1970: cut) as NSDate
        }
        try device.adapter.didSend(saved: records, deleted: [])
        #expect(try device.adapter.collectOutgoing().isEmpty)
        #expect(try device.tracker.pendingChanges().isEmpty)
    }

    @Test func aNewerServerVersionWinsTheConflictAndIsNotSentAgain() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var edited = expense
        edited.title = "Local edit"
        try populated.device.services.expenses.update(edited)
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        let server = try serverVersion(of: sent, device: populated.device) {
            $0.modifiedAt = $0.modifiedAt.addingTimeInterval(1_000)
            $0.fields.set("title", "Server edit")
        }
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: conflictError(server: server, client: sent))
        #expect(outcome.failure == .conflict)
        #expect(!outcome.requeue)
        #expect(try populated.device.services.expenses.expense(id: expense.id)?.title == "Server edit")
        #expect(try populated.device.tracker.pendingChanges().filter { $0.recordType == .expense }.isEmpty)
    }

    @Test func aNewerLocalVersionWinsTheConflictAndIsQueuedAgain() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var edited = expense
        edited.title = "Local edit"
        try populated.device.services.expenses.update(edited)
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        let server = try serverVersion(of: sent, device: populated.device) {
            $0.modifiedAt = $0.modifiedAt.addingTimeInterval(-1_000)
            $0.fields.set("title", "Old server edit")
        }
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: conflictError(server: server, client: sent))
        #expect(outcome.requeue)
        #expect(try populated.device.services.expenses.expense(id: expense.id)?.title == "Local edit")
        #expect(try populated.device.tracker.pendingChanges().contains { $0.recordType == .expense })
    }

    @Test func aConflictOnAPersonCopyMergesAndKeepsTheLocalNameWhenItIsNewer() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var renamed = populated.sam
        renamed.name = "Samuel"
        try populated.device.services.people.update(renamed)
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Person" })
        let server = try serverVersion(of: sent, device: populated.device) {
            $0.modifiedAt = $0.modifiedAt.addingTimeInterval(-500)
            $0.fields.set("name", "Sammy")
        }
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: conflictError(server: server, client: sent))
        #expect(outcome.requeue)
        #expect(try populated.device.services.people.person(id: populated.sam.id)?.name == "Samuel")
        #expect(populated.device.adapter.metadata.personQueue.contains(
            PersonCopyKey(zoneName: populated.zone, recordName: populated.sam.id.description)
        ))
    }

    @Test func aMissingServerRecordIsRecreatedFromScratch() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        var edited = expense
        edited.title = "Edit"
        try populated.device.services.expenses.update(edited)
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: CKError(.unknownItem))
        #expect(outcome.failure == .itemMissing)
        #expect(outcome.requeue)
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: populated.device.tracker.context))
        #expect(record.systemFields == nil)
        #expect(record.isDirty)
    }

    @Test func aKnownPrivateZoneThatIsMissingWaitsForTheServerToExplain() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try populated.addExpense("Another")
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: CKError(.zoneNotFound))
        #expect(outcome.askServerAbout?.zoneName == populated.zone)
        #expect(outcome.recreateZone == nil)
        #expect(!outcome.requeue)
        #expect(populated.device.adapter.metadata.zones[populated.zone] != nil)
    }

    @Test func aSaveStillOnItsWayDoesNotBringBackTheZoneOfADeletedGroup() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        // an edit is handed to the engine, then the group is deleted and its zone with it
        try populated.addExpense("Late")
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        try populated.device.services.groups.delete(id: populated.group.id)
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        try populated.device.adapter.zoneDeleteConfirmed(zone)
        #expect(!populated.device.adapter.metadata.isKnown(zoneName: populated.zone))

        let outcome = try populated.device.adapter.saveFailed(record: sent, error: CKError(.zoneNotFound))
        #expect(outcome.recreateZone == nil)
        #expect(!outcome.requeue)
        #expect(outcome.askServerAbout == nil)
    }

    @Test func aSaveIntoAZoneThatWasNeverMadeMakesItFirst() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let sent = try #require(try populated.device.outgoing().records.first { $0.recordType == "Expense" })
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: CKError(.zoneNotFound))
        #expect(outcome.recreateZone?.zoneName == populated.zone)
        #expect(outcome.requeue)
    }

    @Test func otherFailuresKeepTheChangesAndReportWhy() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let sent = try #require(try populated.device.outgoing().records.first)
        let outcome = try populated.device.adapter.saveFailed(record: sent, error: CKError(.quotaExceeded))
        #expect(outcome.failure == .quotaExceeded)
        #expect(!outcome.requeue)
        #expect(try populated.device.tracker.pendingChanges().count > 0)
    }

    // MARK: Incoming

    @Test func aStalePersonCopyDoesNotOverwriteANewerLocalName() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let staleCopy = try #require(cloud.records.values.first { $0.recordID.recordName == populated.sam.id.description })
        populated.device.clock.advance(by: 100)
        var renamed = populated.sam
        renamed.name = "Samuel"
        try populated.device.services.people.update(renamed)
        try cloud.upload(from: populated.device)
        let report = try populated.device.adapter.applyFetched(modifications: [staleCopy], deletions: [])
        #expect(try populated.device.services.people.person(id: populated.sam.id)?.name == "Samuel")
        #expect(report.requeue.contains(staleCopy.recordID))
    }

    @Test func aDeletedPersonCopyOnlyRemovesThePersonWhenNoCopyIsLeft() throws {
        let populated = try PopulatedDevice()
        let second = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [populated.me.id, populated.sam.id])
        try populated.device.services.groups.create(second)
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let other = try SyncDevice()
        try cloud.download(to: other)
        let zones = other.adapter.metadata.zonesHoldingCopy(of: populated.sam.id.description)
        #expect(zones.count == 2)
        let first = RecordMapper.recordID(recordName: populated.sam.id.description, zoneID: other.adapter.metadata.zoneID(forZoneName: zones[0]))
        let last = RecordMapper.recordID(recordName: populated.sam.id.description, zoneID: other.adapter.metadata.zoneID(forZoneName: zones[1]))
        try other.adapter.applyFetched(modifications: [], deletions: [(first, "Person")])
        #expect(try other.services.people.person(id: populated.sam.id) != nil)
        try other.adapter.applyFetched(modifications: [], deletions: [(last, "Person")])
        #expect(try other.services.people.person(id: populated.sam.id) == nil)
    }

    @Test func serverDeletionsBecomeLocalTombstonesThatAreNotUploaded() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let comment = ExpenseComment(
            groupID: populated.group.id, expenseID: expense.id, authorID: populated.me.id, text: "hi",
            createdAt: populated.device.clock.start
        )
        try populated.device.services.comments.add(comment)
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let other = try SyncDevice()
        try cloud.download(to: other)
        let id = RecordMapper.recordID(
            recordName: comment.id.uuidString, zoneID: other.adapter.metadata.zoneID(forZoneName: populated.zone)
        )
        try other.adapter.applyFetched(modifications: [], deletions: [(id, "Comment")])
        #expect(try other.services.comments.comments(on: expense.id).isEmpty)
        #expect(try other.tracker.pendingChanges().isEmpty)
    }

    @Test func unknownRecordTypesAndSharesAreSetAside() throws {
        let device = try SyncDevice()
        let zone = CKRecordZone.ID(zoneName: UUID().uuidString, ownerName: "_owner")
        let unknown = CKRecord(recordType: "Mystery", recordID: CKRecord.ID(recordName: "x", zoneID: zone))
        let share = CKShare(recordZoneID: zone)
        let report = try device.adapter.applyFetched(modifications: [unknown, share], deletions: [])
        #expect(report.shares.count == 1)
        #expect(report.inserted.isEmpty)
        #expect(try device.tracker.pendingChanges().isEmpty)
    }

    @Test func fetchedZonesAreRememberedWithTheirOwner() throws {
        let device = try SyncDevice()
        let shared = CKRecordZone.ID(zoneName: "ABC", ownerName: "_friend")
        device.adapter.zonesSaved([CKRecordZone(zoneID: shared)])
        #expect(device.adapter.metadata.zones["ABC"] == ZoneInfo(ownerName: "_friend", scope: .sharedDatabase))
        #expect(device.adapter.metadata.zoneID(forZoneName: "ABC") == shared)
        #expect(device.adapter.metadata.zoneID(forZoneName: "DEF").ownerName == CKCurrentUserDefaultName)
    }

    // MARK: Zone loss

    @Test func aZoneDeletedByTheOwnerHidesTheGroupButKeepsHistoryOnDisk() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: "_owner")
        // the upload above made it a private zone; here it is one the device knows as someone else's
        populated.device.adapter.updateMetadata { $0.zones[populated.zone] = ZoneInfo(ownerName: "_owner", scope: .sharedDatabase) }
        let needsSend = try populated.device.adapter.zoneDeleted(zone, reason: .deleted)
        #expect(!needsSend)
        #expect(try populated.device.services.groups.group(id: populated.group.id) == nil)
        #expect(try populated.device.tracker.pendingChanges().filter { $0.recordType != .person }.isEmpty)
        #expect(populated.device.adapter.metadata.zones[populated.zone] == nil)
        let kept = try populated.device.tracker.context.fetch(FetchDescriptor<ExpenseRecord>())
        #expect(!kept.isEmpty)
    }

    @Test func aPrivateZoneTheUserDeletedInICloudStaysLocalAndIsNotUploadedAgain() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        let needsSend = try populated.device.adapter.zoneDeleted(zone, reason: .purged)
        #expect(!needsSend)
        #expect(try populated.device.services.groups.group(id: populated.group.id) != nil)
        #expect(populated.device.adapter.metadata.isDetached(zoneName: populated.zone))
        #expect(try populated.device.adapter.collectOutgoing().isEmpty)
        // a later edit stays on the device too
        try populated.addExpense("Lunch", cents: 800)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.zonesToSave.isEmpty)
        #expect(try names(plan.saves, populated.device, of: .expense).isEmpty)
    }

    @Test func aPrivateZoneTheServerLostIsUploadedAgainFromTheDevice() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        let needsSend = try populated.device.adapter.zoneDeleted(zone, reason: .lost)
        #expect(needsSend)
        #expect(try populated.device.services.groups.group(id: populated.group.id) != nil)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.zonesToSave == [zone])
        #expect(try names(plan.saves, populated.device, of: .expense).count == 1)
        #expect(try names(plan.saves, populated.device, of: .person).count == 3)
    }

    @Test func switchingAccountsKeepsTheDataButStopsUploadingIt() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try populated.addExpense("Lunch", cents: 800)
        #expect(!(try populated.device.tracker.pendingChanges().isEmpty))
        try populated.device.adapter.resetForNewAccount(userRecordName: "_new")
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
        #expect(populated.device.adapter.metadata.userRecordName == "_new")
        #expect(populated.device.adapter.metadata.zones.isEmpty)
        #expect(try populated.device.services.expenses.expenses(in: populated.group.id).count == 2)
        let record = try #require(try GroupRecord.find(recordName: populated.zone, in: populated.device.tracker.context))
        #expect(record.systemFields == nil)
    }

    @Test func metadataSurvivesARestart() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        let reloaded = SyncStoreAdapter(tracker: populated.device.tracker, store: populated.device.store)
        #expect(reloaded.metadata == populated.device.adapter.metadata)
        #expect(reloaded.metadata.zones[populated.zone] != nil)
    }

    @Test func theNameOfSomeoneWhoJoinedIsNotReplacedByTheOneFromTheShare() throws {
        let owner = try PopulatedDevice()
        let joined = CloudIdentity.personID(forUserRecordName: "_jane")
        try ParticipantImporter(services: owner.device.services).importPeople(from: [ParticipantSnapshot(
            userRecordName: "_jane", displayName: nil, contactHints: [], isCurrentUser: false, hasJoined: true
        )], myUserRecordName: "_owner")
        #expect(try owner.device.services.people.person(id: joined)?.name == "Friend")
        #expect(try owner.device.tracker.pendingChanges().allSatisfy { $0.recordName != joined.description })

        var fields = SyncFields()
        fields.set("name", "Jane")
        fields.set("kind", PersonKind.friend.rawValue)
        let chosenLongAgo = owner.device.clock.start.addingTimeInterval(-10_000_000)
        let record = RecordMapper.record(
            for: SyncPayload(recordType: .person, recordName: joined.description, modifiedAt: chosenLongAgo, fields: fields),
            in: CKRecordZone.ID(zoneName: owner.zone, ownerName: CKCurrentUserDefaultName)
        )
        let report = try owner.device.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(report.requeue.isEmpty)
        #expect(try owner.device.services.people.person(id: joined)?.name == "Jane")
    }

    @Test func mergingAPlaceholderDoesNotBringBackADeletedZone() throws {
        let populated = try PopulatedDevice()
        try populated.addExpense()
        try FakeCloud().upload(from: populated.device)
        let zone = CKRecordZone.ID(zoneName: populated.zone, ownerName: CKCurrentUserDefaultName)
        try populated.device.adapter.zoneDeleted(zone, reason: .deleted)
        try ReferenceRewriter(tracker: populated.device.tracker).rewrite(from: populated.sam.id.rawValue, to: UUID())
        #expect(try populated.device.adapter.collectOutgoing().isEmpty)
        #expect(try populated.device.tracker.pendingChanges().isEmpty)
    }

    @Test func aGroupFromThePreviousAccountIsNotUploadedAfterAnEdit() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        try FakeCloud().upload(from: populated.device)
        try populated.device.adapter.resetForNewAccount(userRecordName: "_other")
        var edited = expense
        edited.title = "After the switch"
        try populated.device.services.expenses.update(edited, extras: nil)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.isEmpty)
    }

    @Test func aNewGroupAfterAnAccountSwitchStillUploads() throws {
        let populated = try PopulatedDevice()
        try FakeCloud().upload(from: populated.device)
        try populated.device.adapter.resetForNewAccount(userRecordName: "_other")
        let fresh = SplitGroup(name: "New", currencyCode: "USD", memberIDs: [populated.me.id])
        try populated.device.services.groups.create(fresh)
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.zonesToSave.map(\.zoneName) == [fresh.id.description])
        #expect(plan.saves.allSatisfy { $0.zoneID.zoneName == fresh.id.description })
    }

    @Test func aGroupFromThePreviousAccountReconnectsWhenItsZoneComesBack() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        try FakeCloud().upload(from: populated.device)
        try populated.device.adapter.resetForNewAccount(userRecordName: "_other")
        var edited = expense
        edited.title = "After the switch"
        try populated.device.services.expenses.update(edited, extras: nil)
        populated.device.adapter.registerZone(CKRecordZone.ID(zoneName: populated.zone, ownerName: "_owner"))
        #expect(try populated.device.adapter.collectOutgoing().saves.contains { $0.recordName == expense.id.description })
    }

    @Test func metadataSavedBeforeDetachedZonesStillLoads() throws {
        let old = #"{"zones":{},"personCopies":{},"personQueue":[]}"#
        let metadata = try JSONDecoder().decode(SyncMetadata.self, from: Data(old.utf8))
        #expect(!metadata.isDetached(zoneName: "zone"))
    }

    @Test func deletingAZoneLeavesTheTombstonesOfOtherZones() throws {
        let populated = try PopulatedDevice()
        let device = populated.device
        let expense = try populated.addExpense()
        let comment = ExpenseComment(
            groupID: populated.group.id, expenseID: expense.id, authorID: populated.me.id, text: "Soon gone",
            createdAt: device.clock.start
        )
        try device.services.comments.add(comment)
        let other = SplitGroup(name: "Other", currencyCode: "USD", memberIDs: [populated.me.id])
        try device.services.groups.create(other)
        let otherExpense = Expense(
            groupID: other.id, title: "Lunch", total: usdAmount(100), date: device.clock.start,
            paidBy: populated.me.id, split: .equal(participants: [populated.me.id])
        )
        try device.services.expenses.add(otherExpense)
        let cloud = FakeCloud()
        try cloud.upload(from: device)
        try device.services.comments.delete(id: comment.id)
        try cloud.upload(from: device)
        try device.services.groups.delete(id: other.id)
        try cloud.upload(from: device)
        let context = device.tracker.context
        #expect(try CommentRecord.find(recordName: comment.id.uuidString, in: context)?.deletedAt != nil)
        #expect(try GroupRecord.find(recordName: other.id.description, in: context) == nil)
        #expect(try ExpenseRecord.find(recordName: otherExpense.id.description, in: context) == nil)
    }

    @Test func aProfileWithoutAChosenNameIsNotUploadedUntilItHasOne() throws {
        let device = try SyncDevice()
        var me = try device.services.people.ensureMe(name: String(localized: "You"))
        try device.services.groups.create(SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id]))
        let first = try device.adapter.collectOutgoing()
        #expect(!first.saves.contains { $0.recordName == me.id.description })

        me.name = "Sam"
        try device.services.people.update(me)
        let named = try device.adapter.collectOutgoing()
        #expect(named.saves.contains { $0.recordName == me.id.description })
    }
}
