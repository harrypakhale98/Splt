import CloudKit
import Foundation

/// The parts of CKSyncEngine the syncer uses, so the logic can be tested without a real engine.
@MainActor
protocol SyncEngineHandle: AnyObject {
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
    func sendChanges() async throws
    func fetchChanges() async throws
    func cancelOperations() async
}

/// The real engine behind `SyncEngineHandle`.
@MainActor
final class CKSyncEngineHandle: SyncEngineHandle {
    private let engine: CKSyncEngine

    init(database: CKDatabase, serialization: CKSyncEngine.State.Serialization?, delegate: any CKSyncEngineDelegate) {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: delegate)
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    func add(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func add(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
        engine.state.add(pendingDatabaseChanges: changes)
    }

    func sendChanges() async throws {
        try await engine.sendChanges()
    }

    func fetchChanges() async throws {
        try await engine.fetchChanges()
    }

    func cancelOperations() async {
        await engine.cancelOperations()
    }
}

/// What a CKSyncEngine event means for Splt, in plain values. Translating the framework event is the
/// only untested step; everything after it runs in tests.
enum SyncEngineInput {
    case stateUpdate(Data?)
    case account(SyncAccountChange)
    case fetchedZones(modified: [CKRecordZone.ID], deleted: [(id: CKRecordZone.ID, reason: ZoneDeletionReason)])
    case fetchedRecords(modifications: [CKRecord], deletions: [(id: CKRecord.ID, recordType: String)])
    case sentZones(
        saved: [CKRecordZone], failedSaves: [(zone: CKRecordZone, error: CKError)],
        deleted: [CKRecordZone.ID], failedDeletes: [CKRecordZone.ID: CKError]
    )
    case sentRecords(
        saved: [CKRecord], failedSaves: [(record: CKRecord, error: CKError)],
        deleted: [CKRecord.ID], failedDeletes: [CKRecord.ID: CKError]
    )
    case operationStarted
    case operationEnded

