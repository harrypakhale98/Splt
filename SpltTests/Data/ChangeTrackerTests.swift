import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Change tracker")
struct ChangeTrackerTests {
    private let clock = TestClock()
    private let services: DataServices
    private let tracker: ChangeTracker
    private let context: ModelContext

    init() throws {
        services = try DataServices.inMemory(now: clock.reading)
        tracker = services.makeChangeTracker()
        context = services.container.mainContext
    }

    private func makePerson(_ name: String = "Sam") throws -> PersonRecord {
        let record = PersonRecord(Person(name: name, createdAt: clock.start))
        context.insert(record)
        tracker.recordEdit(record)
        try tracker.save()
        return record
    }

    private func synced(_ record: PersonRecord, systemFields: Data? = Data([9])) throws {
        try tracker.markSynced(
            recordType: .person, recordName: record.recordName, sentModifiedAt: record.modifiedAt, systemFields: systemFields
        )
    }

    @Test func localEditsMarkARecordDirtyWithASave() throws {
        let record = try makePerson()
        #expect(record.isDirty)
        #expect(record.pendingOperation == .save)
        #expect(record.modifiedAt > clock.start)
    }

    @Test func editsMoveTheModifiedDateForward() throws {
        let record = try makePerson()
        let first = record.modifiedAt
        record.name = "Samuel"
        tracker.recordEdit(record)
        #expect(record.modifiedAt > first)
    }

    @Test func aBackwardsClockNeverMovesTheModifiedDateBack() throws {
        let record = try makePerson()
        record.modifiedAt = clock.start.addingTimeInterval(1_000_000)
        tracker.recordEdit(record)
        #expect(record.modifiedAt == clock.start.addingTimeInterval(1_000_000))
    }

    @Test func softDeleteIsADirtySaveWithATombstone() throws {
        let record = try makePerson()
        tracker.softDelete(record)
        #expect(record.deletedAt != nil)
        #expect(record.deletedAt == record.modifiedAt)
        #expect(record.pendingOperation == .save)
    }

    @Test func tombstoneOfASyncedRecordIsADirtyDelete() throws {
        let record = try makePerson()
        try synced(record)
        tracker.tombstone(record)
        #expect(record.pendingOperation == .delete)
        #expect(record.isDirty)
        #expect(record.deletedAt != nil)
    }

    @Test func tombstoneOfARecordThatNeverSyncedJustRemovesIt() throws {
        let record = try makePerson()
        tracker.tombstone(record)
        try tracker.save()
        #expect(try PersonRecord.find(recordName: record.recordName, in: context) == nil)
        #expect(try tracker.pendingChanges().isEmpty)
    }

    @Test func restoreClearsTheTombstoneAndLaterThanIt() throws {
        let record = try makePerson()
        tracker.softDelete(record)
        let deletedAt = try #require(record.deletedAt)
        tracker.restore(record)
        #expect(record.deletedAt == nil)
        #expect(record.modifiedAt > deletedAt)
        #expect(record.pendingOperation == .save)
    }

    @Test func pendingChangesListsDirtyRecordsOldestFirst() throws {
        let first = try makePerson("A")
        let second = try makePerson("B")
        let changes = try tracker.pendingChanges()
        #expect(changes.map(\.recordName) == [first.recordName, second.recordName])
        #expect(changes.allSatisfy { $0.recordType == .person && $0.operation == .save })
    }

    @Test func pendingChangesSpanEveryRecordType() throws {
        let fixture = try Fixture()
        try fixture.addExpense()
        let types = Set(try fixture.services.makeChangeTracker().pendingChanges().map(\.recordType))
        #expect(types == [.person, .group, .expense, .activity])
    }

    @Test func markSyncedClearsTheDirtyFlagAndKeepsSystemFields() throws {
        let record = try makePerson()
        try synced(record, systemFields: Data([1, 2, 3]))
        #expect(!record.isDirty)
        #expect(record.pendingOperation == nil)
        #expect(record.systemFields == Data([1, 2, 3]))
        #expect(try tracker.pendingChanges().isEmpty)
    }

