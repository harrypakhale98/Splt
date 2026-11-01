import CloudKit
import Foundation

/// One CKSyncEngine for one database. It turns engine events into coordinator calls and builds
/// the batches the engine asks for; the decisions live in `SyncCoordinator`.
@MainActor
final class DatabaseSyncer: CKSyncEngineDelegate, EngineQueue {
    let scope: DatabaseScope
    private let database: CKDatabase
    private let coordinator: SyncCoordinator
    private let store: any SyncStateStore
    private(set) var engine: CKSyncEngine?

    init(scope: DatabaseScope, database: CKDatabase, coordinator: SyncCoordinator, store: any SyncStateStore) {
        self.scope = scope
        self.database = database
        self.coordinator = coordinator
        self.store = store
    }

    var hasSavedState: Bool { store.loadEngineState(scope) != nil }

    func start() {
        let saved = store.loadEngineState(scope).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self)
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    func stop() async {
        await engine?.cancelOperations()
        engine = nil
    }

    // MARK: EngineQueue

    func queue(_ plan: OutgoingPlan) {
        guard let state = engine?.state else { return }
        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = plan.zonesToSave.map { .saveZone(CKRecordZone(zoneID: $0)) }
        databaseChanges += (plan.zonesToDelete + plan.zonesToLeave).map { .deleteZone($0) }
        if !databaseChanges.isEmpty { state.add(pendingDatabaseChanges: databaseChanges) }
        var recordChanges = plan.saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        recordChanges += plan.deletes.map { .deleteRecord($0) }
        if !recordChanges.isEmpty { state.add(pendingRecordZoneChanges: recordChanges) }
    }

    func queue(saves: [CKRecord.ID]) {
        engine?.state.add(pendingRecordZoneChanges: saves.map { .saveRecord($0) })
    }

    func queue(zonesToSave: [CKRecordZone.ID]) {
        engine?.state.add(pendingDatabaseChanges: zonesToSave.map { .saveZone(CKRecordZone(zoneID: $0)) })
    }

    func queue(zonesToDelete: [CKRecordZone.ID]) {
        engine?.state.add(pendingDatabaseChanges: zonesToDelete.map { .deleteZone($0) })
    }

    func sendChanges() async throws {
        try await engine?.sendChanges()
    }

    func fetchChanges() async throws {
        do {
            try await engine?.fetchChanges()
            coordinator.fetchSucceeded(scope: scope)
        } catch {
            coordinator.fetchFailed(error, scope: scope)
            throw error
        }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        do {
            try handle(event)
        } catch {
            coordinator.updateStatus { $0.failed(SyncFailure(error), source: .init(scope: scope, isSending: false)) }
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.record(for: id)
        }
    }

    private func record(for id: CKRecord.ID) -> CKRecord? {
        try? coordinator.adapter.outgoingRecord(for: id)
    }

    private func handle(_ event: CKSyncEngine.Event) throws {
        switch event {
        case .stateUpdate(let update):
            store.saveEngineState(try? JSONEncoder().encode(update.stateSerialization), scope: scope)
        case .accountChange(let change):
            try coordinator.accountChanged(Self.accountChange(change.changeType))
        case .fetchedDatabaseChanges(let changes):
            try coordinator.fetchedZones(
                modified: changes.modifications.map(\.zoneID),
                deleted: changes.deletions.map { ($0.zoneID, Self.reason($0.reason)) }
            )
        case .fetchedRecordZoneChanges(let changes):
            try coordinator.fetchedRecords(
                modifications: changes.modifications.map(\.record),
                deletions: changes.deletions.map { ($0.recordID, $0.recordType) }
            )
        case .sentDatabaseChanges(let sent):
            try coordinator.sentZones(
                saved: sent.savedZones, failedSaves: sent.failedZoneSaves.map { ($0.zone, $0.error) },
                deleted: sent.deletedZoneIDs, failedDeletes: sent.failedZoneDeletes, scope: scope
            )
        case .sentRecordZoneChanges(let sent):
            try coordinator.sentRecords(
                saved: sent.savedRecords, failedSaves: sent.failedRecordSaves.map { ($0.record, $0.error) },
                deleted: sent.deletedRecordIDs, failedDeletes: sent.failedRecordDeletes, scope: scope
            )
        case .willFetchChanges, .willSendChanges:
            coordinator.updateStatus { $0.began() }
        case .didFetchChanges, .didSendChanges:
            coordinator.updateStatus { $0.ended() }
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    private static func accountChange(_ type: CKSyncEngine.Event.AccountChange.ChangeType) -> SyncAccountChange {
        switch type {
        case .signIn(let user): .signedIn(user: user.recordName)
        case .signOut: .signedOut
        case .switchAccounts(_, let user): .switched(to: user.recordName)
        @unknown default: .signedOut
        }
    }

    private static func reason(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) -> ZoneDeletionReason {
        switch reason {
        case .deleted: .deleted
        case .purged: .purged
        case .encryptedDataReset: .encryptedDataReset
        @unknown default: .deleted
        }
    }
}
