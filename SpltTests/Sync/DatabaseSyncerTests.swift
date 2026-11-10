import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Database syncer")
struct DatabaseSyncerTests {
    @MainActor
    private struct Rig {
        let populated: PopulatedDevice
        let coordinator: SyncCoordinator
        let handle = FakeEngineHandle()
        let syncer: DatabaseSyncer
        let cloud = FakeCloud()

        var device: SyncDevice { populated.device }

        init() throws {
            populated = try PopulatedDevice()
            coordinator = SyncCoordinator(services: populated.device.services, adapter: populated.device.adapter)
            syncer = DatabaseSyncer(scope: .privateDatabase, coordinator: coordinator, store: populated.device.store)
            let handle = handle
            syncer.start { _, _ in handle }
            coordinator.attach(syncer, for: .privateDatabase)
            coordinator.markReady()
        }

        /// A record the engine is about to upload for a fresh edit, as the engine would hand it back.
        func pendingExpenseRecord() throws -> CKRecord {
            try populated.addExpense("Edited \(UUID().uuidString.prefix(4))")
            return try #require(try device.outgoing().records.first { $0.recordType == "Expense" })
        }
    }

    // MARK: Queueing

    @Test func aPlanBecomesPendingChangesInTheEngine() throws {
        let rig = try Rig()
        try rig.populated.addExpense()
        let plan = try rig.device.adapter.collectOutgoing()
        rig.syncer.queue(plan)
        #expect(rig.handle.savedZoneIDs == plan.zonesToSave)
        #expect(Set(rig.handle.savedRecordIDs) == Set(plan.saves))
        #expect(rig.handle.deletedRecordIDs.isEmpty)
    }