    @Test func anEditMadeWhileUploadingStaysDirty() throws {
        let record = try makePerson()
        let sent = record.modifiedAt
        record.name = "Edited during upload"
        tracker.recordEdit(record)
        try tracker.markSynced(recordType: .person, recordName: record.recordName, sentModifiedAt: sent, systemFields: Data([7]))
        #expect(record.isDirty)
        #expect(record.systemFields == Data([7]))
    }

    @Test func payloadCarriesFieldsAndBookkeeping() throws {
        let record = try makePerson("Maya")
        try synced(record, systemFields: Data([5]))
        let payload = try #require(try tracker.payload(recordType: .person, recordName: record.recordName))
        #expect(payload.fields.string("name") == "Maya")
        #expect(payload.systemFields == Data([5]))
        #expect(payload.modifiedAt == record.modifiedAt)
        #expect(payload.deletedAt == nil)
    }

    private func remotePayload(for record: PersonRecord, name: String, modified: Date, deleted: Date? = nil) -> SyncPayload {
        var payload = record.syncPayload
        payload.fields.set("name", name)
        payload.modifiedAt = modified
        payload.deletedAt = deleted
        payload.systemFields = Data([42])
        return payload
    }

    @Test func remoteInsertCreatesACleanRecord() throws {
        let id = UUID()
        var fields = SyncFields()
        fields.set("name", "Priya")
        fields.set("kind", PersonKind.friend.rawValue)
        let payload = SyncPayload(
            recordType: .person, recordName: id.uuidString, systemFields: Data([1]),
            modifiedAt: clock.start, fields: fields
        )
        #expect(try tracker.applyRemote(payload) == .inserted)
        let record = try #require(try PersonRecord.find(recordName: id.uuidString, in: context))
        #expect(record.name == "Priya")
        #expect(record.id == id)
        #expect(!record.isDirty)
        #expect(record.systemFields == Data([1]))
        #expect(try tracker.pendingChanges().isEmpty)
    }

    @Test func remoteUpdateOfACleanRecordDoesNotMarkItDirty() throws {
        let record = try makePerson()
        try synced(record)
        let payload = remotePayload(for: record, name: "Renamed", modified: record.modifiedAt.addingTimeInterval(60))
        #expect(try tracker.applyRemote(payload) == .updated)
        #expect(record.name == "Renamed")
        #expect(!record.isDirty)
        #expect(record.pendingOperation == nil)
        #expect(record.systemFields == Data([42]))
    }

    @Test func aNewerRemoteVersionReplacesLocalChanges() throws {
        let record = try makePerson()
        record.name = "Local"
        tracker.recordEdit(record)
        let payload = remotePayload(for: record, name: "Remote", modified: record.modifiedAt.addingTimeInterval(60))
        #expect(try tracker.applyRemote(payload) == .replacedLocalChanges)
        #expect(record.name == "Remote")
        #expect(!record.isDirty)
    }

    @Test func anOlderRemoteVersionKeepsLocalChangesAndTakesTheNewSystemFields() throws {
        let record = try makePerson()
        record.name = "Local"
        tracker.recordEdit(record)
        let payload = remotePayload(for: record, name: "Remote", modified: record.modifiedAt.addingTimeInterval(-60))
        #expect(try tracker.applyRemote(payload) == .keptLocal)
        #expect(record.name == "Local")
        #expect(record.isDirty)
        #expect(record.systemFields == Data([42]))
    }

    @Test func aRemoteTombstoneBeatsAnOlderLocalEdit() throws {
        let record = try makePerson()
        let deleted = record.modifiedAt.addingTimeInterval(30)
        let payload = remotePayload(for: record, name: record.name, modified: deleted, deleted: deleted)
        #expect(try tracker.applyRemote(payload) == .replacedLocalChanges)
        #expect(record.deletedAt == deleted)
        #expect(!record.isDirty)
    }

    @Test func aLocalEditNewerThanTheRemoteTombstoneSurvives() throws {
        let record = try makePerson()
        let deleted = record.modifiedAt.addingTimeInterval(-30)
        let payload = remotePayload(for: record, name: record.name, modified: deleted, deleted: deleted)
        #expect(try tracker.applyRemote(payload) == .keptLocal)
        #expect(record.deletedAt == nil)
        #expect(record.isDirty)
    }