    init?(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            self = .stateUpdate(try? JSONEncoder().encode(update.stateSerialization))
        case .accountChange(let change):
            switch change.changeType {
            case .signIn(let user): self = .account(.signedIn(user: user.recordName))
            case .signOut: self = .account(.signedOut)
            case .switchAccounts(_, let user): self = .account(.switched(to: user.recordName))
            @unknown default: self = .account(.signedOut)
            }
        case .fetchedDatabaseChanges(let changes):
            self = .fetchedZones(
                modified: changes.modifications.map(\.zoneID),
                deleted: changes.deletions.map { ($0.zoneID, Self.reason($0.reason)) }
            )
        case .fetchedRecordZoneChanges(let changes):
            self = .fetchedRecords(
                modifications: changes.modifications.map(\.record),
                deletions: changes.deletions.map { ($0.recordID, $0.recordType) }
            )
        case .sentDatabaseChanges(let sent):
            self = .sentZones(
                saved: sent.savedZones, failedSaves: sent.failedZoneSaves.map { ($0.zone, $0.error) },
                deleted: sent.deletedZoneIDs, failedDeletes: sent.failedZoneDeletes
            )
        case .sentRecordZoneChanges(let sent):
            self = .sentRecords(
                saved: sent.savedRecords, failedSaves: sent.failedRecordSaves.map { ($0.record, $0.error) },
                deleted: sent.deletedRecordIDs, failedDeletes: sent.failedRecordDeletes
            )
        case .willFetchChanges, .willSendChanges:
            self = .operationStarted
        case .didFetchChanges, .didSendChanges:
            self = .operationEnded
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            return nil
        @unknown default:
            return nil
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

/// One CKSyncEngine for one database. It turns engine events into coordinator calls and builds
/// the batches the engine asks for; the decisions live in `SyncCoordinator`.
@MainActor
final class DatabaseSyncer: CKSyncEngineDelegate, EngineQueue {
    typealias EngineFactory = @MainActor (CKSyncEngine.State.Serialization?, any CKSyncEngineDelegate) -> any SyncEngineHandle

    let scope: DatabaseScope
    private let coordinator: SyncCoordinator
    private let store: any SyncStateStore
    private(set) var engine: (any SyncEngineHandle)?

    init(scope: DatabaseScope, coordinator: SyncCoordinator, store: any SyncStateStore) {
        self.scope = scope
        self.coordinator = coordinator
        self.store = store
    }

    /// The factory for a real CKSyncEngine on one database.
    static func cloudKitEngine(database: CKDatabase) -> EngineFactory {
        { serialization, delegate in
            CKSyncEngineHandle(database: database, serialization: serialization, delegate: delegate)
        }
    }

    var hasSavedState: Bool { store.loadEngineState(scope) != nil }

    func start(makeEngine: EngineFactory) {
        let saved = store.loadEngineState(scope).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        engine = makeEngine(saved, self)
    }

    func stop() async {
        await engine?.cancelOperations()
        engine = nil
    }

    // MARK: EngineQueue

    func queue(_ plan: OutgoingPlan) {
        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = plan.zonesToSave.map { .saveZone(CKRecordZone(zoneID: $0)) }
        databaseChanges += (plan.zonesToDelete + plan.zonesToLeave).map { .deleteZone($0) }
        if !databaseChanges.isEmpty { engine?.add(pendingDatabaseChanges: databaseChanges) }
        var recordChanges = plan.saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        recordChanges += plan.deletes.map { .deleteRecord($0) }
        if !recordChanges.isEmpty { engine?.add(pendingRecordZoneChanges: recordChanges) }
    }

    func queue(saves: [CKRecord.ID]) {
        engine?.add(pendingRecordZoneChanges: saves.map { .saveRecord($0) })
    }

    func queue(zonesToSave: [CKRecordZone.ID]) {
        engine?.add(pendingDatabaseChanges: zonesToSave.map { .saveZone(CKRecordZone(zoneID: $0)) })
    }

    func queue(zonesToDelete: [CKRecordZone.ID]) {
        engine?.add(pendingDatabaseChanges: zonesToDelete.map { .deleteZone($0) })
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
        guard let input = SyncEngineInput(event) else { return }
        handle(input)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await batch(from: syncEngine.state.pendingRecordZoneChanges, scope: context.options.scope)
    }

    /// The records to send for the pending changes the engine may send now.
    func batch(
        from pending: [CKSyncEngine.PendingRecordZoneChange], scope allowed: CKSyncEngine.SendChangesOptions.Scope
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let wanted = pending.filter { allowed.contains($0) }
        guard !wanted.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: wanted) { [weak self] id in
            await self?.record(for: id)
        }
    }

    private func record(for id: CKRecord.ID) -> CKRecord? {
        try? coordinator.adapter.outgoingRecord(for: id)
    }

    /// Applies one engine event. A failure is shown as a status and never stops the engine.
    func handle(_ input: SyncEngineInput) {
        do {
            try apply(input)
        } catch {
            coordinator.updateStatus { $0.failed(SyncFailure(error), source: .init(scope: scope, isSending: false)) }
        }
    }

    private func apply(_ input: SyncEngineInput) throws {
        switch input {
        case .stateUpdate(let data):
            store.saveEngineState(data, scope: scope)
        case .account(let change):
            try coordinator.accountChanged(change)
        case .fetchedZones(let modified, let deleted):
            try coordinator.fetchedZones(modified: modified, deleted: deleted)
        case .fetchedRecords(let modifications, let deletions):
            try coordinator.fetchedRecords(modifications: modifications, deletions: deletions)
        case .sentZones(let saved, let failedSaves, let deleted, let failedDeletes):
            try coordinator.sentZones(
                saved: saved, failedSaves: failedSaves, deleted: deleted, failedDeletes: failedDeletes, scope: scope
            )
        case .sentRecords(let saved, let failedSaves, let deleted, let failedDeletes):
            try coordinator.sentRecords(
                saved: saved, failedSaves: failedSaves, deleted: deleted, failedDeletes: failedDeletes, scope: scope
            )
        case .operationStarted:
            coordinator.updateStatus { $0.began() }
        case .operationEnded:
            coordinator.updateStatus { $0.ended() }
        }
    }
}