    @Test func deletesAndZoneRemovalsAreQueuedToo() throws {
        let rig = try Rig()
        let zone = CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName)
        let left = CKRecordZone.ID(zoneName: "L", ownerName: "_owner")
        let record = CKRecord.ID(recordName: "R", zoneID: zone)
        rig.syncer.queue(OutgoingPlan(deletes: [record], zonesToDelete: [zone], zonesToLeave: [left]))
        #expect(rig.handle.deletedRecordIDs == [record])
        #expect(rig.handle.deletedZoneIDs == [zone, left])
        rig.syncer.queue(OutgoingPlan())
        #expect(rig.handle.recordChanges.count == 1)
    }

    @Test func singleSavesAndZonesCanBeQueuedAgain() throws {
        let rig = try Rig()
        let zone = CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord.ID(recordName: "R", zoneID: zone)
        rig.syncer.queue(saves: [record])
        rig.syncer.queue(zonesToSave: [zone])
        rig.syncer.queue(zonesToDelete: [zone])
        #expect(rig.handle.savedRecordIDs == [record])
        #expect(rig.handle.savedZoneIDs == [zone])
        #expect(rig.handle.deletedZoneIDs == [zone])
    }

    @Test func queueingBeforeStartOrAfterStopDoesNothing() async throws {
        let rig = try Rig()
        await rig.syncer.stop()
        #expect(rig.handle.cancelCount == 1)
        rig.syncer.queue(saves: [CKRecord.ID(recordName: "R", zoneID: CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName))])
        #expect(rig.handle.recordChanges.isEmpty)
        try await rig.syncer.sendChanges()
        #expect(rig.handle.sendCount == 0)
    }

    // MARK: Batches

    @Test func theBatchHoldsTheCurrentRecordsAndDeletes() async throws {
        let rig = try Rig()
        try rig.populated.addExpense()
        let plan = try rig.device.adapter.collectOutgoing()
        let tombstone = CKRecord.ID(recordName: "Gone", zoneID: plan.saves[0].zoneID)
        let pending = plan.saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) } + [.deleteRecord(tombstone)]
        let batch = try #require(await rig.syncer.batch(from: pending, scope: .all))
        #expect(Set(batch.recordsToSave.map(\.recordID)) == Set(plan.saves))
        #expect(batch.recordIDsToDelete == [tombstone])
        #expect(batch.recordsToSave.allSatisfy { $0.object(forKey: RecordSchema.modifiedAtKey) != nil })
    }

    @Test func changesOutsideTheAllowedScopeOrWithoutRecordsAreLeftOut() async throws {
        let rig = try Rig()
        try rig.populated.addExpense()
        let plan = try rig.device.adapter.collectOutgoing()
        let pending = plan.saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        let elsewhere = CKRecordZone.ID(zoneName: "Other", ownerName: CKCurrentUserDefaultName)
        #expect(await rig.syncer.batch(from: pending, scope: .zoneIDs([elsewhere])) == nil)
        #expect(await rig.syncer.batch(from: [], scope: .all) == nil)

        let unknown = CKRecord.ID(recordName: UUID().uuidString, zoneID: plan.saves[0].zoneID)
        let batch = await rig.syncer.batch(from: [.saveRecord(unknown)], scope: .all)
        #expect(batch?.recordsToSave.isEmpty ?? true)
    }

    @Test func recordsThatAreAlreadySyncedAreDroppedFromTheBatch() async throws {
        let rig = try Rig()
        try rig.populated.addExpense()
        try rig.cloud.upload(from: rig.device)
        let ids = rig.cloud.records.keys.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        let batch = await rig.syncer.batch(from: ids, scope: .all)
        #expect(batch?.recordsToSave.isEmpty ?? true)
    }

    // MARK: State and status

    @Test func stateUpdatesArePersistedForTheNextLaunch() throws {
        let rig = try Rig()
        #expect(!rig.syncer.hasSavedState)
        rig.syncer.handle(.stateUpdate(Data([1, 2, 3])))
        #expect(rig.syncer.hasSavedState)
        #expect(rig.device.store.loadEngineState(.privateDatabase) == Data([1, 2, 3]))
        #expect(rig.device.store.loadEngineState(.sharedDatabase) == nil)
    }

    @Test func savedStateThatCannotBeReadStartsFresh() throws {
        let rig = try Rig()
        rig.device.store.saveEngineState(Data("garbage".utf8), scope: .privateDatabase)
        var received: [Bool] = []
        rig.syncer.start { serialization, _ in
            received.append(serialization == nil)
            return FakeEngineHandle()
        }
        #expect(received == [true])
    }

    @Test func runningOperationsShowAsSyncing() throws {
        let rig = try Rig()
        rig.syncer.handle(.operationStarted)
        #expect(rig.coordinator.status == .syncing)
        rig.syncer.handle(.operationEnded)
        #expect(rig.coordinator.status == .idle)
    }

    @Test func aSignOutShowsNoAccount() throws {
        let rig = try Rig()
        rig.syncer.handle(.account(.signedOut))
        #expect(rig.coordinator.status == .noAccount)
    }

    @Test func fetchesReportSuccessAndFailure() async throws {
        let rig = try Rig()
        try await rig.syncer.fetchChanges()
        #expect(rig.handle.fetchCount == 1)
        rig.handle.fetchError = CKError(.networkUnavailable)
        await #expect(throws: CKError.self) { try await rig.syncer.fetchChanges() }
        #expect(rig.coordinator.status == .offline)
        rig.handle.fetchError = nil
        try await rig.syncer.fetchChanges()
        #expect(rig.coordinator.status == .idle)
    }

    // MARK: Fetched changes

    @Test func fetchedRecordsAreAppliedToTheStore() throws {
        let source = try PopulatedDevice()
        try source.addExpense("Taxi")
        let cloud = FakeCloud()
        try cloud.upload(from: source.device)
        let rig = try Rig()
        rig.syncer.handle(.fetchedRecords(modifications: Array(cloud.records.values), deletions: []))
        let titles = try rig.device.services.expenses.expenses(in: source.group.id).map(\.title)
        #expect(titles == ["Taxi"])
    }

    @Test func fetchedZonesAreRememberedAndDeletedZonesRetireTheirGroup() throws {
        let rig = try Rig()
        let owner = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: "_owner")
        rig.syncer.handle(.fetchedZones(modified: [owner], deleted: []))
        #expect(rig.device.adapter.metadata.zones[rig.populated.zone]?.scope == .sharedDatabase)
        rig.syncer.handle(.fetchedZones(modified: [], deleted: [(owner, .deleted)]))
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) == nil)
    }

    // MARK: Failed saves

    private func fail(_ rig: Rig, _ record: CKRecord, _ error: CKError) {
        rig.syncer.handle(.sentRecords(saved: [], failedSaves: [(record, error)], deleted: [], failedDeletes: [:]))
    }

    @Test func fullStorageKeepsTheChangeAndShowsAFriendlyError() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        fail(rig, record, CKError(.quotaExceeded))
        guard case .error(let message) = rig.coordinator.status else {
            Issue.record("expected an error status")
            return
        }
        #expect(message.contains("storage"))
        #expect(try rig.device.tracker.pendingChanges().contains { $0.recordName == record.recordID.recordName })
        #expect(rig.handle.savedRecordIDs.isEmpty)
    }

    @Test func noNetworkKeepsTheChangeAndShowsOffline() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        fail(rig, record, CKError(.networkUnavailable))
        #expect(rig.coordinator.status == .offline)
        #expect(try rig.device.tracker.pendingChanges().contains { $0.recordName == record.recordID.recordName })
    }

    @Test func aNewerServerVersionReplacesTheLocalOneWithoutAResend() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        var payload = try RecordMapper.payload(from: record)
        payload.modifiedAt = payload.modifiedAt.addingTimeInterval(1_000)
        payload.fields.set("title", "From the server")
        let server = RecordMapper.record(for: payload, in: record.recordID.zoneID, systemFields: payload.systemFields)
        fail(rig, record, CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]))
        let id = ExpenseID(rawValue: try #require(UUID(uuidString: record.recordID.recordName)))
        #expect(try rig.device.services.expenses.expense(id: id)?.title == "From the server")
        #expect(!rig.handle.savedRecordIDs.contains(record.recordID))
        #expect(rig.coordinator.status == .idle)
    }

    @Test func aNewerLocalVersionIsQueuedAgainAfterAConflict() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        var payload = try RecordMapper.payload(from: record)
        payload.modifiedAt = payload.modifiedAt.addingTimeInterval(-1_000)
        payload.fields.set("title", "Stale server title")
        let server = RecordMapper.record(for: payload, in: record.recordID.zoneID, systemFields: payload.systemFields)
        fail(rig, record, CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]))
        #expect(rig.handle.savedRecordIDs.contains(record.recordID))
        #expect(rig.coordinator.status == .idle)
    }

    @Test func aMissingZoneIsCreatedAgainAndTheRecordSentAfterIt() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        fail(rig, record, CKError(.zoneNotFound))
        #expect(rig.handle.savedZoneIDs == [record.recordID.zoneID])
        #expect(rig.handle.savedRecordIDs == [record.recordID])
    }

    @Test func aRecordMissingOnTheServerIsSentAsNewWithoutOldSystemFields() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        let stored = try #require(try ExpenseRecord.find(recordName: record.recordID.recordName, in: rig.device.tracker.context))
        stored.systemFields = Data([9])
        fail(rig, record, CKError(.unknownItem))
        #expect(stored.systemFields == nil)
        #expect(stored.isDirty)
        #expect(rig.handle.savedRecordIDs == [record.recordID])
    }

    @Test func aSuccessfulSendClearsAnEarlierProblem() throws {
        let rig = try Rig()
        let record = try rig.pendingExpenseRecord()
        fail(rig, record, CKError(.networkUnavailable))
        #expect(rig.coordinator.status == .offline)
        rig.syncer.handle(.sentRecords(saved: [record], failedSaves: [], deleted: [], failedDeletes: [:]))
        #expect(rig.coordinator.status == .idle)
        #expect(try rig.device.tracker.pendingChanges().filter { $0.recordType == .expense }.isEmpty)
    }

    @Test func zoneSavesAndDeletesAreRecorded() throws {
        let rig = try Rig()
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        rig.syncer.handle(.sentZones(saved: [CKRecordZone(zoneID: zone)], failedSaves: [], deleted: [], failedDeletes: [:]))
        #expect(rig.device.adapter.metadata.zones[rig.populated.zone] != nil)
        rig.syncer.handle(.sentZones(saved: [], failedSaves: [], deleted: [zone], failedDeletes: [:]))
        #expect(rig.device.adapter.metadata.zones[rig.populated.zone] == nil)
    }

    @Test func aFailedZoneSaveIsShown() throws {
        let rig = try Rig()
        let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName))
        rig.syncer.handle(.sentZones(saved: [], failedSaves: [(zone, CKError(.quotaExceeded))], deleted: [], failedDeletes: [:]))
        if case .error = rig.coordinator.status {} else { Issue.record("expected an error status") }
    }

    @Test func aFailedDeleteOfAMissingRecordCountsAsDone() throws {
        let rig = try Rig()
        let zone = CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        rig.syncer.handle(.sentRecords(saved: [], failedSaves: [], deleted: [], failedDeletes: [id: CKError(.unknownItem)]))
        #expect(rig.coordinator.status == .idle)
        rig.syncer.handle(.sentRecords(saved: [], failedSaves: [], deleted: [], failedDeletes: [id: CKError(.networkFailure)]))
        #expect(rig.coordinator.status == .offline)
    }

    @Test func aFetchedBatchThatCouldNotBeAppliedIsFetchedAgainNextLaunch() throws {
        let rig = try Rig()
        rig.device.store.saveEngineState(Data([1]), scope: .privateDatabase)
        rig.syncer.applyFault = { input in
            if case .fetchedRecords = input { throw CKError(.internalError) }
        }
        rig.syncer.handle(.fetchedRecords(modifications: [], deletions: []))
        rig.syncer.applyFault = nil
        rig.syncer.handle(.stateUpdate(Data([2])))
        #expect(rig.device.store.loadEngineState(.privateDatabase) == nil)
    }
}