    @Test func remoteBatchesSaveOnceAndReportEachOutcome() throws {
        let id = UUID()
        let payloads = [
            SyncPayload(recordType: .person, recordName: id.uuidString, modifiedAt: clock.start, fields: SyncFields()),
            SyncPayload(recordType: .group, recordName: UUID().uuidString, modifiedAt: clock.start, fields: SyncFields())
        ]
        #expect(try tracker.applyRemote(payloads) == [.inserted, .inserted])
        #expect(try tracker.pendingChanges().isEmpty)
    }

    @Test func remoteDeletionTombstonesTheLocalCopyWithoutMarkingItDirty() throws {
        let record = try makePerson()
        try synced(record)
        let outcome = try tracker.applyRemoteDeletion(recordType: .person, recordName: record.recordName)
        #expect(outcome == .updated)
        #expect(record.deletedAt != nil)
        #expect(!record.isDirty)
    }

    @Test func remoteDeletionOfUnknownRecordIsIgnored() throws {
        #expect(try tracker.applyRemoteDeletion(recordType: .person, recordName: UUID().uuidString) == nil)
    }

    @Test func remoteDeletionOverUnsentEditsReportsTheDiscard() throws {
        let record = try makePerson()
        let outcome = try tracker.applyRemoteDeletion(
            recordType: .person, recordName: record.recordName, at: record.modifiedAt.addingTimeInterval(10)
        )
        #expect(outcome == .replacedLocalChanges)
        #expect(!record.isDirty)
    }

    @Test func confirmedTombstonesArePurgedAfterTheCutoff() throws {
        let record = try makePerson()
        try synced(record)
        tracker.tombstone(record)
        try tracker.markSynced(
            recordType: .person, recordName: record.recordName, sentModifiedAt: record.modifiedAt, systemFields: nil
        )
        let deletedAt = try #require(record.deletedAt)
        #expect(try tracker.purgeConfirmedTombstones(olderThan: deletedAt.addingTimeInterval(-1)) == 0)
        #expect(try tracker.purgeConfirmedTombstones(olderThan: deletedAt.addingTimeInterval(1)) == 1)
        #expect(try PersonRecord.find(recordName: record.recordName, in: context) == nil)
    }

    @Test func unconfirmedTombstonesAreKept() throws {
        let record = try makePerson()
        try synced(record)
        tracker.tombstone(record)
        #expect(try tracker.purgeConfirmedTombstones(olderThan: .distantFuture) == 0)
    }

    @Test func softDeletedExpensesAreNeverPurged() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.expenses.delete(id: expense.id)
        let tracker = fixture.services.makeChangeTracker()
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.container.mainContext))
        try tracker.markSynced(recordType: .expense, recordName: record.recordName, sentModifiedAt: record.modifiedAt, systemFields: nil)
        #expect(try tracker.purgeConfirmedTombstones(olderThan: .distantFuture) == 0)
        #expect(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.container.mainContext) != nil)
    }

    @Test func tombstonesOfADeletedGroupsContentArePurgedWithTheGroup() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let tracker = fixture.services.makeChangeTracker()
        let context = fixture.services.container.mainContext
        for change in try tracker.pendingChanges() {
            try tracker.markSynced(
                recordType: change.recordType, recordName: change.recordName,
                sentModifiedAt: .distantFuture, systemFields: Data([1])
            )
        }
        try fixture.services.groups.delete(id: fixture.group.id)
        for change in try tracker.pendingChanges() {
            try tracker.markSynced(
                recordType: change.recordType, recordName: change.recordName,
                sentModifiedAt: .distantFuture, systemFields: nil
            )
        }
        #expect(try tracker.purgeConfirmedTombstones(olderThan: .distantFuture) > 0)
        #expect(try ExpenseRecord.find(recordName: expense.id.description, in: context) == nil)
        #expect(try GroupRecord.find(recordName: fixture.group.id.description, in: context) == nil)
    }
}
